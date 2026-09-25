import AVFoundation
import Foundation

/// Whisper は話し始め前の長い無音で幻聴を起こし、実際の発話ごと
/// 「ご視聴ありがとうございました」「この動画は…」に置き換えることがある
/// （2026-09-25 実測: 室内ノイズ8秒以上の先頭無音で再現、3秒では起きない）。
/// 送信前に先頭の無音だけを削る。語尾側は小さな声を消さないよう触らない。
public struct LeadingSilenceTrimmer: Sendable {
    /// これより短い先頭無音は削らない（削っても効果がなく、ファイルを書き直すだけになる）。
    public static let minimumTrimSeconds = 1.5
    /// 発話の立ち上がりを切らないよう、検出位置より前に残す秒数。
    public static let paddingSeconds = 0.4
    public static let windowSeconds = 0.02
    /// 室内ノイズの床からこれだけ大きければ声とみなす。
    static let speechAboveNoiseFloorDB = 12.0
    static let absoluteSpeechFloorDBFS = -50.0

    public init() {}

    /// 先頭無音の秒数（削る量）を返す。声が見つからない・削る必要がないときは 0。
    public static func leadingTrimSeconds(windowRMSDBFS: [Double], windowSeconds: Double = windowSeconds) -> Double {
        guard windowRMSDBFS.isEmpty == false else { return 0 }
        let sorted = windowRMSDBFS.sorted()
        let noiseFloor = sorted[sorted.count / 10]
        let threshold = max(noiseFloor + speechAboveNoiseFloorDB, absoluteSpeechFloorDBFS)
        // 単発のクリック音で止まらないよう、3窓（60ms）続いたところを声の始まりとする。
        let run = 3
        guard windowRMSDBFS.count >= run else { return 0 }
        for index in 0...(windowRMSDBFS.count - run) {
            if windowRMSDBFS[index..<(index + run)].allSatisfy({ $0 >= threshold }) {
                let trim = Double(index) * windowSeconds - paddingSeconds
                return trim >= minimumTrimSeconds ? trim : 0
            }
        }
        return 0
    }

    /// 先頭無音が長ければ削った新しいファイルを書き出して、その URL と削った秒数を返す。
    /// 削らない場合は元の URL と 0 を返す。
    public func trimIfNeeded(audioFileURL: URL) throws -> (url: URL, trimmedSeconds: Double) {
        let input = try AVAudioFile(forReading: audioFileURL)
        let format = input.processingFormat
        let sampleRate = max(format.sampleRate, 1)
        let windowFrames = max(Int(sampleRate * Self.windowSeconds), 1)
        let capacity = AVAudioFrameCount(windowFrames * 200)

        var windows: [Double] = []
        var pendingSquares = 0.0
        var pendingCount = 0
        while input.framePosition < input.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { break }
            try input.read(into: buffer)
            let frames = Int(buffer.frameLength)
            if frames == 0 { break }
            guard let channels = buffer.floatChannelData else { continue }
            let samples = channels[0]
            for index in 0..<frames {
                let value = Double(samples[index])
                pendingSquares += value * value
                pendingCount += 1
                if pendingCount == windowFrames {
                    windows.append(Self.dbfs(sqrt(pendingSquares / Double(pendingCount))))
                    pendingSquares = 0
                    pendingCount = 0
                }
            }
        }

        let trimSeconds = Self.leadingTrimSeconds(windowRMSDBFS: windows)
        guard trimSeconds > 0 else { return (audioFileURL, 0) }

        let startFrame = AVAudioFramePosition(trimSeconds * sampleRate)
        let source = try AVAudioFile(forReading: audioFileURL)
        source.framePosition = startFrame
        let outputURL = audioFileURL.deletingPathExtension()
            .appendingPathExtension("trimmed")
            .appendingPathExtension(audioFileURL.pathExtension)
        try? FileManager.default.removeItem(at: outputURL)
        let output = try AVAudioFile(
            forWriting: outputURL,
            settings: source.fileFormat.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        while source.framePosition < source.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { break }
            try source.read(into: buffer)
            if buffer.frameLength == 0 { break }
            try output.write(from: buffer)
        }
        return (outputURL, trimSeconds)
    }

    private static func dbfs(_ linear: Double) -> Double {
        guard linear > 0 else { return -160 }
        return 20 * log10(linear)
    }
}
