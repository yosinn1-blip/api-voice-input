import Foundation
import Testing
@testable import APIVoiceInputCore

@Suite("DiagnosticStatus")
struct DiagnosticStatusTests {
    @Test("reports ready when key and required permissions are available")
    func readySnapshot() {
        let status = DiagnosticStatus(
            snapshot: DiagnosticSnapshot(
                hasGroqAPIKey: true,
                isAccessibilityTrusted: true,
                microphonePermission: .authorized,
                debugLogPath: "/tmp/debug.log",
                debugLogExists: true
            )
        )

        #expect(status.kind == .ready)
        #expect(status.title == "診断結果: 使用できます")
        #expect(status.message.contains("✅ Groq APIキー: 設定済み"))
        #expect(status.message.contains("✅ アクセシビリティ: 許可済み"))
        #expect(status.message.contains("✅ マイク: 許可済み"))
        #expect(status.message.contains("録音できる状態です"))
    }

    @Test("shows concrete next actions for missing setup pieces")
    func blockedSnapshot() {
        let status = DiagnosticStatus(
            snapshot: DiagnosticSnapshot(
                hasGroqAPIKey: false,
                isAccessibilityTrusted: false,
                microphonePermission: .denied,
                debugLogPath: "/Users/test/Library/Application Support/APIVoiceInput/debug.log",
                debugLogExists: false
            )
        )

        #expect(status.kind == .needsAttention)
        #expect(status.title == "診断結果: 確認が必要です")
        #expect(status.message.contains("⚠️ Groq APIキー: 未設定"))
        #expect(status.message.contains("メニューの「Groq APIキーを設定…」"))
        #expect(status.message.contains("⚠️ アクセシビリティ: 未許可"))
        #expect(status.message.contains("⚠️ マイク: 拒否または制限中"))
        #expect(status.message.contains("⚠️ debug.log: まだ作成されていません"))
        #expect(status.message.contains("/Users/test/Library/Application Support/APIVoiceInput/debug.log"))
    }

    @Test("describes not determined microphone permission without treating it as permanently denied")
    func notDeterminedMicrophone() {
        let status = DiagnosticStatus(
            snapshot: DiagnosticSnapshot(
                hasGroqAPIKey: true,
                isAccessibilityTrusted: true,
                microphonePermission: .notDetermined,
                debugLogPath: "/tmp/debug.log",
                debugLogExists: true
            )
        )

        #expect(status.kind == .needsAttention)
        #expect(status.message.contains("⚠️ マイク: 未確認"))
        #expect(status.message.contains("アプリ起動時の確認で許可してください"))
    }
}
