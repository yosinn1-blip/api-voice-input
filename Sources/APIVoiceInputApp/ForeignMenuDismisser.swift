import APIVoiceInputCore
import AppKit
import CoreGraphics

/// 貼り付け直前に、他アプリで開いたままのメニューを Esc で閉じる。
/// 開いたままだと ⌘V と Enter がメニューに吸われ、入力欄に文字が入らず送信もされない。
/// メニュー表示中のキー入力はメニューが受け取るので、この Esc は入力欄に届かない（2026-10-12 実測）。
@MainActor
enum ForeignMenuDismisser {
    private static var nonClosingWindowNumbers = Set<Int>()

    static func dismissIfNeeded() async {
        let menus = openMenuWindows()
        guard menus.isEmpty == false else { return }
        let owners = Set(menus.map(\.ownerPID)).map { "\(NSRunningApplication(processIdentifier: $0)?.localizedName ?? "?")(\($0))" }
        sendEscape()
        let closed = await waitUntilClosed(menus)
        if closed == false {
            nonClosingWindowNumbers.formUnion(menus.map(\.windowNumber))
        }
        DebugLog.write("foreign menu dismiss owners=\(owners.joined(separator: ",")) closed=\(closed)")
    }

    private static func openMenuWindows() -> [ScreenWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let windows = list.compactMap { info -> ScreenWindow? in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let number = info[kCGWindowNumber as String] as? Int else { return nil }
            return ScreenWindow(ownerPID: pid, layer: layer, windowNumber: number)
        }
        return ForeignMenuDetector.menuWindows(in: windows, ownPID: getpid(), ignoring: nonClosingWindowNumbers)
    }

    private static func waitUntilClosed(_ menus: [ScreenWindow]) async -> Bool {
        let numbers = Set(menus.map(\.windowNumber))
        for _ in 0..<12 {
            if openMenuWindows().contains(where: { numbers.contains($0.windowNumber) }) == false { return true }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return false
    }

    private static func sendEscape() {
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
    }
}
