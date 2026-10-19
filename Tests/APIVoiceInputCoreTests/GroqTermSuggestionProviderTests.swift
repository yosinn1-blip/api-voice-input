import XCTest
@testable import APIVoiceInputCore

final class GroqTermSuggestionProviderTests: XCTestCase {
    private func reply(_ content: String) -> HTTPResponse {
        let envelope: [String: Any] = ["choices": [["message": ["role": "assistant", "content": content]]]]
        // 失敗しないはずの変換なので try! ではなく空データにして、テスト側で気づけるようにする
        let data = (try? JSONSerialization.data(withJSONObject: envelope)) ?? Data()
        return HTTPResponse(statusCode: 200, data: data)
    }

    func testSendsTheTextsAndKnownTermsToGroq() async throws {
        let client = MockHTTPClient(response: reply(#"{"items":[]}"#))
        let provider = GroqTermSuggestionProvider(apiKey: "groq-key", httpClient: client)

        _ = try await provider.suggest(
            texts: ["オブシリアンにメモした", "今日は晴れです"],
            knownTerms: ["Obsidian", "Groq"]
        )

        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.requests[0].url.absoluteString, "https://api.groq.com/openai/v1/chat/completions")
        XCTAssertEqual(client.requests[0].method, "POST")
        XCTAssertEqual(client.requests[0].headers["Authorization"], "Bearer groq-key")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: client.requests[0].body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "openai/gpt-oss-120b")
        XCTAssertEqual(json["temperature"] as? Int, 0)
        XCTAssertEqual(json["reasoning_effort"] as? String, "low")
        XCTAssertEqual(json["include_reasoning"] as? Bool, false)
        XCTAssertEqual((json["response_format"] as? [String: String])?["type"], "json_object")
        XCTAssertGreaterThanOrEqual(json["max_tokens"] as? Int ?? 0, 1000)
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertEqual(messages[0]["content"], GroqTermSuggestionProvider.systemPrompt)
        XCTAssertEqual(messages[1]["role"], "user")
        XCTAssertEqual(
            messages[1]["content"],
            "辞書にある正しい語（参考）: Obsidian, Groq\n文章:\n1. オブシリアンにメモした\n2. 今日は晴れです"
        )
    }

    func testTellsTheAIWhenThereAreNoKnownTerms() async throws {
        let client = MockHTTPClient(response: reply(#"{"items":[]}"#))
        let provider = GroqTermSuggestionProvider(apiKey: "groq-key", httpClient: client)

        _ = try await provider.suggest(texts: ["今日は晴れです"], knownTerms: [])

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: client.requests[0].body) as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages[1]["content"], "辞書にある正しい語（参考）: （なし）\n文章:\n1. 今日は晴れです")
    }

    func testReadsSuggestionsAndWhetherTheAIWasSure() async throws {
        let content = #"{"items":[{"wrong":"オブシリアン","correct":"Obsidian","confidence":"high"},{"wrong":"Glog","correct":"Groq","confidence":"low"}]}"#
        let provider = GroqTermSuggestionProvider(apiKey: "k", httpClient: MockHTTPClient(response: reply(content)))

        let suggestions = try await provider.suggest(texts: ["x"], knownTerms: [])

        XCTAssertEqual(suggestions, [
            TermSuggestion(wrong: "オブシリアン", correct: "Obsidian", isConfident: true),
            TermSuggestion(wrong: "Glog", correct: "Groq", isConfident: false)
        ])
    }

    func testReadsAnswersWrappedInCodeFencesOrPreface() async throws {
        let wrapped = "結果です。\n```json\n{\"items\":[{\"wrong\":\"オブシリアン\",\"correct\":\"Obsidian\",\"confidence\":\"high\"}]}\n```"
        let provider = GroqTermSuggestionProvider(apiKey: "k", httpClient: MockHTTPClient(response: reply(wrapped)))

        let suggestions = try await provider.suggest(texts: ["x"], knownTerms: [])

        XCTAssertEqual(suggestions.map(\.correct), ["Obsidian"])
    }

    func testSkipsItemsThatAreMissingFieldsAndTreatsMissingConfidenceAsNotSure() async throws {
        let content = #"{"items":[{"wrong":"オブシリアン"},{"correct":"Obsidian"},{"wrong":"ソニョックス","correct":"Soniox"}]}"#
        let provider = GroqTermSuggestionProvider(apiKey: "k", httpClient: MockHTTPClient(response: reply(content)))

        let suggestions = try await provider.suggest(texts: ["x"], knownTerms: [])

        XCTAssertEqual(suggestions, [TermSuggestion(wrong: "ソニョックス", correct: "Soniox", isConfident: false)])
    }

