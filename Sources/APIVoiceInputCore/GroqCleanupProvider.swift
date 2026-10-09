import Foundation

public struct GroqCleanupProvider: CleanupProvider {
    public let id = "groq-gpt-oss-120b"
    private let apiKey: String
    private let model: String
    private let httpClient: any HTTPClient

    /// 旧既定の llama-3.3-70b-versatile は 2026-08-16 に Groq で停止済み（今は 404 model_not_found）。
    /// Groq の推奨代替 openai/gpt-oss-120b（Free: 30 RPM / 1,000 RPD / 8,000 TPM）に切り替える。
    public init(apiKey: String, model: String = "openai/gpt-oss-120b", httpClient: any HTTPClient = URLSessionHTTPClient()) {
        self.apiKey = apiKey
        self.model = model
        self.httpClient = httpClient
    }

    public func clean(transcript: String, prompt: String) async throws -> String {
        // gpt-oss は推論トークンも completion_tokens に含まれる（実測: 短文で 23 トークン）。
        // 短文でも推論分が答えを押し出さないよう下限 256。上限は従来どおり文字数×2
        // （実測: 3,617 字入力で prompt 2,188 + completion 1,954 = 4,142 トークン、8,000 TPM 内）。
        let maxTokens = max(256, transcript.count * 2)
        let requestBody = GroqChatRequest(
            model: model,
            messages: [
                GroqChatMessage(role: "system", content: prompt),
                GroqChatMessage(role: "user", content: "<transcription>\(transcript)</transcription>")
            ],
            maxTokens: maxTokens,
            temperature: 0,
            reasoningEffort: "low",
            includeReasoning: false
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
    /// gpt-oss 専用。整形は推論不要なので最小の low、推論本文は返させない（content だけ受け取る）。
    let reasoningEffort: String
    let includeReasoning: Bool

    enum CodingKeys: String, CodingKey {
        case model, messages
        case maxTokens = "max_tokens"
        case temperature
        case reasoningEffort = "reasoning_effort"
        case includeReasoning = "include_reasoning"
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
