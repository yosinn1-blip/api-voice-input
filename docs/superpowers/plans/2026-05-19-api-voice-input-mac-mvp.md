# API Voice Input Mac MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first working macOS voice input loop: menu bar app, one hotkey, microphone recording, minimal bottom overlay, swappable STT/cleanup providers, profile storage, Keychain API key storage, and paste into the foreground app.

**Architecture:** Use a Swift Package with a testable `APIVoiceInputCore` library and an `APIVoiceInputApp` executable. Keep macOS UI/permissions in AppKit-facing adapters, while profiles, provider interfaces, API clients, and pipeline logic stay testable without UI.

**Tech Stack:** Swift 6.3, Swift Package Manager, XCTest, AppKit, AVFoundation, Security.framework Keychain, Carbon hotkeys, URLSession, NSPasteboard, CGEvent.

---

## File structure

Create these files under `/Users/yoshiki/api音声ソフト`:

```text
Package.swift
Sources/APIVoiceInputCore/Profile.swift
Sources/APIVoiceInputCore/ProfileStore.swift
Sources/APIVoiceInputCore/Providers.swift
Sources/APIVoiceInputCore/VoiceInputPipeline.swift
Sources/APIVoiceInputCore/KeychainStore.swift
Sources/APIVoiceInputCore/GroqTranscriptionProvider.swift
Sources/APIVoiceInputCore/GeminiCleanupProvider.swift
Sources/APIVoiceInputCore/PasteController.swift
Sources/APIVoiceInputApp/main.swift
Sources/APIVoiceInputApp/AppDelegate.swift
Sources/APIVoiceInputApp/StatusMenuController.swift
Sources/APIVoiceInputApp/HotkeyController.swift
Sources/APIVoiceInputApp/RecorderController.swift
Sources/APIVoiceInputApp/OverlayWindowController.swift
Sources/APIVoiceInputApp/AppSettings.swift
Tests/APIVoiceInputCoreTests/ProfileStoreTests.swift
Tests/APIVoiceInputCoreTests/VoiceInputPipelineTests.swift
Tests/APIVoiceInputCoreTests/KeychainStoreTests.swift
Tests/APIVoiceInputCoreTests/GroqTranscriptionProviderTests.swift
Tests/APIVoiceInputCoreTests/GeminiCleanupProviderTests.swift
Tests/APIVoiceInputCoreTests/PasteControllerTests.swift
scripts/build-app.sh
Info.plist
```

Responsibility map:

- `Profile.swift`: Codable profile data and defaults.
- `ProfileStore.swift`: load/save profiles as JSON in Application Support.
- `Providers.swift`: provider protocols and shared errors.
- `VoiceInputPipeline.swift`: audio file -> transcription -> cleanup -> final text.
- `KeychainStore.swift`: save/load/delete API keys from Keychain.
- `GroqTranscriptionProvider.swift`: Groq Whisper file transcription.
- `GeminiCleanupProvider.swift`: Gemini text cleanup.
- `PasteController.swift`: clipboard-safe paste and optional Enter.
- `AppDelegate.swift`: app lifecycle, permissions, dependency wiring.
- `StatusMenuController.swift`: menu bar status and manual actions.
- `HotkeyController.swift`: global hotkey registration.
- `RecorderController.swift`: AVAudioRecorder temp-file capture.
- `OverlayWindowController.swift`: minimal lower-screen overlay states.
- `AppSettings.swift`: paths and app constants.
- `scripts/build-app.sh`: build a runnable `.app` bundle with microphone usage description.

---

### Task 1: Swift Package scaffold

**Files:**
- Create: `/Users/yoshiki/api音声ソフト/Package.swift`
- Create: `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputCore/Profile.swift`
- Create: `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputApp/main.swift`
- Create: `/Users/yoshiki/api音声ソフト/Tests/APIVoiceInputCoreTests/ProfileStoreTests.swift`

- [ ] **Step 1: Create package file**

Write `/Users/yoshiki/api音声ソフト/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "APIVoiceInput",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "APIVoiceInputCore", targets: ["APIVoiceInputCore"]),
        .executable(name: "APIVoiceInputApp", targets: ["APIVoiceInputApp"])
    ],
    targets: [
        .target(
            name: "APIVoiceInputCore",
            dependencies: []
        ),
        .executableTarget(
            name: "APIVoiceInputApp",
            dependencies: ["APIVoiceInputCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "APIVoiceInputCoreTests",
            dependencies: ["APIVoiceInputCore"]
        )
    ]
)
```

- [ ] **Step 2: Add the first core model**

Write `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputCore/Profile.swift`:

```swift
import Foundation

public enum PasteMode: String, Codable, Equatable, Sendable {
    case pasteOnly
    case pasteThenEnter
}

public struct VoiceProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var displayName: String
    public var sttLanguageHint: String
    public var transcriptionProviderID: String
    public var cleanupProviderID: String
    public var cleanupPrompt: String
    public var pasteMode: PasteMode

    public init(
        id: UUID = UUID(),
        displayName: String,
        sttLanguageHint: String,
        transcriptionProviderID: String,
        cleanupProviderID: String,
        cleanupPrompt: String,
        pasteMode: PasteMode
    ) {
        self.id = id
        self.displayName = displayName
        self.sttLanguageHint = sttLanguageHint
        self.transcriptionProviderID = transcriptionProviderID
        self.cleanupProviderID = cleanupProviderID
        self.cleanupPrompt = cleanupPrompt
        self.pasteMode = pasteMode
    }

    public static let defaultJapanese = VoiceProfile(
        displayName: "日本語 default",
        sttLanguageHint: "ja",
        transcriptionProviderID: "groq-whisper-large-v3-turbo",
        cleanupProviderID: "none",
        cleanupPrompt: "日本語として自然に整え、意味を変えず、余計な説明を追加しないでください。",
        pasteMode: .pasteOnly
    )
}
```

