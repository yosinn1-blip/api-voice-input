import Foundation

public struct EmptyUtteranceGuard: Sendable {
    public static let minimumUsefulDurationSeconds = 0.35
    public static let silenceRMSDBFS = -50.0
    public static let silencePeakDBFS = -38.0
    public static let quietHallucinationRMSDBFS = -30.0

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
        // Peak is deliberately excluded: transient background noise (AC, keyboard) can spike peak
        // above -18 dBFS even with no speech, causing false negatives. RMS alone reliably
        // distinguishes silence from actual voice.
        return activity.rmsDBFS < Self.quietHallucinationRMSDBFS
    }

    private static let commonSilenceHallucinations: Set<String> = [
        // 感謝系
        "ありがとうございました",
        "ありがとうございます",
        "ありがとうございました",
        "ご視聴ありがとうございました",
        "ご視聴ありがとうございます",
        "ご清聴ありがとうございました",
        "ご清聴ありがとうございます",
        "ご覧いただきありがとうございました",
        "最後までご覧いただきありがとうございました",
        "最後までご視聴ありがとうございました",
        "本日もありがとうございました",
        // 締め・挨拶系
        "お疲れ様でした",
        "お疲れ様です",
        "失礼しました",
        "失礼いたします",
        "以上です",
        "以上になります",
        "それでは失礼します",
        // 字幕・チャンネル系（YouTube幻覚の定番）
        "字幕は自動生成されています",
        "チャンネル登録よろしくお願いします",
        "チャンネル登録よろしくお願いいたします",
        "次回もよろしくお願いします",
        "よろしくお願いいたします"
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
