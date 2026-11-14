import Foundation

/// Calculatrice et convertisseur : « 12*(3+4) », « 2^10 », « 15 % de 80 »,
/// « 10 km en mi », « 72 f en c », « 100 eur en usd ».
@MainActor
final class Calculator: ObservableObject {
    static let shared = Calculator()

    @Published var input = "" { didSet { evaluate() } }
    @Published private(set) var result: String?
    @Published private(set) var isLoading = false

    private var currencyTask: Task<Void, Never>?

    private init() {}

    private func evaluate() {
        currencyTask?.cancel()
        isLoading = false
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { result = nil; return }

        if let conversion = Self.parseConversion(text) {
            if let units = Self.convertUnits(conversion) {
                result = units
            } else if let from = Self.currency(conversion.from), let to = Self.currency(conversion.to) {
                convertCurrency(conversion.value, from: from, to: to)
            } else {
                result = nil
            }
            return
        }
        if let value = MathExpression.evaluate(text) {
            result = Self.format(value)
        } else {
            result = nil
        }
    }

    // MARK: - Conversion

    struct Conversion {
        let value: Double
        let from: String
        let to: String
    }

    static func parseConversion(_ text: String) -> Conversion? {
        let pattern = #"^\s*(-?[\d\s.,]+)\s*([^\d\s]+)\s+(?:en|in|to|vers|=|->|→)\s+([^\d\s]+)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let valueRange = Range(match.range(at: 1), in: text),
              let fromRange = Range(match.range(at: 2), in: text),
              let toRange = Range(match.range(at: 3), in: text),
              let value = MathExpression.number(String(text[valueRange])) else { return nil }
        return Conversion(value: value, from: text[fromRange].lowercased(), to: text[toRange].lowercased())
    }

    private static let units: [String: Dimension] = [
        // Longueur
        "km": UnitLength.kilometers, "m": UnitLength.meters, "cm": UnitLength.centimeters, "mm": UnitLength.millimeters,
        "mi": UnitLength.miles, "mile": UnitLength.miles, "miles": UnitLength.miles, "ft": UnitLength.feet, "pied": UnitLength.feet,
        "pieds": UnitLength.feet, "pouce": UnitLength.inches, "pouces": UnitLength.inches, "inch": UnitLength.inches, "\"": UnitLength.inches,
        "yd": UnitLength.yards, "nmi": UnitLength.nauticalMiles,
        // Masse
        "kg": UnitMass.kilograms, "g": UnitMass.grams, "mg": UnitMass.milligrams, "t": UnitMass.metricTons,
        "lb": UnitMass.pounds, "lbs": UnitMass.pounds, "oz": UnitMass.ounces, "st": UnitMass.stones,
        // Volume
        "l": UnitVolume.liters, "cl": UnitVolume.centiliters, "ml": UnitVolume.milliliters, "dl": UnitVolume.deciliters,
        "gal": UnitVolume.gallons, "floz": UnitVolume.fluidOunces, "cup": UnitVolume.cups, "m3": UnitVolume.cubicMeters,
        // Température
        "c": UnitTemperature.celsius, "°c": UnitTemperature.celsius, "f": UnitTemperature.fahrenheit,
        "°f": UnitTemperature.fahrenheit, "k": UnitTemperature.kelvin,
        // Vitesse
        "km/h": UnitSpeed.kilometersPerHour, "kmh": UnitSpeed.kilometersPerHour, "mph": UnitSpeed.milesPerHour,
        "m/s": UnitSpeed.metersPerSecond, "nd": UnitSpeed.knots, "kn": UnitSpeed.knots,
        // Données
        "o": UnitInformationStorage.bytes, "ko": UnitInformationStorage.kilobytes, "mo": UnitInformationStorage.megabytes,
        "go": UnitInformationStorage.gigabytes, "to": UnitInformationStorage.terabytes,
        "kb": UnitInformationStorage.kilobytes, "mb": UnitInformationStorage.megabytes,
        "gb": UnitInformationStorage.gigabytes, "tb": UnitInformationStorage.terabytes,
        // Durée
        "h": UnitDuration.hours, "min": UnitDuration.minutes, "s": UnitDuration.seconds, "ms": UnitDuration.milliseconds,
        // Surface
        "m2": UnitArea.squareMeters, "km2": UnitArea.squareKilometers, "ha": UnitArea.hectares, "acre": UnitArea.acres,
        // Énergie
        "kcal": UnitEnergy.kilocalories, "kj": UnitEnergy.kilojoules, "kwh": UnitEnergy.kilowattHours,
    ]

    private static func convertUnits(_ c: Conversion) -> String? {
        guard let from = units[c.from], let to = units[c.to],
              ObjectIdentifier(type(of: from)) == ObjectIdentifier(type(of: to)) else { return nil }
        // Toutes les unités Foundation passent par leur unité de base.
        let base = from.converter.baseUnitValue(fromValue: c.value)
        let value = to.converter.value(fromBaseUnitValue: base)
        return "\(format(value)) \(c.to)"
    }

    private static let currencySymbols: [String: String] = [
        "€": "EUR", "$": "USD", "£": "GBP", "¥": "JPY", "chf": "CHF", "fr": "CHF",
    ]

