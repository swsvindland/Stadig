import Foundation

/// Bodyweight-relative strength standards, Symmetric Strength style: each lift category is scored
/// on the same scale, so categories can be compared and imbalances found.
public enum StrengthStandards {
    /// Score anchors: beginner 20, novice 40, intermediate 60, advanced 80, elite 100.
    public static let anchors: [Double] = [20, 40, 60, 80, 100]

    public static func level(for score: Double) -> String {
        switch score {
        case ..<20: "Untrained"
        case ..<40: "Beginner"
        case ..<60: "Novice"
        case ..<80: "Intermediate"
        case ..<100: "Advanced"
        default: "Elite"
        }
    }

    /// Reference bodyweight the ratios are written for.
    static func referenceBodyweight(_ sex: BiologicalSex) -> Double {
        switch sex {
        case .male: 80
        case .female: 62
        case .unspecified: 72
        }
    }

    /// One-rep max as a multiple of bodyweight at each anchor, at the reference bodyweight.
    static func ratios(_ category: StrengthCategory, _ sex: BiologicalSex) -> [Double] {
        switch sex {
        case .male: maleRatios(category)
        case .female: femaleRatios(category)
        case .unspecified: zip(maleRatios(category), femaleRatios(category)).map { ($0 + $1) / 2 }
        }
    }

    private static func maleRatios(_ category: StrengthCategory) -> [Double] {
        switch category {
        case .squat: [0.8, 1.15, 1.55, 2.05, 2.6]
        case .floorPull: [1.0, 1.45, 1.9, 2.45, 3.05]
        case .horizontalPress: [0.65, 0.9, 1.25, 1.65, 2.1]
        case .inclinePress: [0.55, 0.75, 1.03, 1.37, 1.75]
        case .verticalPress: [0.4, 0.58, 0.8, 1.05, 1.35]
        // Pull-ups count the whole body plus any added load.
        case .verticalPull: [0.95, 1.12, 1.35, 1.6, 1.88]
        case .horizontalPull: [0.5, 0.72, 1.0, 1.3, 1.62]
        }
    }

    private static func femaleRatios(_ category: StrengthCategory) -> [Double] {
        switch category {
        case .squat: [0.55, 0.85, 1.15, 1.55, 2.0]
        case .floorPull: [0.7, 1.05, 1.4, 1.85, 2.35]
        case .horizontalPress: [0.35, 0.52, 0.75, 1.0, 1.3]
        case .inclinePress: [0.3, 0.44, 0.63, 0.85, 1.1]
        case .verticalPress: [0.25, 0.36, 0.5, 0.7, 0.9]
        case .verticalPull: [0.75, 0.95, 1.15, 1.37, 1.6]
        case .horizontalPull: [0.35, 0.5, 0.7, 0.95, 1.2]
        }
    }

    /// The score for a reference-lift 1RM at a bodyweight. Strength grows with about the
    /// two-thirds power of bodyweight, so heavier lifters need a smaller multiple for the same score.
    public static func score(_ category: StrengthCategory, oneRepMaxKg: Double, bodyweightKg: Double, sex: BiologicalSex) -> Double {
        guard oneRepMaxKg > 0, bodyweightKg > 0 else { return 0 }
        let reference = referenceBodyweight(sex)
        let adjusted = oneRepMaxKg / bodyweightKg * pow(bodyweightKg / reference, 1.0 / 3.0)
        let table = ratios(category, sex)
        if adjusted <= table[0] { return anchors[0] * adjusted / table[0] }
        for i in 1..<table.count where adjusted <= table[i] {
            let t = (adjusted - table[i - 1]) / (table[i] - table[i - 1])
            return anchors[i - 1] + t * (anchors[i] - anchors[i - 1])
        }
        let slope = (anchors[4] - anchors[3]) / (table[4] - table[3])
        return anchors[4] + (adjusted - table[4]) * slope
    }

