import AppKit

/// Minimal horizontal slider drawn with three layers. NSSlider is avoided because
/// rendering it allocates ~200 MB of transient memory on first display.
final class LayerSlider: NSView {
    var value: Double {
        didSet { layoutLayers() }
    }
    var onChange: ((Double) -> Void)?
    var onCommit: (() -> Void)?

    private let track = CALayer()
    private let fill = CALayer()
    private let knob = CALayer()
    private let knobSize: CGFloat = 16
    private let trackHeight: CGFloat = 4

    init(value: Double) {
        self.value = min(max(value, 0), 1)
        super.init(frame: NSRect(x: 0, y: 0, width: 160, height: 20))
        wantsLayer = true
        track.cornerRadius = trackHeight / 2
        fill.cornerRadius = trackHeight / 2
        knob.cornerRadius = knobSize / 2
        knob.shadowOpacity = 0.3
        knob.shadowRadius = 1.5
        knob.shadowOffset = CGSize(width: 0, height: -0.5)
        [track, fill, knob].forEach(layer!.addSublayer)
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 160, height: 20) }
    override var wantsUpdateLayer: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            track.backgroundColor = NSColor.quaternaryLabelColor.cgColor
            fill.backgroundColor = NSColor.controlAccentColor.cgColor
            knob.backgroundColor = NSColor.white.cgColor
            knob.borderColor = NSColor.separatorColor.cgColor
            knob.borderWidth = 0.5
        }
    }

    override func layout() {
        super.layout()
        layoutLayers()
    }

    private var usableWidth: CGFloat { max(bounds.width - knobSize, 1) }

    private func layoutLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let midY = bounds.midY
        let x = knobSize / 2 + usableWidth * CGFloat(value)
        track.frame = CGRect(x: knobSize / 2, y: midY - trackHeight / 2, width: usableWidth, height: trackHeight)
        fill.frame = CGRect(x: knobSize / 2, y: midY - trackHeight / 2, width: x - knobSize / 2, height: trackHeight)
        knob.frame = CGRect(x: x - knobSize / 2, y: midY - knobSize / 2, width: knobSize, height: knobSize)
        CATransaction.commit()
        setAccessibilityValue(NSNumber(value: value))
    }

    override func mouseDown(with event: NSEvent) { track(event) }
    override func mouseDragged(with event: NSEvent) { track(event) }
    override func mouseUp(with event: NSEvent) { onCommit?() }

    private func track(_ event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x - knobSize / 2
        set(Double(min(max(x / usableWidth, 0), 1)))
    }

    private func set(_ newValue: Double) {
        let snapped = (newValue * 100).rounded() / 100
        guard snapped != value else { return }
        value = snapped
        onChange?(snapped)
    }

    override func accessibilityPerformIncrement() -> Bool { set(min(value + 0.1, 1)); onCommit?(); return true }
    override func accessibilityPerformDecrement() -> Bool { set(max(value - 0.1, 0)); onCommit?(); return true }
}
