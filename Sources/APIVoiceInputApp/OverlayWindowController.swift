import AppKit
import APIVoiceInputCore

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
        case conversationWaiting = "待機中"
    }

    private let window: NSWindow
    private let waveformView = WaveformView()
    private let progressView = ProcessingGaugeView()
    private let style = RecordingOverlayVisualStyle.typelessInspired
    private let contentView = NSView()

    init() {
        waveformView.translatesAutoresizingMaskIntoConstraints = false
        progressView.translatesAutoresizingMaskIntoConstraints = false

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor(calibratedWhite: 0.035, alpha: 0.90).cgColor
        contentView.layer?.cornerRadius = CGFloat(style.cornerRadius)
        contentView.layer?.masksToBounds = true
        contentView.layer?.borderWidth = 1.1
        contentView.layer?.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
        contentView.addSubview(progressView)
        contentView.addSubview(waveformView)

        NSLayoutConstraint.activate([
            waveformView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            waveformView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            waveformView.widthAnchor.constraint(equalToConstant: CGFloat(style.waveformWidth)),
            waveformView.heightAnchor.constraint(equalToConstant: CGFloat(style.waveformHeight)),

            progressView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            progressView.topAnchor.constraint(equalTo: contentView.topAnchor),
            progressView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: style.windowWidth, height: style.windowHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = contentView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = true
        window.hasShadow = true
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

    func setConversationGlow(_ active: Bool) {
        let layer = contentView.layer
        if active {
            layer?.borderWidth = 2.5
            layer?.borderColor = NSColor(calibratedRed: 0.2, green: 0.75, blue: 1.0, alpha: 1.0).cgColor
            let pulse = CABasicAnimation(keyPath: "borderColor")
            pulse.fromValue = NSColor(calibratedRed: 0.2, green: 0.75, blue: 1.0, alpha: 1.0).cgColor
            pulse.toValue = NSColor(calibratedRed: 0.2, green: 0.75, blue: 1.0, alpha: 0.25).cgColor
            pulse.duration = 1.2
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer?.add(pulse, forKey: "conversationGlow")
        } else {
            layer?.removeAnimation(forKey: "conversationGlow")
            layer?.borderWidth = 1.1
            layer?.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
        }
    }

    func updateRecordingLevel(_ level: Double) {
        waveformView.updateAudioLevel(level)
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
        case .pasted:
            waveformView.isHidden = true
            progressView.isHidden = false
            waveformView.stopAnimating()
            progressView.showComplete()
        case .failed, .canceled:
            waveformView.isHidden = true
            progressView.isHidden = false
            waveformView.stopAnimating()
            progressView.showIdle()
        case .conversationWaiting:
            waveformView.isHidden = false
            progressView.isHidden = true
            waveformView.startAnimating()
            progressView.stopAnimating()
        }
    }

    private func positionWindow() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = CGFloat(style.windowWidth)
        let height = CGFloat(style.windowHeight)
        let x = screen.midX - width / 2
        let y = screen.minY + 36
        window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}

private final class WaveformView: NSView {
    private var timer: Timer?
    private var phase: CGFloat = 0
    private var targetLevel: CGFloat = 0
    private var displayedLevel: CGFloat = 0
    private let style = RecordingOverlayVisualStyle.typelessInspired

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
                self.phase += 0.28
                let reactiveTarget = Self.visualLevel(from: self.targetLevel)
                let attack: CGFloat = reactiveTarget > self.displayedLevel ? 0.62 : 0.26
                self.displayedLevel += (reactiveTarget - self.displayedLevel) * attack
                self.needsDisplay = true
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func updateAudioLevel(_ level: Double) {
        targetLevel = min(max(CGFloat(level), 0), 1)
    }

    private static func visualLevel(from level: CGFloat) -> CGFloat {
        let lifted = max(0, (level - 0.10) * 1.45)
        return min(0.86, pow(lifted, 0.76))
    }

    func stopAnimating() {
        timer?.invalidate()
        timer = nil
        phase = 0
        targetLevel = 0
        displayedLevel = 0
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 0, bounds.height > 0 else { return }

        let barCount = style.waveformBarCount
        let barWidth = CGFloat(style.waveformBarWidth)
        let gap = (bounds.width - CGFloat(barCount) * barWidth) / CGFloat(max(barCount - 1, 1))
        let midY = bounds.midY
        let maxHeight = bounds.height - 2
        let color = NSColor.white.withAlphaComponent(0.92)
        color.setFill()
        let heightFactors = RecordingWaveformShape.barHeightFactors(
            level: Double(displayedLevel),
            phase: Double(phase),
            barCount: barCount
        )

        for index in 0..<barCount {
            let x = CGFloat(index) * (barWidth + gap)
            let visualLevel = CGFloat(heightFactors[index])
            let height = max(2.8, visualLevel * maxHeight)
            let rect = NSRect(x: x, y: midY - height / 2, width: barWidth, height: height)
            NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        }
    }
}

private final class ProcessingGaugeView: NSView {
    private var timer: Timer?
    private var phase: CGFloat = 0
    private var pulse: CGFloat = 0
    private let style = ProcessingGaugeVisualStyle.typelessInspired

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
        phase = 0
        pulse = 0
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.phase < 0.94 {
                    self.phase = min(0.94, self.phase + 0.018)
                } else {
                    self.pulse += 0.12
                }
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

    func showComplete() {
        stopAnimating()
        phase = 1
        isHidden = false
        needsDisplay = true
    }

    func stopAnimating() {
        timer?.invalidate()
        timer = nil
        phase = 0
        pulse = 0
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 0, bounds.height > 0 else { return }

        guard phase > 0 else { return }

        let fillWidth = bounds.width * min(max(phase, 0), 1)
        let fillRect = NSRect(x: bounds.minX, y: bounds.minY, width: fillWidth, height: bounds.height)
        let alpha: CGFloat = phase >= 0.94
            ? style.fillAlpha * (0.55 + 0.45 * CGFloat((sin(Double(pulse)) + 1) * 0.5))
            : style.fillAlpha
        NSColor(
            calibratedRed: style.fillRed,
            green: style.fillGreen,
            blue: style.fillBlue,
            alpha: alpha
        ).setFill()
        NSBezierPath(rect: fillRect).fill()
    }
}
