import Cocoa
import QuartzCore

// MARK: - Shared pieces

enum BarPaint {
    case automatic, accent, gradient([NSColor]), custom(NSColor)

    /// Always at least two colors so they can feed a gradient layer directly.
    var colors: [NSColor] {
        switch self {
        case .automatic: return [.labelColor, .labelColor]
        case .accent: return [.controlAccentColor, .controlAccentColor]
        case .gradient(let colors): return colors
        case .custom(let color): return [color, color]
        }
    }

    var opacity: CGFloat {
        if case .automatic = self { return 0.85 }
        return 1
    }

    func color(at fraction: CGFloat) -> NSColor {
        let stops = colors
        let position = max(0, min(1, fraction)) * CGFloat(stops.count - 1)
        let index = min(Int(position), stops.count - 2)
        let lower = stops[index]
        return lower.blended(withFraction: position - CGFloat(index), of: stops[index + 1]) ?? lower
    }
}

enum HUDBackground {
    case glass(cornerRadius: CGFloat)
    case dark(cornerRadius: CGFloat)
    case gradient(cornerRadius: CGFloat)
    case none
}

func speakerSymbol(level: CGFloat, muted: Bool) -> String {
    if muted || level == 0 { return "speaker.slash.fill" }
    if level < 0.34 { return "speaker.wave.1.fill" }
    if level < 0.67 { return "speaker.wave.2.fill" }
    return "speaker.wave.3.fill"
}

private func makeLabel(size: CGFloat, weight: NSFont.Weight, color: NSColor, monospaced: Bool = false) -> NSTextField {
    let label = NSTextField(labelWithString: "")
    label.font = monospaced ? .monospacedDigitSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
    label.textColor = color
    label.lineBreakMode = .byTruncatingTail
    return label
}

/// An image view that only swaps its SF Symbol when the name actually changes.
final class SymbolView: NSImageView {
    private var symbolName: String?

    init(pointSize: CGFloat, weight: NSFont.Weight = .semibold, color: NSColor = .labelColor) {
        super.init(frame: .zero)
        symbolConfiguration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        contentTintColor = color
        imageScaling = .scaleNone
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setSymbol(_ name: String) {
        guard name != symbolName else { return }
        symbolName = name
        image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }
}

/// Layer-backed bar so level changes are a single frame update on the render server.
final class BarView: NSView {
    var paint: BarPaint = .automatic { didSet { applyColors() } }
    var fixedColor: NSColor? { didSet { applyColors() } }
    var trackOpacity: CGFloat = 0.14 { didSet { applyColors() } }

    private let vertical: Bool
    private let track = CALayer()
    private let fill = CAGradientLayer()
    private var level: CGFloat = 0
    private var dimmed = false

    init(vertical: Bool = false) {
        self.vertical = vertical
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(track)
        track.addSublayer(fill)
        track.masksToBounds = true
        fill.startPoint = vertical ? CGPoint(x: 0.5, y: 0) : CGPoint(x: 0, y: 0.5)
        fill.endPoint = vertical ? CGPoint(x: 0.5, y: 1) : CGPoint(x: 1, y: 0.5)
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.frame = bounds
        track.cornerRadius = min(bounds.width, bounds.height) / 2
        fill.cornerRadius = track.cornerRadius
        fill.frame = fillFrame()
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    func set(level: CGFloat, dimmed: Bool, animated: Bool) {
        let dimmedChanged = dimmed != self.dimmed
        self.level = level
        self.dimmed = dimmed
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.12)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        fill.frame = fillFrame()
        if dimmedChanged { applyColors() }
        CATransaction.commit()
    }

    private func fillFrame() -> CGRect {
        let thickness = vertical ? bounds.width : bounds.height
        let extent = vertical ? bounds.height : bounds.width
        let length = level > 0 ? max(thickness, extent * level) : 0
        return vertical
            ? CGRect(x: 0, y: 0, width: bounds.width, height: length)
            : CGRect(x: 0, y: 0, width: length, height: bounds.height)
    }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let base = fixedColor ?? .labelColor
            track.backgroundColor = base.withAlphaComponent(trackOpacity).cgColor
            let opacity = dimmed ? 0.3 : (fixedColor == nil ? paint.opacity : 1)
            let colors = fixedColor.map { [$0, $0] } ?? paint.colors
            fill.colors = colors.map { $0.withAlphaComponent(opacity).cgColor }
        }
    }
}

// MARK: - Style base

class HUDStyleView: NSView {
    let scale: CGFloat
    let paint: BarPaint

