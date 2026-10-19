import XCTest
@testable import APIVoiceInputCore

extension XCTestCase {
    /// テストごとの一時フォルダ。テスト終了時に消える。
    func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("APIVoiceInputTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// 中身の配列から、複数の辞書ファイルを読む辞書を作る。nil の要素はファイルを作らない（無いファイルの扱いを試す）。
    func makeReplacementDictionary(files contents: [String?]) throws -> ReplacementDictionary {
        let directory = try makeTemporaryDirectory()
        var fileURLs: [URL] = []
        for (index, text) in contents.enumerated() {
            let fileURL = directory.appendingPathComponent("dictionary-\(index).txt")
            if let text {
                try text.write(to: fileURL, atomically: true, encoding: .utf8)
            }
            fileURLs.append(fileURL)
        }
        return ReplacementDictionary(fileURL: fileURLs[0], additionalFileURLs: Array(fileURLs.dropFirst()))
    }

    /// 指定した中身の辞書ファイルを一時フォルダに作り、それを読む辞書を返す。
    func makeReplacementDictionary(_ contents: String) throws -> ReplacementDictionary {
        let fileURL = try makeTemporaryDirectory().appendingPathComponent("dictionary.txt")
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return ReplacementDictionary(fileURL: fileURL)
    }
}
