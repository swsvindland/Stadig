import Foundation

/// Every stored mass is in kilograms and every length in centimetres. Units are a display choice.
public enum WeightUnit: String, Codable, Sendable, CaseIterable, Identifiable {
    case kg, lb

    public var id: String { rawValue }
    public static let kilogramsPerPound = 0.45359237

    public func fromKilograms(_ kg: Double) -> Double { self == .kg ? kg : kg / Self.kilogramsPerPound }
    public func toKilograms(_ value: Double) -> Double { self == .kg ? value : value * Self.kilogramsPerPound }

    public var symbol: String { rawValue }
}

public enum LengthUnit: String, Codable, Sendable, CaseIterable, Identifiable {
    case cm, inch

    public var id: String { rawValue }
    public static let centimetresPerInch = 2.54

    public func fromCentimetres(_ cm: Double) -> Double { self == .cm ? cm : cm / Self.centimetresPerInch }
    public func toCentimetres(_ value: Double) -> Double { self == .cm ? value : value * Self.centimetresPerInch }

    public var symbol: String { self == .cm ? "cm" : "in" }
}

public struct UnitPreference: Codable, Hashable, Sendable {
    public var weight: WeightUnit
    public var length: LengthUnit

    public init(weight: WeightUnit = .kg, length: LengthUnit = .cm) {
        self.weight = weight
        self.length = length
    }

    /// The person's region's habit.
    public static var regional: UnitPreference { regional(for: .current) }

    /// Only the US system is pounds and inches. The UK's is its own (`.uk`), and British gyms load in
    /// kilograms.
    public static func regional(for locale: Locale) -> UnitPreference {
        locale.measurementSystem == .us ? UnitPreference(weight: .lb, length: .inch) : UnitPreference(weight: .kg, length: .cm)
    }
}

public func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T { min(upper, max(lower, value)) }

extension Array where Element == Double {
    public var mean: Double? { isEmpty ? nil : reduce(0, +) / Double(count) }

    /// Least-squares slope against the element index.
    public var slope: Double? {
        guard count >= 2 else { return nil }
        return leastSquaresSlope(x: (0..<count).map(Double.init), y: self) ?? 0
    }
}

/// The least-squares slope of y against x; nil with fewer than two points, mismatched lengths, or
/// when every x is the same.
public func leastSquaresSlope(x: [Double], y: [Double]) -> Double? {
    guard x.count == y.count, x.count >= 2 else { return nil }
    let n = Double(x.count)
    let mx = x.reduce(0, +) / n
    let my = y.reduce(0, +) / n
    var num = 0.0
    var den = 0.0
    for (xi, yi) in zip(x, y) {
        num += (xi - mx) * (yi - my)
        den += (xi - mx) * (xi - mx)
    }
    return den == 0 ? nil : num / den
}

/// Exponentially weighted moving average over a daily series, oldest first.
public func ewma(_ values: [Double], span: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let alpha = 2 / (span + 1)
    var average = values[0]
    for value in values.dropFirst() { average = alpha * value + (1 - alpha) * average }
    return average
}
