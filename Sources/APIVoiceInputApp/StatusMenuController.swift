import AppKit

@MainActor
final class StatusMenuController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let toggleAction: () -> Void
    private let openAccessibilitySettings: () -> Void
    private let openGroqAPIKeyPage: () -> Void
    private let openSetupGuide: () -> Void
    private let setGroqAPIKey: () -> Void
    private let showGroqAPIKeyStatus: () -> Void
    private let getMediaControlEnabled: () -> Bool
    private let setMediaControlEnabled: (Bool) -> Void
    private let mediaControlItem: NSMenuItem

    init(
        toggleAction: @escaping () -> Void,
        openAccessibilitySettings: @escaping () -> Void,
        openGroqAPIKeyPage: @escaping () -> Void,
        openSetupGuide: @escaping () -> Void,
        setGroqAPIKey: @escaping () -> Void,
        showGroqAPIKeyStatus: @escaping () -> Void,
        getMediaControlEnabled: @escaping () -> Bool,
        setMediaControlEnabled: @escaping (Bool) -> Void
    ) {
        self.toggleAction = toggleAction
        self.openAccessibilitySettings = openAccessibilitySettings
        self.openGroqAPIKeyPage = openGroqAPIKeyPage
        self.openSetupGuide = openSetupGuide
        self.setGroqAPIKey = setGroqAPIKey
        self.showGroqAPIKeyStatus = showGroqAPIKeyStatus
        self.getMediaControlEnabled = getMediaControlEnabled
        self.setMediaControlEnabled = setMediaControlEnabled
        self.mediaControlItem = NSMenuItem(title: "録音開始時にYouTubeを一時停止", action: #selector(toggleMediaControl), keyEquivalent: "")
        super.init()
        item.button?.title = "🎙"
        let toggle = NSMenuItem(title: "録音開始/停止", action: #selector(toggleRecording), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        mediaControlItem.target = self
        mediaControlItem.state = getMediaControlEnabled() ? .on : .off
        menu.addItem(mediaControlItem)
        menu.addItem(NSMenuItem.separator())
        let setupGuide = NSMenuItem(title: "初回セットアップを開く", action: #selector(openFirstRunSetupGuide), keyEquivalent: "")
        setupGuide.target = self
        menu.addItem(setupGuide)
        let getGroqKey = NSMenuItem(title: "無料のGroq APIキーを取得", action: #selector(openGroqKeyPage), keyEquivalent: "")
        getGroqKey.target = self
        menu.addItem(getGroqKey)
        let setGroqKey = NSMenuItem(title: "Groq APIキーを設定…", action: #selector(setGroqKey), keyEquivalent: "")
        setGroqKey.target = self
        menu.addItem(setGroqKey)
        let groqKeyStatus = NSMenuItem(title: "Groq APIキー設定状況", action: #selector(showGroqKeyStatus), keyEquivalent: "")
        groqKeyStatus.target = self
        menu.addItem(groqKeyStatus)
        menu.addItem(NSMenuItem.separator())
        let accessibility = NSMenuItem(title: "アクセシビリティ設定を開く", action: #selector(openAccessibility), keyEquivalent: "")
        accessibility.target = self
        menu.addItem(accessibility)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    @objc private func toggleRecording() {
        toggleAction()
    }

    @objc private func openAccessibility() {
        openAccessibilitySettings()
    }

    @objc private func openFirstRunSetupGuide() {
        openSetupGuide()
    }

    @objc private func openGroqKeyPage() {
        openGroqAPIKeyPage()
    }

    @objc private func setGroqKey() {
        setGroqAPIKey()
    }

    @objc private func showGroqKeyStatus() {
        showGroqAPIKeyStatus()
    }

    @objc private func toggleMediaControl() {
        let nextValue = getMediaControlEnabled() == false
        setMediaControlEnabled(nextValue)
        mediaControlItem.state = nextValue ? .on : .off
    }

    func setConversationModeActive(_ active: Bool) {
        item.button?.title = active ? "💬" : "🎙"
    }
}
