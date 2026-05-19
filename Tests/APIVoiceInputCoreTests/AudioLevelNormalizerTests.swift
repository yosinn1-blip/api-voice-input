import Testing
@testable import APIVoiceInputCore

@Suite("AudioLevelNormalizer")
struct AudioLevelNormalizerTests {
    @Test("silence stays low")
    func silenceStaysLow() {
        let level = AudioLevelNormalizer.normalizedLevel(averagePower: -67, peakPower: -42)
        #expect(level < 0.12)
    }

    @Test("normal speech does not saturate")
    func normalSpeechDoesNotSaturate() {
        let level = AudioLevelNormalizer.normalizedLevel(averagePower: -32.6, peakPower: -14.2)
        #expect(level > 0.45)
        #expect(level < 0.62)
    }

    @Test("loud speech remains below full scale")
    func loudSpeechRemainsBelowFullScale() {
        let level = AudioLevelNormalizer.normalizedLevel(averagePower: -29.9, peakPower: -11.9)
        #expect(level > 0.48)
        #expect(level < 0.68)
    }

    @Test("strong sustained input can still reach high range")
    func strongSustainedInputCanReachHighRange() {
        let level = AudioLevelNormalizer.normalizedLevel(averagePower: -16, peakPower: -8)
        #expect(level > 0.72)
        #expect(level < 0.90)
    }
}
