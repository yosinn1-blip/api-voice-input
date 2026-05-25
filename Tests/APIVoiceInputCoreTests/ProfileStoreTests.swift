import XCTest
@testable import APIVoiceInputCore

final class ProfileStoreTests: XCTestCase {
    func testDefaultProfileUsesPasteThenEnter() {
        let profile = VoiceProfile.defaultJapanese
        XCTAssertEqual(profile.sttLanguageHint, "ja")
        XCTAssertEqual(profile.transcriptionProviderID, "groq-whisper-large-v3")
        XCTAssertEqual(profile.cleanupProviderID, "rule-based-filler-removal")
        XCTAssertEqual(profile.pasteMode, .pasteThenEnter)
    }

    func testLoadCreatesDefaultProfileWhenFileDoesNotExist() throws {
        let directory = try temporaryDirectory()
        let store = ProfileStore(directoryURL: directory)

        let profiles = try store.loadProfiles()

        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles[0].displayName, "日本語 default")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("profiles.json").path))
    }

    func testSaveAndLoadMultipleProfiles() throws {
        let directory = try temporaryDirectory()
        let store = ProfileStore(directoryURL: directory)
        let english = VoiceProfile(
            displayName: "English email",
            sttLanguageHint: "en",
            transcriptionProviderID: "groq-whisper-large-v3",
            cleanupProviderID: "groq-llama-instant",
            cleanupPrompt: "Rewrite as a concise, polite English email without changing the meaning.",
            pasteMode: .pasteThenEnter
        )

        try store.saveProfiles([.defaultJapanese, english])
        let loaded = try store.loadProfiles()

        XCTAssertEqual(loaded.map(\.displayName), ["日本語 default", "English email"])
        XCTAssertEqual(loaded[1].pasteMode, .pasteThenEnter)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("APIVoiceInputTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
