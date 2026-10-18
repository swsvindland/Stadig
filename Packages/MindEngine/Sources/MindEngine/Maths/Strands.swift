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

    public var detail: String {
        switch self {
        case .numeracy: "Mental arithmetic, estimates, percentages and units, quick and accurate."
        case .classic: "Algebra, functions, trigonometry and calculus."
        case .discrete: "Probability, statistics, counting and logic: reading studies and charts, base rates."
        }
    }
}

extension MathTopic {
    /// The strand a topic belongs to. The maths rework gives every topic its strand explicitly;
    /// until then, the data and probability topics are discrete and the rest classic.
    public var strand: MathsStrand {
        switch id {
        case "averages", "probability", "counting", "expected-value": .discrete
        default: .classic
        }
    }
}
