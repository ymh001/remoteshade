import AppKit

/// Template silhouette of the approved curtains hanging below a monitor bezel.
enum MenuBarIcon {
    static func make(color: NSColor = .black) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 20), flipped: false) { _ in
            color.setFill()
            color.setStroke()
            let frame = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 5, width: 19, height: 13), xRadius: 1.5, yRadius: 1.5)
            frame.lineWidth = 1.2
            frame.stroke()
            NSBezierPath(rect: NSRect(x: 10.2, y: 1.5, width: 1.6, height: 3.7)).fill()
            NSBezierPath(roundedRect: NSRect(x: 6.7, y: 0.7, width: 8.6, height: 1.4), xRadius: 0.7, yRadius: 0.7).fill()

            let curtain = NSBezierPath()
            curtain.move(to: NSPoint(x: 2.5, y: 16.7))
            curtain.line(to: NSPoint(x: 10.25, y: 16.7))
            curtain.curve(to: NSPoint(x: 9.15, y: 4), controlPoint1: NSPoint(x: 10.1, y: 12), controlPoint2: NSPoint(x: 9.6, y: 8))
            curtain.curve(to: NSPoint(x: 7.1, y: 3.7), controlPoint1: NSPoint(x: 8.4, y: 3.5), controlPoint2: NSPoint(x: 7.8, y: 4.1))
            curtain.curve(to: NSPoint(x: 4.9, y: 3.8), controlPoint1: NSPoint(x: 6.3, y: 3.3), controlPoint2: NSPoint(x: 5.6, y: 4.2))
            curtain.curve(to: NSPoint(x: 1.8, y: 4), controlPoint1: NSPoint(x: 3.8, y: 3.3), controlPoint2: NSPoint(x: 2.7, y: 4.3))
            curtain.curve(to: NSPoint(x: 2.5, y: 16.7), controlPoint1: NSPoint(x: 2.3, y: 7.5), controlPoint2: NSPoint(x: 2.4, y: 13))
            curtain.close()
            curtain.fill()
            let right = curtain.copy() as! NSBezierPath
            var mirror = AffineTransform(scaleByX: -1, byY: 1)
            mirror.translate(x: -22, y: 0)
            right.transform(using: mirror)
            right.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "RemoteShade"
        return image
    }
}
