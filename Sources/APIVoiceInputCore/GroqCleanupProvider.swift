import Foundation

public struct GroqCleanupProvider: CleanupProvider {
    public let id = "groq-llama-instant"
    private let apiKey: String
    private let model: String
    private let httpClient: any HTTPClient

    public init(apiKey: String, model: String = "llama-3.3-70b-versatile", httpClient: any HTTPClient = URLSessionHTTPClient()) {
        self.apiKey = apiKey
        self.model = model
        self.httpClient = httpClient
    }

    public func clean(transcript: String, prompt: String) async throws -> String {
        let maxTokens = max(80, transcript.count * 2)
        let requestBody = GroqChatRequest(
            model: model,
            messages: [
                GroqChatMessage(role: "system", content: prompt),
                GroqChatMessage(role: "user", content: "<transcription>\(transcript)</transcription>")
            ],
            maxTokens: maxTokens,
            temperature: 0
        )
        let body = try JSONEncoder().encode(requestBody)
        let response = try await httpClient.send(
            url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            method: "POST",
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Content-Type": "application/json"
            ],
            body: body
        )
        if response.statusCode == 429 {
            throw VoiceInputError.providerRateLimited("groq-cleanup")
        }
        guard (200..<300).contains(response.statusCode) else {
            throw VoiceInputError.providerFailed("Groq cleanup failed with HTTP \(response.statusCode).")
        }
        let decoded = try JSONDecoder().decode(GroqChatResponse.self, from: response.data)
        return decoded.choices.first?.message.content ?? transcript
    }
}

private struct GroqChatRequest: Encodable {
    let model: String
    let messages: [GroqChatMessage]
    let maxTokens: Int
    let temperature: Int

    enum CodingKeys: String, CodingKey {
        case model, messages
        case maxTokens = "max_tokens"
        case temperature
    }
}

private struct GroqChatMessage: Codable {
    let role: String
    let content: String
}

private struct GroqChatResponse: Decodable {
    let choices: [GroqChatChoice]
}

private struct GroqChatChoice: Decodable {
    let message: GroqChatMessage
}
