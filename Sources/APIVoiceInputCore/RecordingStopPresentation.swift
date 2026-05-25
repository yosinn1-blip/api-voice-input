import Foundation

public enum RecordingStopPresentation {
    public static let quickHideMaximumRecordingLevel = 0.25

    public static func shouldHideOverlayImmediately(maxRecordingLevel: Double) -> Bool {
        maxRecordingLevel < quickHideMaximumRecordingLevel
    }

    public static func shouldHideOverlayImmediately(maxRecordingLevel: Double, stopSource: String) -> Bool {
        isFnStopSource(stopSource) || isConversationCancel(stopSource) || shouldHideOverlayImmediately(maxRecordingLevel: maxRecordingLevel)
    }

    public static func shouldCancelTranscription(stopSource: String) -> Bool {
        isConversationCancel(stopSource)
    }

    public static func pasteMode(stopSource: String) -> PasteMode {
        isFnStopSource(stopSource) ? .pasteOnly : .pasteThenEnter
    }

    public static func shouldSkipTranscription(activity: AudioActivitySummary, stopSource: String) -> Bool {
        guard isFnStopSource(stopSource) else { return false }
        return activity.durationSeconds < 1.0 && activity.rmsDBFS < -42.0
    }

    private static func isFnStopSource(_ stopSource: String) -> Bool {
        stopSource == "f19-hotkey" || stopSource == "direct-fn-eventtap"
    }

    private static func isConversationCancel(_ stopSource: String) -> Bool {
        stopSource == "conversation-mode-cancel"
    }
}
