import Foundation

public final class ProfileStore: Sendable {
    public let directoryURL: URL
    public let fileURL: URL

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
        self.fileURL = directoryURL.appendingPathComponent("profiles.json")
    }

    public func loadProfiles() throws -> [VoiceProfile] {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let defaults = [VoiceProfile.defaultJapanese]
            try saveProfiles(defaults)
            return defaults
        }
        let data = try Data(contentsOf: fileURL)
        let profiles = try JSONDecoder().decode([VoiceProfile].self, from: data)
        return profiles.isEmpty ? [VoiceProfile.defaultJapanese] : profiles
    }

    public func saveProfiles(_ profiles: [VoiceProfile]) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder.prettySorted.encode(profiles)
        try data.write(to: fileURL, options: [.atomic])
    }
}

private extension JSONEncoder {
    static var prettySorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
