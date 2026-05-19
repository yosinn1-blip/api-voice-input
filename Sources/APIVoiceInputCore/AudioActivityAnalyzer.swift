import AVFoundation
import Foundation

public struct AudioActivitySummary: Equatable, Sendable {
    public let durationSeconds: Double
    public let rmsDBFS: Double
    public let peakDBFS: Double

    public init(durationSeconds: Double, rmsDBFS: Double, peakDBFS: Double) {
        self.durationSeconds = durationSeconds
        self.rmsDBFS = rmsDBFS
        self.peakDBFS = peakDBFS
    }
}

public struct AudioActivityAnalyzer: Sendable {
    public init() {}

    public func analyze(audioFileURL: URL) throws -> AudioActivitySummary {
        let file = try AVAudioFile(forReading: audioFileURL)
        let format = file.processingFormat
        let sampleRate = max(format.sampleRate, 1)
        let channelCount = max(Int(format.channelCount), 1)
        let capacity = AVAudioFrameCount(min(max(file.length, 1), 4_096))

        var sumSquares = 0.0
        var peak = 0.0
        var sampleCount = 0
        var frameCount = 0

        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
                break
            }
            try file.read(into: buffer)
            let frames = Int(buffer.frameLength)
            if frames == 0 { break }
            frameCount += frames

            guard let channels = buffer.floatChannelData else {
                continue
            }

            for channel in 0..<channelCount {
                let samples = channels[channel]
                for index in 0..<frames {
                    let value = Double(samples[index])
                    let absValue = abs(value)
                    sumSquares += value * value
                    if absValue > peak { peak = absValue }
                    sampleCount += 1
                }
            }
        }

        let duration = Double(frameCount) / sampleRate
        let rms = sampleCount > 0 ? sqrt(sumSquares / Double(sampleCount)) : 0
        return AudioActivitySummary(
            durationSeconds: duration,
            rmsDBFS: Self.dbfs(rms),
            peakDBFS: Self.dbfs(peak)
        )
    }

    private static func dbfs(_ linear: Double) -> Double {
        guard linear > 0 else { return -160 }
        return 20 * log10(linear)
    }
}
