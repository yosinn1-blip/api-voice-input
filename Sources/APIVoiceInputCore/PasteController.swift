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

public protocol PasteTimingClient: Sendable {
    func waitBeforeEnter(characterCount: Int)
}

public struct AdaptivePasteEnterDelay: Sendable {
    private let baseDelaySeconds: TimeInterval
    private let longTextThreshold: Int
    private let additionalDelayPerCharacter: TimeInterval
    private let maximumDelaySeconds: TimeInterval

    public init(
        baseDelaySeconds: TimeInterval = 0.18,
        longTextThreshold: Int = 300,
        additionalDelayPerCharacter: TimeInterval = 0.0005,
        maximumDelaySeconds: TimeInterval = 0.65
    ) {
        self.baseDelaySeconds = baseDelaySeconds
        self.longTextThreshold = longTextThreshold
        self.additionalDelayPerCharacter = additionalDelayPerCharacter
        self.maximumDelaySeconds = maximumDelaySeconds
    }

    public func delaySeconds(forCharacterCount characterCount: Int) -> TimeInterval {
        let extraCharacters = max(0, characterCount - longTextThreshold)
        let adaptiveDelay = baseDelaySeconds + TimeInterval(extraCharacters) * additionalDelayPerCharacter
        return min(maximumDelaySeconds, adaptiveDelay)
    }
}

public struct DefaultPasteTimingClient: PasteTimingClient {
    private let delay: AdaptivePasteEnterDelay

    public init(delay: AdaptivePasteEnterDelay = AdaptivePasteEnterDelay()) {
        self.delay = delay
    }

    public func waitBeforeEnter(characterCount: Int) {
        Thread.sleep(forTimeInterval: delay.delaySeconds(forCharacterCount: characterCount))
    }
}

public enum PasteControllerError: Error, Equatable, Sendable {
    case emptyText
}

public final class PasteController: Sendable {
    private let clipboard: any ClipboardClient
    private let keyboard: any KeyboardClient
    private let timing: any PasteTimingClient

    public init(
        clipboard: any ClipboardClient,
        keyboard: any KeyboardClient,
        timing: any PasteTimingClient = DefaultPasteTimingClient()
    ) {
        self.clipboard = clipboard
        self.keyboard = keyboard
        self.timing = timing
    }

    public func paste(_ text: String, mode: PasteMode) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw PasteControllerError.emptyText
        }
        try clipboard.writeString(text)
        try keyboard.sendPaste()
        if mode == .pasteThenEnter {
            timing.waitBeforeEnter(characterCount: text.count)
            try keyboard.sendEnter()
        }
    }
}