    init(scale: CGFloat, paint: BarPaint) {
        self.scale = scale
        self.paint = paint
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var baseSize: NSSize { NSSize(width: 300, height: 64) }
    var background: HUDBackground { .glass(cornerRadius: 26) }
    var defaultPosition: HUDPosition { .topRight }
    var margin: CGFloat { 10 }

    func size(on screen: NSScreen) -> NSSize {
        NSSize(width: s(baseSize.width), height: s(baseSize.height))
    }

    func previewSize(in available: NSSize) -> NSSize {
        NSSize(width: s(baseSize.width), height: s(baseSize.height))
    }

    /// Return nil to use the standard placement for `position`.
    func origin(on screen: NSScreen, size: NSSize, position: HUDPosition) -> NSPoint? { nil }

    func update(level: CGFloat, muted: Bool, title: String, animated: Bool) {}

    func s(_ value: CGFloat) -> CGFloat { value * scale }
}

extension HUDStyle {
    func makeView(scale: CGFloat, paint: BarPaint) -> HUDStyleView {
        switch self {
        case .glassPanel: return MacOSStyle(scale: scale, paint: paint)
        case .glassPill: return GlassPillStyle(scale: scale, paint: paint)
        case .classic: return ClassicStyle(scale: scale, paint: paint)
        case .vertical: return VerticalStyle(scale: scale, paint: paint)
        case .ring: return RingStyle(scale: scale, paint: paint)
        case .edgeLine: return EdgeLineStyle(scale: scale, paint: paint)
        case .candy: return CandyStyle(scale: scale, paint: paint)
        }
    }
}

// MARK: - 1. macOS (system volume bar)

final class MacOSStyle: HUDStyleView {
    private let tickCount = 17
    private let title: NSTextField
    private let lowIcon: SymbolView
    private let highIcon: SymbolView
    private let bar = BarView()
    private let ticks = CALayer()

    override init(scale: CGFloat, paint: BarPaint) {
        title = makeLabel(size: 13 * scale, weight: .semibold, color: .labelColor)
        lowIcon = SymbolView(pointSize: 11 * scale, weight: .medium, color: .secondaryLabelColor)
        highIcon = SymbolView(pointSize: 11 * scale, weight: .medium, color: .secondaryLabelColor)
        super.init(scale: scale, paint: paint)
        wantsLayer = true
        bar.paint = paint
        bar.trackOpacity = 0.16
        lowIcon.setSymbol("speaker.fill")
        highIcon.setSymbol("speaker.wave.3.fill")
        for _ in 0..<tickCount { ticks.addSublayer(CALayer()) }
        layer?.addSublayer(ticks)
        [title, lowIcon, highIcon, bar].forEach(addSubview)
        applyTickColor()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var baseSize: NSSize { NSSize(width: 300, height: 64) }
    override var background: HUDBackground { .glass(cornerRadius: 20) }

    override func layout() {
        super.layout()
        let width = bounds.width
        title.frame = NSRect(x: s(20), y: s(36), width: width - s(40), height: s(18))
        lowIcon.frame = NSRect(x: s(18), y: s(14), width: s(16), height: s(16))
        highIcon.frame = NSRect(x: width - s(40), y: s(14), width: s(24), height: s(16))
        let barX = s(40)
        let barWidth = width - s(40) - s(44)
        bar.frame = NSRect(x: barX, y: s(20), width: barWidth, height: s(5))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let dot = s(2)
        for (index, tick) in (ticks.sublayers ?? []).enumerated() {
            let x = barX + barWidth * CGFloat(index) / CGFloat(tickCount - 1) - dot / 2
            tick.frame = CGRect(x: x, y: s(10), width: dot, height: dot)
            tick.cornerRadius = dot / 2
        }
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTickColor()
    }

    override func update(level: CGFloat, muted: Bool, title text: String, animated: Bool) {
        title.stringValue = text
        lowIcon.setSymbol(muted ? "speaker.slash.fill" : "speaker.fill")
        bar.set(level: muted ? 0 : level, dimmed: muted, animated: animated)
    }

    private func applyTickColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color = NSColor.labelColor.withAlphaComponent(0.25).cgColor
            ticks.sublayers?.forEach { $0.backgroundColor = color }
        }
    }
}

// MARK: - 2. Glass pill

final class GlassPillStyle: HUDStyleView {
    private let icon: SymbolView
    private let bar = BarView()

