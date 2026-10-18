import Foundation

/// An exact fraction, always in lowest terms with a positive denominator. Maths answers are exact
/// wherever they can be, so 0.333 is never marked right for 1/3 by accident.
public struct Rational: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let numerator: Int
    public let denominator: Int

    public init(_ numerator: Int, _ denominator: Int = 1) {
        precondition(denominator != 0, "zero denominator")
        let g = Swift.max(1, gcd(abs(numerator), abs(denominator)))
        let sign = denominator < 0 ? -1 : 1
        self.numerator = sign * numerator / g
        self.denominator = abs(denominator) / g
    }

    /// "3/4", "-2", "0.75", "1 1/2", "−5" (a typographic minus), "2.5". Nil for anything else,
    /// including numbers too big to work with: this reads whatever is typed or pasted.
    public init?(parsing raw: String) {
        var text = raw.replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "⁄", with: "/")
            .trimmingCharacters(in: .whitespaces)
        // Thousands separators: "8,400" and "12,000.5", never a decimal comma.
        if text.wholeMatch(of: /-?\d{1,3}(,\d{3})+(\.\d+)?/) != nil { text = text.replacingOccurrences(of: ",", with: "") }
        guard !text.isEmpty else { return nil }
        let parts = text.split(separator: " ")
        if parts.count == 2, let whole = Self.integer(parts[0]), let fraction = Rational(parsing: String(parts[1])), fraction.numerator >= 0 {
            // Composed with checked arithmetic: "1000000000 1/10000000000" would overflow.
            let (scaled, overflowScaling) = abs(whole).multipliedReportingOverflow(by: fraction.denominator)
            let (numerator, overflowAdding) = scaled.addingReportingOverflow(fraction.numerator)
            guard !overflowScaling, !overflowAdding else { return nil }
            self.init(whole < 0 ? -numerator : numerator, fraction.denominator)
            return
        }
        if let slash = text.firstIndex(of: "/") {
            guard let n = Self.integer(text[..<slash].trimmingCharacters(in: .whitespaces)),
                  let d = Self.integer(text[text.index(after: slash)...].trimmingCharacters(in: .whitespaces)), d != 0 else { return nil }
            self.init(n, d)
            return
        }
        if let dot = text.firstIndex(of: ".") {
            let decimals = text[text.index(after: dot)...]
            guard decimals.count <= 9, decimals.allSatisfy(\.isNumber), let whole = Self.integer(text.replacingOccurrences(of: ".", with: "")) else {
                return nil
            }
            var scale = 1
            for _ in 0..<decimals.count { scale *= 10 }
            self.init(whole, scale)
            return
        }
        guard let n = Self.integer(text) else { return nil }
        self.init(n)
    }

    /// A whole number that fits. `Int.min` is left out: it has no positive counterpart, so
    /// lowest terms would trap on it.
    private static func integer<S: StringProtocol>(_ text: S) -> Int? {
        guard let value = Int(text), value != .min else { return nil }
        return value
    }

    public var double: Double { Double(numerator) / Double(denominator) }

    /// Written as a decimal when it ends within six places: 3/4 is "0.75", -5/2 is "-2.5". Nil
    /// for 1/3.
    public var decimal: String? {
        var scaled = self
        var places = 0
        while !scaled.isInteger && places < 6 {
            scaled = scaled * 10
            places += 1
        }
        guard scaled.isInteger else { return nil }
        var digits = String(abs(scaled.numerator))
        guard places > 0 else { return (scaled.numerator < 0 ? "-" : "") + digits }
        while digits.count <= places { digits = "0" + digits }
        let split = digits.index(digits.endIndex, offsetBy: -places)
        return (scaled.numerator < 0 ? "-" : "") + digits[..<split] + "." + digits[split...]
    }
    public var isInteger: Bool { denominator == 1 }

    /// "3/4", "-2". `tex` gives "\frac{3}{4}".
    public var description: String { isInteger ? "\(numerator)" : "\(numerator)/\(denominator)" }

    public var tex: String {
        if isInteger { return "\(numerator)" }
        return numerator < 0 ? "-\\frac{\(-numerator)}{\(denominator)}" : "\\frac{\(numerator)}{\(denominator)}"
    }

    public static func + (a: Rational, b: Rational) -> Rational {
        Rational(a.numerator * b.denominator + b.numerator * a.denominator, a.denominator * b.denominator)
    }
    public static func - (a: Rational, b: Rational) -> Rational { a + Rational(-b.numerator, b.denominator) }
    public static func * (a: Rational, b: Rational) -> Rational {
        Rational(a.numerator * b.numerator, a.denominator * b.denominator)
    }
    public static func / (a: Rational, b: Rational) -> Rational {
        Rational(a.numerator * b.denominator, a.denominator * b.numerator)
    }
    public static prefix func - (a: Rational) -> Rational { Rational(-a.numerator, a.denominator) }
    public static func < (a: Rational, b: Rational) -> Bool { a.numerator * b.denominator < b.numerator * a.denominator }

    public func power(_ n: Int) -> Rational {
        var result = Rational(1)
        for _ in 0..<abs(n) { result = result * self }
        return n < 0 ? Rational(1) / result : result
    }
}

extension Rational: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self.init(value) }
}

func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
func lcm(_ a: Int, _ b: Int) -> Int { a / gcd(a, b) * b }
