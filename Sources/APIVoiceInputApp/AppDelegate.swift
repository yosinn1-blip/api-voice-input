import APIVoiceInputCore
import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusMenu: StatusMenuController?
    private var hotkeyController: HotkeyController?
    private let overlay = OverlayWindowController()
    private let recorder = RecorderController()
    private let youTubePauseController = YouTubePauseController()
    private var isRecording = false
    private var isStartingRecording = false
    private var audioLevelTimer: Timer?
    private var youTubeAudioSnapshot: YouTubePauseController.SystemAudioSnapshot?
    private var maxRecordingLevel: Double = 0


    func applicationWillTerminate(_ notification: Notification) {
        youTubePauseController.restoreSystemAudioIfNeeded(youTubeAudioSnapshot)
        youTubeAudioSnapshot = nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.write("app launched")
        statusMenu = StatusMenuController { [weak self] in
            self?.toggleRecording(source: "menu")
        } openAccessibilitySettings: {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        hotkeyController = HotkeyController { [weak self] source in
            Task { @MainActor in self?.toggleRecording(source: source) }
        }
        hotkeyController?.registerCommandShiftSpace()
        hotkeyController?.registerF19Bridge()
        let fnRegistered = hotkeyController?.registerFnKey() ?? false
        if fnRegistered == false {
            overlay.show(.failed, detail: "Fn検出にはアクセシビリティ権限が必要です")
        }
        requestAccessibilityPermissionIfNeeded()
        requestMicrophonePermission()
    }

    private func requestAccessibilityPermissionIfNeeded() {
        guard AXIsProcessTrusted() == false else {
            DebugLog.write("accessibility already trusted")
            return
        }
        DebugLog.write("accessibility not trusted; requesting prompt")
        overlay.show(.failed, detail: "アクセシビリティ権限を許可してください")
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if granted == false {
                Task { @MainActor in
                    self.overlay.show(.failed, detail: "マイク権限が必要です")
                }
            }
        }
    }

    private func toggleRecording(source: String) {
        DebugLog.write("toggle source=\(source) isRecording=\(isRecording) isStarting=\(isStartingRecording)")
        if isStartingRecording {
            DebugLog.write("toggle ignored while recording startup is in progress source=\(source)")
            return
        }
        if isRecording {
            finishRecording(source: source)
        } else {
            startRecording(source: source)
        }
    }

    private func startRecording(source: String) {
        let startTime = Date()
        isStartingRecording = true
        DebugLog.write("startRecording requested source=\(source)")
        overlay.show(.recording, detail: "Enterで停止して送信")
        do {
            youTubeAudioSnapshot = youTubePauseController.prepareYouTubeBeforeRecording()
            _ = try recorder.startRecording()
            isStartingRecording = false
            isRecording = true
            hotkeyController?.setRecordingActive(true)
            maxRecordingLevel = 0
            DebugLog.write(String(format: "startRecording ok elapsed=%.3fs url=%@", Date().timeIntervalSince(startTime), recorder.currentURL?.path ?? "nil"))
            startAudioLevelUpdates()
        } catch {
            youTubePauseController.restoreSystemAudioIfNeeded(youTubeAudioSnapshot)
            youTubeAudioSnapshot = nil
            isStartingRecording = false
            isRecording = false
            hotkeyController?.setRecordingActive(false)
            DebugLog.write(String(format: "startRecording failed elapsed=%.3fs error=%@", Date().timeIntervalSince(startTime), error.localizedDescription))
            overlay.show(.failed, detail: "録音開始失敗: \(error.localizedDescription)")
        }
    }

    private func finishRecording(source: String) {
        DebugLog.write("finishRecording requested source=\(source)")
        stopAudioLevelUpdates()
        DebugLog.write(String(format: "recordingLevel max=%.3f", maxRecordingLevel))
        guard let audioURL = recorder.stopRecording() else {
            youTubePauseController.restoreSystemAudioIfNeeded(youTubeAudioSnapshot)
            youTubeAudioSnapshot = nil
            isRecording = false
            hotkeyController?.setRecordingActive(false)
            DebugLog.write("finishRecording failed no audioURL")
            overlay.show(.failed, detail: "録音ファイルなし")
            return
        }
        youTubePauseController.restoreSystemAudioIfNeeded(youTubeAudioSnapshot)
        youTubeAudioSnapshot = nil
        isRecording = false
        hotkeyController?.setRecordingActive(false)
        DebugLog.write("finishRecording ok url=\(audioURL.path)")
        overlay.show(.transcribing)
        Task {
            await process(audioURL: audioURL)
        }
    }

    private func process(audioURL: URL) async {
        do {
            let activity = try AudioActivityAnalyzer().analyze(audioFileURL: audioURL)
            DebugLog.write(
                String(
                    format: "audioActivity duration=%.2f rms=%.1f peak=%.1f",
                    activity.durationSeconds,
                    activity.rmsDBFS,
                    activity.peakDBFS
                )
            )
            let emptyGuard = EmptyUtteranceGuard()
            if emptyGuard.shouldSkipTranscription(activity: activity) {
                DebugLog.write("process canceled empty audio before transcription")
                try? FileManager.default.removeItem(at: audioURL)
                overlay.hide()
                return
            }

            guard let groqKey = APIKeyStore.loadGroqAPIKey(), groqKey.isEmpty == false else {
                DebugLog.write("process failed missing Groq API key")
                overlay.show(.failed, detail: "Groq API key未設定")
                return
            }
            let profile = VoiceProfile.defaultJapanese
            let transcription = GroqTranscriptionProvider(apiKey: groqKey)
            let pipeline = VoiceInputPipeline(transcriptionProvider: transcription, cleanupProvider: FillerRemovalCleanupProvider())
            DebugLog.write("process transcription begin")
            let result = try await pipeline.run(audioFileURL: audioURL, profile: profile)
            DebugLog.write("process transcription ok rawChars=\(result.rawTranscript.count) finalChars=\(result.finalText.count)")
            if emptyGuard.shouldSuppressTranscript(result.finalText, activity: activity) {
                DebugLog.write("process canceled common silence hallucination transcript=\(result.finalText)")
                try? FileManager.default.removeItem(at: audioURL)
                overlay.hide()
                return
            }
            overlay.show(.pasting, detail: "クリップボードへ保存")
            let paste = PasteController(clipboard: SystemClipboardClient(), keyboard: SystemKeyboardClient())
            DebugLog.write("paste begin finalChars=\(result.finalText.count) mode=\(profile.pasteMode.rawValue) accessibilityTrusted=\(AXIsProcessTrusted())")
            if AXIsProcessTrusted() == false {
                try SystemClipboardClient().writeString(result.finalText)
                DebugLog.write("paste skipped because Accessibility is not trusted; text kept in clipboard")
                overlay.show(.failed, detail: "アクセシビリティ権限が必要・文字はクリップボード")
                return
            }
            try paste.paste(result.finalText, mode: profile.pasteMode)
            DebugLog.write("paste command sent")
            overlay.show(.pasted)
            try? FileManager.default.removeItem(at: audioURL)
            try? await Task.sleep(nanoseconds: 900_000_000)
            overlay.hide()
        } catch {
            DebugLog.write("process failed error=\(error.localizedDescription)")
            overlay.show(.failed, detail: error.localizedDescription)
        }
    }

    private func startAudioLevelUpdates() {
        stopAudioLevelUpdates()
        overlay.updateRecordingLevel(0)
        let timer = Timer(timeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                let level = self.recorder.normalizedAudioLevel()
                self.maxRecordingLevel = max(self.maxRecordingLevel, level)
                self.overlay.updateRecordingLevel(level)
            }
        }
        audioLevelTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopAudioLevelUpdates() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        overlay.updateRecordingLevel(0)
    }

}

struct SystemClipboardClient: ClipboardClient {
    func readString() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    func writeString(_ string: String) throws {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

struct SystemKeyboardClient: KeyboardClient {
    func sendPaste() throws {
        sendKey(keyCode: 9, flags: .maskCommand)
    }

    func sendEnter() throws {
        sendKey(keyCode: 36, flags: [])
    }

    private func sendKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
