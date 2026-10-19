import Foundation
import Testing
@testable import APIVoiceInputCore

@Suite("RecentRecordingArchive")
struct RecentRecordingArchiveTests {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecentRecordingArchiveTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("keeps the audio and the raw and final transcripts side by side")
    func keepsAudioAndTranscripts() throws {
        let root = try makeTempDirectory()
        let audio = root.appendingPathComponent("in.m4a")
        try Data([1, 2, 3]).write(to: audio)
        let archive = RecentRecordingArchive(directory: root.appendingPathComponent("recent"), limit: 10)

        let saved = try archive.save(audioFileURL: audio, rawTranscript: "生の文", finalText: "整形後", stamp: "20260927-010203")

        #expect(try Data(contentsOf: saved) == Data([1, 2, 3]))
        let text = try String(contentsOf: saved.deletingPathExtension().appendingPathExtension("txt"), encoding: .utf8)
        #expect(text.contains("raw: 生の文"))
        #expect(text.contains("final: 整形後"))
        #expect(FileManager.default.fileExists(atPath: audio.path))
    }

    @Test("drops the oldest recordings beyond the limit")
    func dropsOldestBeyondLimit() throws {
        let root = try makeTempDirectory()
        let audio = root.appendingPathComponent("in.m4a")
        try Data([0]).write(to: audio)
        let directory = root.appendingPathComponent("recent")
        let archive = RecentRecordingArchive(directory: directory, limit: 2)

        for stamp in ["20260927-000001", "20260927-000002", "20260927-000003"] {
            _ = try archive.save(audioFileURL: audio, rawTranscript: "a", finalText: "a", stamp: stamp)
        }

        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(names == ["20260927-000002.m4a", "20260927-000002.txt", "20260927-000003.m4a", "20260927-000003.txt"])
    }

    @Test("is off unless explicitly turned on")
    func isOffByDefault() {
        #expect(RecentRecordingArchive.defaultEnabled == false)
    }

    @Test("keeps the folder and the saved files readable only by the owner and out of backups")
    func restrictsPermissionsAndBackup() throws {
        let root = try makeTempDirectory()
        let audio = root.appendingPathComponent("in.m4a")
        try Data([1]).write(to: audio)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: audio.path)
        let directory = root.appendingPathComponent("recent")
        // 以前の版が作った 0755 のフォルダも締め直す。
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        let archive = RecentRecordingArchive(directory: directory, limit: 10)

        let saved = try archive.save(audioFileURL: audio, rawTranscript: "a", finalText: "a", stamp: "20260927-010203")

        func permissions(_ url: URL) throws -> Int {
            try (FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? -1
        }
        #expect(try permissions(directory) == 0o700)
        #expect(try permissions(saved) == 0o600)
        #expect(try permissions(saved.deletingPathExtension().appendingPathExtension("txt")) == 0o600)
        #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test("drops recordings older than the maximum age on the next save")
    func dropsExpiredRecordings() throws {
        let root = try makeTempDirectory()
        let audio = root.appendingPathComponent("in.m4a")
        try Data([0]).write(to: audio)
        let directory = root.appendingPathComponent("recent")
        let archive = RecentRecordingArchive(directory: directory, limit: 10, maxAge: 24 * 60 * 60)
        let now = Date()

        let old = try archive.save(audioFileURL: audio, rawTranscript: "a", finalText: "a", stamp: "20260925-000001", now: now)
        let twoDaysAgo = now.addingTimeInterval(-2 * 24 * 60 * 60)
        for url in [old, old.deletingPathExtension().appendingPathExtension("txt")] {
            try FileManager.default.setAttributes([.modificationDate: twoDaysAgo], ofItemAtPath: url.path)
        }
        _ = try archive.save(audioFileURL: audio, rawTranscript: "b", finalText: "b", stamp: "20260927-000002", now: now)

        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(names == ["20260927-000002.m4a", "20260927-000002.txt"])
    }
}
