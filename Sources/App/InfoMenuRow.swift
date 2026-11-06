import AppKit

/// A menu-style toggle with a separate, timed explanation target.
final class InfoMenuRow: NSView {
    var checked = false { didSet { if oldValue != checked { needsDisplay = true } } }
    var mixed = false { didSet { if oldValue != mixed { needsDisplay = true } } }
    var title: String { didSet { if oldValue != title { setAccessibilityLabel(title); needsDisplay = true } } }
    var enabled = true { didSet { if oldValue != enabled { setAccessibilityEnabled(enabled); needsDisplay = true } } }
    private let explanationText: String
    private let isToggle: Bool
    var onToggle: (() -> Void)?
    private var highlighted = false
    private var tracking: NSTrackingArea?
    private var hoverTimer: Timer?
    private var explanation: NSPanel?
    private var overInfo = false
    private var infoRect: NSRect { NSRect(x: bounds.width - 28, y: (bounds.height - 16) / 2, width: 16, height: 16) }

    init(title: String, explanation: String, isToggle: Bool = true) {
        self.title = title
        self.explanationText = explanation
        self.isToggle = isToggle
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        autoresizingMask = [.width]
        setAccessibilityElement(true)
        setAccessibilityRole(isToggle ? .checkBox : .button)
        setAccessibilityLabel(title)
        setAccessibilityHelp(explanation)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func accessibilityValue() -> Any? { isToggle ? (mixed ? 2 : (checked ? 1 : 0)) : nil }
    override func accessibilityPerformPress() -> Bool { activate(); return true }

    override func draw(_ dirtyRect: NSRect) {
        if highlighted && enabled {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 0), xRadius: 4, yRadius: 4).fill()
        }
        let color: NSColor = enabled ? (highlighted ? .alternateSelectedControlTextColor : .labelColor) : .disabledControlTextColor
        let font = NSFont.menuFont(ofSize: 0)
        let text = title as NSString
        let size = text.size(withAttributes: [.font: font])
        text.draw(at: NSPoint(x: 24, y: (bounds.height - size.height) / 2), withAttributes: [.font: font, .foregroundColor: color])
        if mixed && isToggle {
            color.setFill()
            NSRect(x: 7, y: bounds.midY - 0.8, width: 9, height: 1.6).fill()
        } else if checked && isToggle {
            color.setStroke()
            let check = NSBezierPath()
            check.lineWidth = 1.6
            check.lineCapStyle = .round
            check.move(to: NSPoint(x: 7, y: bounds.midY))
            check.line(to: NSPoint(x: 10, y: bounds.midY - 3))
            check.line(to: NSPoint(x: 16, y: bounds.midY + 4))
            check.stroke()
        }
        color.withAlphaComponent(highlighted ? 1 : 0.65).setStroke()
        let circle = NSBezierPath(ovalIn: infoRect.insetBy(dx: 1.5, dy: 1.5))
        circle.lineWidth = 1.2
        circle.stroke()
        let mark = NSBezierPath()
        mark.lineWidth = 1.2
        mark.lineCapStyle = .round
        mark.move(to: NSPoint(x: infoRect.midX, y: infoRect.midY + 3))
        mark.line(to: NSPoint(x: infoRect.midX, y: infoRect.midY))
        mark.stroke()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: infoRect.midX - 0.7, y: infoRect.midY - 3.3, width: 1.4, height: 1.4)).fill()
    }

    override func updateTrackingAreas() {
        if let tracking = tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect], owner: self)
        tracking = area
        addTrackingArea(area)
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { highlighted = true; needsDisplay = true; trackInfo(event) }
    override func mouseMoved(with event: NSEvent) { trackInfo(event) }
    override func mouseExited(with event: NSEvent) { highlighted = false; needsDisplay = true; dismissExplanation() }
    override func mouseUp(with event: NSEvent) {
        if infoRect.insetBy(dx: -4, dy: -4).contains(convert(event.locationInWindow, from: nil)) { showExplanation() }
        else { activate() }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 || event.keyCode == 36 { activate() } else { super.keyDown(with: event) }
    }
    private func activate() {
        guard enabled else { return }
        dismissExplanation()
        onToggle?()
        enclosingMenuItem?.menu?.cancelTracking()
    }
    private func trackInfo(_ event: NSEvent) {
        let inside = infoRect.insetBy(dx: -4, dy: -4).contains(convert(event.locationInWindow, from: nil))
        guard inside != overInfo else { return }
        dismissExplanation()
        overInfo = inside
        guard inside else { return }
        let timer = Timer(timeInterval: 0.5, repeats: false) { [weak self] _ in self?.showExplanation() }
        hoverTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
    }
    func dismissExplanation() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        explanation?.orderOut(nil)
        explanation = nil
        overInfo = false
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        dismissExplanation()
        super.viewWillMove(toWindow: newWindow)
    }
    private func showExplanation() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        guard explanation == nil, let window = window else { return }
        let label = NSTextField(wrappingLabelWithString: explanationText)
        label.font = .systemFont(ofSize: 12)
        let textHeight = ceil(label.sizeThatFits(NSSize(width: 250, height: CGFloat.greatestFiniteMagnitude)).height)
        let panelHeight = textHeight + 20
        label.frame = NSRect(x: 12, y: 10, width: 250, height: textHeight)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 274, height: panelHeight), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        let background = NSVisualEffectView(frame: panel.contentView!.bounds)
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true
        background.addSubview(label)
        panel.contentView = background
        let anchor = window.convertToScreen(convert(infoRect, to: nil))
        let visible = window.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        var x = window.frame.maxX + 8
        if x + 274 > visible.maxX { x = window.frame.minX - 282 }
        x = max(visible.minX, min(x, visible.maxX - 274))
        let y = max(visible.minY, min(anchor.maxY - panelHeight, visible.maxY - panelHeight))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        explanation = panel
        panel.orderFrontRegardless()
    }
}
