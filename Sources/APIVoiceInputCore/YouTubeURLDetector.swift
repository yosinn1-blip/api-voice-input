import Foundation

public enum YouTubeURLDetector {
    public static func isYouTubeURL(_ string: String) -> Bool {
        guard let url = URL(string: string),
              let host = url.host?.lowercased()
        else { return false }

        return host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
    }
}
