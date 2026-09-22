import Foundation

/// A bounded grace period after Enter: allow a final syllable to finish instead
/// of cutting off at a fixed deadline. Levels use AudioLevelNormalizer's scale.
public struct RecordingTailPolicy {
    private var lastSpeechTime: TimeInterval = 0
    public static let quietSeconds: TimeInterval = 0.35
    public static let maximumSeconds: TimeInterval = 1.5
    private static let speechLevel = 0.25

    public init() {}

    /// `elapsed` must be monotonic seconds since the stop request.
    public mutating func shouldStop(elapsed: TimeInterval, level: Double) -> Bool {
        if level >= Self.speechLevel {
            lastSpeechTime = elapsed
        }
        return elapsed >= Self.maximumSeconds
            || (elapsed >= Self.quietSeconds && elapsed - lastSpeechTime >= Self.quietSeconds)
    }
}
