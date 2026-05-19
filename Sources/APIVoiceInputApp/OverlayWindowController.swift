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
        contentView.layer?.backgroundColor = NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.18, alpha: 0.76).cgColor
        contentView.layer?.cornerRadius = 14
        contentView.layer?.masksToBounds = true
        contentView.layer?.borderWidth = 1
        contentView.layer?.borderColor = NSColor.white.withAlphaComponent(0.26).cgColor
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
    private var targetLevel: CGFloat = 0
    private var displayedLevel: CGFloat = 0
    private let pointCount = 46
    private var waveformHistory = Array(repeating: CGFloat(0), count: 46)

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
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.phase += 0.26
                let reactiveTarget = Self.visualLevel(from: self.targetLevel)
                let attack: CGFloat = reactiveTarget > self.displayedLevel ? 0.72 : 0.34
                self.displayedLevel += (reactiveTarget - self.displayedLevel) * attack
                self.waveformHistory.removeFirst()
                self.waveformHistory.append(self.nextWaveformSample())
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

    private func nextWaveformSample() -> CGFloat {
        guard displayedLevel > 0.015 else {
            return 0.018 * sin(phase * 0.9)
        }

        let baseWave =
            0.54 * sin(phase * 2.7) +
            0.28 * sin(phase * 6.2 + 0.9) +
            0.14 * sin(phase * 12.0 + 1.7)
        let spikePhase = sin(phase * 1.45)
        let spike = spikePhase > 0.90 ? (spikePhase - 0.90) * 5.5 : 0
        let signed = (baseWave + spike) * displayedLevel
        return min(0.92, max(-0.92, signed))
    }

    func stopAnimating() {
        timer?.invalidate()
        timer = nil
        phase = 0
        targetLevel = 0
        displayedLevel = 0
        waveformHistory = Array(repeating: CGFloat(0), count: pointCount)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 0, bounds.height > 0 else { return }
        guard waveformHistory.count > 1 else { return }

        let midY = bounds.midY
        let horizontalInset: CGFloat = 9
        let usableWidth = max(1, bounds.width - horizontalInset * 2)
        let step = usableWidth / CGFloat(max(waveformHistory.count - 1, 1))
        let amplitude = bounds.height * 0.36

        let baseline = NSBezierPath()
        baseline.move(to: NSPoint(x: horizontalInset, y: midY))
        baseline.line(to: NSPoint(x: bounds.width - horizontalInset, y: midY))
        baseline.lineWidth = 1
        NSColor.white.withAlphaComponent(0.14).setStroke()
        baseline.stroke()

        for (index, sample) in waveformHistory.enumerated() {
            let x = horizontalInset + CGFloat(index) * step
            let y = midY - sample * amplitude
            let recency = CGFloat(index) / CGFloat(max(waveformHistory.count - 1, 1))
            let activity = min(1, abs(sample) * 1.35 + displayedLevel * 0.45)
            let radius = index == waveformHistory.count - 1
                ? CGFloat(2.15)
                : CGFloat(1.15 + recency * 0.22 + activity * 0.26)
            let alpha = index == waveformHistory.count - 1
                ? CGFloat(0.96)
                : CGFloat(0.30 + recency * 0.42 + activity * 0.18)

            NSColor.white.withAlphaComponent(min(alpha, 0.88)).setFill()
            let dotRect = NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            NSBezierPath(ovalIn: dotRect).fill()
        }
    }
}

private final class ProcessingGaugeView: NSView {
    private var timer: Timer?
    private var phase: CGFloat = 0
    private var pulse: CGFloat = 0

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
        NSColor(calibratedRed: 0.74, green: 0.82, blue: 0.90, alpha: 0.58).setFill()
        NSBezierPath(rect: fillRect).fill()

        let edgeAlpha = 0.34 + 0.10 * (sin(pulse) + 1) / 2
        let edgeRect = NSRect(
            x: max(bounds.minX, fillRect.maxX - 14),
            y: bounds.minY,
            width: min(18, fillWidth),
            height: bounds.height
        )
        NSColor(calibratedRed: 0.94, green: 0.97, blue: 1.0, alpha: edgeAlpha).setFill()
        NSBezierPath(rect: edgeRect).fill()
    }
}
