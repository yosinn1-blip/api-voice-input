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