    private static let currencyCodes: Set<String> = [
        "EUR", "USD", "GBP", "JPY", "CHF", "CAD", "AUD", "CNY", "SEK", "NOK", "DKK", "PLN", "CZK",
        "HUF", "TRY", "BRL", "MXN", "INR", "KRW", "SGD", "HKD", "NZD", "ZAR", "ILS", "THB", "RON",
    ]

    private static func currency(_ text: String) -> String? {
        if let code = currencySymbols[text] { return code }
        let upper = text.uppercased()
        return currencyCodes.contains(upper) || CurrencyService.currencies.contains(where: { $0.code == upper }) ? upper : nil
    }

    private func convertCurrency(_ value: Double, from: String, to: String) {
        let service = CurrencyService.shared
        if let converted = service.convert(value, from: from, to: to) {
            result = "\(Self.format(converted, decimals: 2)) \(to)"
        }
        guard service.rates.isEmpty || service.rate(from: from, to: to) == nil else {
            service.refreshIfNeeded()
            return
        }
        // Taux pas encore chargés : on attend la réponse puis on recalcule.
        isLoading = true
        service.refresh()
        currencyTask = Task { [weak self] in
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(250))
                if Task.isCancelled { return }
                if !service.isLoading { break }
            }
            guard let self, !Task.isCancelled else { return }
            self.isLoading = false
            if let converted = service.convert(value, from: from, to: to) {
                self.result = "\(Self.format(converted, decimals: 2)) \(to)"
            } else {
                self.result = service.failed ? "Taux indisponible" : "Devise inconnue"
            }
        }
    }

    // MARK: - Format

    static func format(_ value: Double, decimals: Int = 6) -> String {
        guard value.isFinite else { return "∞" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.numberStyle = abs(value) >= 1e15 || (abs(value) < 1e-6 && value != 0) ? .scientific : .decimal
        formatter.maximumFractionDigits = decimals
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Analyseur d'expressions

/// Analyseur à descente récursive : + − × ÷ ^ %, parenthèses, pi, sqrt().
enum MathExpression {
    static func evaluate(_ text: String) -> Double? {
        var normalized = text.lowercased()
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "x", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "π", with: "pi")
            .replacingOccurrences(of: " de ", with: " of ")
        // « 15 % of 80 » → 15/100*80
        normalized = normalized.replacingOccurrences(of: "% of", with: "%*")
        var parser = Parser(Array(normalized.filter { !$0.isWhitespace }))
        guard let value = parser.parseExpression(), parser.isAtEnd else { return nil }
        // Un nombre seul n'est pas un calcul : rien à afficher.
        if number(text) != nil { return nil }
        return value
    }

    /// « 1 234,5 » ou « 1234.5 »
    static func number(_ text: String) -> Double? {
        var t = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{202F}", with: "")
        if t.contains(",") && !t.contains(".") { t = t.replacingOccurrences(of: ",", with: ".") }
        else { t = t.replacingOccurrences(of: ",", with: "") }
        return Double(t)
    }

    private struct Parser {
        let chars: [Character]
        var index = 0

        init(_ chars: [Character]) { self.chars = chars }

        var isAtEnd: Bool { index >= chars.count }
        private var current: Character? { isAtEnd ? nil : chars[index] }

        mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while let c = current, c == "+" || c == "-" {
                index += 1
                guard let rhs = parseTerm() else { return nil }
                value = c == "+" ? value + rhs : value - rhs
            }
            return value
        }

        private mutating func parseTerm() -> Double? {
            guard var value = parsePower() else { return nil }
            while let c = current, c == "*" || c == "/" {
                index += 1
                guard let rhs = parsePower() else { return nil }
                value = c == "*" ? value * rhs : value / rhs
            }
            return value
        }

        private mutating func parsePower() -> Double? {
            guard let base = parseUnary() else { return nil }
            if current == "^" {
                index += 1
                guard let exponent = parsePower() else { return nil }   // associatif à droite
                return pow(base, exponent)
            }
            return base
        }

        private mutating func parseUnary() -> Double? {
            if current == "-" { index += 1; return parseUnary().map { -$0 } }
            if current == "+" { index += 1; return parseUnary() }
            guard var value = parsePrimary() else { return nil }
            while current == "%" { index += 1; value /= 100 }
            return value
        }

        private mutating func parsePrimary() -> Double? {
            guard let c = current else { return nil }
            if c == "(" {
                index += 1
                guard let value = parseExpression(), current == ")" else { return nil }
                index += 1
                return value
            }
            if c.isLetter {
                var name = ""
                while let l = current, l.isLetter { name.append(l); index += 1 }
                switch name {
                case "pi": return Double.pi
                case "e": return M_E
                case "sqrt", "racine":
                    guard current == "(" else { return nil }
                    return parsePrimary().map { $0.squareRoot() }
                default: return nil
                }
            }
            var literal = ""
            while let d = current, d.isNumber || d == "." || d == "," {
                literal.append(d == "," ? "." : d)
                index += 1
            }
            return Double(literal)
        }
    }
}
