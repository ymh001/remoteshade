import AppKit
import CoreGraphics

final class RemoteBridge {
    static let shared = RemoteBridge()
    typealias GammaWriter = (CGDirectDisplayID, UInt32, [Float], [Float], [Float]) -> Void
    private let gammaWriter: GammaWriter
    init(gammaWriter: @escaping GammaWriter = { display, count, red, green, blue in
        CGSetDisplayTransferByTable(display, count, red, green, blue)
    }) {
        self.gammaWriter = gammaWriter
    }
    private let lock = NSRecursiveLock()
    private var protecting = true
    private var lastUIProtection = true
    var isProtecting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return protecting
    }
    func protect(_ value: Bool) {
        lock.lock()
        let changed = protecting != value
        protecting = value
        lock.unlock()
        if changed && value {
            // Drain writes queued before ownership changed before RS captures originals.
            DisplayManager.shared.globalDDCQueue.sync(flags: .barrier) {}
        }
    }
    func applyGamma(_ display: CGDirectDisplayID, _ count: UInt32, _ red: [Float], _ green: [Float], _ blue: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        guard !protecting else { return }
        gammaWriter(display, count, red, green, blue)
    }
    func refreshControls() {
        guard let app = app, app.automation.initialized else { return }
        let blocked = isProtecting
        let resumed = lastUIProtection && !blocked
        lastUIProtection = blocked
        if resumed { app.resumeDisplayPolling() }
        for display in DisplayManager.shared.displays {
            display.sliderHandler[.brightness]?.slider?.isEnabled = !blocked
            display.sliderHandler[.brightness]?.slider?.toolTip = blocked ? "远控黑屏或恢复期间暂停亮度调节" : nil
        }
        if !blocked && app.pendingDisplayConfiguration {
            app.pendingDisplayConfiguration = false
            DispatchQueue.main.async { app.configure() }
        }
    }
    func attachMenu(_ menu: NSMenu) {
        let remote = app.automation
        guard remote.initialized else { return }
        for item in [remote.remoteItem, remote.stateItem, remote.brightnessItem, remote.displayItem] {
            item.menu?.removeItem(item)
        }
        menu.insertItem(remote.stateItem, at: 0)
        menu.insertItem(remote.remoteItem, at: 0)
        menu.insertItem(.separator(), at: 2)
        menu.addItem(.separator())
        menu.addItem(remote.brightnessItem)
        menu.addItem(remote.displayItem)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "设置…", action: #selector(AppDelegate.prefsClicked(_:)), keyEquivalent: ",")
        settings.target = app
        settings.view = RemoteShadeMenuActionView(title: "设置…", shortcut: "⌘,")
        menu.addItem(settings)
        let quit = NSMenuItem(title: "退出 RemoteShade", action: #selector(AppDelegate.quitClicked(_:)), keyEquivalent: "q")
        quit.target = app
        quit.view = RemoteShadeMenuActionView(title: "退出 RemoteShade", shortcut: "⌘Q")
        menu.addItem(quit)
        refreshControls()
    }
}

/// Uses the same text and trailing insets as the custom control rows.
final class RemoteShadeMenuActionView: NSView {
    private let title: String
    private let shortcut: String
    private var highlighted = false
    private var tracking: NSTrackingArea?

    init(title: String, shortcut: String) {
        self.title = title
        self.shortcut = shortcut
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
        autoresizingMask = [.width]
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        if highlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 0), xRadius: 4, yRadius: 4).fill()
        }
        let color: NSColor = highlighted ? .alternateSelectedControlTextColor : .labelColor
        let font = NSFont.menuFont(ofSize: 0)
        let height = (title as NSString).size(withAttributes: [.font: font]).height
        (title as NSString).draw(at: NSPoint(x: 24, y: (bounds.height - height) / 2), withAttributes: [.font: font, .foregroundColor: color])
        let size = (shortcut as NSString).size(withAttributes: [.font: font])
        (shortcut as NSString).draw(at: NSPoint(x: bounds.width - 24 - size.width, y: (bounds.height - size.height) / 2), withAttributes: [.font: font, .foregroundColor: highlighted ? color : NSColor.secondaryLabelColor])
    }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        tracking = area
        addTrackingArea(area)
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { highlighted = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { highlighted = false; needsDisplay = true }
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        activate()
    }
    override func accessibilityPerformPress() -> Bool { activate(); return true }
    private func activate() {
        guard let item = enclosingMenuItem, let menu = item.menu, item.isEnabled else { return }
        let index = menu.index(of: item)
        menu.cancelTracking()
        menu.performActionForItem(at: index)
    }
}
