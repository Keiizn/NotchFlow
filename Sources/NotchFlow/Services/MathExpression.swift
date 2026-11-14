import Foundation

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
