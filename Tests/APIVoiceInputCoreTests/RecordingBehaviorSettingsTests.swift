import Testing
@testable import APIVoiceInputCore

@Suite("RecordingBehaviorSettings")
struct RecordingBehaviorSettingsTests {
    @Test("browser media control is off by default for public builds")
    func browserMediaControlDefaultsOff() {
        #expect(RecordingBehaviorSettings.defaultMediaControlEnabled == false)
    }

    @Test("prepares browser media only when explicitly enabled")
    func preparesMediaOnlyWhenEnabled() {
        #expect(RecordingBehaviorSettings.shouldPrepareMediaBeforeRecording(mediaControlEnabled: false) == false)
        #expect(RecordingBehaviorSettings.shouldPrepareMediaBeforeRecording(mediaControlEnabled: true))
    }
}
