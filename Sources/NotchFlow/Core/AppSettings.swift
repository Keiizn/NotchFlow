import AppKit
import Combine

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    enum Style: String, CaseIterable, Identifiable {
        case notch, island
        var id: String { rawValue }
    }

    private enum Keys {
        static let style = "style"
        static let openOnHover = "openOnHover"
        static let hoverDelay = "hoverDelay"
        static let haptics = "haptics"
        static let openWidth = "openWidth"
        static let openHeight = "openHeight"
        static let showMusicActivity = "showMusicActivity"
        static let showBatteryActivity = "showBatteryActivity"
        static let showVolumeHUD = "showVolumeHUD"
        static let showEventActivity = "showEventActivity"
        static let showCalendar = "showCalendar"
        static let showWeather = "showWeather"
        static let weatherCity = "weatherCity"
        static let useFahrenheit = "useFahrenheit"
        static let clipboardEnabled = "clipboardEnabled"
        static let enabledTabs = "enabledTabs"
        static let favoriteApps = "favoriteApps"
        static let closeOnClickOutside = "closeOnClickOutside"
        static let showShadow = "showShadow"
        static let hoverGrow = "hoverGrow"
        static let showBatteryInHeader = "showBatteryInHeader"
    }

    /// Onglets activés par défaut (le miroir est désactivé par défaut).
    static let defaultTabs = ["home", "apps", "shelf", "timer", "notes", "clipboard", "system"]

    @Published var enabledTabs: [String] { didSet { store(enabledTabs, Keys.enabledTabs) } }
    @Published var favoriteApps: [String] { didSet { store(favoriteApps, Keys.favoriteApps) } }
    @Published var closeOnClickOutside: Bool { didSet { store(closeOnClickOutside, Keys.closeOnClickOutside) } }
    @Published var showShadow: Bool { didSet { store(showShadow, Keys.showShadow) } }
    @Published var hoverGrow: Bool { didSet { store(hoverGrow, Keys.hoverGrow) } }
    @Published var showBatteryInHeader: Bool { didSet { store(showBatteryInHeader, Keys.showBatteryInHeader) } }

    func isTabEnabled(_ id: String) -> Bool { enabledTabs.contains(id) }

    func setTab(_ id: String, enabled: Bool) {
        if enabled {
            if !enabledTabs.contains(id) { enabledTabs.append(id) }
        } else if enabledTabs.count > 1 {
            enabledTabs.removeAll { $0 == id }
        }
    }

    func resetToDefaults() {
        for key in [Keys.style, Keys.openOnHover, Keys.hoverDelay, Keys.haptics, Keys.openWidth, Keys.openHeight,
                    Keys.showMusicActivity, Keys.showBatteryActivity, Keys.showVolumeHUD, Keys.showEventActivity,
                    Keys.showCalendar, Keys.showWeather, Keys.useFahrenheit, Keys.clipboardEnabled,
                    Keys.enabledTabs, Keys.closeOnClickOutside, Keys.showShadow, Keys.hoverGrow, Keys.showBatteryInHeader] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        let d = UserDefaults.standard
        style = Style(rawValue: d.string(forKey: Keys.style) ?? "") ?? .notch
        openOnHover = d.bool(forKey: Keys.openOnHover)
        hoverDelay = d.double(forKey: Keys.hoverDelay)
        haptics = d.bool(forKey: Keys.haptics)
        openWidth = d.double(forKey: Keys.openWidth)
        openHeight = d.double(forKey: Keys.openHeight)
        showMusicActivity = true; showBatteryActivity = true; showVolumeHUD = true; showEventActivity = true
        showCalendar = true; showWeather = true; useFahrenheit = false; clipboardEnabled = true
        enabledTabs = Self.defaultTabs
        closeOnClickOutside = true; showShadow = true; hoverGrow = true; showBatteryInHeader = true
    }

    private static func defaultFavoriteApps() -> [String] {
        let ids = ["com.apple.finder", "com.apple.Safari", "com.google.Chrome", "com.apple.mail", "com.apple.MobileSMS",
                   "com.apple.iCal", "com.apple.Notes", "com.spotify.client", "com.apple.Music", "com.apple.systempreferences"]
        return ids.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)?.path }
    }

    @Published var style: Style { didSet { store(style.rawValue, Keys.style) } }
    @Published var openOnHover: Bool { didSet { store(openOnHover, Keys.openOnHover) } }
    @Published var hoverDelay: Double { didSet { store(hoverDelay, Keys.hoverDelay) } }
    @Published var haptics: Bool { didSet { store(haptics, Keys.haptics) } }
    @Published var openWidth: Double { didSet { store(openWidth, Keys.openWidth) } }
    @Published var openHeight: Double { didSet { store(openHeight, Keys.openHeight) } }

    @Published var showMusicActivity: Bool { didSet { store(showMusicActivity, Keys.showMusicActivity) } }
    @Published var showBatteryActivity: Bool { didSet { store(showBatteryActivity, Keys.showBatteryActivity) } }
    @Published var showVolumeHUD: Bool { didSet { store(showVolumeHUD, Keys.showVolumeHUD) } }
    @Published var showEventActivity: Bool { didSet { store(showEventActivity, Keys.showEventActivity) } }

    @Published var showCalendar: Bool { didSet { store(showCalendar, Keys.showCalendar) } }
    @Published var showWeather: Bool { didSet { store(showWeather, Keys.showWeather) } }
    @Published var weatherCity: String { didSet { store(weatherCity, Keys.weatherCity) } }
    @Published var useFahrenheit: Bool { didSet { store(useFahrenheit, Keys.useFahrenheit) } }
    @Published var clipboardEnabled: Bool { didSet { store(clipboardEnabled, Keys.clipboardEnabled) } }

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            Keys.style: Style.notch.rawValue,
            Keys.openOnHover: true,
            Keys.hoverDelay: 0.15,
            Keys.haptics: true,
            Keys.openWidth: 680.0,
            Keys.enabledTabs: Self.defaultTabs,
            Keys.closeOnClickOutside: true,
            Keys.showShadow: true,
            Keys.hoverGrow: true,
            Keys.showBatteryInHeader: true,
            Keys.openHeight: 170.0,
            Keys.showMusicActivity: true,
            Keys.showBatteryActivity: true,
            Keys.showVolumeHUD: true,
            Keys.showEventActivity: true,
            Keys.showCalendar: true,
            Keys.showWeather: true,
            Keys.weatherCity: "",
            Keys.useFahrenheit: false,
            Keys.clipboardEnabled: true,
        ])
        style = Style(rawValue: d.string(forKey: Keys.style) ?? "") ?? .notch
        openOnHover = d.bool(forKey: Keys.openOnHover)
        hoverDelay = d.double(forKey: Keys.hoverDelay)
        haptics = d.bool(forKey: Keys.haptics)
        openWidth = d.double(forKey: Keys.openWidth)
        openHeight = d.double(forKey: Keys.openHeight)
        showMusicActivity = d.bool(forKey: Keys.showMusicActivity)
        showBatteryActivity = d.bool(forKey: Keys.showBatteryActivity)
        showVolumeHUD = d.bool(forKey: Keys.showVolumeHUD)
        showEventActivity = d.bool(forKey: Keys.showEventActivity)
        showCalendar = d.bool(forKey: Keys.showCalendar)
        showWeather = d.bool(forKey: Keys.showWeather)
        weatherCity = d.string(forKey: Keys.weatherCity) ?? ""
        useFahrenheit = d.bool(forKey: Keys.useFahrenheit)
        clipboardEnabled = d.bool(forKey: Keys.clipboardEnabled)
        enabledTabs = d.stringArray(forKey: Keys.enabledTabs) ?? Self.defaultTabs
        favoriteApps = d.stringArray(forKey: Keys.favoriteApps) ?? Self.defaultFavoriteApps()
        closeOnClickOutside = d.bool(forKey: Keys.closeOnClickOutside)
        showShadow = d.bool(forKey: Keys.showShadow)
        hoverGrow = d.bool(forKey: Keys.hoverGrow)
        showBatteryInHeader = d.bool(forKey: Keys.showBatteryInHeader)
    }

    private func store(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
