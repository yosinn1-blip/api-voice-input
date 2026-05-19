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
