import AppKit

@MainActor
final class TranscriptPopupController {
    private var panel: NSPanel?
    private var dismissTimer: Timer?
    private var storedText: String = ""

    func show(text: String, autoHideAfter seconds: TimeInterval = 3) {
        dismiss()
        storedText = text
        let panel = buildPanel(text: text)
        positionPanel(panel)
        panel.alphaValue = 0.28
        panel.orderFrontRegardless()
        self.panel = panel
        scheduleDismiss(after: seconds)
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)
            }
        })
    }

    private func onHoverEnter() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel?.animator().alphaValue = 1.0
        }
    }

    private func onHoverExit() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel?.animator().alphaValue = 0.28
        }
        scheduleDismiss(after: 8)
    }

    private func scheduleDismiss(after seconds: TimeInterval) {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.dismiss() }
        }
    }

    private func buildPanel(text: String) -> NSPanel {
        // --- 寸法定義 ---
        let W: CGFloat       = 300
        let hPad: CGFloat    = 14
        let topPad: CGFloat  = 12
        let botPad: CGFloat  = 10
        let btnH: CGFloat    = 22
        let btnGap: CGFloat  = 8
        let closeSz: CGFloat = 18

        let display = text.count > 100 ? String(text.prefix(100)) + "…" : text
        let font     = NSFont.systemFont(ofSize: 13)
        // ラベル幅 = 全体 - 左pad - 閉じるボタン幅 - 閉じるボタン右余白 - ギャップ
        let labelW   = W - hPad - closeSz - 10 - 4
        let textH    = max(18, ceil((display as NSString).boundingRect(
            with: CGSize(width: labelW, height: 400),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        ).height))
        let H = topPad + textH + btnGap + btnH + botPad

        // --- Panel ---
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: W, height: H),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = true
        panel.ignoresMouseEvents = false

        // --- ルートビュー ---
        let root = HoverView(
            frame: NSRect(x: 0, y: 0, width: W, height: H),
            onHoverEnter: { [weak self] in self?.onHoverEnter() },
            onHoverExit:  { [weak self] in self?.onHoverExit() }
        )
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.97, alpha: 0.96).cgColor
        root.layer?.cornerRadius = 12
        root.layer?.borderWidth = 1
        root.layer?.borderColor = NSColor.black.withAlphaComponent(0.12).cgColor

        // --- 閉じるボタン（右上） macOS座標: y=0が下 ---
        let closeBtn = NonActivatingButton(title: "✕", target: self, action: #selector(closeTapped))
        closeBtn.isBordered = false
        closeBtn.font = .systemFont(ofSize: 11)
        closeBtn.contentTintColor = NSColor.black.withAlphaComponent(0.35)
        closeBtn.frame = NSRect(x: W - 10 - closeSz, y: H - 8 - closeSz, width: closeSz, height: closeSz)

        // --- テキストラベル ---
        let label = NSTextField(wrappingLabelWithString: display)
        label.font = font
        label.textColor = NSColor(calibratedWhite: 0.1, alpha: 1.0)
        label.frame = NSRect(x: hPad, y: botPad + btnH + btnGap, width: labelW, height: textH)

        // --- 貼り付けボタン（左下） ---
        let pasteBtn = makeActionButton(title: "貼り付け", action: #selector(pasteText))
        pasteBtn.frame = NSRect(x: hPad, y: botPad, width: 90, height: btnH)

        root.addSubview(label)
        root.addSubview(pasteBtn)
        root.addSubview(closeBtn)
        panel.contentView = root
        return panel
    }

    private func makeActionButton(title: String, action: Selector) -> NonActivatingButton {
        let btn = NonActivatingButton(title: "", target: self, action: action)
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.backgroundColor = NSColor(calibratedWhite: 0.88, alpha: 1.0).cgColor
        btn.layer?.cornerRadius = 5
        btn.layer?.borderWidth = 0.8
        btn.layer?.borderColor = NSColor.black.withAlphaComponent(0.18).cgColor
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor(calibratedWhite: 0.1, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 12)
        ]
        btn.attributedTitle = NSAttributedString(string: title, attributes: attrs)
        return btn
    }

    @objc private func pasteText() {
        let src  = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        DebugLog.write("transcriptPopup paste sent")
        dismiss()
    }

    @objc private func closeTapped() {
        dismiss()
    }

    private func positionPanel(_ panel: NSPanel) {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrame(NSRect(
            x: screen.midX - panel.frame.width / 2,
            y: screen.minY + 90,
            width: panel.frame.width,
            height: panel.frame.height
        ), display: true)
    }
}

private final class NonActivatingButton: NSButton {
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class HoverView: NSView {
    private let onHoverEnter: () -> Void
    private let onHoverExit: () -> Void

    init(frame: NSRect, onHoverEnter: @escaping () -> Void, onHoverExit: @escaping () -> Void) {
        self.onHoverEnter = onHoverEnter
        self.onHoverExit = onHoverExit
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        ))
    }

    required init?(coder: NSCoder) { nil }
    override func mouseEntered(with event: NSEvent) { onHoverEnter() }
    override func mouseExited(with event: NSEvent) { onHoverExit() }
}
