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
    /// Groq's more accurate multilingual Whisper (`whisper-large-v3`, WER 10.3%).
    /// `whisper-large-v3-turbo` is faster (WER 12%) but worse for error-sensitive Japanese dictation.
    public let id = "groq-whisper-large-v3"
    static let modelName = "whisper-large-v3"
    static let temperature = "0"

    /// Whisper prompt (max 224 tokens) guides style, not instructions.
    /// Conversational Japanese dictation; do not include YouTube outro / app-name strings
    /// because Whisper copies prompt wording into the transcript.
    static let transcriptionPrompt =
        "これは日本語の日常会話の書き起こしです。話した内容だけを正確に書き取り、字幕や動画エンディングの定型文は付けない。Codex, Claude, ChatGPT, Gemini, Groq, Whisper, OpenAI, Anthropic, YouTube, GitHub, Git, Swift, Xcode, API"

    private let apiKey: String
    private let httpClient: any HTTPClient

    public init(apiKey: String, httpClient: any HTTPClient = URLSessionHTTPClient()) {
        self.apiKey = apiKey
        self.httpClient = httpClient
    }

    /// Empty/blank hints fall back to Japanese. Named profiles (e.g. English) still pass through.
    static func resolvedLanguage(from languageHint: String) -> String {
        let trimmed = languageHint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "ja" : trimmed
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
        append("\(Self.modelName)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
        append("\(Self.resolvedLanguage(from: languageHint))\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"temperature\"\r\n\r\n")
        append("\(Self.temperature)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
        append("\(Self.transcriptionPrompt)\r\n")

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
