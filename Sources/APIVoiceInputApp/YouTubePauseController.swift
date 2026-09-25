import APIVoiceInputCore
import AppKit
import Foundation

struct YouTubePauseController {
    struct SystemAudioSnapshot {
        let wasMuted: Bool
    }

    private struct BrowserTarget {
        let name: String
        let bundleIdentifier: String
        let scriptKind: ScriptKind
    }

    private enum ScriptKind {
        case chromium
        case safari
    }

    func prepareYouTubeBeforeRecording() -> SystemAudioSnapshot? {
        let targets = Self.supportedBrowsers.filter { target in
            NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleIdentifier).isEmpty == false
        }

        guard targets.isEmpty == false else {
            DebugLog.write("youtube pause skipped no supported browser running")
            return nil
        }

        // MediaRemote は「再生元が対象ブラウザだ」と確認できたときだけの近道。
        // 確認が取れない場合は必ず下の AppleScript タブ巡回（実効性のある正規ルート）へ進む。
        for target in targets {
            if Self.tryMediaRemotePause(for: target, reason: "fast-preflight") {
                DebugLog.write("youtube pause handled by media-remote browser=\(target.name) skipping tab scan")
                return nil
            }
        }

        var audioSnapshot: SystemAudioSnapshot?
        for target in targets {
            let script = Self.pauseScript(for: target)
            let startedAt = Date()
            let result = Self.runAppleScript(script)
            let elapsed = Date().timeIntervalSince(startedAt)
            DebugLog.write(String(
                format: "youtube pause browser=%@ status=%d elapsed=%.2fs output=%@",
                target.name, result.status, elapsed, result.output
            ))
            if audioSnapshot == nil && YouTubePauseFallbackDecision.fallbackAction(scriptOutput: result.output) == .tryMediaRemotePause {
                let didPause = Self.tryMediaRemotePause(for: target, reason: "apple-script-fallback")
                if didPause == false {
                    audioSnapshot = Self.muteSystemOutput()
                    DebugLog.write("youtube pause fallback=system-output-muted browser=\(target.name) reason=media-remote-pause-unavailable")
                }
            }
        }
        return audioSnapshot
    }

    func restoreSystemAudioIfNeeded(_ snapshot: SystemAudioSnapshot?) {
        guard let snapshot, snapshot.wasMuted == false else { return }
        let result = Self.runAppleScript("set volume without output muted")
        UserDefaults.standard.removeObject(forKey: Self.pendingMuteKey)
        DebugLog.write("youtube pause restore system-output-muted=false status=\(result.status) output=\(result.output)")
    }

    static func restorePendingMuteOnLaunchIfNeeded() {
        guard UserDefaults.standard.bool(forKey: pendingMuteKey) else { return }
        let result = runAppleScript("set volume without output muted")
        UserDefaults.standard.removeObject(forKey: pendingMuteKey)
        DebugLog.write("youtube pause launch-restore system-output-muted=false status=\(result.status) output=\(result.output)")
    }

    private static let pendingMuteKey = "YouTubePauseController.pendingMute"

    private static let supportedBrowsers: [BrowserTarget] = [
        BrowserTarget(name: "Google Chrome", bundleIdentifier: "com.google.Chrome", scriptKind: .chromium),
        BrowserTarget(name: "Google Chrome Beta", bundleIdentifier: "com.google.Chrome.beta", scriptKind: .chromium),
        BrowserTarget(name: "Google Chrome Canary", bundleIdentifier: "com.google.Chrome.canary", scriptKind: .chromium),
        BrowserTarget(name: "Microsoft Edge", bundleIdentifier: "com.microsoft.edgemac", scriptKind: .chromium),
        BrowserTarget(name: "Brave Browser", bundleIdentifier: "com.brave.Browser", scriptKind: .chromium),
        BrowserTarget(name: "Vivaldi", bundleIdentifier: "com.vivaldi.Vivaldi", scriptKind: .chromium),
        BrowserTarget(name: "Safari", bundleIdentifier: "com.apple.Safari", scriptKind: .safari)
    ]

    private static func pauseScript(for target: BrowserTarget) -> String {
        switch target.scriptKind {
        case .chromium:
            return YouTubePauseScript.chromium(bundleIdentifier: target.bundleIdentifier)
        case .safari:
            return YouTubePauseScript.safari(bundleIdentifier: target.bundleIdentifier)
        }
    }

    private static func tryMediaRemotePause(for target: BrowserTarget, reason: String) -> Bool {
        let controller = MediaRemotePauseController()
        let snapshot = controller.snapshot()
        DebugLog.write("youtube pause media-remote reason=\(reason) snapshot displayID=\(snapshot.displayID ?? "nil") isPlaying=\(snapshot.isPlaying.map(String.init) ?? "nil") target=\(target.bundleIdentifier)")
        let shouldSendPause = MediaRemotePauseSendDecision.shouldSendPause(
            snapshotDisplayID: snapshot.displayID,
            targetDisplayID: target.bundleIdentifier
        )
        guard shouldSendPause else {
            DebugLog.write("youtube pause media-remote-pause skipped reason=\(reason) browser=\(target.name) guardedDisplayID=\(snapshot.displayID ?? "nil")")
            return false
        }
        let sent = controller.sendPause()
        let handled = MediaRemotePauseHandlingDecision.isHandledPause(
            sent: sent,
            snapshotDisplayID: snapshot.displayID,
            snapshotIsPlaying: snapshot.isPlaying,
            targetDisplayID: target.bundleIdentifier
        )
        DebugLog.write("youtube pause media-remote-pause reason=\(reason) browser=\(target.name) sent=\(sent) handled=\(handled) guardedDisplayID=\(snapshot.displayID ?? "nil")")
        return handled
    }

    private static func muteSystemOutput() -> SystemAudioSnapshot? {
        let snapshotResult = runAppleScript("return output muted of (get volume settings)")
        let wasMuted = snapshotResult.output.lowercased().contains("true")
        let muteResult = runAppleScript("set volume with output muted")
        if wasMuted == false {
            UserDefaults.standard.set(true, forKey: pendingMuteKey)
        }
        DebugLog.write("youtube pause system-output-muted=true previousMuted=\(wasMuted) status=\(muteResult.status) output=\(muteResult.output)")
        return SystemAudioSnapshot(wasMuted: wasMuted)
    }

    private static func runAppleScript(_ script: String) -> (status: Int32, output: String) {
        guard let appleScript = NSAppleScript(source: script) else {
            return (-1, "compileError")
        }

        var errorInfo: NSDictionary?
        let descriptor = appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            return (-1, String(describing: errorInfo))
        }

        return (0, descriptor.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "empty")
    }
}
