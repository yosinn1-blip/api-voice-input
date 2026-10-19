import Foundation

struct AppSettings {
    static let bundleIdentifier = "com.yoshiki.APIVoiceInput"
    static let appName = "API音声ソフト"
    static let groqKeyAccount = "groq-api-key"
    static let groqOnboardingDismissedKey = "groq-api-key-onboarding-dismissed"
    static let mediaControlEnabledKey = "recording-media-control-enabled"
    static let recentRecordingArchiveEnabledKey = "recent-recordings-archive-enabled"
    static let dictionaryLearningEnabledKey = "dictionary-learning-enabled"
    /// 使いながら辞書を育てる機能の初期値。貼り付けた文章を（音声と同じ）Groq に送るので、メニューでいつでも切れる。
    static let dictionaryLearningDefaultEnabled = true

    static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("APIVoiceInput", isDirectory: true)
    }

    static var dictionaryFileURL: URL {
        applicationSupportDirectory.appendingPathComponent("dictionary.txt")
    }

    /// 使いながら自動で覚えた語（手書きの辞書とは別のファイル）
    static var autoDictionaryFileURL: URL {
        applicationSupportDirectory.appendingPathComponent("dictionary-auto.txt")
    }

    /// 学習の途中経過（語の組と回数だけ。文章は入っていない）
    static var learningStateFileURL: URL {
        applicationSupportDirectory.appendingPathComponent("dictionary-learning.json")
    }
}
