import AVFoundation
import Foundation

@MainActor
final class RecorderController: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private(set) var currentURL: URL?

    func startRecording() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("APIVoiceInput-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()
        recorder.record()
        self.recorder = recorder
        self.currentURL = url
        return url
    }

    func normalizedAudioLevel() -> Double {
        guard let recorder else { return 0 }
        recorder.updateMeters()
        let averagePower = recorder.averagePower(forChannel: 0)
        let peakPower = recorder.peakPower(forChannel: 0)
        return Self.normalizedLevel(averagePower: averagePower, peakPower: peakPower)
    }

    func stopRecording() -> URL? {
        recorder?.stop()
        recorder = nil
        return currentURL
    }

    private static func normalizedLevel(averagePower: Float, peakPower: Float) -> Double {
        let floorDB: Float = -64
        let ceilingDB: Float = -16
        let weightedPower = max(averagePower, peakPower - 8)
        let clamped = min(max(weightedPower, floorDB), ceilingDB)
        let linear = (clamped - floorDB) / (ceilingDB - floorDB)
        return Double(pow(linear, 0.58))
    }
}
