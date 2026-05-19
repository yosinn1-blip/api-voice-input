import Testing
@testable import APIVoiceInputCore

@Suite("RecordingOverlayVisualStyle")
struct RecordingOverlayVisualStyleTests {
    @Test("Typeless-inspired overlay is narrower and thinner without side icons")
    func typelessInspiredOverlayDimensions() {
        let style = RecordingOverlayVisualStyle.typelessInspired

        #expect(style.windowWidth == 136)
        #expect(style.windowHeight == 36)
        #expect(style.cornerRadius == 18)
        #expect(style.waveformWidth == 84)
        #expect(style.waveformHeight == 20)
        #expect(style.waveformBarCount == 13)

        let horizontalPadding = (style.windowWidth - style.waveformWidth) / 2
        #expect(horizontalPadding <= 26)
    }

    @Test("waveform stays center-weighted instead of scrolling left to right")
    func waveformIsCenterWeighted() {
        let heights = RecordingWaveformShape.barHeightFactors(
            level: 0.72,
            phase: 0.4,
            barCount: 13
        )

        let center = heights[6]
        let nearCenterAverage = (heights[5] + heights[6] + heights[7]) / 3
        let edgeAverage = (heights[0] + heights[1] + heights[11] + heights[12]) / 4

        #expect(heights.count == 13)
        #expect(center > 0.72)
        #expect(nearCenterAverage > edgeAverage * 1.65)
    }

    @Test("quiet input renders as small center dots")
    func quietInputKeepsSmallDots() {
        let heights = RecordingWaveformShape.barHeightFactors(
            level: 0.0,
            phase: 1.0,
            barCount: 13
        )

        #expect(heights.allSatisfy { $0 >= 0.10 })
        #expect(heights.allSatisfy { $0 <= 0.24 })
    }

    @Test("processing gauge uses one flat fill color")
    func processingGaugeUsesFlatFillColor() {
        let style = ProcessingGaugeVisualStyle.typelessInspired

        #expect(style.usesLeadingEdgeHighlight == false)
        #expect(style.fillAlpha == 0.52)
    }
}
