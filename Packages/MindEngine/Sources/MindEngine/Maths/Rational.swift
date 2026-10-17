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

    /// "3/4", "-2", "0.75", "1 1/2", "−5" (a typographic minus), "2.5". Nil for anything else.
    public init?(parsing raw: String) {
        let text = raw.replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "⁄", with: "/")
            .trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let parts = text.split(separator: " ")
        if parts.count == 2, let whole = Int(parts[0]), let fraction = Rational(parsing: String(parts[1])), fraction.numerator >= 0 {
            self = whole < 0 ? Rational(whole) - fraction : Rational(whole) + fraction
            return
        }
        if let slash = text.firstIndex(of: "/") {
            guard let n = Int(text[..<slash].trimmingCharacters(in: .whitespaces)),
                  let d = Int(text[text.index(after: slash)...].trimmingCharacters(in: .whitespaces)), d != 0 else { return nil }
            self.init(n, d)
            return
        }
        if let dot = text.firstIndex(of: ".") {
            let decimals = text[text.index(after: dot)...]
            guard decimals.count <= 9, decimals.allSatisfy(\.isNumber), let whole = Int(text.replacingOccurrences(of: ".", with: "")) else {
                return nil
            }
            var scale = 1
            for _ in 0..<decimals.count { scale *= 10 }
            self.init(whole, scale)
            return
        }
        guard let n = Int(text) else { return nil }
        self.init(n)
    }

    public var double: Double { Double(numerator) / Double(denominator) }
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
