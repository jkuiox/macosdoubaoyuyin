import Cocoa

class OverlayWindow {
    private var window: NSWindow?
    private var micView: MicIndicatorView?

    func show() {
        guard window == nil else { return }
        guard let screen = NSScreen.main else { return }

        let capsuleWidth: CGFloat = 180
        let capsuleHeight: CGFloat = 44

        // Position: centered horizontally, just above the dock
        let dockHeight: CGFloat = 80
        let x = (screen.frame.width - capsuleWidth) / 2
        let y = dockHeight

        let frame = NSRect(x: x, y: y, width: capsuleWidth, height: capsuleHeight)
        let win = NSWindow(contentRect: frame,
                           styleMask: .borderless,
                           backing: .buffered,
                           defer: false)
        win.level = .floating
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let view = MicIndicatorView(frame: NSRect(x: 0, y: 0, width: capsuleWidth, height: capsuleHeight))
        win.contentView = view
        self.micView = view
        self.window = win

        // Enter animation: scale from 0 to 1
        win.alphaValue = 0
        win.orderFrontRegardless()
        view.startAnimation()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            win.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let win = window else { return }
        micView?.stopAnimation()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            win.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            win.orderOut(nil)
            self?.window = nil
            self?.micView = nil
        })
    }

    func updateLevel(_ level: Float) {
        // Audio level not used by the new wave animation design
    }
}

class MicIndicatorView: NSView {
    // MARK: - Constants
    private let barCount = 7
    private let barWidth: CGFloat = 3
    private let barGap: CGFloat = 2.5
    private let barRadius: CGFloat = 1.5
    private let minHeight: CGFloat = 5
    private let maxHeight: CGFloat = 22
    private let barColor = NSColor(calibratedRed: 180/255, green: 180/255, blue: 180/255, alpha: 0.70)
    private let labelColor = NSColor(calibratedRed: 180/255, green: 180/255, blue: 180/255, alpha: 0.75)
    private let capsuleBackground = NSColor(calibratedRed: 30/255, green: 30/255, blue: 30/255, alpha: 0.92)
    private let paddingLeft: CGFloat = 16
    private let paddingRight: CGFloat = 20
    private let barsLabelGap: CGFloat = 12

    // MARK: - State
    private var tick: Int = 0
    private var timer: Timer?
    var audioLevel: CGFloat = 0 // kept for API compatibility

    // MARK: - Lifecycle

    func startAnimation() {
        tick = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.13, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tick += 1
            self.needsDisplay = true
        }
    }

    func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Draw capsule background
        let capsulePath = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        capsuleBackground.setFill()
        capsulePath.fill()

        // Draw bars
        let barsGroupWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap
        let barsStartX = paddingLeft

        for i in 0..<barCount {
            let h = computeBarHeight(index: i, t: tick)
            let x = barsStartX + CGFloat(i) * (barWidth + barGap)
            let y = (bounds.height - h) / 2

            let barRect = CGRect(x: x, y: y, width: barWidth, height: h)
            let barPath = NSBezierPath(roundedRect: barRect, xRadius: barRadius, yRadius: barRadius)
            barColor.setFill()
            barPath.fill()
        }

        // Draw label
        let labelX = barsStartX + barsGroupWidth + barsLabelGap
        let labelText = L10n.listening
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: labelColor,
            .kern: 0.5
        ]
        let attrStr = NSAttributedString(string: labelText, attributes: attrs)
        let textSize = attrStr.size()
        let textY = (bounds.height - textSize.height) / 2
        attrStr.draw(at: NSPoint(x: labelX, y: textY))
    }

    // MARK: - Wave computation

    private func computeBarHeight(index i: Int, t: Int) -> CGFloat {
        let center = Double(barCount - 1) / 2.0
        let dist = abs(Double(i) - center) / center
        let base = 0.35 + 0.65 * (1.0 - dist * dist)

        let phase = Double(i) * 0.9 + Double(t) * 0.08
        let osc = sin(phase) * 0.3
            + sin(phase * 1.7 + 0.5) * 0.2
            + sin(phase * 0.6 + 2.1) * 0.15

        let value = max(0.15, min(1.0, base * (0.5 + osc)))
        return minHeight + CGFloat(value) * (maxHeight - minHeight)
    }
}
