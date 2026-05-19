import XCTest
@testable import APIVoiceInputCore

final class ProfileStoreTests: XCTestCase {
    func testDefaultProfileIsJapaneseAndPasteOnly() {
        let profile = VoiceProfile.defaultJapanese
        XCTAssertEqual(profile.sttLanguageHint, "ja")
        XCTAssertEqual(profile.transcriptionProviderID, "groq-whisper-large-v3-turbo")
        XCTAssertEqual(profile.cleanupProviderID, "none")
        XCTAssertEqual(profile.pasteMode, .pasteOnly)
    }
}
