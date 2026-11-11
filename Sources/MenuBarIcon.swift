import AppKit

/// Two little speakers in the app icon's peach-to-purple palette; the front one has a face.
/// Drawn at display time so it follows the menu bar's light or dark appearance.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
            draw(dark: NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Multi-output volume"
        return image
    }()

    private static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    private static func draw(dark: Bool) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let ink = color(0x3B2255)
        let outline = dark ? nil : color(0x3B2255, 0.45)

        let back = NSBezierPath(roundedRect: NSRect(x: 1, y: 2.5, width: 10, height: 13), xRadius: 3, yRadius: 3)
        let front = NSBezierPath(roundedRect: NSRect(x: 9, y: 1, width: 12, height: 16), xRadius: 3.5, yRadius: 3.5)

        // A transparency layer lets the gap around the front speaker cut only the back speaker.
        context.beginTransparencyLayer(auxiliaryInfo: nil)

        NSGradient(starting: color(0xEBDCFF), ending: color(0xBE9BFF))!.draw(in: back, angle: -70)
        outline.map { stroke(back, $0, width: 0.6) }
        color(0xFFFFFF, 0.9).setFill()
        NSBezierPath(ovalIn: NSRect(x: 4.6, y: 11.2, width: 2.6, height: 2.6)).fill()
        let woofer = NSBezierPath(ovalIn: NSRect(x: 3.2, y: 4.6, width: 5.4, height: 5.4))
        woofer.fill()
        color(0x9C7BE0).setFill()
        NSBezierPath(ovalIn: NSRect(x: 4.9, y: 6.3, width: 2, height: 2)).fill()

        NSGraphicsContext.current?.compositingOperation = .clear
        stroke(front, .black, width: 2.4)
        NSGraphicsContext.current?.compositingOperation = .sourceOver

        NSGradient(colors: [color(0xFFB199), color(0xFF8FB1), color(0xB07CFF)])!.draw(in: front, angle: -60)
        outline.map { stroke(front, $0, width: 0.6) }

        color(0xFFFFFF, 0.95).setFill()
        NSBezierPath(ovalIn: NSRect(x: 13.7, y: 12.4, width: 2.6, height: 2.6)).fill()

        ink.setFill()
        for x in [CGFloat(12.6), 16.0] {
            NSBezierPath(ovalIn: NSRect(x: x, y: 7.4, width: 1.5, height: 1.9)).fill()
        }
        color(0xFFFFFF, 0.6).setFill()
        for x in [CGFloat(11.3), 17.4] {
            NSBezierPath(ovalIn: NSRect(x: x, y: 5.6, width: 1.4, height: 0.9)).fill()
        }
        let smile = NSBezierPath()
        smile.appendArc(withCenter: NSPoint(x: 15, y: 6.3), radius: 1.5, startAngle: 200, endAngle: 340)
        stroke(smile, ink, width: 0.8)

        context.endTransparencyLayer()
    }

    private static func stroke(_ path: NSBezierPath, _ color: NSColor, width: CGFloat) {
        color.setStroke()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.stroke()
    }
}
