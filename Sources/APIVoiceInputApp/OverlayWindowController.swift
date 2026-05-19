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
        contentView.layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 0.74).cgColor
        contentView.layer?.cornerRadius = 14
        contentView.layer?.masksToBounds = true
        contentView.layer?.borderWidth = 1
        contentView.layer?.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
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

        guard timer != nil else { return }

        let bandWidth = bounds.width * 0.52
        let travel = bounds.width + bandWidth
        let bandX = phase * travel - bandWidth

        let leadingRect = NSRect(
            x: bandX - bandWidth * 0.45,
            y: 0,
            width: bandWidth * 0.45,
            height: bounds.height
        )
        NSColor(calibratedWhite: 0.68, alpha: 0.08).setFill()
        NSBezierPath(rect: leadingRect).fill()

        let bandRect = NSRect(
            x: bandX,
            y: 0,
            width: bandWidth,
            height: bounds.height
        )
        NSColor(calibratedWhite: 0.72, alpha: 0.23).setFill()
        NSBezierPath(rect: bandRect).fill()

        let coreRect = NSRect(
            x: bandX + bandWidth * 0.42,
            y: 0,
            width: bandWidth * 0.18,
            height: bounds.height
        )
        NSColor(calibratedWhite: 0.82, alpha: 0.26).setFill()
        NSBezierPath(rect: coreRect).fill()

        let trailingRect = NSRect(
            x: bandX + bandWidth,
            y: 0,
            width: bandWidth * 0.45,
            height: bounds.height
        )
        NSColor(calibratedWhite: 0.68, alpha: 0.08).setFill()
        NSBezierPath(rect: trailingRect).fill()
    }
}