- [ ] **Step 3: Add a temporary executable entrypoint**

Write `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputApp/main.swift`:

```swift
import APIVoiceInputCore
import Foundation

let profile = VoiceProfile.defaultJapanese
print("APIVoiceInputApp boot: \(profile.displayName)")
```

- [ ] **Step 4: Add the first test**

Write `/Users/yoshiki/api音声ソフト/Tests/APIVoiceInputCoreTests/ProfileStoreTests.swift`:

```swift
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
```

- [ ] **Step 5: Build and test**

Run:

```bash
cd /Users/yoshiki/api音声ソフト
swift test
swift run APIVoiceInputApp
```

Expected:

```text
Test Suite 'All tests' passed
APIVoiceInputApp boot: 日本語 default
```

- [ ] **Step 6: Commit**

```bash
cd /Users/yoshiki/api音声ソフト
git add Package.swift Sources Tests
git commit -m "feat: scaffold Swift voice input app"
```

---

### Task 2: ProfileStore with multiple-profile-ready storage

**Files:**
- Create: `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputCore/ProfileStore.swift`
- Modify: `/Users/yoshiki/api音声ソフト/Tests/APIVoiceInputCoreTests/ProfileStoreTests.swift`

- [ ] **Step 1: Replace profile tests with store tests**

Write `/Users/yoshiki/api音声ソフト/Tests/APIVoiceInputCoreTests/ProfileStoreTests.swift`:

```swift
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
            transcriptionProviderID: "groq-whisper-large-v3-turbo",
            cleanupProviderID: "gemini-free",
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
```

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
cd /Users/yoshiki/api音声ソフト
swift test --filter ProfileStoreTests
```

Expected: FAIL because `ProfileStore` is not defined.

- [ ] **Step 3: Implement ProfileStore**

Write `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputCore/ProfileStore.swift`:

```swift
import Foundation

public final class ProfileStore: Sendable {
    public let directoryURL: URL
    public let fileURL: URL

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
        self.fileURL = directoryURL.appendingPathComponent("profiles.json")
    }

    public func loadProfiles() throws -> [VoiceProfile] {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let defaults = [VoiceProfile.defaultJapanese]
            try saveProfiles(defaults)
            return defaults
        }
        let data = try Data(contentsOf: fileURL)
        let profiles = try JSONDecoder().decode([VoiceProfile].self, from: data)
        return profiles.isEmpty ? [VoiceProfile.defaultJapanese] : profiles
    }

    public func saveProfiles(_ profiles: [VoiceProfile]) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder.prettySorted.encode(profiles)
        try data.write(to: fileURL, options: [.atomic])
    }
}

private extension JSONEncoder {
    static var prettySorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
```

- [ ] **Step 4: Run test and verify pass**

Run:

```bash
cd /Users/yoshiki/api音声ソフト
swift test --filter ProfileStoreTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/yoshiki/api音声ソフト
git add Sources/APIVoiceInputCore/ProfileStore.swift Tests/APIVoiceInputCoreTests/ProfileStoreTests.swift
git commit -m "feat: add profile storage"
```

---

### Task 3: Provider protocols and pipeline

**Files:**
- Create: `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputCore/Providers.swift`
- Create: `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputCore/VoiceInputPipeline.swift`
- Create: `/Users/yoshiki/api音声ソフト/Tests/APIVoiceInputCoreTests/VoiceInputPipelineTests.swift`

- [ ] **Step 1: Write pipeline tests**

Write `/Users/yoshiki/api音声ソフト/Tests/APIVoiceInputCoreTests/VoiceInputPipelineTests.swift`:

```swift
import XCTest
@testable import APIVoiceInputCore

final class VoiceInputPipelineTests: XCTestCase {
    func testPipelineTranscribesCleansAndReturnsFinalText() async throws {
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("voice.m4a")
        try Data("fake".utf8).write(to: audioURL)
        let transcription = MockTranscriptionProvider(result: "えー今日はテストです")
        let cleanup = MockCleanupProvider(result: "今日はテストです。")
        let pipeline = VoiceInputPipeline(transcriptionProvider: transcription, cleanupProvider: cleanup)

        let result = try await pipeline.run(audioFileURL: audioURL, profile: .defaultJapanese)

        XCTAssertEqual(result.rawTranscript, "えー今日はテストです")
        XCTAssertEqual(result.finalText, "今日はテストです。")
        XCTAssertEqual(transcription.receivedLanguageHint, "ja")
        XCTAssertEqual(cleanup.receivedPrompt, VoiceProfile.defaultJapanese.cleanupPrompt)
    }

