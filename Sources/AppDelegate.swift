import Cocoa

private let systemDefinedEventType: UInt32 = 14 // NX_SYSDEFINED
private let mediaKeySubtype: Int16 = 8
private let keyDownState = 0xA
private let feedbackSoundPath = "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff"

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let delegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
    return delegate.handleEvent(type: type, event: event)
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = VolumeController()
    private lazy var hud = VolumeHUD()
    private var statusItem: NSStatusItem!
    private let outputItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let volumeItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "", action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private var settingsController: SettingsWindowController?
    private var feedbackSound: NSSound?
    private var settingsObserver: NSObjectProtocol?
    private var eventTap: CFMachPort?
    private var lastHandledKey: MediaKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = MenuBarIcon.image
        statusItem.button?.imagePosition = .imageLeading

        let menu = NSMenu()
        menu.delegate = self
        outputItem.isEnabled = false
        volumeItem.isEnabled = false
        permissionItem.target = self
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(outputItem)
        menu.addItem(volumeItem)
        menu.addItem(permissionItem)
        menu.addItem(.separator())
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        controller.onChange = { [weak self] in
            guard let self else { return }
            self.updateTitle()
            self.hud.show(volume: self.controller.volume, muted: self.controller.muted, title: self.controller.outputName)
        }
        settingsObserver = NotificationCenter.default.addObserver(forName: Settings.didChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if !Settings.shared.feedbackSound { self.feedbackSound = nil }
            self.updateTitle()
        }
        controller.refresh()

        let trusted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        log("launched; accessibility trusted: \(trusted); output: \(controller.currentOutputDescription())")
        if !trusted || !installEventTap() {
            statusItem.button?.title = " Needs Accessibility"
            Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
                guard let self, AXIsProcessTrusted(), self.installEventTap() else { return }
                timer.invalidate()
                self.updateTitle()
            }
        }
    }

    private func installEventTap() -> Bool {
        let mask = CGEventMask(1 << systemDefinedEventType)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log("event tap creation failed")
            return false
        }
        log("event tap installed")

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        return true
    }

    func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            log("event tap disabled by system (\(type.rawValue)); re-enabling")
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return passThrough
        }
        guard type.rawValue == systemDefinedEventType,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == mediaKeySubtype
        else { return passThrough }

        let keyCode = (nsEvent.data1 & 0xFFFF_0000) >> 16
        let keyState = (nsEvent.data1 & 0xFF00) >> 8

        let key: MediaKey
        switch keyCode {
        case 0: key = .volumeUp // NX_KEYTYPE_SOUND_UP
        case 1: key = .volumeDown // NX_KEYTYPE_SOUND_DOWN
        case 7: key = .mute // NX_KEYTYPE_MUTE
        default: return passThrough
        }

        if keyState == keyDownState {
            let fineStep = nsEvent.modifierFlags.contains([.option, .shift])
            lastHandledKey = controller.handle(key, fineStep: fineStep) ? key : nil
            return lastHandledKey == nil ? passThrough : nil
        }

        // Swallow the matching key-up so macOS doesn't show its "volume unavailable" HUD.
        guard let handledKey = lastHandledKey else { return passThrough }
        if handledKey != .mute { playFeedback() }
        return nil
    }

    private func playFeedback() {
        guard Settings.shared.feedbackSound, !controller.muted else { return }
        if feedbackSound == nil {
            feedbackSound = NSSound(contentsOfFile: feedbackSoundPath, byReference: true) ?? NSSound(named: "Pop")
        }
        feedbackSound?.stop()
        feedbackSound?.play()
    }

    private func updateTitle() {
        guard eventTap != nil else {
            statusItem.button?.title = " Needs Accessibility"
            return
        }
        guard controller.isActive, Settings.shared.showPercentInMenuBar else {
            statusItem.button?.title = ""
            return
        }
        statusItem.button?.title = controller.muted ? " Muted" : " \(Int((controller.volume * 100).rounded()))%"
    }

    func menuWillOpen(_ menu: NSMenu) {
        controller.refresh()
        outputItem.title = controller.currentOutputDescription()
        volumeItem.title = controller.muted ? "Muted" : "Volume: \(Int((controller.volume * 100).rounded()))%"
        permissionItem.title = "⚠️ Volume keys need Accessibility access…"
        permissionItem.isHidden = eventTap != nil
        updateTitle()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    @objc private func openSettings() {
        let settingsWindow = settingsController ?? SettingsWindowController(outputName: controller.outputName)
        if settingsController == nil {
            settingsWindow.onShowOnScreen = { [weak self] in
                guard let self else { return }
                self.hud.show(volume: self.controller.volume, muted: self.controller.muted, title: self.controller.outputName, force: true)
            }
            settingsController = settingsWindow
        }
        settingsWindow.outputName = controller.outputName
        settingsWindow.present()
    }

    @objc private func openAccessibilitySettings() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
