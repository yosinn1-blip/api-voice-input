import Foundation

public struct ScreenWindow: Equatable, Sendable {
    public let ownerPID: Int32
    public let layer: Int
    public let windowNumber: Int

    public init(ownerPID: Int32, layer: Int, windowNumber: Int) {
        self.ownerPID = ownerPID
        self.layer = layer
        self.windowNumber = windowNumber
    }
}

/// 他アプリのメニュー（CodexBar などメニューバーのメニュー、右クリックメニュー）が開いていると、
/// 貼り付けの ⌘V と送信の Enter がそのメニューに吸われて入力欄へ届かない（2026-10-12 実測）。
/// 貼り付け前に閉じる対象を、画面上の窓の一覧から見つける。
public enum ForeignMenuDetector {
    /// kCGPopUpMenuWindowLevel
    public static let popUpMenuLayer = 101

    /// `ignoring` は Esc で閉じなかった窓（メニューと同じ高さに常駐する窓）の番号。
    public static func menuWindows(in windows: [ScreenWindow], ownPID: Int32, ignoring: Set<Int>) -> [ScreenWindow] {
        windows.filter {
            $0.layer == popUpMenuLayer && $0.ownerPID != ownPID && ignoring.contains($0.windowNumber) == false
        }
    }
}
