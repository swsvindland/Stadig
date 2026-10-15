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
    public static var regional: UnitPreference {
        Locale.current.measurementSystem == .metric ? UnitPreference(weight: .kg, length: .cm) : UnitPreference(weight: .lb, length: .inch)
    }
}

public func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T { min(upper, max(lower, value)) }

public extension Array where Element == Double {
    var mean: Double? { isEmpty ? nil : reduce(0, +) / Double(count) }

    /// Least-squares slope against the element index.
    var slope: Double? {
        guard count >= 2 else { return nil }
        let n = Double(count)
        let xs = (0..<count).map(Double.init)
        let mx = xs.reduce(0, +) / n
        let my = reduce(0, +) / n
        var num = 0.0, den = 0.0
        for (x, y) in zip(xs, self) {
            num += (x - mx) * (y - my)
            den += (x - mx) * (x - mx)
        }
        return den == 0 ? 0 : num / den
    }
}

/// Exponentially weighted moving average over a daily series, oldest first.
public func ewma(_ values: [Double], span: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let alpha = 2 / (span + 1)
    var average = values[0]
    for value in values.dropFirst() { average = alpha * value + (1 - alpha) * average }
    return average
}