    func testNoItemsIsNotAnError() async throws {
        let provider = GroqTermSuggestionProvider(apiKey: "k", httpClient: MockHTTPClient(response: reply(#"{"items":[]}"#)))

        let suggestions = try await provider.suggest(texts: ["x"], knownTerms: [])

        XCTAssertEqual(suggestions, [])
    }

    func testDoesNotCallGroqWithoutTexts() async throws {
        let client = MockHTTPClient(response: reply(#"{"items":[]}"#))
        let provider = GroqTermSuggestionProvider(apiKey: "k", httpClient: client)

        let suggestions = try await provider.suggest(texts: [], knownTerms: ["Groq"])

        XCTAssertEqual(suggestions, [])
        XCTAssertEqual(client.requests.count, 0)
    }

    func testMaps429ToRateLimit() async throws {
        let provider = GroqTermSuggestionProvider(
            apiKey: "k",
            httpClient: MockHTTPClient(response: HTTPResponse(statusCode: 429, data: Data()))
        )

        do {
            _ = try await provider.suggest(texts: ["x"], knownTerms: [])
            XCTFail("Expected rate limit")
        } catch VoiceInputError.providerRateLimited(let providerID) {
            XCTAssertEqual(providerID, "groq-term-suggestion")
        }
    }

    func testMapsOtherHTTPErrorsToProviderFailed() async throws {
        let provider = GroqTermSuggestionProvider(
            apiKey: "k",
            httpClient: MockHTTPClient(response: HTTPResponse(statusCode: 500, data: Data()))
        )

        do {
            _ = try await provider.suggest(texts: ["x"], knownTerms: [])
            XCTFail("Expected failure")
        } catch VoiceInputError.providerFailed(let message) {
            XCTAssertTrue(message.contains("500"), message)
        }
    }

    func testMapsRefusedRequestsToRequestRejected() async throws {
        for status in [400, 401, 403, 404, 413] {
            let provider = GroqTermSuggestionProvider(
                apiKey: "k",
                httpClient: MockHTTPClient(response: HTTPResponse(statusCode: status, data: Data()))
            )
            do {
                _ = try await provider.suggest(texts: ["x"], knownTerms: [])
                XCTFail("Expected rejection: \(status)")
            } catch TermSuggestionError.requestRejected {
            }
        }
    }

    func testTreatsServerTroubleAndTimeoutsAsTemporaryFailures() async throws {
        for status in [408, 500, 502, 503] {
            let provider = GroqTermSuggestionProvider(
                apiKey: "k",
                httpClient: MockHTTPClient(response: HTTPResponse(statusCode: status, data: Data()))
            )
            do {
                _ = try await provider.suggest(texts: ["x"], knownTerms: [])
                XCTFail("Expected failure: \(status)")
            } catch VoiceInputError.providerFailed {
            }
        }
    }

    func testThrowsWhenTheAnswerCannotBeRead() async throws {
        for content in ["これはJSONではありません", #"{"result":"ok"}"#, ""] {
            let provider = GroqTermSuggestionProvider(apiKey: "k", httpClient: MockHTTPClient(response: reply(content)))
            do {
                _ = try await provider.suggest(texts: ["x"], knownTerms: [])
                XCTFail("Expected unreadable: \(content)")
            } catch TermSuggestionError.unreadableResponse {
            }
        }
        let broken = GroqTermSuggestionProvider(
            apiKey: "k",
            httpClient: MockHTTPClient(response: HTTPResponse(statusCode: 200, data: Data("{}".utf8)))
        )
        do {
            _ = try await broken.suggest(texts: ["x"], knownTerms: [])
            XCTFail("Expected unreadable")
        } catch TermSuggestionError.unreadableResponse {
        }
    }

    func testThePromptDoesNotShowTheUsersOwnWordsAsExamples() {
        // 例に本人の語を入れると、評価が甘くなる。例は別の語にしてある。
        for word in ["Groq", "Soniox", "Obsidian", "OpenCode", "Glog"] {
            XCTAssertFalse(GroqTermSuggestionProvider.systemPrompt.contains(word), word)
        }
    }
}
