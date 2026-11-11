import Cocoa

protocol SettingOption: CaseIterable, Equatable, RawRepresentable where RawValue == String, AllCases == [Self] {
    var title: String { get }
}

enum HUDStyle: String, SettingOption {
    case glassPanel, glassPill, classic, vertical, ring, edgeLine, candy

    var title: String {
        switch self {
        case .glassPanel: return "macOS"
        case .glassPill: return "Glass pill"
        case .classic: return "Classic"
        case .vertical: return "Vertical"
        case .ring: return "Ring"
        case .edgeLine: return "Edge line"
        case .candy: return "Candy"
        }
    }

    var summary: String {
        switch self {
        case .glassPanel: return "Matches the system volume bar, with the device name and tick marks"
        case .glassPill: return "Compact glass capsule with just the icon and bar"
        case .classic: return "The big square with 16 segments from older macOS"
        case .vertical: return "Tall glass slider at the edge of the screen"
        case .ring: return "Circular gauge with the percentage in the middle"
        case .edgeLine: return "A thin line across the top of the screen"
        case .candy: return "Gradient panel with the app's mascot"
        }
    }
}

enum HUDPosition: String, SettingOption {
    case styleDefault, topLeft, topCenter, topRight, leftCenter, center, rightCenter, bottomCenter

    var title: String {
        switch self {
        case .styleDefault: return "Style default"
        case .topLeft: return "Top left"
        case .topCenter: return "Top center"
        case .topRight: return "Top right"
        case .leftCenter: return "Left edge"
        case .center: return "Center"
        case .rightCenter: return "Right edge"
        case .bottomCenter: return "Bottom center"
        }
    }
}

enum HUDScreen: String, SettingOption {
    case pointer, main, all

    var title: String {
        switch self {
        case .pointer: return "Display with pointer"
        case .main: return "Main display"
        case .all: return "All displays"
        }
    }
}

enum HUDSize: String, SettingOption {
    case small, medium, large

    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    var scale: CGFloat {
        switch self {
        case .small: return 0.85
        case .medium: return 1
        case .large: return 1.2
        }
    }
}

enum VolumeStep: String, SettingOption {
    case sixteenth, thirtySecond, fivePercent, tenPercent

    var title: String {
        switch self {
        case .sixteenth: return "16 steps (macOS)"
        case .thirtySecond: return "32 steps"
        case .fivePercent: return "5%"
        case .tenPercent: return "10%"
        }
    }

    var value: Float {
        switch self {
        case .sixteenth: return 1 / 16
        case .thirtySecond: return 1 / 32
        case .fivePercent: return 0.05
        case .tenPercent: return 0.1
        }
    }
}

enum BarColor: String, SettingOption {
    case automatic, accent, candy, custom

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .accent: return "Accent color"
        case .candy: return "Gradient"
        case .custom: return "Custom"
        }
    }
}

final class Settings {
    static let shared = Settings()
    static let didChange = Notification.Name("MultiOutputVolume.settingsDidChange")
    static let defaultGradient = [
        NSColor(srgbRed: 1, green: 0.694, blue: 0.6, alpha: 1),
        NSColor(srgbRed: 0.69, green: 0.486, blue: 1, alpha: 1),
    ]

    /// The setting key a `didChange` notification was posted for; nil after a reset.
    static func changedKey(_ notification: Notification) -> String? {
        notification.userInfo?["key"] as? String
    }

    private let defaults = UserDefaults.standard
    private let keys = [
        "style", "position", "screen", "size", "barColor", "volumeStep", "customColor",
        "gradientStart", "gradientEnd", "hideDelay", "backgroundOpacity", "showHUD", "animations", "feedbackSound", "showPercentInMenuBar",
    ]

    func resetToDefaults() {
        keys.forEach(defaults.removeObject(forKey:))
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    var style: HUDStyle {
        get { option("style", .glassPanel) }
        set { setOption("style", newValue) }
    }
    var position: HUDPosition {
        get { option("position", .styleDefault) }
        set { setOption("position", newValue) }
    }
    var screen: HUDScreen {
        get { option("screen", .pointer) }
        set { setOption("screen", newValue) }
    }
    var size: HUDSize {
        get { option("size", .medium) }
        set { setOption("size", newValue) }
    }
    var barColor: BarColor {
        get { option("barColor", .automatic) }
        set { setOption("barColor", newValue) }
    }
    var volumeStep: VolumeStep {
        get { option("volumeStep", .sixteenth) }
        set { setOption("volumeStep", newValue) }
    }
    var customColor: NSColor {
        get { defaults.string(forKey: "customColor").flatMap(NSColor.init(hex:)) ?? .systemPink }
        set { set(newValue.hexString, "customColor") }
    }
    var gradientColors: [NSColor] {
        get {
            ["gradientStart", "gradientEnd"].enumerated().map { index, key in
                defaults.string(forKey: key).flatMap(NSColor.init(hex:)) ?? Self.defaultGradient[index]
            }
        }
    }
    func setGradientColor(_ color: NSColor, at index: Int) {
        set(color.hexString, index == 0 ? "gradientStart" : "gradientEnd")
    }
    var hideDelay: Double {
        get { defaults.object(forKey: "hideDelay") as? Double ?? 1.5 }
        set { set(newValue, "hideDelay") }
    }
    /// 0 leaves the glass fully translucent; 1 makes the background solid.
    var backgroundOpacity: Double {
        get { defaults.object(forKey: "backgroundOpacity") as? Double ?? 0 }
        set { set(min(max(newValue, 0), 1), "backgroundOpacity") }
    }
    var showHUD: Bool {
        get { flag("showHUD", true) }
        set { set(newValue, "showHUD") }
    }
    var animations: Bool {
        get { flag("animations", true) }
        set { set(newValue, "animations") }
    }
    var feedbackSound: Bool {
        get { flag("feedbackSound", false) }
        set { set(newValue, "feedbackSound") }
    }
    var showPercentInMenuBar: Bool {
        get { flag("showPercentInMenuBar", true) }
        set { set(newValue, "showPercentInMenuBar") }
    }

    var barPaint: BarPaint {
        switch barColor {
        case .automatic: return .automatic
        case .accent: return .accent
        case .candy: return .gradient(gradientColors)
        case .custom: return .custom(customColor)
        }
    }

    private func option<T: SettingOption>(_ key: String, _ fallback: T) -> T {
        defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
    }

    private func setOption<T: SettingOption>(_ key: String, _ value: T) {
        set(value.rawValue, key)
    }

    private func flag(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    private func set(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: Self.didChange, object: nil, userInfo: ["key": key])
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#FF2D55" }
        return String(
            format: "#%02X%02X%02X",
            Int((rgb.redComponent * 255).rounded()),
            Int((rgb.greenComponent * 255).rounded()),
            Int((rgb.blueComponent * 255).rounded())
        )
    }
}
