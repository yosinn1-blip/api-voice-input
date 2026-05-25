import Foundation

public enum DiagnosticStatusKind: Equatable {
    case ready
    case needsAttention
}

public enum DiagnosticMicrophonePermission: Equatable {
    case authorized
    case notDetermined
    case denied
    case restricted
    case unknown
}

public struct DiagnosticSnapshot: Equatable {
    public let hasGroqAPIKey: Bool
    public let isAccessibilityTrusted: Bool
    public let microphonePermission: DiagnosticMicrophonePermission
    public let debugLogPath: String
    public let debugLogExists: Bool

    public init(
        hasGroqAPIKey: Bool,
        isAccessibilityTrusted: Bool,
        microphonePermission: DiagnosticMicrophonePermission,
        debugLogPath: String,
        debugLogExists: Bool
    ) {
        self.hasGroqAPIKey = hasGroqAPIKey
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.microphonePermission = microphonePermission
        self.debugLogPath = debugLogPath
        self.debugLogExists = debugLogExists
    }
}

public struct DiagnosticStatus: Equatable {
    public let snapshot: DiagnosticSnapshot

    public init(snapshot: DiagnosticSnapshot) {
        self.snapshot = snapshot
    }

    public var kind: DiagnosticStatusKind {
        if snapshot.hasGroqAPIKey,
           snapshot.isAccessibilityTrusted,
           snapshot.microphonePermission == .authorized {
            return .ready
        }
        return .needsAttention
    }

    public var title: String {
        switch kind {
        case .ready:
            return "診断結果: 使用できます"
        case .needsAttention:
            return "診断結果: 確認が必要です"
        }
    }

    public var message: String {
        var lines: [String] = []
        lines.append(apiKeyLine)
        lines.append(accessibilityLine)
        lines.append(microphoneLine)
        lines.append(debugLogLine)
        lines.append("")
        lines.append("debug.log: \(snapshot.debugLogPath)")
        lines.append("")
        lines.append(contentsOf: nextActionLines)
        return lines.joined(separator: "\n")
    }

    private var apiKeyLine: String {
        if snapshot.hasGroqAPIKey {
            return "✅ Groq APIキー: 設定済み"
        }
        return "⚠️ Groq APIキー: 未設定"
    }

    private var accessibilityLine: String {
        if snapshot.isAccessibilityTrusted {
            return "✅ アクセシビリティ: 許可済み"
        }
        return "⚠️ アクセシビリティ: 未許可"
    }

    private var microphoneLine: String {
        switch snapshot.microphonePermission {
        case .authorized:
            return "✅ マイク: 許可済み"
        case .notDetermined:
            return "⚠️ マイク: 未確認"
        case .denied, .restricted:
            return "⚠️ マイク: 拒否または制限中"
        case .unknown:
            return "⚠️ マイク: 状態不明"
        }
    }

    private var debugLogLine: String {
        if snapshot.debugLogExists {
            return "✅ debug.log: 作成済み"
        }
        return "⚠️ debug.log: まだ作成されていません"
    }

    private var nextActionLines: [String] {
        if kind == .ready {
            return ["録音できる状態です。うまく貼り付かない場合は、ログをFinderで表示して直近の状態を確認してください。"]
        }

        var actions = ["次に確認すること:"]
        if snapshot.hasGroqAPIKey == false {
            actions.append("- メニューの「Groq APIキーを設定…」からキーを保存してください。")
        }
        if snapshot.isAccessibilityTrusted == false {
            actions.append("- 「アクセシビリティ設定を開く」からこのアプリを許可してください。")
        }
        switch snapshot.microphonePermission {
        case .authorized:
            break
        case .notDetermined:
            actions.append("- マイクは未確認です。アプリ起動時の確認で許可してください。")
        case .denied, .restricted:
            actions.append("- macOSのプライバシー設定でマイク権限を許可してください。")
        case .unknown:
            actions.append("- マイク権限の状態を確認できませんでした。macOSのプライバシー設定を確認してください。")
        }
        if snapshot.debugLogExists == false {
            actions.append("- まだログがないため、一度アプリを起動してFn操作を試してください。")
        }
        return actions
    }
}
