import Cocoa

/// Shows the volume bar. Panels are built once per settings change and reused for every key press.
final class VolumeHUD {
    private final class Slot {
        let panel: NSPanel
        let chrome: HUDChrome
        var isShown = false
        var frame = NSRect.zero

        init(panel: NSPanel, chrome: HUDChrome) {
            self.panel = panel
            self.chrome = chrome
        }
    }

    private var slots: [Slot] = []
    private var lastState: (level: CGFloat, muted: Bool, title: String)?
    private var hideGeneration = 0
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: Settings.didChange, object: nil, queue: .main) { [weak self] note in
            self?.settingsChanged(Settings.changedKey(note))
        })
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.invalidate()
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func invalidate() {
        slots.forEach { $0.panel.orderOut(nil) }
        slots.removeAll()
    }

    /// Updates visible panels in place so a bar on screen doesn't vanish or flash while settings change.
    private func settingsChanged(_ key: String?) {
        let settings = Settings.shared
        guard let first = slots.first, first.chrome.matches(style: settings.style, scale: settings.size.scale) else {
            return invalidate()
        }
        for slot in slots {
            slot.chrome.refresh(settings, changedKey: key)
            if let lastState {
                slot.chrome.content.update(level: lastState.level, muted: lastState.muted, title: lastState.title, animated: false)
            }
        }
    }

    func show(volume: Float, muted: Bool, title: String, force: Bool = false) {
        let settings = Settings.shared
        lastState = (CGFloat(volume), muted, title)
        guard settings.showHUD || force else { return }
        let screens = targetScreens(settings.screen)
        guard !screens.isEmpty else { return }

        while slots.count < screens.count { slots.append(makeSlot(settings)) }
        let animate = settings.animations && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        for (index, slot) in slots.enumerated() {
            guard index < screens.count else {
                slot.panel.orderOut(nil)
                slot.isShown = false
                continue
            }
            present(slot, on: screens[index], level: CGFloat(volume), muted: muted, title: title, animate: animate, settings: settings)
        }
        scheduleHide(after: settings.hideDelay, animate: animate)
    }

    private func present(_ slot: Slot, on screen: NSScreen, level: CGFloat, muted: Bool, title: String, animate: Bool, settings: Settings) {
        let view = slot.chrome.content
        let panel = slot.panel
        let size = view.size(on: screen)
        let position = settings.position == .styleDefault ? view.defaultPosition : settings.position
        let origin = view.origin(on: screen, size: size, position: position)
            ?? Self.origin(for: size, position: position, in: screen.visibleFrame, margin: view.margin)
        let frame = NSRect(origin: origin, size: size)
        let alreadyShown = slot.isShown && slot.frame == frame

        view.update(level: level, muted: muted, title: title, animated: alreadyShown && animate)
        slot.isShown = true
        slot.frame = frame

        if alreadyShown {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                panel.animator().alphaValue = 1
            }
            return
        }

        guard animate else {
            panel.setFrame(frame, display: true)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }
        panel.setFrame(frame.offsetBy(dx: 0, dy: Self.slideOffset(for: position)), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }
    }

    private func scheduleHide(after delay: Double, animate: Bool) {
        hideGeneration += 1
        let generation = hideGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, generation == self.hideGeneration else { return }
            for slot in self.slots where slot.isShown {
                guard animate else {
                    slot.panel.orderOut(nil)
                    slot.isShown = false
                    continue
                }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.25
                    slot.panel.animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    guard generation == self?.hideGeneration else { return }
                    slot.panel.orderOut(nil)
                    slot.isShown = false
                })
            }
        }
    }

    private func targetScreens(_ choice: HUDScreen) -> [NSScreen] {
        switch choice {
        case .all:
            return NSScreen.screens
        case .main:
            return NSScreen.screens.first.map { [$0] } ?? []
        case .pointer:
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
            return screen.map { [$0] } ?? []
        }
    }

    private func makeSlot(_ settings: Settings) -> Slot {
        let chrome = HUDChrome(style: settings.style, scale: settings.size.scale, settings: settings)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: chrome.content.baseSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Window shadows draw a dark outline around glass, so only the solid dark panel gets one.
        if case .dark = chrome.content.background {
            panel.hasShadow = true
        } else {
            panel.hasShadow = false
        }
        panel.contentView = chrome.view
        return Slot(panel: panel, chrome: chrome)
    }

    private static func origin(for size: NSSize, position: HUDPosition, in visible: NSRect, margin: CGFloat) -> NSPoint {
        let top = visible.maxY - size.height - margin
        let middle = visible.midY - size.height / 2
        switch position {
        case .styleDefault, .topRight: return NSPoint(x: visible.maxX - size.width - margin, y: top)
        case .topLeft: return NSPoint(x: visible.minX + margin, y: top)
        case .topCenter: return NSPoint(x: visible.midX - size.width / 2, y: top)
        case .leftCenter: return NSPoint(x: visible.minX + margin, y: middle)
        case .center: return NSPoint(x: visible.midX - size.width / 2, y: middle)
        case .rightCenter: return NSPoint(x: visible.maxX - size.width - margin, y: middle)
        case .bottomCenter: return NSPoint(x: visible.midX - size.width / 2, y: visible.minY + max(margin, visible.height * 0.1))
        }
    }

    private static func slideOffset(for position: HUDPosition) -> CGFloat {
        switch position {
        case .styleDefault, .topLeft, .topCenter, .topRight: return 8
        case .bottomCenter: return -8
        case .leftCenter, .center, .rightCenter: return 0
        }
    }
}

