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
}
