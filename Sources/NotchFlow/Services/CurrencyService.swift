import Foundation

/// Taux de change (Banque centrale européenne via Frankfurter, sans clé API),
/// mis en cache une heure et conservés hors ligne.
@MainActor
final class CurrencyService: ObservableObject {
    static let shared = CurrencyService()

    struct Currency: Identifiable, Hashable {
        let code: String
        let flag: String
        let name: String
        var id: String { code }
    }

    static let currencies: [Currency] = [
        .init(code: "EUR", flag: "🇪🇺", name: "Euro"),
        .init(code: "USD", flag: "🇺🇸", name: "Dollar américain"),
        .init(code: "GBP", flag: "🇬🇧", name: "Livre sterling"),
        .init(code: "CHF", flag: "🇨🇭", name: "Franc suisse"),
        .init(code: "JPY", flag: "🇯🇵", name: "Yen japonais"),
        .init(code: "CAD", flag: "🇨🇦", name: "Dollar canadien"),
        .init(code: "AUD", flag: "🇦🇺", name: "Dollar australien"),
        .init(code: "NZD", flag: "🇳🇿", name: "Dollar néo-zélandais"),
        .init(code: "CNY", flag: "🇨🇳", name: "Yuan chinois"),
        .init(code: "HKD", flag: "🇭🇰", name: "Dollar de Hong Kong"),
        .init(code: "SGD", flag: "🇸🇬", name: "Dollar de Singapour"),
        .init(code: "KRW", flag: "🇰🇷", name: "Won sud-coréen"),
        .init(code: "INR", flag: "🇮🇳", name: "Roupie indienne"),
        .init(code: "THB", flag: "🇹🇭", name: "Baht thaïlandais"),
        .init(code: "IDR", flag: "🇮🇩", name: "Roupie indonésienne"),
        .init(code: "MYR", flag: "🇲🇾", name: "Ringgit malaisien"),
        .init(code: "PHP", flag: "🇵🇭", name: "Peso philippin"),
        .init(code: "SEK", flag: "🇸🇪", name: "Couronne suédoise"),
        .init(code: "NOK", flag: "🇳🇴", name: "Couronne norvégienne"),
        .init(code: "DKK", flag: "🇩🇰", name: "Couronne danoise"),
        .init(code: "ISK", flag: "🇮🇸", name: "Couronne islandaise"),
        .init(code: "PLN", flag: "🇵🇱", name: "Zloty polonais"),
        .init(code: "CZK", flag: "🇨🇿", name: "Couronne tchèque"),
        .init(code: "HUF", flag: "🇭🇺", name: "Forint hongrois"),
        .init(code: "RON", flag: "🇷🇴", name: "Leu roumain"),
        .init(code: "BGN", flag: "🇧🇬", name: "Lev bulgare"),
        .init(code: "TRY", flag: "🇹🇷", name: "Livre turque"),
        .init(code: "ILS", flag: "🇮🇱", name: "Shekel israélien"),
        .init(code: "ZAR", flag: "🇿🇦", name: "Rand sud-africain"),
        .init(code: "BRL", flag: "🇧🇷", name: "Réal brésilien"),
        .init(code: "MXN", flag: "🇲🇽", name: "Peso mexicain"),
    ]

    static func currency(_ code: String) -> Currency {
        currencies.first { $0.code == code } ?? Currency(code: code, flag: "💱", name: code)
    }

    /// Taux par rapport à l'euro (EUR = 1).
    @Published private(set) var rates: [String: Double] = [:]
    @Published private(set) var date: String?
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false

    private var fetchedAt: Date?
    private let ratesKey = "currency.rates"
    private let dateKey = "currency.date"

    private init() {
        rates = (UserDefaults.standard.dictionary(forKey: ratesKey) as? [String: Double]) ?? [:]
        date = UserDefaults.standard.string(forKey: dateKey)
    }

    /// Recharge les taux s'ils ont plus d'une heure.
    func refreshIfNeeded() {
        if let fetchedAt, Date().timeIntervalSince(fetchedAt) < 3600, !rates.isEmpty { return }
        refresh()
    }

    func refresh() {
        guard !isLoading, let url = URL(string: "https://api.frankfurter.app/latest?from=EUR") else { return }
        isLoading = true
        Task {
            defer { self.isLoading = false }
            guard let response = try? await URLSession.shared.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: response.0) as? [String: Any],
                  let raw = json["rates"] as? [String: Any] else {
                self.failed = self.rates.isEmpty
                return
            }
            var parsed = raw.compactMapValues { ($0 as? NSNumber)?.doubleValue }
            parsed["EUR"] = 1
            self.rates = parsed
            self.date = json["date"] as? String
            self.fetchedAt = Date()
            self.failed = false
            UserDefaults.standard.set(parsed, forKey: self.ratesKey)
            UserDefaults.standard.set(self.date, forKey: self.dateKey)
        }
    }

    /// Taux de `from` vers `to`, si connus.
    func rate(from: String, to: String) -> Double? {
        guard let a = rates[from], let b = rates[to], a > 0 else { return nil }
        return b / a
    }

    func convert(_ amount: Double, from: String, to: String) -> Double? {
        rate(from: from, to: to).map { amount * $0 }
    }

    /// « 15 novembre 2026 »
    var formattedDate: String? {
        guard let date else { return nil }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "en_US_POSIX")
        guard let parsed = parser.date(from: date) else { return date }
        return parsed.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "fr_FR")))
    }
}
