import ExerciseLibrary
import Foundation
import SystemCore

/// The person's own history with one exercise, for the Library: how often, when last, the best
/// sets, and the estimated one-rep max over time.
public struct ExerciseRecord: Sendable {
    /// A session's best estimate.
    public struct Point: Hashable, Sendable {
        public var day: Day
        public var e1rm: Double
    }

    /// A set worth showing, with its estimate (nil for work an estimate means nothing for: timed or
    /// counted, a warm-up).
    public struct BestSet: Hashable, Sendable {
        public var set: LoggedSet
        public var e1rm: Double?
    }

    /// Sessions it was done in (sets less than three hours apart are one session).
    public var sessions: Int
    public var lastDone: Day?
    /// The best work set of each of its best sessions, best first, at most three.
    public var bestSets: [BestSet]
    /// Each session's best estimate, oldest first.
    public var trend: [Point]
    /// The current estimate: the best of the last few sessions, so one off day doesn't erase it.
    public var current: Double?
    /// How far the current estimate is from the first, as a fraction; nil without two sessions.
    public var change: Double?

    public var isEmpty: Bool { sessions == 0 }

    /// Built from every set logged on it (`LiftAnalysis.history[exercise.id]`), read by its own load
    /// basis so less help on an assisted lift counts as progress.
    public static func of(_ sets: [LoggedSet], exercise: Exercise, trust: TrustState) -> ExerciseRecord {
        let own = sets.filter { $0.exerciseID == exercise.id }.sorted { $0.date < $1.date }
        let grouped = StrengthEstimator.sessions(own)
        let work = own.filter { $0.kind.countsAsWork }
        let trend = StrengthEstimator.sessionBests(work, basis: exercise.loadBasis, trust: trust).map { Point(day: $0.day, e1rm: $0.e1rm) }
        // The best set of each session, so three sets from one good day don't hide every other.
        let bests = grouped.compactMap { session -> BestSet? in
            let candidates = session.filter { $0.kind.countsAsWork }
            let scored = candidates.map { BestSet(set: $0, e1rm: StrengthEstimator.estimate($0, basis: exercise.loadBasis, trust: trust)) }
            return scored.max(by: Self.worse)
        }
        let current = StrengthEstimator.current(work, basis: exercise.loadBasis, trust: trust)
        let change: Double? =
            if trend.count >= 2, let first = trend.first?.e1rm, first > 0, let current { current / first - 1 } else { nil }
        return ExerciseRecord(
            sessions: grouped.count, lastDone: own.last.map { Day($0.date) }, bestSets: Array(bests.sorted { Self.worse($1, $0) }.prefix(3)),
            trend: trend, current: current, change: change)
    }

    /// Ordered by estimate; without one (timed and counted work), by reps, then load.
    private static func worse(_ a: BestSet, _ b: BestSet) -> Bool {
        switch (a.e1rm, b.e1rm) {
        case (let x?, let y?) where x != y: return x < y
        case (nil, _?): return true
        case (_?, nil): return false
        default:
            if a.set.reps != b.set.reps { return a.set.reps < b.set.reps }
            if a.set.loadKg != b.set.loadKg { return a.set.loadKg < b.set.loadKg }
            return a.set.date > b.set.date
        }
    }
}

extension ExerciseRecord {
    /// How the estimate has moved along its line: the current estimate against the first session's,
    /// over the days from the first session to the last.
    public struct Movement: Hashable, Sendable {
        public var kg: Double
        public var days: Int
    }

    /// Nil until two sessions have an estimate.
    public var movement: Movement? {
        guard trend.count >= 2, let first = trend.first, let last = trend.last, let current else { return nil }
        return Movement(kg: current - first.e1rm, days: first.day.days(until: last.day))
    }

    /// The line in one plain sentence: "Up 4 kg in 6 weeks", "Down 2.5 kg in 3 weeks", "Level over 5
    /// weeks", or, with one session, that the line starts with the next. Nil without any estimate
    /// (never done, or work an estimate means nothing for). Changes are rounded to what a gym loads
    /// (half a kilogram, a pound), so a change smaller than that reads as level.
    public func trendSentence(unit: WeightUnit) -> String? {
        guard !trend.isEmpty else { return nil }
        guard let movement else { return "One session so far: the line starts with the next." }
        let step = unit == .kg ? 0.5 : 1
        let change = (unit.fromKilograms(abs(movement.kg)) / step).rounded() * step
        let span = Self.span(days: movement.days)
        guard change > 0 else { return "Level over \(span)" }
        let amount = change.formatted(.number.precision(.fractionLength(0...1)))
        return "\(movement.kg > 0 ? "Up" : "Down") \(amount) \(unit.symbol) in \(span)"
    }

    /// "5 days", "6 weeks", "4 months", "2 years": weeks from a fortnight, months from three of them.
    static func span(days: Int) -> String {
        func count(_ n: Int, _ unit: String) -> String { "\(n) \(unit)\(n == 1 ? "" : "s")" }
        switch days {
        case ..<14: return count(max(1, days), "day")
        case ..<91: return count(Int((Double(days) / 7).rounded()), "week")
        case ..<730: return count(Int((Double(days) / 30.44).rounded()), "month")
        default: return count(Int((Double(days) / 365.25).rounded()), "year")
        }
    }

    /// The current estimate as a strength score (the standards' 0–100, where 20 is beginner and 100
    /// elite), for a free-weight lift the standards know; nil for anything else or with no estimate.
    /// It's this exercise's own score, which can be below its category's on Progress when another
    /// variant scores higher.
    public func score(for exercise: Exercise, bodyweightKg: Double, sex: BiologicalSex) -> Double? {
        guard let mapping = exercise.strength, let current else { return nil }
        return StrengthStandards.score(mapping.category, oneRepMaxKg: current * mapping.factor, bodyweightKg: bodyweightKg, sex: sex)
    }
}