    override init(scale: CGFloat, paint: BarPaint) {
        icon = SymbolView(pointSize: 14 * scale)
        super.init(scale: scale, paint: paint)
        bar.paint = paint
        [icon, bar].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var baseSize: NSSize { NSSize(width: 230, height: 48) }
    override var background: HUDBackground { .glass(cornerRadius: 24) }

    override func layout() {
        super.layout()
        icon.frame = NSRect(x: s(14), y: (bounds.height - s(22)) / 2, width: s(28), height: s(22))
        bar.frame = NSRect(x: s(48), y: (bounds.height - s(6)) / 2, width: bounds.width - s(48) - s(20), height: s(6))
    }

    override func update(level: CGFloat, muted: Bool, title: String, animated: Bool) {
        icon.setSymbol(speakerSymbol(level: level, muted: muted))
        bar.set(level: muted ? 0 : level, dimmed: muted, animated: animated)
    }
}

// MARK: - 3. Classic

final class ClassicStyle: HUDStyleView {
    private let segmentCount = 16
    private let icon: SymbolView
    private let segments = CALayer()
    private var filled = -1
    private var muted = false

    override init(scale: CGFloat, paint: BarPaint) {
        icon = SymbolView(pointSize: 70 * scale, weight: .regular, color: NSColor.white.withAlphaComponent(0.9))
        super.init(scale: scale, paint: paint)
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        icon.imageAlignment = .alignCenter
        for _ in 0..<segmentCount { segments.addSublayer(CALayer()) }
        layer?.addSublayer(segments)
        addSubview(icon)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var baseSize: NSSize { NSSize(width: 200, height: 200) }
    override var background: HUDBackground { .dark(cornerRadius: 20) }
    override var defaultPosition: HUDPosition { .bottomCenter }

    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 0, y: s(56), width: bounds.width, height: s(120))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let padding = s(20)
        let gap = s(2)
        let width = (bounds.width - padding * 2 - gap * CGFloat(segmentCount - 1)) / CGFloat(segmentCount)
        for (index, segment) in (segments.sublayers ?? []).enumerated() {
            segment.frame = CGRect(x: padding + CGFloat(index) * (width + gap), y: s(26), width: width, height: s(7))
        }
        CATransaction.commit()
    }

    override func update(level: CGFloat, muted: Bool, title: String, animated: Bool) {
        icon.setSymbol(speakerSymbol(level: level, muted: muted))
        let count = muted ? 0 : Int((level * CGFloat(segmentCount)).rounded())
        guard count != filled || muted != self.muted else { return }
        filled = count
        self.muted = muted
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            for (index, segment) in (segments.sublayers ?? []).enumerated() {
                segment.backgroundColor = index < count
                    ? paint.color(at: CGFloat(index) / CGFloat(segmentCount - 1)).withAlphaComponent(paint.opacity).cgColor
                    : NSColor.white.withAlphaComponent(0.15).cgColor
            }
        }
        CATransaction.commit()
    }
}

// MARK: - 4. Vertical

final class VerticalStyle: HUDStyleView {
    private let icon: SymbolView
    private let bar = BarView(vertical: true)

    override init(scale: CGFloat, paint: BarPaint) {
        icon = SymbolView(pointSize: 14 * scale)
        super.init(scale: scale, paint: paint)
        icon.imageAlignment = .alignCenter
        bar.paint = paint
        [icon, bar].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var baseSize: NSSize { NSSize(width: 56, height: 220) }
    override var background: HUDBackground { .glass(cornerRadius: 28) }
    override var defaultPosition: HUDPosition { .rightCenter }
    override var margin: CGFloat { 14 }

    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 0, y: s(14), width: bounds.width, height: s(24))
        bar.frame = NSRect(x: (bounds.width - s(10)) / 2, y: s(48), width: s(10), height: bounds.height - s(48) - s(20))
    }

    override func update(level: CGFloat, muted: Bool, title: String, animated: Bool) {
        icon.setSymbol(speakerSymbol(level: level, muted: muted))
        bar.set(level: muted ? 0 : level, dimmed: muted, animated: animated)
    }
}

// MARK: - 5. Ring

final class RingStyle: HUDStyleView {
    private let icon: SymbolView
    private let percent: NSTextField
    private let track = CAShapeLayer()
    private let progress = CAGradientLayer()
    private let progressMask = CAShapeLayer()
    private var muted = false