    func testPipelineUsesRawTranscriptWhenCleanupProviderIsNone() async throws {
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("voice-none.m4a")
        try Data("fake".utf8).write(to: audioURL)
        let transcription = MockTranscriptionProvider(result: "そのまま貼ります")
        let pipeline = VoiceInputPipeline(transcriptionProvider: transcription, cleanupProvider: NoCleanupProvider())

        let result = try await pipeline.run(audioFileURL: audioURL, profile: .defaultJapanese)

        XCTAssertEqual(result.rawTranscript, "そのまま貼ります")
        XCTAssertEqual(result.finalText, "そのまま貼ります")
    }

    func testEmptyTranscriptFailsBeforeCleanup() async throws {
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("voice-empty.m4a")
        try Data("fake".utf8).write(to: audioURL)
        let transcription = MockTranscriptionProvider(result: "   ")
        let cleanup = MockCleanupProvider(result: "unused")
        let pipeline = VoiceInputPipeline(transcriptionProvider: transcription, cleanupProvider: cleanup)

        do {
            _ = try await pipeline.run(audioFileURL: audioURL, profile: .defaultJapanese)
            XCTFail("Expected emptyTranscript")
        } catch VoiceInputError.emptyTranscript {
            XCTAssertEqual(cleanup.callCount, 0)
        }
    }
}

private final class MockTranscriptionProvider: TranscriptionProvider, @unchecked Sendable {
    let id = "mock-stt"
    let result: String
    var receivedLanguageHint: String?

    init(result: String) {
        self.result = result
    }

    func transcribe(audioFileURL: URL, languageHint: String) async throws -> String {
        receivedLanguageHint = languageHint
        return result
    }
}

private final class MockCleanupProvider: CleanupProvider, @unchecked Sendable {
    let id = "mock-cleanup"
    let result: String
    var receivedPrompt: String?
    var callCount = 0

    init(result: String) {
        self.result = result
    }

    func clean(transcript: String, prompt: String) async throws -> String {
        callCount += 1
        receivedPrompt = prompt
        return result
    }
}
```

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
cd /Users/yoshiki/api音声ソフト
swift test --filter VoiceInputPipelineTests
```

Expected: FAIL because provider protocols and pipeline are not defined.

- [ ] **Step 3: Implement provider protocols**

Write `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputCore/Providers.swift`:

```swift
import Foundation

public enum VoiceInputError: Error, Equatable, LocalizedError, Sendable {
    case emptyTranscript
    case emptyCleanedText
    case providerRateLimited(String)
    case providerFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyTranscript:
            return "音声認識結果が空でした。"
        case .emptyCleanedText:
            return "清書結果が空でした。"
        case .providerRateLimited(let provider):
            return "\(provider) の無料枠またはレート制限に達しました。"
        case .providerFailed(let message):
            return message
        }
    }
}

public protocol TranscriptionProvider: Sendable {
    var id: String { get }
    func transcribe(audioFileURL: URL, languageHint: String) async throws -> String
}

public protocol CleanupProvider: Sendable {
    var id: String { get }
    func clean(transcript: String, prompt: String) async throws -> String
}

public struct NoCleanupProvider: CleanupProvider {
    public let id = "none"

    public init() {}

    public func clean(transcript: String, prompt: String) async throws -> String {
        transcript
    }
}
```

- [ ] **Step 4: Implement pipeline**

Write `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputCore/VoiceInputPipeline.swift`:

```swift
import Foundation

public struct VoiceInputResult: Equatable, Sendable {
    public let rawTranscript: String
    public let finalText: String

    public init(rawTranscript: String, finalText: String) {
        self.rawTranscript = rawTranscript
        self.finalText = finalText
    }
}

public final class VoiceInputPipeline: Sendable {
    private let transcriptionProvider: any TranscriptionProvider
    private let cleanupProvider: any CleanupProvider

    public init(transcriptionProvider: any TranscriptionProvider, cleanupProvider: any CleanupProvider) {
        self.transcriptionProvider = transcriptionProvider
        self.cleanupProvider = cleanupProvider
    }

    public func run(audioFileURL: URL, profile: VoiceProfile) async throws -> VoiceInputResult {
        let transcript = try await transcriptionProvider
            .transcribe(audioFileURL: audioFileURL, languageHint: profile.sttLanguageHint)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard transcript.isEmpty == false else {
            throw VoiceInputError.emptyTranscript
        }

        let cleaned = try await cleanupProvider
            .clean(transcript: transcript, prompt: profile.cleanupPrompt)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty == false else {
            throw VoiceInputError.emptyCleanedText
        }

        return VoiceInputResult(rawTranscript: transcript, finalText: cleaned)
    }
}
```

- [ ] **Step 5: Run tests and verify pass**

Run:

```bash
cd /Users/yoshiki/api音声ソフト
swift test --filter VoiceInputPipelineTests
swift test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /Users/yoshiki/api音声ソフト
git add Sources/APIVoiceInputCore/Providers.swift Sources/APIVoiceInputCore/VoiceInputPipeline.swift Tests/APIVoiceInputCoreTests/VoiceInputPipelineTests.swift
git commit -m "feat: add voice input pipeline"
```

---

### Task 4: Keychain-backed API key storage

**Files:**
- Create: `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputCore/KeychainStore.swift`
- Create: `/Users/yoshiki/api音声ソフト/Tests/APIVoiceInputCoreTests/KeychainStoreTests.swift`

- [ ] **Step 1: Write Keychain tests**

Write `/Users/yoshiki/api音声ソフト/Tests/APIVoiceInputCoreTests/KeychainStoreTests.swift`:

```swift
import XCTest
@testable import APIVoiceInputCore

final class KeychainStoreTests: XCTestCase {
    func testSaveLoadDeleteAPIKey() throws {
        let account = "test-\(UUID().uuidString)"
        let store = KeychainStore(service: "com.yoshiki.APIVoiceInput.tests")
        try store.saveAPIKey("secret-value", account: account)

        XCTAssertEqual(try store.loadAPIKey(account: account), "secret-value")

        try store.deleteAPIKey(account: account)
        XCTAssertNil(try store.loadAPIKey(account: account))
    }
}
```

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
cd /Users/yoshiki/api音声ソフト
swift test --filter KeychainStoreTests
```

Expected: FAIL because `KeychainStore` is not defined.

- [ ] **Step 3: Implement KeychainStore**

Write `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputCore/KeychainStore.swift`:

```swift
import Foundation
import Security

public enum KeychainStoreError: Error, Equatable, Sendable {
    case encodingFailed
    case unexpectedStatus(OSStatus)
}

public final class KeychainStore: Sendable {
    private let service: String

