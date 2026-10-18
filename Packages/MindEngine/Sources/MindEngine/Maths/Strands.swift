import Foundation

/// Maths as three strands, each with its own level.
public enum MathsStrand: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Mental arithmetic, estimation, percentages, fractions and unit conversions, scored on speed
    /// and accuracy. A short block opens every maths session, whatever the main topic.
    case numeracy
    /// Algebra, functions, trigonometry and calculus: depth and understanding, not the daily focus.
    case classic
    /// Logic, sets, counting, probability and statistics: high real-world value.
    case discrete

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .numeracy: "Numeracy"
        case .classic: "Algebra to calculus"
        case .discrete: "Statistics and logic"
        }
    }

    /// One word, for a line of levels: "numeracy 6, algebra 5, statistics 3".
    public var short: String {
        switch self {
        case .numeracy: "numeracy"
        case .classic: "algebra"
        case .discrete: "statistics"
        }
    }

    public var detail: String {
        switch self {
        case .numeracy: "Mental arithmetic, estimates, percentages and units, quick and accurate."
        case .classic: "Algebra, functions, trigonometry and calculus."
        case .discrete: "Probability, statistics, counting and logic: reading studies and charts, base rates."
        }
    }

    /// The test that measures a strand at a check-in.
    public var test: TestKind {
        switch self {
        case .numeracy: .numeracy
        case .classic: .maths
        case .discrete: .discrete
        }
    }

    /// The strand a maths test measures.
    public init?(test: TestKind) {
        switch test {
        case .numeracy: self = .numeracy
        case .mathsPlacement, .maths: self = .classic
        case .discrete: self = .discrete
        default: return nil
        }
    }
}

extension MindSettings {
    /// The maths strands to work on, most important first: numeracy always leads, and the order
    /// of the rest is the person's.
    public var strands: [MathsStrand] {
        var out: [MathsStrand] = [.numeracy]
        for strand in mathsStrands where !out.contains(strand) { out.append(strand) }
        return out
    }
}
