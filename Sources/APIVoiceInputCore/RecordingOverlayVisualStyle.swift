import Foundation

public struct RecordingOverlayVisualStyle: Equatable, Sendable {
    public let windowWidth: Double
    public let windowHeight: Double
    public let cornerRadius: Double
    public let waveformWidth: Double
    public let waveformHeight: Double
    public let waveformBarCount: Int
    public let waveformBarWidth: Double

    public static let typelessInspired = RecordingOverlayVisualStyle(
        windowWidth: 136,
        windowHeight: 36,
        cornerRadius: 18,
        waveformWidth: 84,
        waveformHeight: 20,
        waveformBarCount: 13,
        waveformBarWidth: 3.2
    )
}

public struct ProcessingGaugeVisualStyle: Equatable, Sendable {
    public let fillRed: Double
    public let fillGreen: Double
    public let fillBlue: Double
    public let fillAlpha: Double
    public let usesLeadingEdgeHighlight: Bool

    public static let typelessInspired = ProcessingGaugeVisualStyle(
        fillRed: 0.74,
        fillGreen: 0.82,
        fillBlue: 0.90,
        fillAlpha: 0.52,
        usesLeadingEdgeHighlight: false
    )
}

public enum RecordingWaveformShape {
    public static func barHeightFactors(level rawLevel: Double, phase: Double, barCount: Int) -> [Double] {
        guard barCount > 0 else { return [] }

        let level = min(max(rawLevel, 0), 1)
        let center = Double(barCount - 1) / 2

        return (0..<barCount).map { index in
            let distanceFromCenter = abs(Double(index) - center) / max(center, 1)
            let centerWeight = 0.22 + pow(1 - distanceFromCenter, 1.70) * 0.78
            let idleBreath = 0.018 * (sin(phase * 1.35 + Double(index) * 0.92) + 1) / 2
            let voiceMotion = 0.92 + 0.15 * sin(phase + Double(index) * 0.72)
            let factor = 0.12 + idleBreath + level * centerWeight * voiceMotion * 1.08
            return min(max(factor, 0.10), 0.96)
        }
    }
}