    public init(service: String = "com.yoshiki.APIVoiceInput") {
        self.service = service
    }

    public func saveAPIKey(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainStoreError.encodingFailed
        }
        try deleteAPIKey(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    public func loadAPIKey(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
        guard let data = item as? Data else {
            throw KeychainStoreError.encodingFailed
        }
        return String(data: data, encoding: .utf8)
    }

    public func deleteAPIKey(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }
}
```

- [ ] **Step 4: Run test and verify pass**

Run:

```bash
cd /Users/yoshiki/api音声ソフト
swift test --filter KeychainStoreTests
```

Expected: PASS. If macOS asks for Keychain access in a test run, allow the test key for the test service only.

- [ ] **Step 5: Commit**

```bash
cd /Users/yoshiki/api音声ソフト
git add Sources/APIVoiceInputCore/KeychainStore.swift Tests/APIVoiceInputCoreTests/KeychainStoreTests.swift
git commit -m "feat: store API keys in Keychain"
```

---

### Task 5: Clipboard-safe PasteController

**Files:**
- Create: `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputCore/PasteController.swift`
- Create: `/Users/yoshiki/api音声ソフト/Tests/APIVoiceInputCoreTests/PasteControllerTests.swift`

- [ ] **Step 1: Write PasteController tests with mocks**

Write `/Users/yoshiki/api音声ソフト/Tests/APIVoiceInputCoreTests/PasteControllerTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
cd /Users/yoshiki/api音声ソフト
swift test --filter PasteControllerTests
```

Expected: FAIL because paste types are not defined.

- [ ] **Step 3: Implement PasteController**

Write `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputCore/PasteController.swift`:

```swift
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
```

- [ ] **Step 4: Run tests and verify pass**

Run:

```bash
cd /Users/yoshiki/api音声ソフト
swift test --filter PasteControllerTests
swift test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/yoshiki/api音声ソフト
git add Sources/APIVoiceInputCore/PasteController.swift Tests/APIVoiceInputCoreTests/PasteControllerTests.swift
git commit -m "feat: add paste controller"
```

---

### Task 6: API provider clients with mocked URLSession

**Files:**
- Create: `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputCore/GroqTranscriptionProvider.swift`
- Create: `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputCore/GeminiCleanupProvider.swift`
- Create: `/Users/yoshiki/api音声ソフト/Tests/APIVoiceInputCoreTests/GroqTranscriptionProviderTests.swift`
- Create: `/Users/yoshiki/api音声ソフト/Tests/APIVoiceInputCoreTests/GeminiCleanupProviderTests.swift`

- [ ] **Step 1: Add Groq provider tests**

Write `/Users/yoshiki/api音声ソフト/Tests/APIVoiceInputCoreTests/GroqTranscriptionProviderTests.swift`:

```swift
import XCTest
@testable import APIVoiceInputCore

final class GroqTranscriptionProviderTests: XCTestCase {
    func testGroqProviderParsesTextResponse() async throws {
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("groq-test.wav")
        try Data("audio".utf8).write(to: audioURL)
        let client = MockHTTPClient(response: HTTPResponse(statusCode: 200, data: Data(#"{"text":"こんにちは。"}"#.utf8)))
        let provider = GroqTranscriptionProvider(apiKey: "test-key", httpClient: client)

        let text = try await provider.transcribe(audioFileURL: audioURL, languageHint: "ja")

        XCTAssertEqual(text, "こんにちは。")
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.requests[0].url.absoluteString, "https://api.groq.com/openai/v1/audio/transcriptions")
        XCTAssertEqual(client.requests[0].headers["Authorization"], "Bearer test-key")
        XCTAssertTrue(client.requests[0].body.contains(Data("whisper-large-v3-turbo".utf8)))
    }

    func testGroqProviderMaps429ToRateLimit() async throws {
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("groq-429.wav")
        try Data("audio".utf8).write(to: audioURL)
        let client = MockHTTPClient(response: HTTPResponse(statusCode: 429, data: Data()))
        let provider = GroqTranscriptionProvider(apiKey: "test-key", httpClient: client)

        do {
            _ = try await provider.transcribe(audioFileURL: audioURL, languageHint: "ja")
            XCTFail("Expected rate limit")
        } catch VoiceInputError.providerRateLimited(let providerID) {
            XCTAssertEqual(providerID, "groq")
        }
    }
}
```

- [ ] **Step 2: Add Gemini provider tests and shared mocks**

Write `/Users/yoshiki/api音声ソフト/Tests/APIVoiceInputCoreTests/GeminiCleanupProviderTests.swift`:

```swift
import XCTest
@testable import APIVoiceInputCore

final class GeminiCleanupProviderTests: XCTestCase {
    func testGeminiProviderParsesCleanupResponse() async throws {
        let responseJSON = #"{"candidates":[{"content":{"parts":[{"text":"今日はテストです。"}]}}]}"#
        let client = MockHTTPClient(response: HTTPResponse(statusCode: 200, data: Data(responseJSON.utf8)))
        let provider = GeminiCleanupProvider(apiKey: "gemini-key", httpClient: client)

        let text = try await provider.clean(transcript: "えー今日はテストです", prompt: "自然に整えて")

        XCTAssertEqual(text, "今日はテストです。")
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertTrue(client.requests[0].url.absoluteString.contains("generativelanguage.googleapis.com"))
        XCTAssertTrue(client.requests[0].body.contains(Data("自然に整えて".utf8)))
        XCTAssertTrue(client.requests[0].body.contains(Data("えー今日はテストです".utf8)))
    }

    func testGeminiProviderMaps429ToRateLimit() async throws {
        let client = MockHTTPClient(response: HTTPResponse(statusCode: 429, data: Data()))
        let provider = GeminiCleanupProvider(apiKey: "gemini-key", httpClient: client)

        do {
            _ = try await provider.clean(transcript: "hello", prompt: "clean")
            XCTFail("Expected rate limit")
        } catch VoiceInputError.providerRateLimited(let providerID) {
            XCTAssertEqual(providerID, "gemini")
        }
    }
}

struct HTTPResponse: Sendable {
    let statusCode: Int
    let data: Data
}

struct HTTPRequestRecord: Sendable {
    let url: URL
    let method: String
    let headers: [String: String]
    let body: Data
}

final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    let response: HTTPResponse
    private(set) var requests: [HTTPRequestRecord] = []

    init(response: HTTPResponse) {
        self.response = response
    }

    func send(url: URL, method: String, headers: [String: String], body: Data) async throws -> HTTPResponse {
        requests.append(HTTPRequestRecord(url: url, method: method, headers: headers, body: body))
        return response
    }
}
```

- [ ] **Step 3: Run provider tests and verify failure**

Run:

```bash
cd /Users/yoshiki/api音声ソフト
swift test --filter GroqTranscriptionProviderTests
swift test --filter GeminiCleanupProviderTests
```

Expected: FAIL because API provider types are not defined.

- [ ] **Step 4: Implement Groq provider and shared HTTP client**

Write `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputCore/GroqTranscriptionProvider.swift`:

```swift
import Foundation

public struct HTTPResponse: Sendable {
    public let statusCode: Int
    public let data: Data

