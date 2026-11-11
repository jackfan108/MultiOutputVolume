import Cocoa

let size = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("no context") }
NSGraphicsContext.current = context

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// Background tile (macOS icon grid: 824pt tile inside 1024pt canvas)
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let tileShadow = NSShadow()
tileShadow.shadowColor = color(0x000000, 0.3)
tileShadow.shadowOffset = NSSize(width: 0, height: -12)
tileShadow.shadowBlurRadius = 24
tileShadow.set()
color(0xFF8FB1).setFill()
tilePath.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: color(0xFFB199), ending: color(0xB07CFF))!.draw(in: tilePath, angle: -60)

// Sound waves on both sides
func waves(centerX: CGFloat, startAngle: CGFloat, endAngle: CGFloat) {
    color(0xFFFFFF, 0.95).setStroke()
    for radius in [CGFloat(125), 185, 245] {
        let arc = NSBezierPath()
        arc.appendArc(withCenter: NSPoint(x: centerX, y: 520), radius: radius,
                      startAngle: startAngle, endAngle: endAngle)
        arc.lineWidth = 30
        arc.lineCapStyle = .round
        arc.stroke()
    }
}
waves(centerX: 640, startAngle: -30, endAngle: 30)
waves(centerX: 384, startAngle: 150, endAngle: 210)

// Speaker body
let body = NSRect(x: 512 - 190, y: 290, width: 380, height: 470)
let bodyPath = NSBezierPath(roundedRect: body, xRadius: 130, yRadius: 130)
NSGraphicsContext.saveGraphicsState()
let bodyShadow = NSShadow()
bodyShadow.shadowColor = color(0x5A2A8C, 0.35)
bodyShadow.shadowOffset = NSSize(width: 0, height: -14)
bodyShadow.shadowBlurRadius = 20
bodyShadow.set()
color(0xFFFFFF).setFill()
bodyPath.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: color(0xFFFFFF), ending: color(0xFFE9F2))!.draw(in: bodyPath, angle: -90)

// Tweeter + woofer dots as the face's "forehead" detail
color(0xE9D5FF).setFill()
NSBezierPath(ovalIn: NSRect(x: 512 - 34, y: 680, width: 68, height: 68)).fill()

// Eyes
let ink = color(0x3B2255)
ink.setFill()
for x in [CGFloat(427), CGFloat(597)] {
    NSBezierPath(ovalIn: NSRect(x: x - 34, y: 500, width: 68, height: 84)).fill()
    color(0xFFFFFF).setFill()
    NSBezierPath(ovalIn: NSRect(x: x - 14, y: 546, width: 24, height: 24)).fill()
    ink.setFill()
}

// Blush
color(0xFF8FB1, 0.55).setFill()
for x in [CGFloat(377), CGFloat(647)] {
    NSBezierPath(ovalIn: NSRect(x: x - 40, y: 440, width: 80, height: 48)).fill()
}

// Smile
let smile = NSBezierPath()
smile.appendArc(withCenter: NSPoint(x: 512, y: 470), radius: 52, startAngle: 200, endAngle: 340)
smile.lineWidth = 16
smile.lineCapStyle = .round
ink.setStroke()
smile.stroke()

NSGraphicsContext.current = nil
let data = rep.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
