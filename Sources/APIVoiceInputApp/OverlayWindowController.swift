import AppKit

@MainActor
final class OverlayWindowController {
    enum State: String {
        case recording = "録音中"
        case transcribing = "文字起こし中"
        case cleaning = "清書中"
        case pasted = "貼り付けました"
        case failed = "失敗しました"
        case canceled = "音声なし"
    }

    private let window: NSWindow
    private let label: NSTextField

    init() {
        label = NSTextField(labelWithString: "")
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSVisualEffectView()
        contentView.material = .hudWindow
        contentView.blendingMode = .behindWindow
        contentView.state = .active
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 18
        contentView.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 9),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -9)
        ])

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 42),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = contentView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func show(_ state: State, detail: String? = nil) {
        label.stringValue = detail.map { "\(state.rawValue) · \($0)" } ?? state.rawValue
        positionWindow()
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
    }

    private func positionWindow() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width: CGFloat = 260
        let height: CGFloat = 42
        let x = screen.midX - width / 2
        let y = screen.minY + 36
        window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}
