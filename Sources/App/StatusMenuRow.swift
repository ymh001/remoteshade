import AppKit

/// Read-only status with a stable label color and a colored indicator.
final class StatusMenuRow: NSView {
    private var text = ""
    private var color = NSColor.secondaryLabelColor
    private var emphasized = false
    private var revision = 0

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
        autoresizingMask = [.width]
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(text: String, color: NSColor, detail: String? = nil) {
        toolTip = detail
        guard self.text != text || self.color != color else { return }
        emphasized = !self.text.isEmpty
        self.text = text
        self.color = color
        revision += 1
        let current = revision
        setAccessibilityLabel(text)
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self = self, self.revision == current else { return }
            self.emphasized = false
            self.needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if emphasized {
            color.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 5, yRadius: 5).fill()
        }
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 10, y: bounds.midY - 3.5, width: 7, height: 7)).fill()
        let font = NSFont.menuFont(ofSize: 0)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let height = font.ascender - font.descender + font.leading
        (text as NSString).draw(in: NSRect(x: 24, y: (bounds.height - height) / 2, width: bounds.width - 34, height: height + 2), withAttributes: [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph])
    }
}
