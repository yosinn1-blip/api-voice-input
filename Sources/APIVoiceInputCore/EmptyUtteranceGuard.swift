import Foundation

public struct EmptyUtteranceGuard: Sendable {
    public static let minimumUsefulDurationSeconds = 0.35
    public static let silenceRMSDBFS = -50.0
    public static let silencePeakDBFS = -38.0
    public static let quietHallucinationRMSDBFS = -42.0
    public static let quietHallucinationPeakDBFS = -25.0

    public init() {}

    public func shouldSkipTranscription(activity: AudioActivitySummary) -> Bool {
        if activity.durationSeconds < Self.minimumUsefulDurationSeconds {
            return true
        }
        return activity.rmsDBFS < Self.silenceRMSDBFS && activity.peakDBFS < Self.silencePeakDBFS
    }

    public func shouldSuppressTranscript(_ transcript: String, activity: AudioActivitySummary) -> Bool {
        let normalized = Self.normalize(transcript)
        guard Self.commonSilenceHallucinations.contains(normalized) else {
            return false
        }
        return activity.rmsDBFS < Self.quietHallucinationRMSDBFS && activity.peakDBFS < Self.quietHallucinationPeakDBFS
    }

    private static let commonSilenceHallucinations: Set<String> = [
        "ありがとうございました",
        "ご視聴ありがとうございました",
        "ご清聴ありがとうございました",
        "お疲れ様でした",
        "以上です"
    ]

    private static func normalize(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .replacingOccurrences(of: "。", with: "")
            .replacingOccurrences(of: "、", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "!", with: "")
            .replacingOccurrences(of: "！", with: "")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "？", with: "")
    }
}
