import Foundation

/// 「話し終わってすぐEnterで語尾が入らない」の切り分け用（2026-09-27）。
/// 録音・先頭トリム・整形はどれも末尾を落とさないと実測済みで、残る候補は
/// 実音声でのWhisperの語尾落ちか、Enterと最後の音の重なり。どちらかは録音を聞かないと分からないため、
/// 直近の録音と認識結果を limit 件だけ手元に残す。
///
/// 音声入力にはパスワードや私的な文章も入るので、残すのは調査でオンにしたときだけ（既定はオフ）。
/// 残すときも、フォルダ 0700・ファイル 0600・バックアップ対象外にし、maxAge を過ぎたものは次の保存時に消す。
public struct RecentRecordingArchive: Sendable {
    public static let defaultEnabled = false

    public let directory: URL
    public let limit: Int
    public let maxAge: TimeInterval

    public init(directory: URL, limit: Int = 10, maxAge: TimeInterval = 24 * 60 * 60) {
        self.directory = directory
        self.limit = limit
        self.maxAge = maxAge
    }

    /// 録音をコピーし、同名の .txt に認識結果を書く。元ファイルは消さない。
    @discardableResult
    public func save(audioFileURL: URL, rawTranscript: String, finalText: String, stamp: String, now: Date = Date()) throws -> URL {
        let fileManager = FileManager.default
        try prepareDirectory()
        let audioCopy = directory.appendingPathComponent(stamp).appendingPathExtension(audioFileURL.pathExtension)
        try? fileManager.removeItem(at: audioCopy)
        // copyItem は元の 0644 を、String.write は umask を引き継ぐので、書いた後に本人だけに絞る。
        try fileManager.copyItem(at: audioFileURL, to: audioCopy)
        try restrictToOwner(audioCopy)
        let textURL = audioCopy.deletingPathExtension().appendingPathExtension("txt")
        let text = "raw: \(rawTranscript)\nfinal: \(finalText)\n"
        try text.write(to: textURL, atomically: true, encoding: .utf8)
        try restrictToOwner(textURL)
        try prune(now: now)
        return audioCopy
    }

    private func prepareDirectory() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // 以前の版が 0755 で作ったフォルダもここで締める。
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = directory
        try url.setResourceValues(values)
    }

    private func restrictToOwner(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func prune(now: Date) throws {
        let fileManager = FileManager.default
        let names = try fileManager.contentsOfDirectory(atPath: directory.path)
        var newestModification: [String: Date] = [:]
        for name in names {
            let stamp = (name as NSString).deletingPathExtension
            let attributes = try? fileManager.attributesOfItem(atPath: directory.appendingPathComponent(name).path)
            let modified = attributes?[.modificationDate] as? Date ?? .distantPast
            newestModification[stamp] = max(newestModification[stamp] ?? .distantPast, modified)
        }
        let fresh = newestModification
            .filter { now.timeIntervalSince($0.value) <= maxAge }
            .map(\.key)
            .sorted()
        let kept = Set(fresh.suffix(limit))
        for name in names where kept.contains((name as NSString).deletingPathExtension) == false {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
