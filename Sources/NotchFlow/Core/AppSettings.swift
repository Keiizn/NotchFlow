import Foundation
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
            Keys.openWidth: 640.0,
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
    }

    private func store(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
