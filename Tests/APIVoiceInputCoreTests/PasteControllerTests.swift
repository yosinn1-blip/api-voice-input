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

    func sendPaste() throws {
        events.append(.paste)
    }

    func sendEnter() throws {
        events.append(.enter)
    }
}
