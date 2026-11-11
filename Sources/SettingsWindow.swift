import Cocoa
import Darwin
import ServiceManagement

private final class ActionHandler: NSObject {
    private let handler: (Any) -> Void

    init(_ handler: @escaping (Any) -> Void) {
        self.handler = handler
    }

    @objc func handleAction(_ sender: Any) {
        handler(sender)
    }
}

/// Live preview of the selected style. It steps the volume up and down like a held key,
/// so the real fill animation is visible. It only runs while the settings window is open.
final class HUDPreviewView: NSView {
    private let padding: CGFloat = 20
    private let demoInterval: TimeInterval = 0.35
    private var chrome: HUDChrome?
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var level: CGFloat = 0.5
    private var direction: CGFloat = 1
    private var builtSize = NSSize.zero
    private let title: String

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
        let backdrop = CAGradientLayer()
        backdrop.colors = [
            NSColor(srgbRed: 0.24, green: 0.62, blue: 0.58, alpha: 1).cgColor,
            NSColor(srgbRed: 0.33, green: 0.38, blue: 0.75, alpha: 1).cgColor,
            NSColor(srgbRed: 0.85, green: 0.47, blue: 0.62, alpha: 1).cgColor,
        ]
        backdrop.startPoint = CGPoint(x: 0, y: 1)
        backdrop.endPoint = CGPoint(x: 1, y: 0)
        backdrop.cornerRadius = 12
        backdrop.masksToBounds = true
        layer = backdrop
        wantsLayer = true
        observer = NotificationCenter.default.addObserver(forName: Settings.didChange, object: nil, queue: .main) { [weak self] note in
            self?.settingsChanged(Settings.changedKey(note))
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return stop() }
        start()
    }

    override func layout() {
        super.layout()
        if bounds.size != builtSize {
            rebuild()
        } else {
            positionContainer()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: demoInterval, repeats: true) { [weak self] _ in
            self?.step()
        }
    }

    private func step() {
        let next = level + direction / 16
        if next > 0.95 || next < 0.1 { direction = -direction }
        level = max(0, min(1, level + direction / 16))
        chrome?.content.update(level: level, muted: false, title: title, animated: Settings.shared.animations)
    }

    private func settingsChanged(_ key: String?) {
        let settings = Settings.shared
        guard let chrome, bounds.size == builtSize, chrome.matches(style: settings.style, scale: fittedScale()) else {
            return rebuild()
        }
        chrome.refresh(settings, changedKey: key)
        chrome.content.update(level: level, muted: false, title: title, animated: false)
    }

    /// The configured size, shrunk if the style would not fit in the preview.
    private func fittedScale() -> CGFloat {
        let settings = Settings.shared
        let available = NSSize(width: bounds.width - padding * 2, height: bounds.height - padding * 2)
        let base = chrome?.style == settings.style
            ? chrome!.content.baseSize
            : settings.style.makeView(scale: 1, paint: .automatic).baseSize
        return max(0.5, min(settings.size.scale, available.width / base.width, available.height / base.height))
    }

    private func rebuild() {
        guard bounds.width > padding * 2, bounds.height > padding * 2 else { return }
        builtSize = bounds.size
        chrome?.view.removeFromSuperview()
        let next = HUDChrome(style: Settings.shared.style, scale: fittedScale(), settings: Settings.shared)
        addSubview(next.view)
        chrome = next
        positionContainer()
        next.content.update(level: level, muted: false, title: title, animated: false)
    }

    private func positionContainer() {
        guard let chrome else { return }
        let container = chrome.view
        let size = chrome.content.previewSize(in: NSSize(width: bounds.width, height: bounds.height - padding * 2))
        let isEdgeLine = Settings.shared.style == .edgeLine
        let origin = isEdgeLine
            ? NSPoint(x: 0, y: bounds.height - size.height - 8)
            : NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        container.frame = NSRect(origin: origin, size: size)
    }
}

