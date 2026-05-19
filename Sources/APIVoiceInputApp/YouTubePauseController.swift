import APIVoiceInputCore
import AppKit
import Foundation

struct YouTubePauseController {
    private struct BrowserTarget {
        let name: String
        let bundleIdentifier: String
        let scriptKind: ScriptKind
    }

    private enum ScriptKind {
        case chromium
        case safari
    }

    private let queue = DispatchQueue(label: "com.yoshiki.APIVoiceInput.youtubePause", qos: .utility)

    func pauseYouTubeOnRecordingStart() {
        queue.async {
            let targets = Self.supportedBrowsers.filter { target in
                NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleIdentifier).isEmpty == false
            }

            guard targets.isEmpty == false else {
                DebugLog.write("youtube pause skipped no supported browser running")
                return
            }

            var didUseFallback = false
            for target in targets {
                let script = Self.pauseScript(for: target)
                let result = Self.runAppleScript(script)
                DebugLog.write("youtube pause browser=\(target.name) status=\(result.status) output=\(result.output)")
                if didUseFallback == false && YouTubePauseFallbackDecision.shouldUseMediaKeyFallback(scriptOutput: result.output) {
                    Self.sendPlayPauseMediaKey()
                    didUseFallback = true
                    DebugLog.write("youtube pause fallback=media-key browser=\(target.name) reason=javascript-pause-failed")
                }
            }
        }
    }

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
            return chromiumPauseScript(bundleIdentifier: target.bundleIdentifier)
        case .safari:
            return safariPauseScript(bundleIdentifier: target.bundleIdentifier)
        }
    }

    private static func chromiumPauseScript(bundleIdentifier: String) -> String {
        """
        set matchedTabs to 0
        set pausedVideos to 0
        set errorCount to 0
        tell application id "\(bundleIdentifier)"
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        set tabURL to URL of t as text
                        if my isYouTubeURL(tabURL) then
                            set matchedTabs to matchedTabs + 1
                            try
                                set jsResult to execute t javascript "(() => { const host = location.hostname.toLowerCase(); if (!(host === 'youtu.be' || host === 'youtube.com' || host.endsWith('.youtube.com'))) return 0; let count = 0; for (const video of document.querySelectorAll('video')) { if (!video.paused) { video.pause(); count += 1; } } return count; })();"
                                try
                                    set pausedVideos to pausedVideos + (jsResult as integer)
                                end try
                            on error
                                set errorCount to errorCount + 1
                            end try
                        end if
                    end try
                end repeat
            end repeat
        end tell
        return "tabs=" & (matchedTabs as text) & " pausedVideos=" & (pausedVideos as text) & " errors=" & (errorCount as text)

        on isYouTubeURL(tabURL)
            return tabURL starts with "https://youtube.com/" or tabURL starts with "http://youtube.com/" or tabURL starts with "https://www.youtube.com/" or tabURL starts with "http://www.youtube.com/" or tabURL starts with "https://m.youtube.com/" or tabURL starts with "http://m.youtube.com/" or tabURL starts with "https://music.youtube.com/" or tabURL starts with "http://music.youtube.com/" or tabURL starts with "https://youtu.be/" or tabURL starts with "http://youtu.be/"
        end isYouTubeURL
        """
    }

    private static func safariPauseScript(bundleIdentifier: String) -> String {
        """
        set matchedTabs to 0
        set pausedVideos to 0
        set errorCount to 0
        tell application id "\(bundleIdentifier)"
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        set tabURL to URL of t as text
                        if my isYouTubeURL(tabURL) then
                            set matchedTabs to matchedTabs + 1
                            try
                                set jsResult to do JavaScript "(() => { const host = location.hostname.toLowerCase(); if (!(host === 'youtu.be' || host === 'youtube.com' || host.endsWith('.youtube.com'))) return 0; let count = 0; for (const video of document.querySelectorAll('video')) { if (!video.paused) { video.pause(); count += 1; } } return count; })();" in t
                                try
                                    set pausedVideos to pausedVideos + (jsResult as integer)
                                end try
                            on error
                                set errorCount to errorCount + 1
                            end try
                        end if
                    end try
                end repeat
            end repeat
        end tell
        return "tabs=" & (matchedTabs as text) & " pausedVideos=" & (pausedVideos as text) & " errors=" & (errorCount as text)

        on isYouTubeURL(tabURL)
            return tabURL starts with "https://youtube.com/" or tabURL starts with "http://youtube.com/" or tabURL starts with "https://www.youtube.com/" or tabURL starts with "http://www.youtube.com/" or tabURL starts with "https://m.youtube.com/" or tabURL starts with "http://m.youtube.com/" or tabURL starts with "https://music.youtube.com/" or tabURL starts with "http://music.youtube.com/" or tabURL starts with "https://youtu.be/" or tabURL starts with "http://youtu.be/"
        end isYouTubeURL
        """
    }

    private static func sendPlayPauseMediaKey() {
        let keyTypePlay: UInt32 = 16
        postMediaKey(keyType: keyTypePlay, isKeyDown: true)
        postMediaKey(keyType: keyTypePlay, isKeyDown: false)
    }

    private static func postMediaKey(keyType: UInt32, isKeyDown: Bool) {
        let keyState: UInt32 = isKeyDown ? 0xA : 0xB
        let data1 = Int((keyType << 16) | (keyState << 8))
        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xA00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        )
        event?.cgEvent?.post(tap: .cghidEventTap)
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
