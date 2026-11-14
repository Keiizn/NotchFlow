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
        static let autoCheckUpdates = "autoCheckUpdates"
        static let autoInstallUpdates = "autoInstallUpdates"
        static let theme = "theme"
        static let glassTint = "glassTint"
        static let replaceSystemHUD = "replaceSystemHUD"
        static let hotKeyEnabled = "hotKeyEnabled"
        static let showLyrics = "showLyrics"
        static let browserMedia = "browserMedia"
        static let showReminderActivity = "showReminderActivity"
        static let tabsMigration = "tabsMigrationV2"
        static let tabsMigrationBattery = "tabsMigrationV3"
        static let chargeLimiterEnabled = "chargeLimiterEnabled"
        static let chargeLimit = "chargeLimit"
        static let sailingRange = "sailingRange"
        static let dischargeToLimit = "dischargeToLimit"
        static let heatProtection = "heatProtection"
        static let heatLimit = "heatLimit"
        static let restoreChargingOnQuit = "restoreChargingOnQuit"
    }

    // MARK: Batterie (façon AlDente)
    @Published var chargeLimiterEnabled: Bool { didSet { store(chargeLimiterEnabled, Keys.chargeLimiterEnabled) } }
    /// Pourcentage maximum de charge (20…100).
    @Published var chargeLimit: Int { didSet { store(chargeLimit, Keys.chargeLimit) } }
    /// Marge de « navigation » : la charge ne reprend que sous (limite − marge).
    @Published var sailingRange: Int { didSet { store(sailingRange, Keys.sailingRange) } }
    @Published var dischargeToLimit: Bool { didSet { store(dischargeToLimit, Keys.dischargeToLimit) } }
    @Published var heatProtection: Bool { didSet { store(heatProtection, Keys.heatProtection) } }
    @Published var heatLimit: Double { didSet { store(heatLimit, Keys.heatLimit) } }
    @Published var restoreChargingOnQuit: Bool { didSet { store(restoreChargingOnQuit, Keys.restoreChargingOnQuit) } }

    enum Theme: String, CaseIterable, Identifiable {
        case glass, black
        var id: String { rawValue }
        var title: String { self == .glass ? "Liquid Glass" : "Noir classique" }
    }

    @Published var theme: Theme { didSet { store(theme.rawValue, Keys.theme) } }
    /// Assombrissement du verre (0 = très transparent, 0,6 = presque opaque).
    @Published var glassTint: Double { didSet { store(glassTint, Keys.glassTint) } }
    @Published var replaceSystemHUD: Bool { didSet { store(replaceSystemHUD, Keys.replaceSystemHUD) } }
    @Published var hotKeyEnabled: Bool { didSet { store(hotKeyEnabled, Keys.hotKeyEnabled) } }
    @Published var showLyrics: Bool { didSet { store(showLyrics, Keys.showLyrics) } }
    @Published var browserMedia: Bool { didSet { store(browserMedia, Keys.browserMedia) } }
    @Published var showReminderActivity: Bool { didSet { store(showReminderActivity, Keys.showReminderActivity) } }

    @Published var autoCheckUpdates: Bool { didSet { store(autoCheckUpdates, Keys.autoCheckUpdates) } }
    @Published var autoInstallUpdates: Bool { didSet { store(autoInstallUpdates, Keys.autoInstallUpdates) } }

    /// Onglets activés par défaut (le miroir est désactivé par défaut).
    static let defaultTabs = ["home", "battery", "apps", "shelf", "timer", "reminders", "actions", "notes", "clipboard", "system"]

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
            Keys.openWidth: 720.0,
            Keys.theme: Theme.glass.rawValue,
            Keys.glassTint: 0.3,
            Keys.replaceSystemHUD: true,
            Keys.hotKeyEnabled: true,
            Keys.showLyrics: true,
            Keys.browserMedia: true,
            Keys.showReminderActivity: true,
            Keys.chargeLimiterEnabled: false,
            Keys.chargeLimit: 80,
            Keys.sailingRange: 5,
            Keys.dischargeToLimit: false,
            Keys.heatProtection: true,
            Keys.heatLimit: 35.0,
            Keys.restoreChargingOnQuit: true,
            Keys.enabledTabs: Self.defaultTabs,
            Keys.closeOnClickOutside: true,
            Keys.showShadow: true,
            Keys.hoverGrow: true,
            Keys.showBatteryInHeader: true,
            Keys.autoCheckUpdates: true,
            Keys.autoInstallUpdates: true,
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
        autoCheckUpdates = d.bool(forKey: Keys.autoCheckUpdates)
        autoInstallUpdates = d.bool(forKey: Keys.autoInstallUpdates)
        theme = Theme(rawValue: d.string(forKey: Keys.theme) ?? "") ?? .glass
        glassTint = d.double(forKey: Keys.glassTint)
        replaceSystemHUD = d.bool(forKey: Keys.replaceSystemHUD)
        hotKeyEnabled = d.bool(forKey: Keys.hotKeyEnabled)
        showLyrics = d.bool(forKey: Keys.showLyrics)
        browserMedia = d.bool(forKey: Keys.browserMedia)
        showReminderActivity = d.bool(forKey: Keys.showReminderActivity)
        chargeLimiterEnabled = d.bool(forKey: Keys.chargeLimiterEnabled)
        chargeLimit = min(max(d.integer(forKey: Keys.chargeLimit), 20), 100)
        sailingRange = min(max(d.integer(forKey: Keys.sailingRange), 1), 20)
        dischargeToLimit = d.bool(forKey: Keys.dischargeToLimit)
        heatProtection = d.bool(forKey: Keys.heatProtection)
        heatLimit = d.double(forKey: Keys.heatLimit)
        restoreChargingOnQuit = d.bool(forKey: Keys.restoreChargingOnQuit)

        if !d.bool(forKey: Keys.tabsMigrationBattery) {
            if !enabledTabs.contains("battery") {
                enabledTabs.insert("battery", at: min(1, enabledTabs.count))
            }
            d.set(enabledTabs, forKey: Keys.enabledTabs)
            d.set(true, forKey: Keys.tabsMigrationBattery)
        }

        // Ajoute une seule fois les nouveaux onglets (Rappels, Actions) aux listes déjà personnalisées.
        if !d.bool(forKey: Keys.tabsMigration) {
            for tab in ["reminders", "actions"] where !enabledTabs.contains(tab) {
                enabledTabs.append(tab)
            }
            d.set(enabledTabs, forKey: Keys.enabledTabs)
            d.set(true, forKey: Keys.tabsMigration)
        }
    }

    private func store(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
