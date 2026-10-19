import Foundation

/// 「話し終わってすぐEnterで語尾が入らない」の切り分け用（2026-09-27）。
/// 録音・先頭トリム・整形はどれも末尾を落とさないと実測済みで、残る候補は
/// 実音声でのWhisperの語尾落ちか、Enterと最後の音の重なり。どちらかは録音を聞かないと分からないため、
/// 直近の録音と認識結果を limit 件だけ手元に残す。
public struct RecentRecordingArchive: Sendable {
    public let directory: URL
    public let limit: Int

    public init(directory: URL, limit: Int = 10) {
        self.directory = directory
        self.limit = limit
    }

    /// 録音をコピーし、同名の .txt に認識結果を書く。元ファイルは消さない。
    @discardableResult
    public func save(audioFileURL: URL, rawTranscript: String, finalText: String, stamp: String) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let audioCopy = directory.appendingPathComponent(stamp).appendingPathExtension(audioFileURL.pathExtension)
        try? fileManager.removeItem(at: audioCopy)
        try fileManager.copyItem(at: audioFileURL, to: audioCopy)
        let text = "raw: \(rawTranscript)\nfinal: \(finalText)\n"
        try text.write(to: audioCopy.deletingPathExtension().appendingPathExtension("txt"), atomically: true, encoding: .utf8)
        try prune()
        return audioCopy
    }

    private func prune() throws {
        let fileManager = FileManager.default
        let names = try fileManager.contentsOfDirectory(atPath: directory.path)
        let stamps = Set(names.map { ($0 as NSString).deletingPathExtension }).sorted()
        guard stamps.count > limit else { return }
        let expired = Set(stamps.prefix(stamps.count - limit))
        for name in names where expired.contains((name as NSString).deletingPathExtension) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
