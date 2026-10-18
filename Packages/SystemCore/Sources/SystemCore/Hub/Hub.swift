import Foundation

// What travels between the apps and the hub. Apps write sessions and summaries; the hub writes
// recommendations back. Every app still works on its own without any of it.

/// What a recommendation is about.
public enum RecommendationSubject: Hashable, Codable, Sendable {
    case strength(StrengthCategory)
    case muscle(Muscle)
    case physique(PhysiqueRegion)
    case mobility(MobilityTarget)
    case conditioning
    case stat(StatKind)

    public var label: String {
        switch self {
        case .strength(let category): category.label
        case .muscle(let muscle): muscle.label
        case .physique(let region): region.label
        case .mobility(let target): target.label
        case .conditioning: "Conditioning"
        case .stat(let stat): stat.label
        }
    }
}

public enum RecommendationKind: String, Codable, Sendable {
    case prioritise, deprioritise, deloadNow
}

/// "Priority: vertical pull; deprioritise horizontal press." Written by the hub, read by an app
/// when it plans.
public struct Recommendation: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var from: AppID
    public var to: AppID
    public var kind: RecommendationKind
    public var subject: RecommendationSubject?
    public var reason: String
    public var created: Date
    public var expires: Date?

    public init(id: UUID = UUID(), from: AppID = .hub, to: AppID, kind: RecommendationKind, subject: RecommendationSubject?,
                reason: String, created: Date = Date(), expires: Date? = nil) {
        self.id = id
        self.from = from
        self.to = to
        self.kind = kind
        self.subject = subject
        self.reason = reason
        self.created = created
        self.expires = expires
    }

    public func isActive(at date: Date = Date()) -> Bool { expires.map { date < $0 } ?? true }
}

public enum QuestStatus: String, Codable, Sendable { case open, done, skipped }

/// One concrete action. Every insight ends in one, or it isn't shown.
public struct Quest: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var stat: StatKind
    public var source: AppID
    public var minutes: Int?
    public var day: Day
    public var timeOfDay: TimeOfDay?
    public var status: QuestStatus
    /// Higher comes first when the day's quests are capped.
    public var priority: Double

    public init(id: String, title: String, detail: String = "", stat: StatKind, source: AppID, minutes: Int? = nil, day: Day,
                timeOfDay: TimeOfDay? = nil, status: QuestStatus = .open, priority: Double = 0) {
        self.id = id
        self.title = title
        self.detail = detail
        self.stat = stat
        self.source = source
        self.minutes = minutes
        self.day = day
        self.timeOfDay = timeOfDay
        self.status = status
        self.priority = priority
    }
}

public enum Quests {
    /// About three a day, never more.
    public static let dailyCap = 3

    /// The day's quests: open ones, highest priority first, one per stat where possible, capped.
    public static func forDay(_ day: Day, from quests: [Quest], cap: Int = dailyCap) -> [Quest] {
        let open = quests.filter { $0.day == day && $0.status == .open }.sorted { $0.priority > $1.priority }
        var picked: [Quest] = []
        var stats: Set<StatKind> = []
        for quest in open where !stats.contains(quest.stat) && picked.count < cap {
            picked.append(quest)
            stats.insert(quest.stat)
        }
        for quest in open where !picked.contains(quest) && picked.count < cap { picked.append(quest) }
        return picked
    }
}

/// A concrete target: "bench 100 kg by March".
public struct TargetGoal: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var stat: StatKind
    public var title: String
    /// What's measured, e.g. "e1rm:barbell-bench-press" or "category:horizontalPress".
    public var metric: String
    public var target: Double
    public var start: Day
    public var deadline: Day

    public init(id: UUID = UUID(), stat: StatKind, title: String, metric: String, target: Double, start: Day, deadline: Day) {
        self.id = id
        self.stat = stat
        self.title = title
        self.metric = metric
        self.target = target
        self.start = start
        self.deadline = deadline
    }
}

public enum Trajectory: String, Codable, Sendable {
    case ahead, onPace, stalled, regressing, notEnoughData

    public var label: String {
        switch self {
        case .ahead: "Ahead"
        case .onPace: "On pace"
        case .stalled: "Stalled"
        case .regressing: "Regressing"
        case .notEnoughData: "Not enough data yet"
        }
    }
}

public enum Trajectories {
    /// On pace, stalled or regressing, from the recent trend against the straight line to target.
    public static func assess(_ series: [(day: Day, value: Double)], goal: TargetGoal, today: Day) -> Trajectory {
        let points = series.filter { $0.day >= goal.start && $0.day <= today }.sorted { $0.day < $1.day }
        guard points.count >= 3, let first = points.first, let last = points.last, first.day != last.day else { return .notEnoughData }
        let recent = points.suffix(4)
        let span = Double(recent.first!.day.days(until: recent.last!.day))
        let recentRate = span > 0 ? (recent.last!.value - recent.first!.value) / span : 0
        let daysLeft = Double(max(1, today.days(until: goal.deadline)))
        let neededRate = (goal.target - last.value) / daysLeft
        if goal.target > first.value {
            if recentRate < -abs(neededRate) * 0.25 { return .regressing }
            if recentRate <= max(0.0001, neededRate * 0.2) { return last.value >= goal.target ? .ahead : .stalled }
            return recentRate >= neededRate * 1.25 ? .ahead : (recentRate >= neededRate * 0.8 ? .onPace : .stalled)
        } else {
            if recentRate > abs(neededRate) * 0.25 { return .regressing }
            if recentRate >= min(-0.0001, neededRate * 0.2) { return last.value <= goal.target ? .ahead : .stalled }
            return recentRate <= neededRate * 1.25 ? .ahead : (recentRate <= neededRate * 0.8 ? .onPace : .stalled)
        }
    }
}

