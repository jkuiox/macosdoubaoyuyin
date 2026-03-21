import Cocoa

class OverlayWindow {
    private var window: NSWindow?
    private var micView: MicIndicatorView?

    func show() {
        guard window == nil else { return }

        let size: CGFloat = 64
        guard let screen = NSScreen.main else { return }

        // Position: centered horizontally, just above the dock
        let dockHeight: CGFloat = 80
        let x = (screen.frame.width - size) / 2
        let y = dockHeight

        let frame = NSRect(x: x, y: y, width: size, height: size)
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

        let view = MicIndicatorView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        win.contentView = view
        self.micView = view
        self.window = win

        win.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
        micView = nil
    }

    func updateLevel(_ level: Float) {
        micView?.audioLevel = CGFloat(level)
    }
}

class MicIndicatorView: NSView {
    var audioLevel: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let baseRadius: CGFloat = 20
        let pulseRadius = baseRadius + audioLevel * 10

        // Glow ring
        let glowAlpha = 0.2 + audioLevel * 0.4
        context.setFillColor(NSColor.systemRed.withAlphaComponent(glowAlpha).cgColor)
        context.fillEllipse(in: CGRect(
            x: center.x - pulseRadius - 4,
            y: center.y - pulseRadius - 4,
            width: (pulseRadius + 4) * 2,
            height: (pulseRadius + 4) * 2
        ))

        // Main circle
        let circleAlpha = 0.8 + audioLevel * 0.2
        context.setFillColor(NSColor.systemRed.withAlphaComponent(circleAlpha).cgColor)
        context.fillEllipse(in: CGRect(
            x: center.x - baseRadius,
            y: center.y - baseRadius,
            width: baseRadius * 2,
            height: baseRadius * 2
        ))

        // Mic icon (simplified)
        let iconColor = NSColor.white
        iconColor.setFill()

        // Mic body
        let micWidth: CGFloat = 8
        let micHeight: CGFloat = 14
        let micRect = CGRect(
            x: center.x - micWidth / 2,
            y: center.y - 2,
            width: micWidth,
            height: micHeight
        )
        let micPath = NSBezierPath(roundedRect: micRect, xRadius: micWidth / 2, yRadius: micWidth / 2)
        micPath.fill()

        // Mic arc
        let arcPath = NSBezierPath()
        arcPath.lineWidth = 2
        iconColor.setStroke()
        let arcRadius: CGFloat = 7
        arcPath.appendArc(
            withCenter: CGPoint(x: center.x, y: center.y + micHeight / 2 - 2),
            radius: arcRadius,
            startAngle: 200,
            endAngle: 340
        )
        arcPath.stroke()

        // Mic stand
        let standPath = NSBezierPath()
        standPath.lineWidth = 2
        standPath.move(to: CGPoint(x: center.x, y: center.y - 4))
        standPath.line(to: CGPoint(x: center.x, y: center.y - 8))
        standPath.move(to: CGPoint(x: center.x - 4, y: center.y - 8))
        standPath.line(to: CGPoint(x: center.x + 4, y: center.y - 8))
        standPath.stroke()
    }
}
