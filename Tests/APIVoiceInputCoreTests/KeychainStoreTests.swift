import XCTest
@testable import APIVoiceInputCore

final class KeychainStoreTests: XCTestCase {
    func testSaveLoadDeleteAPIKey() throws {
        let account = "test-\(UUID().uuidString)"
        let store = KeychainStore(service: "com.yoshiki.APIVoiceInput.tests")
        try store.saveAPIKey("secret-value", account: account)

        XCTAssertEqual(try store.loadAPIKey(account: account), "secret-value")
        XCTAssertTrue(try store.containsAPIKey(account: account))

        try store.deleteAPIKey(account: account)
        XCTAssertNil(try store.loadAPIKey(account: account))
        XCTAssertFalse(try store.containsAPIKey(account: account))
    }
}