    /// The reference-lift 1RM that scores a given number, for goals like "reach intermediate".
    public static func oneRepMax(for score: Double, _ category: StrengthCategory, bodyweightKg: Double, sex: BiologicalSex) -> Double {
        var lo = 0.0
        var hi = bodyweightKg * 5
        for _ in 0..<50 {
            let mid = (lo + hi) / 2
            if self.score(category, oneRepMaxKg: mid, bodyweightKg: bodyweightKg, sex: sex) < score { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }
}

public struct CategoryScore: Hashable, Codable, Sendable, Identifiable {
    public var category: StrengthCategory
    /// The reference lift's estimated 1RM, kg.
    public var oneRepMaxKg: Double
    public var score: Double
    /// The exercise the estimate came from.
    public var exerciseID: String
    public var day: Day

    public var id: StrengthCategory { category }
    public var level: String { StrengthStandards.level(for: score) }

    public init(category: StrengthCategory, oneRepMaxKg: Double, score: Double, exerciseID: String, day: Day) {
        self.category = category
        self.oneRepMaxKg = oneRepMaxKg
        self.score = score
        self.exerciseID = exerciseID
        self.day = day
    }
}

/// A priority for the next mesocycle, with its reason. The person can switch auto-prioritisation off.
public struct TrainingPriority: Hashable, Codable, Sendable, Identifiable {
    public enum Target: Hashable, Codable, Sendable {
        case category(StrengthCategory)
        case region(StrengthCategory.Region)
        case physique(PhysiqueRegion)
        case mobility(MobilityTarget)
        case conditioning
    }

    public var target: Target
    /// Positive to bring up, negative to hold back.
    public var emphasis: Double
    public var reason: String
    public var source: Source

    public enum Source: String, Codable, Sendable { case strength, physique, agility, endurance, hub, person }

    public var id: String { "\(target)-\(source.rawValue)" }

    public init(target: Target, emphasis: Double, reason: String, source: Source) {
        self.target = target
        self.emphasis = emphasis
        self.reason = reason
        self.source = source
    }

    public var label: String {
        switch target {
        case .category(let c): c.label
        case .region(let r): r.label
        case .physique(let p): p.label
        case .mobility(let m): "\(m.label) mobility"
        case .conditioning: "Conditioning"
        }
    }
}

public struct StrengthProfile: Hashable, Codable, Sendable {
    public var categories: [CategoryScore]
    public var bodyweightKg: Double
    public var sex: BiologicalSex
    /// The overall strength score: the mean of the categories with data. Session count never moves it.
    public var overall: Double?

    public init(categories: [CategoryScore], bodyweightKg: Double, sex: BiologicalSex) {
        self.categories = categories.sorted {
            StrengthCategory.allCases.firstIndex(of: $0.category)! < StrengthCategory.allCases.firstIndex(of: $1.category)!
        }
        self.bodyweightKg = bodyweightKg
        self.sex = sex
        overall = categories.isEmpty ? nil : categories.map(\.score).reduce(0, +) / Double(categories.count)
    }

    public subscript(_ category: StrengthCategory) -> CategoryScore? { categories.first { $0.category == category } }

    public func regionScore(_ region: StrengthCategory.Region) -> Double? {
        let scores = categories.filter { $0.category.region == region }.map(\.score)
        return scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
    }

    /// The weakest lift relative to the rest, when it lags by a meaningful margin.
    public var weakest: CategoryScore? {
        guard let overall, categories.count >= 3, let low = categories.min(by: { $0.score < $1.score }),
            overall - low.score >= 7
        else { return nil }
        return low
    }

    /// Priorities from imbalances: the weakest lift, and a region far behind the others.
    public var priorities: [TrainingPriority] {
        var list: [TrainingPriority] = []
        let lower = regionScore(.lower)
        let upper = [regionScore(.upperPush), regionScore(.upperPull)].compactMap { $0 }.mean
        if let lower, let upper {
            if lower - upper >= 12 {
                list.append(
                    TrainingPriority(
                        target: .region(.upperPush), emphasis: 1,
                        reason: "Legs are well ahead of upper body, so upper body comes first this block.", source: .strength))
                list.append(
                    TrainingPriority(
                        target: .region(.upperPull), emphasis: 1,
                        reason: "Legs are well ahead of upper body, so upper body comes first this block.", source: .strength))
                list.append(
                    TrainingPriority(
                        target: .region(.lower), emphasis: -0.5,
                        reason: "Legs hold at maintenance volume while upper body catches up.", source: .strength))
            } else if upper - lower >= 12 {
                list.append(
                    TrainingPriority(
                        target: .region(.lower), emphasis: 1,
                        reason: "Upper body is well ahead of legs, so legs come first this block.", source: .strength))
            }
        }
        if let push = regionScore(.upperPush), let pull = regionScore(.upperPull) {
            if push - pull >= 10 {
                list.append(
                    TrainingPriority(
                        target: .region(.upperPull), emphasis: 0.7,
                        reason: "Pressing is ahead of pulling; more pulling evens it out and is kinder to shoulders.", source: .strength))
            } else if pull - push >= 10 {
                list.append(
                    TrainingPriority(
                        target: .region(.upperPush), emphasis: 0.7,
                        reason: "Pulling is ahead of pressing.", source: .strength))
            }
        }
        if let weakest,
            !list.contains(where: { if case .region(let r) = $0.target { r == weakest.category.region && $0.emphasis > 0 } else { false } })
        {
            list.append(
                TrainingPriority(
                    target: .category(weakest.category), emphasis: 0.8,
                    reason: "\(weakest.category.label) is the weakest lift relative to the rest.", source: .strength))
        }
        // Legs ahead and pressing ahead of pulling can both ask for pulling: one row, both reasons.
        return list.mergedByID()
    }
}

extension Array where Element == TrainingPriority {
    /// One priority per id (target and source), so lists keyed by id never repeat one. Emphasis adds
    /// up, as the generator would add it anyway, and the reasons are joined.
    public func mergedByID() -> [TrainingPriority] {
        var merged: [TrainingPriority] = []
        for priority in self {
            if let i = merged.firstIndex(where: { $0.id == priority.id }) {
                merged[i].emphasis += priority.emphasis
                if !merged[i].reason.contains(priority.reason) { merged[i].reason += " " + priority.reason }
            } else {
                merged.append(priority)
            }
        }
        return merged
    }
}

/// Estimated 1RMs from logged sets, weighted by how far the person's ratings can be believed.
public enum StrengthEstimator {
    /// Sets heavier than this many reps say little about a 1RM.
    public static let maxUsefulReps = 15

    /// The estimate one set supports. Failure (a rep-out or a miss) is objective. A rated set
    /// sits between the objective floor (as if no reps were left) and the rating's claim, by trust.
    /// Deload sets are kept far from failure on purpose, so they say little and are skipped.
    public static func estimate(_ set: LoggedSet, basis: LoadBasis, trust: TrustState) -> Double? {
        guard set.kind.countsAsWork, set.kind != .deload, set.reps > 0, set.reps <= maxUsefulReps else { return nil }
        let load = OneRepMax.effectiveLoad(set.loadKg, basis: basis, bodyweightKg: set.bodyweightKg)
        guard load > 0 else { return nil }
        let floor = OneRepMax.epley(load, reps: set.reps)
        if set.reachedFailure { return floor }
        guard let rating = set.rating else { return floor }
        let claimed = OneRepMax.epley(load, reps: set.reps, rir: trust.reserve(for: rating))
        return floor + trust.score * (claimed - floor)
    }

    /// Sets this far apart belong to different sessions; nothing rests three hours between sets.
    public static let sessionGap: TimeInterval = 3 * 3600

    /// Sets grouped into the sessions they were done in, oldest first, each in the order it was done.
    /// Grouped by time rather than by calendar day, so a workout that runs past midnight stays one
    /// session and a change of time zone doesn't regroup old ones.
    public static func sessions(_ sets: [LoggedSet]) -> [[LoggedSet]] {
        let ordered = sets.enumerated().sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }.map(\.element)
        var sessions: [[LoggedSet]] = []
        for set in ordered {
            if let previous = sessions.last?.last, set.date.timeIntervalSince(previous.date) <= sessionGap {
                sessions[sessions.count - 1].append(set)
            } else {
                sessions.append([set])
            }
        }
        return sessions
    }

    /// Per-session best estimates for one exercise, oldest first. A session counts on the day it
    /// started; two on one day count as that day's best.
    public static func sessionBests(_ sets: [LoggedSet], basis: LoadBasis, trust: TrustState) -> [(day: Day, e1rm: Double)] {
        var byDay: [Day: Double] = [:]
        for session in sessions(sets) {
            guard let first = session.first, let best = session.compactMap({ estimate($0, basis: basis, trust: trust) }).max() else { continue }
            let day = Day(first.date)
            byDay[day] = max(byDay[day] ?? 0, best)
        }
        return byDay.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// The current estimate: the best of the last few sessions, so one off day doesn't erase it.
    public static func current(_ sets: [LoggedSet], basis: LoadBasis, trust: TrustState, sessions: Int = 3) -> Double? {
        sessionBests(sets, basis: basis, trust: trust).suffix(sessions).map(\.e1rm).max()
    }

    /// Category scores from every mapped exercise's recent history. Only free-weight variants
    /// with known ratios are mapped; machines never are.
    public static func profile(
        history: [String: [LoggedSet]], exercises: [String: any ExerciseTraits], trust: TrustState,
        bodyweightKg: Double, sex: BiologicalSex, today: Day, windowDays: Int = 56
    ) -> StrengthProfile {
        var best: [StrengthCategory: CategoryScore] = [:]
        let cutoff = today.adding(days: -windowDays)
        for (id, sets) in history {
            guard let exercise = exercises[id], let mapping = exercise.strength else { continue }
            let recent = sets.filter { Day($0.date) >= cutoff }
            for point in sessionBests(recent, basis: exercise.loadBasis, trust: trust) {
                let reference = point.e1rm * mapping.factor
                let score = StrengthStandards.score(mapping.category, oneRepMaxKg: reference, bodyweightKg: bodyweightKg, sex: sex)
                if score > best[mapping.category]?.score ?? -1 {
                    best[mapping.category] = CategoryScore(
                        category: mapping.category, oneRepMaxKg: reference, score: score,
                        exerciseID: id, day: point.day)
                }
            }
        }
        return StrengthProfile(categories: Array(best.values), bodyweightKg: bodyweightKg, sex: sex)
    }
}
