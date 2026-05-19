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
    private let keychain = KeychainStore()
    private var isRecording = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.write("app launched")
        overlay.show(.pasted, detail: "起動しました")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            if self.isRecording == false { self.overlay.hide() }
        }
        statusMenu = StatusMenuController { [weak self] in
            self?.toggleRecording(source: "menu")
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
        requestMicrophonePermission()
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
        DebugLog.write("toggle source=\(source) isRecording=\(isRecording)")
        overlay.show(.pasted, detail: "入力検出: \(source)")
        if isRecording {
            finishRecording(source: source)
        } else {
            startRecording(source: source)
        }
    }

    private func startRecording(source: String) {
        DebugLog.write("startRecording requested source=\(source)")
        do {
            _ = try recorder.startRecording()
            isRecording = true
            DebugLog.write("startRecording ok url=\(recorder.currentURL?.path ?? "nil")")
            overlay.show(.recording, detail: "Fn / F19 / ⌘⇧Spaceで停止")
        } catch {
            DebugLog.write("startRecording failed error=\(error.localizedDescription)")
            overlay.show(.failed, detail: "録音開始失敗: \(error.localizedDescription)")
        }
    }

    private func finishRecording(source: String) {
        DebugLog.write("finishRecording requested source=\(source)")
        guard let audioURL = recorder.stopRecording() else {
            isRecording = false
            DebugLog.write("finishRecording failed no audioURL")
            overlay.show(.failed, detail: "録音ファイルなし")
            return
        }
        isRecording = false
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
                overlay.show(.canceled, detail: "貼り付けなし")
                try? FileManager.default.removeItem(at: audioURL)
                try? await Task.sleep(nanoseconds: 900_000_000)
                overlay.hide()
                return
            }

            let groqKey = try keychain.loadAPIKey(account: AppSettings.groqKeyAccount)
            guard let groqKey, groqKey.isEmpty == false else {
                DebugLog.write("process failed missing Groq API key")
                overlay.show(.failed, detail: "Groq API key未設定")
                return
            }
            let profile = VoiceProfile.defaultJapanese
            let transcription = GroqTranscriptionProvider(apiKey: groqKey)
            let pipeline = VoiceInputPipeline(transcriptionProvider: transcription, cleanupProvider: NoCleanupProvider())
            DebugLog.write("process transcription begin")
            let result = try await pipeline.run(audioFileURL: audioURL, profile: profile)
            DebugLog.write("process transcription ok rawChars=\(result.rawTranscript.count) finalChars=\(result.finalText.count)")
            if emptyGuard.shouldSuppressTranscript(result.finalText, activity: activity) {
                DebugLog.write("process canceled common silence hallucination transcript=\(result.finalText)")
                overlay.show(.canceled, detail: "誤認識を破棄")
                try? FileManager.default.removeItem(at: audioURL)
                try? await Task.sleep(nanoseconds: 900_000_000)
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
