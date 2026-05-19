import XCTest
@testable import APIVoiceInputCore

final class PasteControllerTests: XCTestCase {
    func testPasteWritesTextAndDoesNotSendEnterForPasteOnly() throws {
        let clipboard = MockClipboard(initial: "before")
        let keyboard = MockKeyboard()
        let controller = PasteController(clipboard: clipboard, keyboard: keyboard)

        try controller.paste("hello", mode: .pasteOnly)

        XCTAssertEqual(clipboard.currentText, "hello")
        XCTAssertEqual(keyboard.events, [.paste])
    }

    func testPasteThenEnterSendsEnterAfterPaste() throws {
        let clipboard = MockClipboard(initial: "before")
        let keyboard = MockKeyboard()
        let controller = PasteController(clipboard: clipboard, keyboard: keyboard)

        try controller.paste("hello", mode: .pasteThenEnter)

        XCTAssertEqual(clipboard.currentText, "hello")
        XCTAssertEqual(keyboard.events, [.paste, .enter])
    }


    func testAdaptiveEnterDelayKeepsShortTextFast() {
        let strategy = AdaptivePasteEnterDelay()

        XCTAssertEqual(strategy.delaySeconds(forCharacterCount: 120), 0.18, accuracy: 0.001)
    }

    func testAdaptiveEnterDelayAddsWaitForLongerText() {
        let strategy = AdaptivePasteEnterDelay()

        XCTAssertEqual(strategy.delaySeconds(forCharacterCount: 700), 0.38, accuracy: 0.001)
    }

    func testAdaptiveEnterDelayCapsVeryLongText() {
        let strategy = AdaptivePasteEnterDelay()

        XCTAssertEqual(strategy.delaySeconds(forCharacterCount: 2_000), 0.65, accuracy: 0.001)
    }

    func testPasteThenEnterPassesCharacterCountToTiming() throws {
        let clipboard = MockClipboard(initial: "before")
        let keyboard = MockKeyboard()
        let timing = MockPasteTiming()
        let controller = PasteController(clipboard: clipboard, keyboard: keyboard, timing: timing)
        let text = String(repeating: "長い文章です。", count: 80)

        try controller.paste(text, mode: .pasteThenEnter)

        XCTAssertEqual(timing.waitedCharacterCounts, [text.count])
    }

    func testPasteThenEnterWaitsBetweenPasteAndEnter() throws {
        let recorder = EventRecorder()
        let clipboard = MockClipboard(initial: "before")
        let keyboard = MockKeyboard(recorder: recorder)
        let timing = MockPasteTiming(recorder: recorder)
        let controller = PasteController(clipboard: clipboard, keyboard: keyboard, timing: timing)

        try controller.paste("hello", mode: .pasteThenEnter)

        XCTAssertEqual(recorder.events, ["paste", "wait", "enter"])
    }
}

private final class EventRecorder: @unchecked Sendable {
    var events: [String] = []
}

private final class MockClipboard: ClipboardClient, @unchecked Sendable {
    var currentText: String?

    init(initial: String?) {
        self.currentText = initial
    }

    func readString() -> String? {
        currentText
    }

    func writeString(_ string: String) throws {
        currentText = string
    }
}

private final class MockKeyboard: KeyboardClient, @unchecked Sendable {
    var events: [KeyboardEvent] = []
    private let recorder: EventRecorder?

    init(recorder: EventRecorder? = nil) {
        self.recorder = recorder
    }

    func sendPaste() throws {
        events.append(.paste)
        recorder?.events.append("paste")
    }

    func sendEnter() throws {
        events.append(.enter)
        recorder?.events.append("enter")
    }
}

private final class MockPasteTiming: PasteTimingClient, @unchecked Sendable {
    private let recorder: EventRecorder?
    var waitedCharacterCounts: [Int] = []

    init(recorder: EventRecorder? = nil) {
        self.recorder = recorder
    }

    func waitBeforeEnter(characterCount: Int) {
        waitedCharacterCounts.append(characterCount)
        recorder?.events.append("wait")
    }
}