    override init(scale: CGFloat, paint: BarPaint) {
        icon = SymbolView(pointSize: 12 * scale, color: .secondaryLabelColor)
        percent = makeLabel(size: 24 * scale, weight: .semibold, color: .labelColor, monospaced: true)
        super.init(scale: scale, paint: paint)
        wantsLayer = true
        percent.alignment = .center
        icon.imageAlignment = .alignCenter
        for shape in [track, progressMask] {
            shape.fillColor = nil
            shape.lineCap = .round
        }
        progressMask.strokeColor = NSColor.black.cgColor
        progressMask.strokeEnd = 0
        progress.mask = progressMask
        progress.startPoint = CGPoint(x: 0, y: 1)
        progress.endPoint = CGPoint(x: 1, y: 0)
        layer?.addSublayer(track)
        layer?.addSublayer(progress)
        [icon, percent].forEach(addSubview)
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var baseSize: NSSize { NSSize(width: 140, height: 140) }
    override var background: HUDBackground { .glass(cornerRadius: 70) }
    override var defaultPosition: HUDPosition { .center }

    override func layout() {
        super.layout()
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let path = CGMutablePath()
        path.addArc(center: center, radius: s(50), startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for shape in [track, progressMask] {
            shape.frame = bounds
            shape.path = path
            shape.lineWidth = s(8)
        }
        progress.frame = bounds
        CATransaction.commit()
        percent.frame = NSRect(x: 0, y: bounds.midY - s(22), width: bounds.width, height: s(30))
        icon.frame = NSRect(x: 0, y: bounds.midY + s(10), width: bounds.width, height: s(18))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    override func update(level: CGFloat, muted: Bool, title: String, animated: Bool) {
        icon.setSymbol(speakerSymbol(level: level, muted: muted))
        percent.stringValue = muted ? "Muted" : "\(Int((level * 100).rounded()))%"
        let mutedChanged = muted != self.muted
        self.muted = muted
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.12)
        progressMask.strokeEnd = muted ? 0 : level
        if mutedChanged { applyColors() }
        CATransaction.commit()
    }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            track.strokeColor = NSColor.labelColor.withAlphaComponent(0.14).cgColor
            let opacity = muted ? 0.3 : paint.opacity
            progress.colors = paint.colors.map { $0.withAlphaComponent(opacity).cgColor }
        }
    }
}

// MARK: - 6. Edge line

final class EdgeLineStyle: HUDStyleView {
    private let bar = BarView()

    override init(scale: CGFloat, paint: BarPaint) {
        super.init(scale: scale, paint: paint)
        bar.paint = paint
        bar.trackOpacity = 0.1
        addSubview(bar)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var background: HUDBackground { .none }
    override var defaultPosition: HUDPosition { .topCenter }

    override func size(on screen: NSScreen) -> NSSize {
        NSSize(width: screen.visibleFrame.width, height: s(5))
    }

    override func previewSize(in available: NSSize) -> NSSize {
        NSSize(width: available.width, height: s(5))
    }

    override func origin(on screen: NSScreen, size: NSSize, position: HUDPosition) -> NSPoint? {
        let visible = screen.visibleFrame
        return NSPoint(x: visible.minX, y: position == .bottomCenter ? visible.minY : visible.maxY - size.height)
    }

    override func layout() {
        super.layout()
        bar.frame = bounds
    }

    override func update(level: CGFloat, muted: Bool, title: String, animated: Bool) {
        bar.set(level: muted ? 0 : level, dimmed: muted, animated: animated)
    }
}

// MARK: - 7. Candy

final class CandyStyle: HUDStyleView {
    private let mascot = NSImageView()
    private let bar = BarView()
    private let percent: NSTextField

    override init(scale: CGFloat, paint: BarPaint) {
        percent = makeLabel(size: 15 * scale, weight: .bold, color: .white, monospaced: true)
        super.init(scale: scale, paint: paint)
        mascot.image = NSApp.applicationIconImage
        mascot.imageScaling = .scaleProportionallyUpOrDown
        percent.alignment = .right
        // The panel already shows the gradient, so a gradient or automatic bar stays white.
        switch paint {
        case .accent, .custom: bar.paint = paint
        case .automatic, .gradient: bar.fixedColor = .white
        }
        bar.trackOpacity = 0.35
        [mascot, bar, percent].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var baseSize: NSSize { NSSize(width: 300, height: 72) }
    override var background: HUDBackground { .gradient(cornerRadius: 36) }

    override func layout() {
        super.layout()
        let height = bounds.height
        mascot.frame = NSRect(x: s(10), y: (height - s(54)) / 2, width: s(54), height: s(54))
        percent.frame = NSRect(x: bounds.width - s(74), y: (height - s(20)) / 2, width: s(54), height: s(20))
        bar.frame = NSRect(x: s(74), y: (height - s(10)) / 2, width: bounds.width - s(74) - s(80), height: s(10))
    }

    override func update(level: CGFloat, muted: Bool, title: String, animated: Bool) {
        mascot.alphaValue = muted ? 0.5 : 1
        percent.stringValue = muted ? "Muted" : "\(Int((level * 100).rounded()))%"
        bar.set(level: muted ? 0 : level, dimmed: muted, animated: animated)
    }
}
