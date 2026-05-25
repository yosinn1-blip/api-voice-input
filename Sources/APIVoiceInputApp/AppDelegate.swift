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
    private let transcriptPopup = TranscriptPopupController()
    private let recorder = RecorderController()
    private let youTubePauseController = YouTubePauseController()
    private var isRecording = false
    private var isStartingRecording = false
    private var conversationMode = false
    private var conversationModeEnteredAt: Date = .distantPast
    private var conversationModeExitedAt: Date = .distantPast
    private var pendingF19Task: Task<Void, Never>?
    private var f19ReceivedAt: Date = .distantPast
    private var audioLevelTimer: Timer?
    private var youTubeAudioSnapshot: YouTubePauseController.SystemAudioSnapshot?
    private var recordingSessionID: UUID?
    private var maxRecordingLevel: Double = 0
    private var savedFocusApp: NSRunningApplication?
    private var savedFocusElement: AXUIElement?

    func applicationWillTerminate(_ notification: Notification) {
        youTubePauseController.restoreSystemAudioIfNeeded(youTubeAudioSnapshot)
        youTubeAudioSnapshot = nil
        recordingSessionID = nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        if bundleID.isEmpty == false {
            let runningInstances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if runningInstances.count > 1 {
                DebugLog.write("duplicate instance detected — terminating")
                NSApp.terminate(nil)
                return
            }
        }
        DebugLog.write("app launched")
        YouTubePauseController.restorePendingMuteOnLaunchIfNeeded()
        statusMenu = StatusMenuController { [weak self] in
            self?.toggleRecording(source: "menu")
        } openAccessibilitySettings: {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        } openGroqAPIKeyPage: {
            NSWorkspace.shared.open(GroqAPIKeySetup.apiKeyURL)
        } openSetupGuide: {
            NSWorkspace.shared.open(GroqAPIKeySetup.setupGuideURL)
        } setGroqAPIKey: { [weak self] in
            self?.showGroqAPIKeySetupDialog()
        } showGroqAPIKeyStatus: { [weak self] in
            self?.showGroqAPIKeyStatusDialog()
        } showDiagnostics: { [weak self] in
            self?.showDiagnosticsDialog()
        } getMediaControlEnabled: {
            UserDefaults.standard.object(forKey: AppSettings.mediaControlEnabledKey) as? Bool
                ?? RecordingBehaviorSettings.defaultMediaControlEnabled
        } setMediaControlEnabled: { enabled in
            UserDefaults.standard.set(enabled, forKey: AppSettings.mediaControlEnabledKey)
            DebugLog.write("media control enabled=\(enabled)")
        }
        hotkeyController = HotkeyController { [weak self] source in
            Task { @MainActor in self?.toggleRecording(source: source) }
        }
        hotkeyController?.registerCommandShiftSpace()
        hotkeyController?.registerF19Bridge()
        hotkeyController?.registerConversationModeHotKey()
        let fnRegistered = hotkeyController?.registerFnKey() ?? false
        if fnRegistered == false {
            overlay.show(.failed, detail: "Fn検出にはアクセシビリティ権限が必要です")
        }
        requestAccessibilityPermissionIfNeeded()
        requestMicrophonePermission()
        showGroqAPIKeyOnboardingIfNeeded()
    }

    private func showGroqAPIKeyOnboardingIfNeeded() {
        let dismissed = UserDefaults.standard.bool(forKey: AppSettings.groqOnboardingDismissedKey)
        guard GroqAPIKeySetup.shouldShowOnboarding(hasAPIKey: APIKeyStore.hasGroqAPIKey(), dismissed: dismissed) else {
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard GroqAPIKeySetup.shouldShowOnboarding(
                hasAPIKey: APIKeyStore.hasGroqAPIKey(),
                dismissed: UserDefaults.standard.bool(forKey: AppSettings.groqOnboardingDismissedKey)
            ) else {
                return
            }
            showGroqAPIKeyOnboardingDialog()
        }
    }

    private func showGroqAPIKeyOnboardingDialog() {
        let alert = NSAlert()
        alert.messageText = "Groq APIキーを設定すると使えます"
        alert.informativeText = "このアプリのアカウント作成は不要です。無料のGroq APIキーを取得して貼り付けると、Fnキーで音声入力できます。キーはMacのKeychainに保存されます。"
        alert.addButton(withTitle: "無料キーを取得")
        alert.addButton(withTitle: "キーを貼り付け")
        alert.addButton(withTitle: "あとで")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(GroqAPIKeySetup.apiKeyURL)
            showGroqAPIKeySetupDialog(markDismissedOnSave: true)
        case .alertSecondButtonReturn:
            showGroqAPIKeySetupDialog(markDismissedOnSave: true)
        default:
            UserDefaults.standard.set(true, forKey: AppSettings.groqOnboardingDismissedKey)
        }
    }

    private func showGroqAPIKeySetupDialog(markDismissedOnSave: Bool = false) {
        let alert = NSAlert()
        alert.messageText = "Groq APIキーを設定"
        alert.informativeText = "Groqの無料APIキーを貼り付けてください。キーはMacのKeychainに保存され、このアプリのサーバーには送信されません。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "キャンセル")

        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        input.placeholderString = "gsk_..."
        alert.accessoryView = input

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        do {
            try APIKeyStore.saveGroqAPIKey(input.stringValue)
            if markDismissedOnSave {
                UserDefaults.standard.set(true, forKey: AppSettings.groqOnboardingDismissedKey)
            }
            showMessage(title: "Groq APIキーを保存しました", message: "次回の音声入力からこのキーを使います。")
        } catch {
            DebugLog.write("failed to save Groq API key error=\(error.localizedDescription)")
            showMessage(title: "Groq APIキーを保存できませんでした", message: error.localizedDescription)
        }
    }

    private func showGroqAPIKeyStatusDialog() {
        if APIKeyStore.hasGroqAPIKey() {
            showMessage(title: "Groq APIキーは設定済みです", message: "キーはMacのKeychainまたは既存のsecrets.envから読み込まれます。")
        } else {
            showMessage(title: "Groq APIキーは未設定です", message: "メニューの「無料のGroq APIキーを取得」からキーを作成し、「Groq APIキーを設定…」で貼り付けてください。")
        }
    }

    private func showDiagnosticsDialog() {
        let status = DiagnosticStatus(snapshot: makeDiagnosticSnapshot())
        let alert = NSAlert()
        alert.messageText = status.title
        alert.informativeText = status.message
        alert.addButton(withTitle: "ログをFinderで表示")
        alert.addButton(withTitle: "セットアップを開く")
        alert.addButton(withTitle: "OK")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            revealDebugLog()
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(GroqAPIKeySetup.setupGuideURL)
        default:
            break
        }
    }

    private func makeDiagnosticSnapshot() -> DiagnosticSnapshot {
        let logPath = DebugLog.fileURL.path
        return DiagnosticSnapshot(
            hasGroqAPIKey: APIKeyStore.hasGroqAPIKey(),
            isAccessibilityTrusted: AXIsProcessTrusted(),
            microphonePermission: currentMicrophonePermission(),
            debugLogPath: logPath,
            debugLogExists: FileManager.default.fileExists(atPath: logPath)
        )
    }

    private func currentMicrophonePermission() -> DiagnosticMicrophonePermission {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unknown
        }
    }

    private func revealDebugLog() {
        let fileManager = FileManager.default
        let logURL = DebugLog.fileURL
        if fileManager.fileExists(atPath: logURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([logURL])
            return
        }

        try? fileManager.createDirectory(
            at: AppSettings.applicationSupportDirectory,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(AppSettings.applicationSupportDirectory)
    }

    private func showMessage(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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

    private func isFnTapSource(_ source: String) -> Bool {
        source == "direct-fn-eventtap" || source == "f19-hotkey"
    }

    private func toggleRecording(source: String) {
        // f19-hotkey は Karabiner が長押し時にも先送りしてくる（fn-long-press が後続）
        // 0.15s 待って fn-long-press が来たらキャンセル、来なければ短押しとして処理
        if source == "f19-hotkey" || source == "direct-fn-eventtap" {
            // デバウンス中に追加タップが来ても無視（タイマーをリセットしない）
            if pendingF19Task != nil { return }
            // フォーカスは Fn タップ時点（デバウンス前）に取得する
            captureFocusAtRecordingStart()
            f19ReceivedAt = Date()
            pendingF19Task = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 450_000_000)
                guard !Task.isCancelled, let self else { return }
                self.pendingF19Task = nil
                self.processToggle(source: source)
            }
            return
        }
        if source == "fn-long-press" {
            let gap = Date().timeIntervalSince(f19ReceivedAt)
            DebugLog.write(String(format: "fn-long-press gap since f19=%.0fms", gap * 1000))
            pendingF19Task?.cancel()
            pendingF19Task = nil
        }
        processToggle(source: source)
    }

    private func processToggle(source: String) {
        DebugLog.write("toggle source=\(source) isRecording=\(isRecording) isStarting=\(isStartingRecording) convMode=\(conversationMode)")
        // Karabiner遅延保護：会話モードON直後0.6s以内のFnイベントは無視
        let isFnEvent = source == "fn-long-press" || isFnTapSource(source)
        if isFnEvent && conversationMode && Date().timeIntervalSince(conversationModeEnteredAt) < 0.6 {
            DebugLog.write("fn event ignored — conversation mode just entered (karabiner delay)")
            return
        }
        if isFnEvent && !conversationMode && Date().timeIntervalSince(conversationModeExitedAt) < 0.6 {
            DebugLog.write("fn event ignored — conversation mode just exited (karabiner delay)")
            return
        }
        if conversationMode && isFnEvent {
            if source == "fn-long-press" {
                // 長押し：通常モードへ静かに移行。今の録音は処理して overlay は自然に消える
                conversationMode = false
                conversationModeExitedAt = Date()
                statusMenu?.setConversationModeActive(false)
                overlay.setConversationGlow(false)
                DebugLog.write("conversation mode OFF → normal (recording continues)")
            } else {
                // 短押し：会話モードを終了し、録音中なら通常どおりペースト
                conversationMode = false
                conversationModeExitedAt = Date()
                statusMenu?.setConversationModeActive(false)
                overlay.setConversationGlow(false)
                transcriptPopup.dismiss()
                DebugLog.write("conversation mode OFF → finish with paste source=\(source)")
                if isRecording {
                    finishRecording(source: source)
                } else {
                    overlay.hide()
                }
            }
            return
        }
        // 通常モード：長押しで会話モードON
        if source == "fn-long-press" {
            handleConversationModeToggle()
            return
        }
        // 通常モード：短押しで録音トグル
        if isRecording {
            finishRecording(source: source)
        } else if isStartingRecording {
            DebugLog.write("toggle ignored before recorder became active source=\(source)")
        } else {
            startRecording(source: source)
        }
    }

    private func handleConversationModeToggle() {
        if conversationMode {
            conversationMode = false
            conversationModeExitedAt = Date()
            statusMenu?.setConversationModeActive(false)
            overlay.setConversationGlow(false)
            transcriptPopup.dismiss()
            DebugLog.write("conversation mode OFF")
            if isRecording {
                finishRecording(source: "conversation-mode-cancel")
            } else {
                overlay.hide()
            }
        } else {
            conversationMode = true
            conversationModeEnteredAt = Date()
            statusMenu?.setConversationModeActive(true)
            overlay.setConversationGlow(true)
            overlay.show(.conversationWaiting)
            DebugLog.write("conversation mode ON")
            if !isRecording && !isStartingRecording {
                startRecording(source: "conversation-mode-start")
            }
        }
    }

    private func captureFocusAtRecordingStart() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.bundleIdentifier != Bundle.main.bundleIdentifier else {
            savedFocusApp = nil
            savedFocusElement = nil
            return
        }
        savedFocusApp = frontApp
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue else {
            savedFocusElement = nil
            return
        }
        savedFocusElement = (focusedValue as! AXUIElement)
    }

    private func restoreFocusIfNeeded() async {
        guard let app = savedFocusApp else { return }
        let element = savedFocusElement
        savedFocusApp = nil
        savedFocusElement = nil
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        if let element {
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
        DebugLog.write("restoreFocus app=\(app.localizedName ?? "?") element=\(element != nil ? "ok" : "nil")")
    }

    private func startRecording(source: String) {
        captureFocusAtRecordingStart()
        DebugLog.write("startRecording focusApp=\(savedFocusApp?.localizedName ?? "nil") hasElement=\(savedFocusElement != nil)")
        let startTime = Date()
        let sessionID = UUID()
        isStartingRecording = true
        recordingSessionID = sessionID
        youTubeAudioSnapshot = nil
        DebugLog.write("startRecording requested source=\(source) session=\(sessionID.uuidString)")
        overlay.show(.recording, detail: "Enterで停止して送信")
        do {
            _ = try recorder.startRecording()
            isStartingRecording = false
            isRecording = true
            hotkeyController?.setRecordingActive(true)
            maxRecordingLevel = 0
            DebugLog.write(String(format: "startRecording ok elapsed=%.3fs url=%@", Date().timeIntervalSince(startTime), recorder.currentURL?.path ?? "nil"))
            startAudioLevelUpdates()
            prepareMediaAfterRecordingStartIfNeeded(sessionID: sessionID)
        } catch {
            recordingSessionID = nil
            youTubePauseController.restoreSystemAudioIfNeeded(youTubeAudioSnapshot)
            youTubeAudioSnapshot = nil
            isStartingRecording = false
            isRecording = false
            hotkeyController?.setRecordingActive(false)
            DebugLog.write(String(format: "startRecording failed elapsed=%.3fs error=%@", Date().timeIntervalSince(startTime), error.localizedDescription))
            overlay.show(.failed, detail: "録音開始失敗: \(error.localizedDescription)")
        }
    }

    private func prepareMediaAfterRecordingStartIfNeeded(sessionID: UUID) {
        guard RecordingBehaviorSettings.shouldPrepareMediaBeforeRecording(mediaControlEnabled: mediaControlEnabled()) else {
            DebugLog.write("youtube pause skipped media-control-disabled")
            return
        }

        DebugLog.write("youtube pause prepare async begin session=\(sessionID.uuidString)")
        DispatchQueue.global(qos: .userInitiated).async {
            let snapshot = YouTubePauseController().prepareYouTubeBeforeRecording()
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    YouTubePauseController().restoreSystemAudioIfNeeded(snapshot)
                    return
                }
                guard self.recordingSessionID == sessionID, self.isRecording else {
                    YouTubePauseController().restoreSystemAudioIfNeeded(snapshot)
                    DebugLog.write("youtube pause prepare async discarded session=\(sessionID.uuidString)")
                    return
                }
                self.youTubeAudioSnapshot = snapshot
                DebugLog.write("youtube pause prepare async complete session=\(sessionID.uuidString) snapshot=\(snapshot == nil ? "nil" : "system-audio")")
            }
        }
    }

    private func mediaControlEnabled() -> Bool {
        UserDefaults.standard.object(forKey: AppSettings.mediaControlEnabledKey) as? Bool
            ?? RecordingBehaviorSettings.defaultMediaControlEnabled
    }

    private func finishRecording(source: String) {
        DebugLog.write("finishRecording requested source=\(source)")
        stopAudioLevelUpdates()
        let recordingLevel = maxRecordingLevel
        let shouldHideImmediately = RecordingStopPresentation.shouldHideOverlayImmediately(maxRecordingLevel: recordingLevel, stopSource: source)
        let shouldCancelTranscription = RecordingStopPresentation.shouldCancelTranscription(stopSource: source)
        let pasteMode = RecordingStopPresentation.pasteMode(stopSource: source)
        DebugLog.write(String(format: "recordingLevel max=%.3f quickHide=%@ cancelTranscription=%@ pasteMode=%@", recordingLevel, shouldHideImmediately ? "true" : "false", shouldCancelTranscription ? "true" : "false", pasteMode.rawValue))
        let audioSnapshot = youTubeAudioSnapshot
        youTubeAudioSnapshot = nil
        recordingSessionID = nil
        guard let audioURL = recorder.stopRecording() else {
            isRecording = false
            hotkeyController?.setRecordingActive(false)
            if shouldHideImmediately {
                overlay.hide()
            } else {
                overlay.show(.failed, detail: "録音ファイルなし")
            }
            DispatchQueue.main.async { [youTubePauseController] in
                youTubePauseController.restoreSystemAudioIfNeeded(audioSnapshot)
            }
            DebugLog.write("finishRecording failed no audioURL")
            return
        }
        isRecording = false
        hotkeyController?.setRecordingActive(false)
        if shouldHideImmediately {
            overlay.hide()
            DebugLog.write("finishRecording quick-hide overlay")
        } else {
            overlay.show(.transcribing)
        }
        DispatchQueue.main.async { [youTubePauseController] in
            youTubePauseController.restoreSystemAudioIfNeeded(audioSnapshot)
        }
        DebugLog.write("finishRecording ok url=\(audioURL.path)")
        if shouldCancelTranscription {
            try? FileManager.default.removeItem(at: audioURL)
            DebugLog.write("finishRecording canceled transcription source=\(source)")
            return
        }
        let currentApp = NSWorkspace.shared.frontmostApplication
        let focusLost = savedFocusApp != nil
            && currentApp?.bundleIdentifier != savedFocusApp?.bundleIdentifier
            && currentApp?.bundleIdentifier != Bundle.main.bundleIdentifier
        DebugLog.write("finishRecording focusLost=\(focusLost) savedApp=\(savedFocusApp?.localizedName ?? "nil") currentApp=\(currentApp?.localizedName ?? "nil")")
        Task {
            await process(audioURL: audioURL, overlayVisible: shouldHideImmediately == false, pasteMode: pasteMode, stopSource: source, showPopup: focusLost)
        }
    }

    private func process(audioURL: URL, overlayVisible: Bool, pasteMode: PasteMode, stopSource: String, showPopup: Bool) async {
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
            if emptyGuard.shouldSkipTranscription(activity: activity)
                || RecordingStopPresentation.shouldSkipTranscription(activity: activity, stopSource: stopSource) {
                DebugLog.write("process canceled empty audio before transcription source=\(stopSource)")
                try? FileManager.default.removeItem(at: audioURL)
                if overlayVisible {
                    overlay.hide()
                }
                return
            }
            if overlayVisible == false {
                overlay.show(.transcribing)
            }

            guard let groqKey = APIKeyStore.loadGroqAPIKey(), groqKey.isEmpty == false else {
                DebugLog.write("process failed missing Groq API key")
                overlay.show(.failed, detail: "Groq API key未設定")
                return
            }
            var profile = VoiceProfile.defaultJapanese
            profile.pasteMode = pasteMode
            let transcription = GroqTranscriptionProvider(apiKey: groqKey)
            let cleanup: any CleanupProvider = FillerRemovalCleanupProvider()
            DebugLog.write("cleanup provider=rule-based-filler-removal")
            let pipeline = VoiceInputPipeline(transcriptionProvider: transcription, cleanupProvider: cleanup)
            DebugLog.write("process transcription begin")
            let result = try await pipeline.run(audioFileURL: audioURL, profile: profile)
            DebugLog.write("process transcription ok rawChars=\(result.rawTranscript.count) finalChars=\(result.finalText.count)")
            if emptyGuard.shouldSuppressTranscript(result.rawTranscript, activity: activity)
                || emptyGuard.shouldSuppressTranscript(result.finalText, activity: activity) {
                DebugLog.write("process canceled common silence hallucination finalChars=\(result.finalText.count)")
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
            if showPopup {
                await restoreFocusIfNeeded()
            }
            try paste.paste(result.finalText, mode: profile.pasteMode)
            DebugLog.write("paste command sent")
            overlay.show(.pasted)
            if showPopup {
                transcriptPopup.show(text: result.finalText)
            } else {
                transcriptPopup.dismiss()
            }
            try? FileManager.default.removeItem(at: audioURL)
            try? await Task.sleep(nanoseconds: 900_000_000)
            if conversationMode {
                overlay.show(.conversationWaiting)
                try? await Task.sleep(nanoseconds: 200_000_000)
                if conversationMode && !isRecording && !isStartingRecording {
                    startRecording(source: "conversation-mode-auto")
                }
            } else {
                overlay.hide()
            }
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

private struct GroqFallbackCleanupProvider: CleanupProvider {
    let id = "groq-llama-fallback"
    private let groq: GroqCleanupProvider
    private let fallback = FillerRemovalCleanupProvider()

    init(apiKey: String) {
        groq = GroqCleanupProvider(apiKey: apiKey)
    }

    func clean(transcript: String, prompt: String) async throws -> String {
        do {
            return try await groq.clean(transcript: transcript, prompt: prompt)
        } catch {
            DebugLog.write("groq cleanup failed, fallback to filler-removal error=\(error.localizedDescription)")
            return try await fallback.clean(transcript: transcript, prompt: prompt)
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
