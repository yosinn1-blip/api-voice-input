import AppKit

@MainActor
final class OverlayWindowController {
    enum State: String {
        case recording = "録音中"
        case transcribing = "文字起こし中"
        case cleaning = "清書中"
        case pasting = "貼り付け中"
        case pasted = "貼り付けました"
        case failed = "失敗しました"
        case canceled = "音声なし"
    }

    private let window: NSWindow
    private let waveformView = WaveformView()
    private let progressView = ProcessingGaugeView()

    init() {
        waveformView.translatesAutoresizingMaskIntoConstraints = false
        progressView.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        contentView.layer?.cornerRadius = 14
        contentView.layer?.masksToBounds = true
        contentView.layer?.borderWidth = 1
        contentView.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        contentView.addSubview(progressView)
        contentView.addSubview(waveformView)

        NSLayoutConstraint.activate([
            waveformView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            waveformView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            waveformView.widthAnchor.constraint(equalToConstant: 88),
            waveformView.heightAnchor.constraint(equalToConstant: 18),

            progressView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            progressView.topAnchor.constraint(equalTo: contentView.topAnchor),
            progressView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
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
        updateVisual(for: state)
        positionWindow()
        window.orderFrontRegardless()
    }

    func hide() {
        waveformView.stopAnimating()
        progressView.stopAnimating()
        window.orderOut(nil)
    }

    private func updateVisual(for state: State) {
        switch state {
        case .recording:
            waveformView.isHidden = false
            progressView.isHidden = true
            waveformView.startAnimating()
            progressView.stopAnimating()
        case .transcribing, .cleaning, .pasting:
            waveformView.isHidden = true
            progressView.isHidden = false
            waveformView.stopAnimating()
            progressView.startAnimating()
        case .pasted, .failed, .canceled:
            waveformView.isHidden = true
            progressView.isHidden = false
            waveformView.stopAnimating()
            progressView.showIdle()
        }
    }

    private func positionWindow() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width: CGFloat = 128
        let height: CGFloat = 32
        let x = screen.midX - width / 2
        let y = screen.minY + 36
        window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}

private final class WaveformView: NSView {
    private var timer: Timer?
    private var phase: CGFloat = 0
    private let barCount = 15

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        isHidden = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    func startAnimating() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.phase += 0.22
                self.needsDisplay = true
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopAnimating() {
        timer?.invalidate()
        timer = nil
        phase = 0
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 0, bounds.height > 0 else { return }

        let barWidth: CGFloat = 2.8
        let gap = (bounds.width - CGFloat(barCount) * barWidth) / CGFloat(max(barCount - 1, 1))
        let midY = bounds.midY
        let maxHeight = bounds.height - 2
        let color = NSColor.white.withAlphaComponent(0.92)
        color.setFill()

        for index in 0..<barCount {
            let x = CGFloat(index) * (barWidth + gap)
            let wave = sin(phase + CGFloat(index) * 0.72)
            let secondary = sin(phase * 0.58 + CGFloat(index) * 1.31)
            let normalized = (wave * 0.62 + secondary * 0.38 + 1) / 2
            let height = max(4, normalized * maxHeight)
            let rect = NSRect(x: x, y: midY - height / 2, width: barWidth, height: height)
            NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        }
    }
}

private final class ProcessingGaugeView: NSView {
    private var timer: Timer?
    private var phase: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        isHidden = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    func startAnimating() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.phase = (self.phase + 0.026).truncatingRemainder(dividingBy: 1)
                self.needsDisplay = true
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func showIdle() {
        stopAnimating()
        isHidden = false
    }

    func stopAnimating() {
        timer?.invalidate()
        timer = nil
        phase = 0
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 0, bounds.height > 0 else { return }

        let trackInset: CGFloat = 18
        let trackHeight: CGFloat = 3
        let trackRect = NSRect(
            x: bounds.minX + trackInset,
            y: bounds.midY - trackHeight / 2,
            width: max(1, bounds.width - trackInset * 2),
            height: trackHeight
        )
        NSColor.white.withAlphaComponent(0.22).setFill()
        NSBezierPath(
            roundedRect: trackRect,
            xRadius: trackHeight / 2,
            yRadius: trackHeight / 2
        ).fill()

        guard timer != nil else { return }

        let highlightWidth: CGFloat = 30
        let travel = max(1, trackRect.width - highlightWidth)
        let highlightX = trackRect.minX + phase * travel

        let glowRect = NSRect(
            x: highlightX - 8,
            y: trackRect.midY - 5,
            width: highlightWidth + 16,
            height: 10
        )
        NSColor.white.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: glowRect, xRadius: 5, yRadius: 5).fill()

        let highlightRect = NSRect(
            x: highlightX,
            y: trackRect.minY,
            width: highlightWidth,
            height: trackRect.height
        )
        NSColor.white.withAlphaComponent(0.88).setFill()
        NSBezierPath(
            roundedRect: highlightRect,
            xRadius: trackHeight / 2,
            yRadius: trackHeight / 2
        ).fill()
    }
}
