import Foundation

public enum RecordingBehaviorSettings {
    public static let defaultMediaControlEnabled = false

    public static func shouldPrepareMediaBeforeRecording(mediaControlEnabled: Bool) -> Bool {
        mediaControlEnabled
    }
}
