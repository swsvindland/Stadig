import Foundation

public enum AdherenceKind: String, Codable, Sendable {
    case session, declaredClass, quest, mealLog, rest
}

/// One thing the plan asked for on a day, and whether it happened.
public struct AdherenceItem: Hashable, Codable, Sendable {
    public var day: Day
    public var kind: AdherenceKind
    public var label: String
    /// Nil when unknown: not logging is never treated as failing.
    public var done: Bool?

    public init(day: Day, kind: AdherenceKind, label: String, done: Bool?) {
        self.day = day
        self.kind = kind
        self.label = label
        self.done = done
    }
}

/// Adherence to the plan as a rolling four-week percentage. The target is a band, not 100%:
/// landing in 80–90% earns full credit, going above it earns nothing extra, and one missed day
/// dents the average instead of resetting anything.
public struct DisciplineScore: Hashable, Codable, Sendable {
    public enum Band: String, Codable, Sendable {
        case below, inZone, above

        public var label: String {
            switch self {
            case .below: "Below the zone"
            case .inZone: "In the zone"
            case .above: "In the zone"
            }
        }
    }

    public var window: DayRange
    public var planned: Int
    public var completed: Int
    public var unknown: Int
    public var exemptDays: Int
    /// Nil when nothing was planned.
    public var rate: Double?

    public var band: Band? {
        guard let rate else { return nil }
        if rate < Discipline.band.lowerBound { return .below }
        return rate > Discipline.band.upperBound ? .above : .inZone
    }

    /// Full credit anywhere in or above the band.
    public var credit: Double? { rate.map { min(1, $0 / Discipline.band.lowerBound) } }

    public var note: String {
        guard let rate, let band else { return "Nothing planned yet." }
        let missed = planned - completed
        switch band {
        case .above: return "Steady. There's no extra credit past 90%; rest when the plan says rest."
        case .inZone: return missed == 0 ? "Right on plan." : "In the zone. \(missed) missed in four weeks barely registers."
        case .below:
            return rate < 0.6 ? "Below the zone. The plan gets smaller and easier to win for a while." : "Just under the zone."
        }
    }
}

public enum Discipline {
    public static let band = 0.8...0.9
    public static let windowDays = 28

    public static func window(ending today: Day) -> DayRange { DayRange(today.adding(days: -(windowDays - 1)), today) }

    /// Exempt days (vacation, illness, exempt crunch) are left out entirely. Unknowns don't count.
    public static func score(_ items: [AdherenceItem], exempt: Set<Day>, window: DayRange) -> DisciplineScore {
        let counted = items.filter { window.contains($0.day) && !exempt.contains($0.day) }
        let known = counted.filter { $0.done != nil }
        let done = known.filter { $0.done == true }.count
        return DisciplineScore(window: window, planned: known.count, completed: done, unknown: counted.count - known.count,
                               exemptDays: exempt.filter { window.contains($0) }.count,
                               rate: known.isEmpty ? nil : Double(done) / Double(known.count))
    }

    /// Below the band for a sustained stretch: quests get smaller and easier to win, not louder.
    public static func wantsEasierPlan(_ recent: [DisciplineScore]) -> Bool {
        let last = recent.suffix(2).compactMap(\.rate)
        return last.count == 2 && last.allSatisfy { $0 < band.lowerBound }
    }
}
