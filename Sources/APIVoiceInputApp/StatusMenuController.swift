import AppKit

@MainActor
final class StatusMenuController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let toggleAction: () -> Void

    init(toggleAction: @escaping () -> Void) {
        self.toggleAction = toggleAction
        super.init()
        item.button?.title = "🎙"
        let toggle = NSMenuItem(title: "録音開始/停止", action: #selector(toggleRecording), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    @objc private func toggleRecording() {
        toggleAction()
    }
}
