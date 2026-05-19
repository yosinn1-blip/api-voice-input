import Foundation

public enum KeyboardEvent: Equatable, Sendable {
    case paste
    case enter
}

public protocol ClipboardClient: Sendable {
    func readString() -> String?
    func writeString(_ string: String) throws
}

public protocol KeyboardClient: Sendable {
    func sendPaste() throws
    func sendEnter() throws
}

public enum PasteControllerError: Error, Equatable, Sendable {
    case emptyText
}

public final class PasteController: Sendable {
    private let clipboard: any ClipboardClient
    private let keyboard: any KeyboardClient

    public init(clipboard: any ClipboardClient, keyboard: any KeyboardClient) {
        self.clipboard = clipboard
        self.keyboard = keyboard
    }

    public func paste(_ text: String, mode: PasteMode) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw PasteControllerError.emptyText
        }
        try clipboard.writeString(text)
        try keyboard.sendPaste()
        if mode == .pasteThenEnter {
            try keyboard.sendEnter()
        }
    }
}