/// The shared format every app writes: a session happened, here are the metrics.
public enum SessionKind: String, Codable, Sendable {
    case strength, conditioning, mobility, benchmark, activity, study, nutrition
}

public struct SessionSummary: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var app: AppID
    public var kind: SessionKind
    public var activity: ActivityType?
    public var start: Date
    public var minutes: Int
    public var metrics: [String: Double]
    public var fatigue: FatigueLoad
    public var statCredit: [StatKind: Double]
    /// Part of the plan (for Discipline), as opposed to extra.
    public var planned: Bool

    public init(id: UUID, app: AppID, kind: SessionKind, activity: ActivityType? = nil, start: Date, minutes: Int,
                metrics: [String: Double] = [:], fatigue: FatigueLoad = .zero, statCredit: [StatKind: Double] = [:], planned: Bool) {
        self.id = id
        self.app = app
        self.kind = kind
        self.activity = activity
        self.start = start
        self.minutes = minutes
        self.metrics = metrics
        self.fatigue = fatigue
        self.statCredit = statCredit
        self.planned = planned
    }

    public var day: Day { Day(start) }
}

/// A stat as one app sees it. The hub combines them; there's no overall level.
public struct StatReading: Hashable, Codable, Sendable {
    public var stat: StatKind
    /// 0–100 where available.
    public var score: Double?
    public var label: String
    public var trend: Trajectory
    public var updated: Date

    public init(stat: StatKind, score: Double?, label: String, trend: Trajectory, updated: Date = Date()) {
        self.stat = stat
        self.score = score
        self.label = label
        self.trend = trend
        self.updated = updated
    }
}

/// System-wide deloads: one coordinated week across all apps, set by the training calendar.
public struct SystemCalendar: Hashable, Codable, Sendable {
    public var currentBlock: DayRange?
    public var deloads: [DayRange]
    public var checkIns: [Day]
    public var updated: Date
    public var publishedBy: AppID

    public init(currentBlock: DayRange?, deloads: [DayRange], checkIns: [Day], updated: Date = Date(), publishedBy: AppID) {
        self.currentBlock = currentBlock
        self.deloads = deloads
        self.checkIns = checkIns
        self.updated = updated
        self.publishedBy = publishedBy
    }

    public func isDeload(_ day: Day) -> Bool { deloads.contains { $0.contains(day) } }
}

/// What Macro Track publishes, read by Lift Track when present.
public struct NutritionDay: Hashable, Codable, Sendable {
    public var day: Day
    public var logged: Bool
    public var proteinHit: Bool?
    public var caloriesHit: Bool?

    public init(day: Day, logged: Bool, proteinHit: Bool?, caloriesHit: Bool?) {
        self.day = day
        self.logged = logged
        self.proteinHit = proteinHit
        self.caloriesHit = caloriesHit
    }
}

public struct NutritionSummary: Hashable, Codable, Sendable {
    public static let schemaVersion = 1

    public var phase: NutritionPhase?
    public var maintenanceKcal: Double?
    public var days: [NutritionDay]
    public var updated: Date

    public init(phase: NutritionPhase?, maintenanceKcal: Double?, days: [NutritionDay], updated: Date = Date()) {
        self.phase = phase
        self.maintenanceKcal = maintenanceKcal
        self.days = days
        self.updated = updated
    }

    /// Protein-target days among logged days in a window. Days not logged are unknown, not misses.
    public func proteinHits(in range: DayRange) -> (hit: Int, known: Int) {
        let known = days.filter { range.contains($0.day) && $0.logged && $0.proteinHit != nil }
        return (known.filter { $0.proteinHit == true }.count, known.count)
    }
}

/// What each app publishes to the shared container for the others and the hub: small, recent and
/// self-describing. The app's own database stays private.
public struct AppSummary: Hashable, Codable, Sendable {
    public static let schemaVersion = 1

    public var app: AppID
    public var updated: Date
    public var stats: [StatReading]
    /// The last few weeks of sessions, in the shared format.
    public var sessions: [SessionSummary]
    /// Work that didn't fit, offered to the hub for free time blocks.
    public var quests: [Quest]
    public var strength: StrengthProfile?
    public var fatigue: FatigueStatus?
    public var discipline: DisciplineScore?
    public var measurements: BodyMeasurements?
    /// Whether fat loss or building would do more for proportions (Lift Track), for the phase planner.
    public var physique: PhysiqueDirection?
    public var mobility: [MobilityResult]
    public var benchmarks: [BenchmarkResult]
    public var stalls: [StallReport]
    /// The nutrition phase the app planned around, and where it came from.
    public var phaseUsed: NutritionPhase?
    /// Daily steps and the step aim (Lift Track).
    public var steps: StepSummary?

    public init(app: AppID, updated: Date = Date(), stats: [StatReading] = [], sessions: [SessionSummary] = [], quests: [Quest] = [],
                strength: StrengthProfile? = nil, fatigue: FatigueStatus? = nil, discipline: DisciplineScore? = nil,
                measurements: BodyMeasurements? = nil, physique: PhysiqueDirection? = nil, mobility: [MobilityResult] = [],
                benchmarks: [BenchmarkResult] = [], stalls: [StallReport] = [], phaseUsed: NutritionPhase? = nil, steps: StepSummary? = nil) {
        self.app = app
        self.updated = updated
        self.stats = stats
        self.sessions = sessions
        self.quests = quests
        self.strength = strength
        self.fatigue = fatigue
        self.discipline = discipline
        self.measurements = measurements
        self.physique = physique
        self.mobility = mobility
        self.benchmarks = benchmarks
        self.stalls = stalls
        self.phaseUsed = phaseUsed
        self.steps = steps
    }
}
