import Foundation

/// Taux de change (open.er-api.com, 160 devises, sans clé API ; repli sur la BCE via Frankfurter),
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
        .init(code: "AED", flag: "🇦🇪", name: "Dirham des Émirats"),
        .init(code: "SAR", flag: "🇸🇦", name: "Riyal saoudien"),
        .init(code: "QAR", flag: "🇶🇦", name: "Riyal qatari"),
        .init(code: "KWD", flag: "🇰🇼", name: "Dinar koweïtien"),
        .init(code: "BHD", flag: "🇧🇭", name: "Dinar bahreïni"),
        .init(code: "OMR", flag: "🇴🇲", name: "Rial omanais"),
        .init(code: "JOD", flag: "🇯🇴", name: "Dinar jordanien"),
        .init(code: "EGP", flag: "🇪🇬", name: "Livre égyptienne"),
        .init(code: "MAD", flag: "🇲🇦", name: "Dirham marocain"),
        .init(code: "TND", flag: "🇹🇳", name: "Dinar tunisien"),
        .init(code: "DZD", flag: "🇩🇿", name: "Dinar algérien"),
        .init(code: "XOF", flag: "🌍", name: "Franc CFA (UEMOA)"),
        .init(code: "XAF", flag: "🌍", name: "Franc CFA (CEMAC)"),
        .init(code: "NGN", flag: "🇳🇬", name: "Naira nigérian"),
        .init(code: "KES", flag: "🇰🇪", name: "Shilling kényan"),
        .init(code: "RUB", flag: "🇷🇺", name: "Rouble russe"),
        .init(code: "UAH", flag: "🇺🇦", name: "Hryvnia ukrainienne"),
        .init(code: "RSD", flag: "🇷🇸", name: "Dinar serbe"),
        .init(code: "PKR", flag: "🇵🇰", name: "Roupie pakistanaise"),
        .init(code: "BDT", flag: "🇧🇩", name: "Taka bangladais"),
        .init(code: "LKR", flag: "🇱🇰", name: "Roupie srilankaise"),
        .init(code: "VND", flag: "🇻🇳", name: "Dong vietnamien"),
        .init(code: "TWD", flag: "🇹🇼", name: "Dollar taïwanais"),
        .init(code: "ARS", flag: "🇦🇷", name: "Peso argentin"),
        .init(code: "CLP", flag: "🇨🇱", name: "Peso chilien"),
        .init(code: "COP", flag: "🇨🇴", name: "Peso colombien"),
        .init(code: "PEN", flag: "🇵🇪", name: "Sol péruvien"),
        .init(code: "XPF", flag: "🇵🇫", name: "Franc pacifique"),
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
        guard !isLoading else { return }
        isLoading = true
        Task {
            defer { self.isLoading = false }
            var fetched = await Self.fetchERAPI()
            if fetched == nil { fetched = await Self.fetchFrankfurter() }
            if let result = fetched {
                self.rates = result.rates
                self.date = result.date
                self.fetchedAt = Date()
                self.failed = false
                UserDefaults.standard.set(result.rates, forKey: self.ratesKey)
                UserDefaults.standard.set(result.date, forKey: self.dateKey)
            } else {
                self.failed = self.rates.isEmpty
            }
        }
    }

    private struct Fetched: Sendable {
        let rates: [String: Double]
        let date: String?
    }

    private static func fetchJSON(_ url: String) async -> [String: Any]? {
        guard let url = URL(string: url),
              let response = try? await URLSession.shared.data(from: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: response.0) as? [String: Any]
    }

    /// 160+ devises (dont AED, MAD, XOF…), mises à jour une fois par jour.
    private static func fetchERAPI() async -> Fetched? {
        guard let json = await fetchJSON("https://open.er-api.com/v6/latest/EUR"),
              json["result"] as? String == "success",
              let raw = json["rates"] as? [String: Any] else { return nil }
        var rates = raw.compactMapValues { ($0 as? NSNumber)?.doubleValue }
        rates["EUR"] = 1
        var date: String?
        if let unix = (json["time_last_update_unix"] as? NSNumber)?.doubleValue {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            date = formatter.string(from: Date(timeIntervalSince1970: unix))
        }
        return Fetched(rates: rates, date: date)
    }

    /// Repli : taux de la Banque centrale européenne (≈ 30 devises).
    private static func fetchFrankfurter() async -> Fetched? {
        guard let json = await fetchJSON("https://api.frankfurter.app/latest?from=EUR"),
              let raw = json["rates"] as? [String: Any] else { return nil }
        var rates = raw.compactMapValues { ($0 as? NSNumber)?.doubleValue }
        rates["EUR"] = 1
        return Fetched(rates: rates, date: json["date"] as? String)
    }

    /// Taux de `from` vers `to`, si connus.
    func rate(from: String, to: String) -> Double? {
        guard let a = rates[from], let b = rates[to], a > 0 else { return nil }
        return b / a
    }

    func convert(_ amount: Double, from: String, to: String) -> Double? {
        rate(from: from, to: to).map { amount * $0 }
    }

    static func format(_ value: Double, decimals: Int = 2) -> String {
        guard value.isFinite else { return "∞" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = decimals
        formatter.minimumFractionDigits = decimals == 2 ? 2 : 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
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