/// AppKit keeps a closed window alive through internal caches, so the app keeps one window
/// and tears down its contents on close. Settings UI costs almost nothing while closed.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    /// Flashes the real volume bar so placement settings can be checked on screen.
    var onShowOnScreen: (() -> Void)?

    private let settings = Settings.shared
    var outputName: String
    private var handlers: [ActionHandler] = []
    private var styleButtons: [NSButton] = []
    private var preview: HUDPreviewView?
    private let labelColumnWidth: CGFloat = 96

    init(outputName: String) {
        self.outputName = outputName
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "MultiOutputVolume settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func present() {
        if window?.contentView?.subviews.isEmpty ?? true {
            rebuildContent()
            window?.center()
        }
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        preview?.stop()
        DispatchQueue.main.async { [weak self] in self?.tearDownContent() }
    }

    private func tearDownContent() {
        window?.contentView = NSView()
        handlers.removeAll()
        styleButtons.removeAll()
        preview = nil
        malloc_zone_pressure_relief(nil, 0)
    }

    // MARK: Layout

    private func rebuildContent() {
        handlers.removeAll()
        styleButtons.removeAll()
        preview?.stop()

        let previewView = HUDPreviewView(title: outputName)
        preview = previewView

        let columns = NSStackView(views: [makeStyleColumn(), makeOptionsColumn()])
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.spacing = 36

        let reset = NSButton(title: "Reset to defaults", target: nil, action: nil)
        bind(reset) { [weak self] _ in self?.resetToDefaults() }
        let footer = NSStackView(views: [reset, NSView()])

        let root = NSStackView(views: [previewView, columns, footer])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 20
        root.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        previewView.heightAnchor.constraint(equalToConstant: 200).isActive = true
        previewView.widthAnchor.constraint(equalTo: columns.widthAnchor).isActive = true
        footer.widthAnchor.constraint(equalTo: columns.widthAnchor).isActive = true

        window?.contentView = root
        window?.setContentSize(root.fittingSize)
    }

    private func makeStyleColumn() -> NSView {
        var rows: [NSView] = [sectionHeader("Style")]
        for (index, style) in HUDStyle.allCases.enumerated() {
            let button = NSButton(radioButtonWithTitle: style.title, target: nil, action: nil)
            button.state = style == settings.style ? .on : .off
            bind(button) { [weak self] _ in self?.selectStyle(at: index) }
            styleButtons.append(button)

            let summary = NSTextField(wrappingLabelWithString: style.summary)
            summary.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            summary.textColor = .secondaryLabelColor
            summary.preferredMaxLayoutWidth = 230
            let summaryRow = NSStackView(views: [summary])
            summaryRow.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 0)

            let item = NSStackView(views: [button, summaryRow])
            item.orientation = .vertical
            item.alignment = .leading
            item.spacing = 2
            item.setHuggingPriority(.required, for: .vertical)
            summaryRow.setHuggingPriority(.required, for: .vertical)
            rows.append(item)
        }

        let column = NSStackView(views: rows)
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 10
        column.setHuggingPriority(.required, for: .vertical)
        return column
    }

    private func makeOptionsColumn() -> NSView {
        let customWell = colorWell(settings.customColor) { [weak self] in self?.settings.customColor = $0 }
        let gradientWells = settings.gradientColors.enumerated().map { index, color in
            colorWell(color) { [weak self] in self?.settings.setGradientColor($0, at: index) }
        }
        let showWells = { (choice: BarColor) in
            customWell.isHidden = choice != .custom
            gradientWells.forEach { $0.isHidden = choice != .candy }
        }
        showWells(settings.barColor)
        let barColorPopup = optionPopup(settings.barColor) { [weak self] value in
            self?.settings.barColor = value
            showWells(value)
        }
        let colorRow = NSStackView(views: [barColorPopup, customWell] + gradientWells)
        colorRow.spacing = 8

        // A popup instead of NSSlider: the system slider costs ~200 MB of transient memory to render.
        let delays: [Double] = [0.5, 1, 1.5, 2, 3, 5]
        let delayPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        delayPopup.addItems(withTitles: delays.map { $0 == 1 ? "1 second" : String(format: "%g seconds", $0) })
        let current = settings.hideDelay
        let nearest = delays.enumerated().min { abs($0.element - current) < abs($1.element - current) }?.offset ?? 2
        delayPopup.selectItem(at: nearest)
        bind(delayPopup) { [weak self] sender in
            guard let popup = sender as? NSPopUpButton else { return }
            self?.settings.hideDelay = delays[popup.indexOfSelectedItem]
        }

        let opacitySlider = LayerSlider(value: settings.backgroundOpacity)
        let opacityLabel = NSTextField(labelWithString: Self.percent(settings.backgroundOpacity))
        opacityLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        opacityLabel.textColor = .secondaryLabelColor
        opacitySlider.onChange = { [weak self] value in
            opacityLabel.stringValue = Self.percent(value)
            self?.settings.backgroundOpacity = value
        }
        opacitySlider.onCommit = { [weak self] in self?.onShowOnScreen?() }
        let opacityRow = NSStackView(views: [opacitySlider, opacityLabel])
        opacityRow.spacing = 8
        opacityLabel.widthAnchor.constraint(equalToConstant: 36).isActive = true

        let appearance = grid([
            ("Size", optionPopup(settings.size) { [weak self] in self?.settings.size = $0 }),
            ("Position", optionPopup(settings.position) { [weak self] in self?.settings.position = $0; self?.onShowOnScreen?() }),
            ("Display", optionPopup(settings.screen) { [weak self] in self?.settings.screen = $0; self?.onShowOnScreen?() }),
            ("Bar color", colorRow),
            ("Opacity", opacityRow),
        ])

        let showOnScreen = NSButton(title: "Show on screen", target: nil, action: nil)
        bind(showOnScreen) { [weak self] _ in self?.onShowOnScreen?() }

        let behavior = grid([
            ("Hide after", delayPopup),
            ("Volume step", optionPopup(settings.volumeStep) { [weak self] in self?.settings.volumeStep = $0 }),
            ("", checkbox("Show the volume bar", settings.showHUD) { [weak self] in self?.settings.showHUD = $0 }),
            ("", checkbox("Animate the volume bar", settings.animations) { [weak self] in self?.settings.animations = $0 }),
            ("", checkbox("Play feedback when volume is changed", settings.feedbackSound) { [weak self] in self?.settings.feedbackSound = $0 }),
            ("", checkbox("Show percentage in menu bar", settings.showPercentInMenuBar) { [weak self] in self?.settings.showPercentInMenuBar = $0 }),
            ("", launchAtLoginCheckbox()),
        ])

        let column = NSStackView(views: [sectionHeader("Appearance"), appearance, showOnScreen, sectionHeader("Behavior"), behavior])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 10
        column.setCustomSpacing(20, after: showOnScreen)
        return column
    }

    private static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    private func sectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        return label
    }

    private func grid(_ rows: [(String, NSView)]) -> NSGridView {
        let grid = NSGridView(views: rows.map { title, control in
            [title.isEmpty ? NSGridCell.emptyContentView : NSTextField(labelWithString: title), control]
        })
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = labelColumnWidth
        grid.rowAlignment = .firstBaseline
        return grid
    }

    // MARK: Controls

    private func optionPopup<T: SettingOption>(_ current: T, onChange: @escaping (T) -> Void) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: T.allCases.map(\.title))
        popup.selectItem(at: T.allCases.firstIndex(of: current) ?? 0)
        bind(popup) { sender in
            guard let popup = sender as? NSPopUpButton else { return }
            onChange(T.allCases[popup.indexOfSelectedItem])
        }
        return popup
    }

    private func colorWell(_ color: NSColor, onChange: @escaping (NSColor) -> Void) -> NSColorWell {
        let well = NSColorWell(style: .minimal)
        well.color = color
        well.widthAnchor.constraint(equalToConstant: 44).isActive = true
        bind(well) { sender in
            guard let well = sender as? NSColorWell else { return }
            onChange(well.color)
        }
        return well
    }

    private func checkbox(_ title: String, _ isOn: Bool, onChange: @escaping (Bool) -> Void) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        button.state = isOn ? .on : .off
        bind(button) { sender in
            guard let button = sender as? NSButton else { return }
            onChange(button.state == .on)
        }
        return button
    }

    private func launchAtLoginCheckbox() -> NSButton {
        checkbox("Launch at login", SMAppService.mainApp.status == .enabled) { [weak self] enabled in
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                guard let window = self?.window else { return }
                NSAlert(error: error).beginSheetModal(for: window)
            }
        }
    }

    private func bind(_ control: NSControl, _ handler: @escaping (Any) -> Void) {
        let target = ActionHandler(handler)
        handlers.append(target)
        control.target = target
        control.action = #selector(ActionHandler.handleAction(_:))
    }

    private func selectStyle(at index: Int) {
        for (buttonIndex, button) in styleButtons.enumerated() {
            button.state = buttonIndex == index ? .on : .off
        }
        settings.style = HUDStyle.allCases[index]
    }

    private func resetToDefaults() {
        settings.resetToDefaults()
        rebuildContent()
    }
}
