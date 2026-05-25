import XCTest
@testable import APIVoiceInputCore

final class GroqCleanupProviderTests: XCTestCase {
    func testGroqProviderParsesCleanupResponse() async throws {
        let responseJSON = #"{"choices":[{"message":{"role":"assistant","content":"今日はテストです。"}}]}"#
        let client = MockHTTPClient(response: HTTPResponse(statusCode: 200, data: Data(responseJSON.utf8)))
        let provider = GroqCleanupProvider(apiKey: "groq-key", httpClient: client)

        let text = try await provider.clean(transcript: "えー今日はテストです", prompt: "自然に整えて")

        XCTAssertEqual(text, "今日はテストです。")
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.requests[0].url.absoluteString, "https://api.groq.com/openai/v1/chat/completions")
        XCTAssertEqual(client.requests[0].headers["Authorization"], "Bearer groq-key")
        let json = try JSONSerialization.jsonObject(with: client.requests[0].body) as? [String: Any]
        XCTAssertEqual(json?["model"] as? String, "llama-3.3-70b-versatile")
        let messages = json?["messages"] as? [[String: String]]
        XCTAssertEqual(messages?[0]["content"], "自然に整えて")
        XCTAssertEqual(messages?[1]["content"], "<transcription>えー今日はテストです</transcription>")
    }

    func testGroqProviderMaps429ToRateLimit() async throws {
        let client = MockHTTPClient(response: HTTPResponse(statusCode: 429, data: Data()))
        let provider = GroqCleanupProvider(apiKey: "groq-key", httpClient: client)

        do {
            _ = try await provider.clean(transcript: "hello", prompt: "clean")
            XCTFail("Expected rate limit")
        } catch VoiceInputError.providerRateLimited(let providerID) {
            XCTAssertEqual(providerID, "groq-cleanup")
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
