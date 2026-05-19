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