    public init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }
}

public protocol HTTPClient: Sendable {
    func send(url: URL, method: String, headers: [String: String], body: Data) async throws -> HTTPResponse
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}

    public func send(url: URL, method: String, headers: [String: String], body: Data) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return HTTPResponse(statusCode: statusCode, data: data)
    }
}

public struct GroqTranscriptionProvider: TranscriptionProvider {
    public let id = "groq-whisper-large-v3-turbo"
    private let apiKey: String
    private let httpClient: any HTTPClient

    public init(apiKey: String, httpClient: any HTTPClient = URLSessionHTTPClient()) {
        self.apiKey = apiKey
        self.httpClient = httpClient
    }

    public func transcribe(audioFileURL: URL, languageHint: String) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = try multipartBody(audioFileURL: audioFileURL, languageHint: languageHint, boundary: boundary)
        let response = try await httpClient.send(
            url: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!,
            method: "POST",
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Content-Type": "multipart/form-data; boundary=\(boundary)"
            ],
            body: body
        )
        if response.statusCode == 429 {
            throw VoiceInputError.providerRateLimited("groq")
        }
        guard (200..<300).contains(response.statusCode) else {
            throw VoiceInputError.providerFailed("Groq transcription failed with HTTP \(response.statusCode).")
        }
        let decoded = try JSONDecoder().decode(GroqTranscriptionResponse.self, from: response.data)
        return decoded.text
    }

    private func multipartBody(audioFileURL: URL, languageHint: String, boundary: String) throws -> Data {
        var data = Data()
        func append(_ string: String) {
            data.append(Data(string.utf8))
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("whisper-large-v3-turbo\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
        append("\(languageHint)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n")
        append("Content-Type: audio/m4a\r\n\r\n")
        data.append(try Data(contentsOf: audioFileURL))
        append("\r\n--\(boundary)--\r\n")
        return data
    }
}

private struct GroqTranscriptionResponse: Decodable {
    let text: String
}
```

- [ ] **Step 5: Implement Gemini cleanup provider**

Write `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputCore/GeminiCleanupProvider.swift`:

```swift
import Foundation

public struct GeminiCleanupProvider: CleanupProvider {
    public let id = "gemini-free"
    private let apiKey: String
    private let httpClient: any HTTPClient
    private let model: String

    public init(apiKey: String, model: String = "gemini-2.5-flash", httpClient: any HTTPClient = URLSessionHTTPClient()) {
        self.apiKey = apiKey
        self.model = model
        self.httpClient = httpClient
    }

    public func clean(transcript: String, prompt: String) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        let request = GeminiGenerateContentRequest(contents: [
            GeminiContent(parts: [
                GeminiPart(text: "\(prompt)\n\n入力:\n\(transcript)")
            ])
        ])
        let body = try JSONEncoder().encode(request)
        let response = try await httpClient.send(
            url: url,
            method: "POST",
            headers: ["Content-Type": "application/json"],
            body: body
        )
        if response.statusCode == 429 {
            throw VoiceInputError.providerRateLimited("gemini")
        }
        guard (200..<300).contains(response.statusCode) else {
            throw VoiceInputError.providerFailed("Gemini cleanup failed with HTTP \(response.statusCode).")
        }
        let decoded = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: response.data)
        return decoded.candidates.first?.content.parts.first?.text ?? ""
    }
}

