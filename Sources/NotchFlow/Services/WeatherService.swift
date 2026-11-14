import Foundation
import CoreLocation

struct WeatherInfo: Equatable {
    var temperature: Double
    var min: Double
    var max: Double
    var code: Int
    var isDay: Bool
    var city: String

    var symbol: String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61...67, 80...82: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }
}

private struct GeoResponse: Decodable {
    struct Result: Decodable { let name: String; let latitude: Double; let longitude: Double }
    let results: [Result]?
}

private struct ForecastResponse: Decodable {
    struct Current: Decodable { let temperature_2m: Double; let weather_code: Int; let is_day: Int }
    struct Daily: Decodable { let temperature_2m_max: [Double]; let temperature_2m_min: [Double] }
    let current: Current
    let daily: Daily
}

/// Météo via l'API gratuite Open-Meteo (aucune clé requise).
/// Utilise la ville définie dans les réglages, sinon la position approximative.
@MainActor
final class WeatherService: NSObject, ObservableObject {
    static let shared = WeatherService()

    @Published private(set) var current: WeatherInfo?
    @Published private(set) var errorMessage: String?

    private let manager = CLLocationManager()
    private var refreshTimer: Timer?
    private var started = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    func start() {
        guard !started else { return }
        started = true
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        guard AppSettings.shared.showWeather else { return }
        errorMessage = nil
        let city = AppSettings.shared.weatherCity.trimmingCharacters(in: .whitespacesAndNewlines)
        if city.isEmpty {
            requestLocation()
        } else {
            Task { await self.load(city: city) }
        }
    }

    private func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            errorMessage = "Localisation refusée. Indiquez une ville dans les réglages."
        default:
            manager.requestLocation()
        }
    }

    private func load(city: String) async {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "fr"),
        ]
        do {
            let (data, _) = try await URLSession.shared.data(from: components.url!)
            let geo = try JSONDecoder().decode(GeoResponse.self, from: data)
            guard let result = geo.results?.first else {
                errorMessage = "Ville introuvable"
                return
            }
            await load(latitude: result.latitude, longitude: result.longitude, city: result.name)
        } catch {
            errorMessage = "Météo indisponible"
        }
    }

    fileprivate func load(latitude: Double, longitude: Double, city: String) async {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        var items = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        if AppSettings.shared.useFahrenheit {
            items.append(URLQueryItem(name: "temperature_unit", value: "fahrenheit"))
        }
        components.queryItems = items
        do {
            let (data, _) = try await URLSession.shared.data(from: components.url!)
            let r = try JSONDecoder().decode(ForecastResponse.self, from: data)
            current = WeatherInfo(
                temperature: r.current.temperature_2m,
                min: r.daily.temperature_2m_min.first ?? r.current.temperature_2m,
                max: r.daily.temperature_2m_max.first ?? r.current.temperature_2m,
                code: r.current.weather_code,
                isDay: r.current.is_day == 1,
                city: city
            )
            errorMessage = nil
        } catch {
            errorMessage = "Météo indisponible"
        }
    }

    fileprivate static func cityName(latitude: Double, longitude: Double) async -> String {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: latitude, longitude: longitude))
        return placemarks?.first?.locality ?? "Ma position"
    }
}

extension WeatherService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .notDetermined: break
            case .denied, .restricted:
                self.errorMessage = "Localisation refusée. Indiquez une ville dans les réglages."
            default:
                self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        Task { @MainActor in
            let city = await WeatherService.cityName(latitude: lat, longitude: lon)
            await self.load(latitude: lat, longitude: lon, city: city)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if self.current == nil {
                self.errorMessage = "Position indisponible. Indiquez une ville dans les réglages."
            }
        }
    }
}
