import XCTest
@testable import APIVoiceInputCore

final class ForeignMenuDetectorTests: XCTestCase {
    private let ownPID: Int32 = 100

    func testNoMenuWindowsMeansNothingToDismiss() {
        let windows = [
            ScreenWindow(ownerPID: 200, layer: 0, windowNumber: 1),
            ScreenWindow(ownerPID: 300, layer: 25, windowNumber: 2)
        ]
        XCTAssertEqual(ForeignMenuDetector.menuWindows(in: windows, ownPID: ownPID, ignoring: []), [])
    }

    func testOpenStatusMenuOfAnotherAppIsDetected() {
        // CodexBar のメニューを開いたまま Enter を押した状態
        let menu = ScreenWindow(ownerPID: 748, layer: 101, windowNumber: 9)
        let windows = [ScreenWindow(ownerPID: 200, layer: 0, windowNumber: 1), menu]
        XCTAssertEqual(ForeignMenuDetector.menuWindows(in: windows, ownPID: ownPID, ignoring: []), [menu])
    }

    func testOwnMenuIsIgnored() {
        let windows = [ScreenWindow(ownerPID: ownPID, layer: 101, windowNumber: 3)]
        XCTAssertEqual(ForeignMenuDetector.menuWindows(in: windows, ownPID: ownPID, ignoring: []), [])
    }

    func testWindowThatDidNotCloseOnEscapeIsNotTargetedAgain() {
        // メニューと同じ高さに常駐する窓だった場合、Esc を入力欄側へ何度も送らない
        let resident = ScreenWindow(ownerPID: 900, layer: 101, windowNumber: 42)
        XCTAssertEqual(ForeignMenuDetector.menuWindows(in: [resident], ownPID: ownPID, ignoring: [42]), [])
    }
}