private struct GeminiGenerateContentRequest: Encodable {
    let contents: [GeminiContent]
}

private struct GeminiContent: Codable {
    let parts: [GeminiPart]
}

private struct GeminiPart: Codable {
    let text: String
}

private struct GeminiGenerateContentResponse: Decodable {
    let candidates: [GeminiCandidate]
}

private struct GeminiCandidate: Decodable {
    let content: GeminiContent
}
```

- [ ] **Step 6: Remove duplicate test-only HTTPResponse definition**

Edit `/Users/yoshiki/api音声ソフト/Tests/APIVoiceInputCoreTests/GeminiCleanupProviderTests.swift` and remove the test-only `HTTPResponse` struct. Keep `HTTPRequestRecord` and `MockHTTPClient`.

The bottom of the file should be:

```swift
struct HTTPRequestRecord: Sendable {
    let url: URL
    let method: String
    let headers: [String: String]
    let body: Data
}

final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    let response: HTTPResponse
    private(set) var requests: [HTTPRequestRecord] = []

    init(response: HTTPResponse) {
        self.response = response
    }

    func send(url: URL, method: String, headers: [String: String], body: Data) async throws -> HTTPResponse {
        requests.append(HTTPRequestRecord(url: url, method: method, headers: headers, body: body))
        return response
    }
}
```

- [ ] **Step 7: Run tests and verify pass**

Run:

```bash
cd /Users/yoshiki/api音声ソフト
swift test --filter GroqTranscriptionProviderTests
swift test --filter GeminiCleanupProviderTests
swift test
```

Expected: PASS. No real API calls are made.

- [ ] **Step 8: Commit**

```bash
cd /Users/yoshiki/api音声ソフト
git add Sources/APIVoiceInputCore/GroqTranscriptionProvider.swift Sources/APIVoiceInputCore/GeminiCleanupProvider.swift Tests/APIVoiceInputCoreTests/GroqTranscriptionProviderTests.swift Tests/APIVoiceInputCoreTests/GeminiCleanupProviderTests.swift
git commit -m "feat: add free tier API providers"
```

---

### Task 7: AppKit menu bar app, hotkey, recording, overlay, and paste adapters

**Files:**
- Replace: `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputApp/main.swift`
- Create: `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputApp/AppSettings.swift`
- Create: `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputApp/AppDelegate.swift`
- Create: `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputApp/StatusMenuController.swift`
- Create: `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputApp/HotkeyController.swift`
- Create: `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputApp/RecorderController.swift`
- Create: `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputApp/OverlayWindowController.swift`
- Modify: `/Users/yoshiki/api音声ソフト/Package.swift`

- [ ] **Step 1: Add AppSettings**

Write `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputApp/AppSettings.swift`:

```swift
import Foundation

struct AppSettings {
    static let bundleIdentifier = "com.yoshiki.APIVoiceInput"
    static let appName = "API音声ソフト"
    static let groqKeyAccount = "groq-api-key"
    static let geminiKeyAccount = "gemini-api-key"

    static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("APIVoiceInput", isDirectory: true)
    }
}
```

- [ ] **Step 2: Add overlay controller**

Write `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputApp/OverlayWindowController.swift`:

```swift
import AppKit

@MainActor
final class OverlayWindowController {
    enum State: String {
        case recording = "録音中"
        case transcribing = "文字起こし中"
        case cleaning = "清書中"
        case pasted = "貼り付けました"
        case failed = "失敗しました"
    }

    private let window: NSWindow
    private let label: NSTextField

    init() {
        label = NSTextField(labelWithString: "")
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSVisualEffectView()
        contentView.material = .hudWindow
        contentView.blendingMode = .behindWindow
        contentView.state = .active
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 18
        contentView.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 9),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -9)
        ])

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 42),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = contentView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func show(_ state: State, detail: String? = nil) {
        label.stringValue = detail.map { "\(state.rawValue) · \($0)" } ?? state.rawValue
        positionWindow()
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
    }

    private func positionWindow() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width: CGFloat = 260
        let height: CGFloat = 42
        let x = screen.midX - width / 2
        let y = screen.minY + 36
        window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}
```

- [ ] **Step 3: Add recorder controller**

Write `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputApp/RecorderController.swift`:

```swift
import AVFoundation
import Foundation

