import Foundation

/// Groq の AI（gpt-oss-120b）に文章を読ませて、崩れた固有名詞の提案をもらう。
/// 使うのは学習係だけで、貼り付けの速さには関わらない（裏で呼ぶ）。
public struct GroqTermSuggestionProvider: TermSuggestionProvider {
    public let id = "groq-term-suggestion"
    private let apiKey: String
    private let model: String
    private let httpClient: any HTTPClient

    public init(apiKey: String, model: String = "openai/gpt-oss-120b", httpClient: any HTTPClient = URLSessionHTTPClient()) {
        self.apiKey = apiKey
        self.model = model
        self.httpClient = httpClient
    }

    /// 例には、利用者の語（辞書の初期登録に入っている語）を使わない。評価が甘くなるため。
    /// 推論は low で足りる（medium にしても見つかる語は増えず、遅く・高くなるだけだった）。
    static let systemPrompt = """
    あなたは、日本語の音声認識結果から「固有名詞の聞き間違い」を見つける校正係です。

    入力は、音声認識で書き起こした文章（番号つき）です。探すのは、IT・AI・ソフトウェア・サービス・製品・会社などの名前のうち、本来は英語（アルファベット）で綴る名前が、カタカナや崩れたアルファベットで書かれてしまっている箇所です。音が少し違うだけの聞き間違い（例: ノーソン → Notion）も、アルファベットの綴りの崩れ（例: Typscript → TypeScript）も、サービス名のふつうのカタカナ表記（例: ファイヤーベース → Firebase）も含みます。

    進め方:
    - 文章を1つずつ読み、カタカナの語とアルファベットの語をすべて確認する。
    - 「辞書にある正しい語」のどれかを言ったつもりだったと思われる箇所は、母音や子音が少し違っていても、綴りが崩れていても、必ず拾う。

    守ること:
    - wrong は、入力の文章にそのまま書かれている1つの語（カタカナだけ、またはアルファベットだけ）。助詞・ひらがな・漢字・空白を含めない。
    - correct は、正しい綴り（半角の英数字）。「辞書にある正しい語」に当てはまるものは、その綴りをそのまま使う。
    - wrong が違えば、correct が同じでも別の項目として出す（同じ wrong が何度も出たときだけ1つにまとめる）。
    - 日本語として定着した語（ファイル、サービス、カーソル、アカウント、プロジェクト など）や、人名・地名、公式の表記がカタカナの会社名・サービス名（例: ランサーズ、ココナラ）は対象外。
    - 確信がなければ confidence を low にする。候補が複数ありうるときも low。
    - 見つからなければ items を空にする。

    次のJSONだけを返す。前置きや説明は書かない。
    {"items":[{"wrong":"...","correct":"...","confidence":"high"}]}
    confidence は high か low。
    """

    public func suggest(texts: [String], knownTerms: [String]) async throws -> [TermSuggestion] {
        guard texts.isEmpty == false else { return [] }
        let request = ChatRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: Self.systemPrompt),
                ChatMessage(role: "user", content: Self.userMessage(texts: texts, knownTerms: knownTerms))
            ],
            maxTokens: 1500,
            temperature: 0,
            reasoningEffort: "low",
            includeReasoning: false,
            responseFormat: ResponseFormat(type: "json_object")
        )
        let response = try await httpClient.send(
            url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            method: "POST",
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Content-Type": "application/json"
            ],
            body: try JSONEncoder().encode(request)
        )
        if response.statusCode == 429 {
            throw VoiceInputError.providerRateLimited(id)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw VoiceInputError.providerFailed("Groq term suggestion failed with HTTP \(response.statusCode).")
        }
        return try Self.parse(response.data)
    }

    static func userMessage(texts: [String], knownTerms: [String]) -> String {
        let known = knownTerms.isEmpty ? "（なし）" : knownTerms.joined(separator: ", ")
        let numbered = texts.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return "辞書にある正しい語（参考）: \(known)\n文章:\n\(numbered)"
    }

    /// 返事は JSON のはずだが、前置きやコードフェンスが付いても、最初の { から最後の } までを読む。
    static func parse(_ data: Data) throws -> [TermSuggestion] {
        guard let envelope = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let content = envelope.choices.first?.message.content,
              let start = content.firstIndex(of: "{"),
              let end = content.lastIndex(of: "}"),
              start < end,
              let payload = try? JSONDecoder().decode(Payload.self, from: Data(content[start...end].utf8)) else {
            throw TermSuggestionError.unreadableResponse
        }
        return payload.items.compactMap { item in
            guard let wrong = item.wrong, let correct = item.correct else { return nil }
            return TermSuggestion(wrong: wrong, correct: correct, isConfident: item.confidence == "high")
        }
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let maxTokens: Int
    let temperature: Int
    let reasoningEffort: String
    let includeReasoning: Bool
    let responseFormat: ResponseFormat

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
        case reasoningEffort = "reasoning_effort"
        case includeReasoning = "include_reasoning"
        case responseFormat = "response_format"
    }
}

private struct ChatMessage: Encodable {
    let role: String
    let content: String
}

private struct ResponseFormat: Encodable {
    let type: String
}

private struct ChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
    }
}

private struct Payload: Decodable {
    let items: [Item]

    struct Item: Decodable {
        let wrong: String?
        let correct: String?
        let confidence: String?
    }
}