/// The background around a style view: glass or blur, plus a tint layer for the opacity
/// setting. Content and tint change in place, because recreating the glass makes it flash.
final class HUDChrome {
    let view: NSView
    let style: HUDStyle
    let scale: CGFloat
    private(set) var content: HUDStyleView
    private let host: NSView
    private let tint: TintView?

    private static let contentKeys: Set<String> = ["barColor", "customColor", "gradientStart", "gradientEnd"]

    init(style: HUDStyle, scale: CGFloat, settings: Settings) {
        self.style = style
        self.scale = scale
        content = style.makeView(scale: scale, paint: settings.barPaint)
        switch content.background {
        case .none:
            tint = nil
            host = NSView()
            view = host
        case .glass(let radius), .gradient(let radius):
            let tint = TintView(cornerRadius: radius * scale)
            self.tint = tint
            host = tint
            view = Self.glass(around: tint, cornerRadius: radius * scale, dark: false)
        case .dark(let radius):
            let tint = TintView(cornerRadius: radius * scale)
            self.tint = tint
            host = tint
            view = Self.glass(around: tint, cornerRadius: radius * scale, dark: true)
        }
        Self.embed(content, in: host)
        applyTint(settings)
    }

    func matches(style: HUDStyle, scale: CGFloat) -> Bool {
        self.style == style && self.scale == scale
    }

    /// A nil key means every setting may have changed, as after a reset.
    func refresh(_ settings: Settings, changedKey key: String?) {
        if key.map(Self.contentKeys.contains) ?? true {
            let next = style.makeView(scale: scale, paint: settings.barPaint)
            content.removeFromSuperview()
            Self.embed(next, in: host)
            content = next
        }
        applyTint(settings)
    }

    private func applyTint(_ settings: Settings) {
        guard let tint else { return }
        let opacity = settings.backgroundOpacity
        switch content.background {
        case .gradient:
            tint.colors = settings.gradientColors
            tint.alpha = 0.5 + 0.5 * opacity
        case .dark:
            tint.colors = [.black]
            tint.alpha = opacity
        case .glass, .none:
            tint.colors = [.windowBackgroundColor]
            tint.alpha = opacity
        }
    }

    private static func glass(around inner: NSView, cornerRadius: CGFloat, dark: Bool) -> NSView {
        if !dark, #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = inner
            return glass
        }
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        if dark { blur.appearance = NSAppearance(named: .darkAqua) }
        blur.wantsLayer = true
        blur.layer?.cornerRadius = cornerRadius
        blur.layer?.masksToBounds = true
        embed(inner, in: blur)
        return blur
    }

    private static func embed(_ view: NSView, in container: NSView) {
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
    }
}

/// Color or gradient overlay; re-resolves dynamic colors when the appearance changes.
final class TintView: NSView {
    var colors: [NSColor] = [.clear] { didSet { applyColors() } }
    var alpha: Double = 0 { didSet { applyColors() } }

    init(cornerRadius: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        if let gradient = layer as? CAGradientLayer {
            gradient.startPoint = CGPoint(x: 0, y: 1)
            gradient.endPoint = CGPoint(x: 1, y: 0)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func makeBackingLayer() -> CALayer { CAGradientLayer() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        guard let gradient = layer as? CAGradientLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let stops = colors.count == 1 ? colors + colors : colors
            gradient.colors = stops.map { $0.withAlphaComponent(alpha).cgColor }
        }
        CATransaction.commit()
    }
}