final class RecorderController: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private(set) var currentURL: URL?

    func startRecording() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("APIVoiceInput-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.prepareToRecord()
        recorder.record()
        self.recorder = recorder
        self.currentURL = url
        return url
    }

    func stopRecording() -> URL? {
        recorder?.stop()
        recorder = nil
        return currentURL
    }
}
```

- [ ] **Step 4: Add hotkey controller**

Write `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputApp/HotkeyController.swift`:

```swift
import Carbon
import Foundation

final class HotkeyController {
    private var hotKeyRef: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let onPressed: @Sendable () -> Void

    init(onPressed: @escaping @Sendable () -> Void) {
        self.onPressed = onPressed
    }

    func registerCommandShiftSpace() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let controller = Unmanaged<HotkeyController>.fromOpaque(userData).takeUnretainedValue()
            controller.onPressed()
            return noErr
        }, 1, &eventType, selfPointer, &handler)

        let hotKeyID = EventHotKeyID(signature: OSType(0x4156494E), id: 1)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey | shiftKey), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let handler {
            RemoveEventHandler(handler)
        }
    }
}
```

- [ ] **Step 5: Add status menu**

Write `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputApp/StatusMenuController.swift`:

```swift
import AppKit

@MainActor
final class StatusMenuController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let toggleAction: () -> Void

    init(toggleAction: @escaping () -> Void) {
        self.toggleAction = toggleAction
        item.button?.title = "🎙"
        let toggle = NSMenuItem(title: "録音開始/停止", action: #selector(toggleRecording), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    @objc private func toggleRecording() {
        toggleAction()
    }
}
```

- [ ] **Step 6: Add AppDelegate wiring with disabled cleanup default**

Write `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputApp/AppDelegate.swift`:

```swift
import APIVoiceInputCore
import AppKit
import AVFoundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusMenu: StatusMenuController?
    private var hotkeyController: HotkeyController?
    private let overlay = OverlayWindowController()
    private let recorder = RecorderController()
    private let keychain = KeychainStore()
    private var isRecording = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusMenu = StatusMenuController { [weak self] in
            self?.toggleRecording()
        }
        hotkeyController = HotkeyController { [weak self] in
            Task { @MainActor in self?.toggleRecording() }
        }
        hotkeyController?.registerCommandShiftSpace()
        requestMicrophonePermission()
    }

    private func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if granted == false {
                Task { @MainActor in
                    self.overlay.show(.failed, detail: "マイク権限が必要です")
                }
            }
        }
    }

    private func toggleRecording() {
        if isRecording {
            finishRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        do {
            _ = try recorder.startRecording()
            isRecording = true
            overlay.show(.recording, detail: "⌘⇧Spaceで停止")
        } catch {
            overlay.show(.failed, detail: error.localizedDescription)
        }
    }

    private func finishRecording() {
        guard let audioURL = recorder.stopRecording() else {
            isRecording = false
            overlay.show(.failed, detail: "録音ファイルなし")
            return
        }
        isRecording = false
        overlay.show(.transcribing)
        Task {
            await process(audioURL: audioURL)
        }
    }

    private func process(audioURL: URL) async {
        do {
            let groqKey = try keychain.loadAPIKey(account: AppSettings.groqKeyAccount)
            guard let groqKey, groqKey.isEmpty == false else {
                overlay.show(.failed, detail: "Groq API key未設定")
                return
            }
            let profile = VoiceProfile.defaultJapanese
            let transcription = GroqTranscriptionProvider(apiKey: groqKey)
            let pipeline = VoiceInputPipeline(transcriptionProvider: transcription, cleanupProvider: NoCleanupProvider())
            let result = try await pipeline.run(audioFileURL: audioURL, profile: profile)
            let paste = PasteController(clipboard: SystemClipboardClient(), keyboard: SystemKeyboardClient())
            try paste.paste(result.finalText, mode: profile.pasteMode)
            overlay.show(.pasted)
            try? FileManager.default.removeItem(at: audioURL)
            try? await Task.sleep(nanoseconds: 900_000_000)
            overlay.hide()
        } catch {
            overlay.show(.failed, detail: error.localizedDescription)
        }
    }
}

