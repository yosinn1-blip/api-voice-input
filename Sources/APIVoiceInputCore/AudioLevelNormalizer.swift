import Foundation

public enum AudioLevelNormalizer {
    public static func normalizedLevel(averagePower: Float, peakPower: Float) -> Double {
        let floorDB: Float = -64
        let ceilingDB: Float = -6
        let peakInfluenceOffsetDB: Float = 18
        let responseCurve = 1.10

        let weightedPower = max(averagePower, peakPower - peakInfluenceOffsetDB)
        let clamped = min(max(weightedPower, floorDB), ceilingDB)
        let linear = Double((clamped - floorDB) / (ceilingDB - floorDB))
        return pow(linear, responseCurve)
    }
}
