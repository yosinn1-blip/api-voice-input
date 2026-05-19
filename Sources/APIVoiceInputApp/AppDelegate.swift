import APIVoiceInputCore
import AppKit
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
        statusMenu = StatusMenuController { [weak self] in
            self?.toggleRecording()
        }
        hotkeyController = HotkeyController { [weak self] in
            Task { @MainActor in self?.toggleRecording() }
        }
        hotkeyController?.registerCommandShiftSpace()
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

    private func toggleRecording() {
        if isRecording {
            finishRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        do {
            _ = try recorder.startRecording()
            isRecording = true
            overlay.show(.recording, detail: "⌘⇧Spaceで停止")
        } catch {
            overlay.show(.failed, detail: error.localizedDescription)
        }
    }

    private func finishRecording() {
        guard let audioURL = recorder.stopRecording() else {
            isRecording = false
            overlay.show(.failed, detail: "録音ファイルなし")
            return
        }
        isRecording = false
        overlay.show(.transcribing)
        Task {
            await process(audioURL: audioURL)
        }
    }

    private func process(audioURL: URL) async {
        do {
            let groqKey = try keychain.loadAPIKey(account: AppSettings.groqKeyAccount)
            guard let groqKey, groqKey.isEmpty == false else {
                overlay.show(.failed, detail: "Groq API key未設定")
                return
            }
            let profile = VoiceProfile.defaultJapanese
            let transcription = GroqTranscriptionProvider(apiKey: groqKey)
            let pipeline = VoiceInputPipeline(transcriptionProvider: transcription, cleanupProvider: NoCleanupProvider())
            let result = try await pipeline.run(audioFileURL: audioURL, profile: profile)
            let paste = PasteController(clipboard: SystemClipboardClient(), keyboard: SystemKeyboardClient())
            try paste.paste(result.finalText, mode: profile.pasteMode)
            overlay.show(.pasted)
            try? FileManager.default.removeItem(at: audioURL)
            try? await Task.sleep(nanoseconds: 900_000_000)
            overlay.hide()
        } catch {
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