struct SystemClipboardClient: ClipboardClient {
    func readString() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    func writeString(_ string: String) throws {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

struct SystemKeyboardClient: KeyboardClient {
    func sendPaste() throws {
        sendKey(keyCode: 9, flags: .maskCommand)
    }

    func sendEnter() throws {
        sendKey(keyCode: 36, flags: [])
    }

    private func sendKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 7: Replace executable entrypoint**

Write `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputApp/main.swift`:

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 8: Add CoreGraphics linker setting**

Modify `/Users/yoshiki/api音声ソフト/Package.swift` so the `APIVoiceInputApp` linker settings include `CoreGraphics`:

```swift
linkerSettings: [
    .linkedFramework("AppKit"),
    .linkedFramework("AVFoundation"),
    .linkedFramework("Carbon"),
    .linkedFramework("Security"),
    .linkedFramework("CoreGraphics")
]
```

- [ ] **Step 9: Build and run tests**

Run:

```bash
cd /Users/yoshiki/api音声ソフト
swift test
swift build
```

Expected: PASS and build succeeds.

- [ ] **Step 10: Commit**

```bash
cd /Users/yoshiki/api音声ソフト
git add Package.swift Sources/APIVoiceInputApp
git commit -m "feat: add mac menu bar voice input shell"
```

---

### Task 8: App bundle script, Info.plist, API key setup, and manual verification

**Files:**
- Create: `/Users/yoshiki/api音声ソフト/Info.plist`
- Create: `/Users/yoshiki/api音声ソフト/scripts/build-app.sh`
- Modify: `/Users/yoshiki/api音声ソフト/docs/superpowers/specs/2026-05-19-api-voice-input-mac-design.md`

- [ ] **Step 1: Add app Info.plist**

Write `/Users/yoshiki/api音声ソフト/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.yoshiki.APIVoiceInput</string>
  <key>CFBundleName</key>
  <string>API音声ソフト</string>
  <key>CFBundleExecutable</key>
  <string>APIVoiceInputApp</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>音声入力のためにマイクを使用します。</string>
</dict>
</plist>
```

- [ ] **Step 2: Add build script**

Write `/Users/yoshiki/api音声ソフト/scripts/build-app.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/build/API音声ソフト.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

cd "$ROOT"
swift build -c debug --product APIVoiceInputApp
rm -rf "$APP_DIR"
mkdir -p "$MACOS"
cp "$ROOT/.build/debug/APIVoiceInputApp" "$MACOS/APIVoiceInputApp"
cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
chmod +x "$MACOS/APIVoiceInputApp"
/usr/bin/codesign --force --sign - "$APP_DIR"
echo "$APP_DIR"
```

- [ ] **Step 3: Make script executable and build app**

Run:

```bash
cd /Users/yoshiki/api音声ソフト
chmod +x scripts/build-app.sh
./scripts/build-app.sh
```

Expected:

```text
/Users/yoshiki/api音声ソフト/build/API音声ソフト.app
```

- [ ] **Step 4: Add temporary API key through Keychain without echoing the key**

Run this only when the user is ready to test real Groq transcription:

```bash
osascript -e 'display dialog "Groq API keyを入力してください" default answer "" with hidden answer buttons {"Cancel", "OK"} default button "OK"' \
  -e 'text returned of result' | \
security add-generic-password -U -s com.yoshiki.APIVoiceInput -a groq-api-key -w
```

Expected: the key is stored in Keychain and not printed to terminal.

- [ ] **Step 5: Launch the app for manual verification**

Run:

```bash
cd /Users/yoshiki/api音声ソフト
open build/API音声ソフト.app
```

Manual checks:

```text
1. macOS asks for microphone permission; allow it.
2. Open TextEdit and click into a blank document.
3. Press Command+Shift+Space.
4. Confirm the lower overlay says 録音中.
5. Say: 今日は音声入力のテストです。
6. Press Command+Shift+Space again.
7. Confirm text is pasted into TextEdit.
8. Confirm generated text remains recoverable in clipboard if paste fails.
9. Confirm no paid provider is used.
```

- [ ] **Step 6: Document first-run verification status in the design spec**

Append this section to `/Users/yoshiki/api音声ソフト/docs/superpowers/specs/2026-05-19-api-voice-input-mac-design.md` after manual verification:

```markdown
## MVP first-run verification

- Build command: `./scripts/build-app.sh`
- App path: `/Users/yoshiki/api音声ソフト/build/API音声ソフト.app`
- Manual target: TextEdit blank document
- Verified flow: hotkey -> recording overlay -> stop -> Groq STT -> paste
- Paid fallback: not enabled
- Known remaining work: cleanup provider UI, profile editor UI, YouTube automation hook UI
```

- [ ] **Step 7: Run final checks**

Run:

```bash
cd /Users/yoshiki/api音声ソフト
swift test
swift build
plutil -lint Info.plist
codesign --verify --deep --strict build/API音声ソフト.app
```

Expected: all pass.

- [ ] **Step 8: Commit**

```bash
cd /Users/yoshiki/api音声ソフト
git add Info.plist scripts/build-app.sh docs/superpowers/specs/2026-05-19-api-voice-input-mac-design.md
git commit -m "feat: package first voice input app bundle"
```

---

## Self-review

Spec coverage:

- Menu bar app: Task 7.
- One hotkey: Task 7.
- Microphone recording: Task 7.
- Minimal bottom overlay: Task 7.
- One STT provider: Task 6 and Task 8.
- Optional cleanup disabled by default plus provider interface: Task 3 and Task 6.
- Paste into foreground app: Task 5 and Task 7.
- Default profile and future multiple profiles: Task 2.
- Keychain API key storage: Task 4 and Task 8.
- Free-tier safety: Task 3 provider errors, Task 6 429 mapping, Task 8 manual verification.
- YouTube future extension point: design spec has `AutomationHooks`; first code slice does not expose hook UI because it is outside the first working loop.

Placeholder scan:

- No unresolved placeholder markers.
- No unresolved task markers.
- Each task has concrete files, code, commands, and expected results.

Type consistency:

- `VoiceProfile`, `PasteMode`, `ProfileStore`, `TranscriptionProvider`, `CleanupProvider`, `NoCleanupProvider`, `VoiceInputPipeline`, `KeychainStore`, `PasteController`, `GroqTranscriptionProvider`, and `GeminiCleanupProvider` names are consistent across tests and implementation steps.
