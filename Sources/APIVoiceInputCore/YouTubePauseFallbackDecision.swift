import Foundation

public enum YouTubePauseFallbackDecision {
    public static func shouldUseMediaKeyFallback(scriptOutput: String) -> Bool {
        let values = parseCounters(from: scriptOutput)
        let tabs = values["tabs", default: 0]
        let pausedVideos = values["pausedVideos", default: 0]
        let errors = values["errors", default: 0]

        return tabs > 0 && pausedVideos == 0 && errors > 0
    }

    private static func parseCounters(from output: String) -> [String: Int] {
        var counters: [String: Int] = [:]
        for part in output.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
            let pair = part.split(separator: "=", maxSplits: 1)
            guard pair.count == 2, let value = Int(pair[1]) else { continue }
            counters[String(pair[0])] = value
        }
        return counters
    }
}
