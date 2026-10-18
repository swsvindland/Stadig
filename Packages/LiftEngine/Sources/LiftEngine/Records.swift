import ExerciseLibrary
import Foundation
import SystemCore

// Lift Track's own records. Each is stored whole (one payload per record) and synced; derived
// things like trust, scores and fatigue are recomputed from them rather than stored, so two
// devices can never disagree about them.

/// Lift Track's settings. Shared setup answers live in ``SharedProfile``; these are the app's own.
public struct LiftSettings: Codable, Hashable, Sendable, Identifiable {
    /// One settings record per person, under one id on every device, so two devices that each set
    /// up the app converge on the newest rather than keeping two. Settings saved before it have an
    /// id of their own until they're saved under this one.
    public static let singletonID = UUID(uuidString: "00000000-0000-0000-0000-00000000F17E")!

    public var id: UUID
    public var gymID: UUID?
    /// The one-tap phase answer, used only when Macro Track hasn't published a phase.
    public var selfReportedPhase: SelfReportedPhase?
    /// When that answer last changed: the step aim's usual count is from the weeks before.
    public var selfReportedPhaseSince: Day?
    /// Strength and physique imbalances set the next block's priorities. Can be switched off.
    public var autoPrioritise: Bool
    /// Areas the person wants brought up, whatever the analysis says: extra volume every block.
    public var focus: Set<PhysiqueRegion>
    /// More than two and a focus stops meaning anything.
    public static let focusLimit = 2
    /// Which proportions the program works toward; nil follows "Standards for".
    public var proportionTargets: ProportionTargets?
    /// Rest can end early on a recovered heart rate (Watch) for accessories.
    public var heartRateGuidedRest: Bool
    public var includeConditioning: Bool
    public var includeCooldown: Bool
    public var benchmark: EnduranceBenchmark
    /// Exercises the person never wants programmed.
    public var avoid: Set<String>
    public var saveToHealth: Bool
    public var onboardedAt: Date?
    public var assessmentStart: Day?
    public var updatedAt: Date

    public init(
        id: UUID = UUID(), gymID: UUID? = nil, selfReportedPhase: SelfReportedPhase? = nil, autoPrioritise: Bool = true,
        focus: Set<PhysiqueRegion> = [], proportionTargets: ProportionTargets? = nil, heartRateGuidedRest: Bool = true,
        includeConditioning: Bool = true, includeCooldown: Bool = false, benchmark: EnduranceBenchmark = .stairs10min,
        avoid: Set<String> = [], saveToHealth: Bool = true, onboardedAt: Date? = nil, assessmentStart: Day? = nil,
        selfReportedPhaseSince: Day? = nil, updatedAt: Date = Date()
    ) {
        self.id = id
        self.gymID = gymID
        self.selfReportedPhase = selfReportedPhase
        self.selfReportedPhaseSince = selfReportedPhaseSince
        self.autoPrioritise = autoPrioritise
        self.focus = focus
        self.proportionTargets = proportionTargets
        self.heartRateGuidedRest = heartRateGuidedRest
        self.includeConditioning = includeConditioning
        self.includeCooldown = includeCooldown
        self.benchmark = benchmark
        self.avoid = avoid
        self.saveToHealth = saveToHealth
        self.onboardedAt = onboardedAt
        self.assessmentStart = assessmentStart
        self.updatedAt = updatedAt
    }
}

// MARK: - Programs

public enum SessionBlockKind: String, Codable, Sendable, CaseIterable, Comparable {
    case warmup, limiter, main, accessory, conditioning, cooldown
    /// Sauna or steam room after training, where the gym has one: optional, outside the session's time.
    case recovery

    public var label: String {
        switch self {
        case .warmup: "Warm-up"
        case .limiter: "Mobility"
        case .main: "Main lifts"
        case .accessory: "Accessories"
        case .conditioning: "Conditioning"
        case .cooldown: "Cool-down"
        case .recovery: "Recovery"
        }
    }

    public var symbol: String {
        switch self {
        case .warmup: "flame"
        case .limiter: "figure.flexibility"
        case .main: "figure.strengthtraining.traditional"
        case .accessory: "dumbbell"
        case .conditioning: "heart.circle"
        case .cooldown: "wind"
        case .recovery: "heat.waves"
        }
    }

    public static func < (a: SessionBlockKind, b: SessionBlockKind) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

public enum SlotRole: String, Codable, Sendable {
    case main, accessory, mobility, warmup, conditioning, stretch, recovery
}

public struct ConditioningPlan: Codable, Hashable, Sendable {
    public var minutes: Int
    public var zones: ClosedRange<Int>
    public var style: ConditioningSpec.Style
    public var workSeconds: Int?
    public var restSeconds: Int?

    public init(minutes: Int, zones: ClosedRange<Int>, style: ConditioningSpec.Style, workSeconds: Int? = nil, restSeconds: Int? = nil) {
        self.minutes = minutes
        self.zones = zones
        self.style = style
        self.workSeconds = workSeconds
        self.restSeconds = restSeconds
    }

    public var summary: String {
        let zone = zones.lowerBound == zones.upperBound ? "Zone \(zones.lowerBound)" : "Zone \(zones.lowerBound)–\(zones.upperBound)"
        if style == .intervals, let work = workSeconds, let rest = restSeconds {
            return "\(minutes) min · \(work)s on / \(rest)s off · \(zone)"
        }
        return "\(minutes) min · \(zone)"
    }
}

/// One exercise in a planned day.
public struct SlotPlan: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var exerciseID: String
    public var role: SlotRole
    /// Working sets for each loading week.
    public var sets: [Int]
    public var repRange: RepRange
    public var restSeconds: Int
    /// Timed work: seconds per set.
    public var seconds: Int?
    /// Paired with another slot as a superset (short sessions).
    public var supersetGroup: Int?
    /// A mobility drill done in this slot's rests (short sessions fold the limiter in here).
    public var restFiller: String?
    public var conditioning: ConditioningPlan?
    /// Why this slot is here, when it isn't obvious.
    public var reason: String?

    public init(
        id: UUID = UUID(), exerciseID: String, role: SlotRole, sets: [Int], repRange: RepRange, restSeconds: Int,
        seconds: Int? = nil, supersetGroup: Int? = nil, restFiller: String? = nil, conditioning: ConditioningPlan? = nil,
        reason: String? = nil
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.role = role
        self.sets = sets
        self.repRange = repRange
        self.restSeconds = restSeconds
        self.seconds = seconds
        self.supersetGroup = supersetGroup
        self.restFiller = restFiller
        self.conditioning = conditioning
        self.reason = reason
    }

    public func sets(week: Int) -> Int { sets.isEmpty ? 3 : sets[min(max(0, week), sets.count - 1)] }
}

public struct SessionBlockPlan: Codable, Hashable, Sendable, Identifiable {
    public var kind: SessionBlockKind
    public var minutes: Int
    public var slots: [SlotPlan]

    public var id: SessionBlockKind { kind }

    public init(kind: SessionBlockKind, minutes: Int, slots: [SlotPlan]) {
        self.kind = kind
        self.minutes = minutes
        self.slots = slots
    }
}

public enum DayFocus: String, Codable, Sendable {
    case full, upper, lower, push, pull, legs

    public var lowerBody: Bool { self == .lower || self == .legs }
}

/// Work that didn't fit the session's time, offered as a quest for a free block instead.
public struct OverflowItem: Codable, Hashable, Sendable {
    public var kind: SessionBlockKind
    public var title: String
    public var minutes: Int
    public var stat: StatKind

    public init(kind: SessionBlockKind, title: String, minutes: Int, stat: StatKind) {
        self.kind = kind
        self.title = title
        self.minutes = minutes
        self.stat = stat
    }
}

public struct PlannedDay: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var focus: DayFocus
    public var blocks: [SessionBlockPlan]
    public var overflow: [OverflowItem]

    public init(id: UUID = UUID(), name: String, focus: DayFocus, blocks: [SessionBlockPlan], overflow: [OverflowItem] = []) {
        self.id = id
        self.name = name
        self.focus = focus
        self.blocks = blocks
        self.overflow = overflow
    }

    public var minutes: Int { blocks.map(\.minutes).reduce(0, +) }
    public var slots: [SlotPlan] { blocks.flatMap(\.slots) }
    public var strengthSlots: [SlotPlan] { blocks.filter { $0.kind == .main || $0.kind == .accessory }.flatMap(\.slots) }
}

public enum SplitKind: String, Codable, Sendable {
    case fullBody, upperLower, upperLowerPushPullLegs, pushPullLegs

    public var label: String {
        switch self {
        case .fullBody: "Full body"
        case .upperLower: "Upper / lower"
        case .upperLowerPushPullLegs: "Upper / lower / push / pull / legs"
        case .pushPullLegs: "Push / pull / legs"
        }
    }
}

/// The single plan, in plain words, with the detail behind an expandable "Why?".
public struct Rationale: Codable, Hashable, Sendable {
    public var headline: String
    public var reasons: [String]
    /// Said honestly when data is thin.
    public var confidence: String?

    public init(headline: String, reasons: [String] = [], confidence: String? = nil) {
        self.headline = headline
        self.reasons = reasons
        self.confidence = confidence
    }
}

/// A mesocycle: a block on the calendar and the days that fill it.
public struct Mesocycle: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var block: TrainingBlock
    public var split: SplitKind
    public var days: [PlannedDay]
    public var priorities: [TrainingPriority]
    public var rationale: Rationale
    public var minutesPerSession: Int
    public var phase: NutritionPhase
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(), block: TrainingBlock, split: SplitKind, days: [PlannedDay], priorities: [TrainingPriority],
        rationale: Rationale, minutesPerSession: Int, phase: NutritionPhase, createdAt: Date = Date(), updatedAt: Date = Date()
    ) {
        self.id = id
        self.block = block
        self.split = split
        self.days = days
        self.priorities = priorities
        self.rationale = rationale
        self.minutesPerSession = minutesPerSession
        self.phase = phase
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var exerciseIDs: Set<String> { Set(days.flatMap { $0.strengthSlots.map(\.exerciseID) }) }
}

// MARK: - Sessions

public struct ExerciseLog: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var slotID: UUID?
    public var exerciseID: String
    public var sets: [LoggedSet]
    /// Replaced the planned exercise (by the person, or for an injury or the gym).
    public var substitutedFor: String?

    public init(id: UUID = UUID(), slotID: UUID? = nil, exerciseID: String, sets: [LoggedSet] = [], substitutedFor: String? = nil) {
        self.id = id
        self.slotID = slotID
        self.exerciseID = exerciseID
        self.sets = sets
        self.substitutedFor = substitutedFor
    }
}

extension [LoggedSet] {
    /// Each exercise's sets, exercises in the order they first appear and sets in their own order.
    func groupedByExercise() -> [(exerciseID: String, sets: [LoggedSet])] {
        var order: [String] = []
        var sets: [String: [LoggedSet]] = [:]
        for set in self {
            if sets[set.exerciseID] == nil { order.append(set.exerciseID) }
            sets[set.exerciseID, default: []].append(set)
        }
        return order.map { ($0, sets[$0] ?? []) }
    }
}

public struct ConditioningLog: Codable, Hashable, Sendable {
    public var exerciseID: String
    public var minutes: Int
    public var averageHeartRate: Double?
    /// Minutes in each zone 1–5, when a watch recorded heart rate.
    public var zoneMinutes: [Int: Double]
    public var zone: Int

    public init(exerciseID: String, minutes: Int, averageHeartRate: Double? = nil, zoneMinutes: [Int: Double] = [:], zone: Int) {
        self.exerciseID = exerciseID
        self.minutes = minutes
        self.averageHeartRate = averageHeartRate
        self.zoneMinutes = zoneMinutes
        self.zone = zone
    }
}

extension ConditioningLog {
    // Kept in a session in progress as well as a finished one (see LiveSession): minutes in each
    // zone decode as none when absent.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        exerciseID = try c.decode(String.self, forKey: .exerciseID)
        minutes = try c.decode(Int.self, forKey: .minutes)
        averageHeartRate = try c.decodeIfPresent(Double.self, forKey: .averageHeartRate)
        zoneMinutes = try c.decodeIfPresent([Int: Double].self, forKey: .zoneMinutes) ?? [:]
        zone = try c.decode(Int.self, forKey: .zone)
    }
}

/// A sauna or steam room after a session: how hot, how long, and how it felt. Rooms vary, so the
/// temperature is what makes one session comparable with the next.
public struct HeatLog: Codable, Hashable, Sendable {
    /// "sauna" or "steam-room".
    public var exerciseID: String
    public var date: Date
    public var minutes: Double
    /// The room's thermometer, when it was read.
    public var temperatureC: Double?
    /// Easy, just right, or too much.
    public var rating: SetRating?
    public var averageHeartRate: Double?
    public var peakHeartRate: Double?

    public init(
        exerciseID: String, date: Date, minutes: Double, temperatureC: Double?, rating: SetRating?,
        averageHeartRate: Double? = nil, peakHeartRate: Double? = nil
    ) {
        self.exerciseID = exerciseID
        self.date = date
        self.minutes = minutes
        self.temperatureC = temperatureC
        self.rating = rating
        self.averageHeartRate = averageHeartRate
        self.peakHeartRate = peakHeartRate
    }
}

/// A finished Lift Track session.
public struct SessionRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var start: Date
    public var end: Date
    public var title: String
    public var mesocycleID: UUID?
    public var dayID: UUID?
    /// Part of the plan, as opposed to an extra.
    public var planned: Bool
    public var deload: Bool
    public var exercises: [ExerciseLog]
    public var conditioning: [ConditioningLog]
    /// Mobility drills and stretches done, by exercise id.
    public var mobility: [String]
    public var feedback: SessionFeedback?
    public var device: String
    public var averageHeartRate: Double?
    /// The sauna or steam room afterwards (nil in sessions saved before it was kept).
    public var heat: [HeatLog]?
    /// The time zone the session was done in, so its day stays put when the phone travels (nil in
    /// sessions saved before it was kept, which read in the phone's zone).
    public var timeZoneID: String?
    public var updatedAt: Date

    public init(
        id: UUID = UUID(), start: Date, end: Date, title: String, mesocycleID: UUID? = nil, dayID: UUID? = nil, planned: Bool = true,
        deload: Bool = false, exercises: [ExerciseLog] = [], conditioning: [ConditioningLog] = [], mobility: [String] = [],
        feedback: SessionFeedback? = nil, device: String = "iPhone", averageHeartRate: Double? = nil, heat: [HeatLog]? = nil,
        timeZoneID: String? = TimeZone.current.identifier, updatedAt: Date = Date()
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.title = title
        self.mesocycleID = mesocycleID
        self.dayID = dayID
        self.planned = planned
        self.deload = deload
        self.exercises = exercises
        self.conditioning = conditioning
        self.mobility = mobility
        self.feedback = feedback
        self.device = device
        self.averageHeartRate = averageHeartRate
        self.heat = heat
        self.timeZoneID = timeZoneID
        self.updatedAt = updatedAt
    }

    /// The day the session was done, where it was done: a late session stays on its day after a flight.
    public var day: Day { Day(start, timeZone: timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current) }
    public var minutes: Int { max(1, Int(end.timeIntervalSince(start) / 60)) }
    public var sets: [LoggedSet] { exercises.flatMap(\.sets) }
    public var workSets: [LoggedSet] { sets.filter { $0.kind.countsAsWork } }

    /// Whether there's anything to keep: lifting, conditioning, mobility or heat. A session ended
    /// with none of them is thrown away rather than saved.
    public var hasContent: Bool { !exercises.isEmpty || !conditioning.isEmpty || !mobility.isEmpty || !(heat ?? []).isEmpty }
}

/// An outside activity, as Lift Track stores it.
public struct ActivityRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var log: ActivityLog
    public var updatedAt: Date

    public init(log: ActivityLog, updatedAt: Date = Date()) {
        id = log.id
        self.log = log
        self.updatedAt = updatedAt
    }
}

public struct MeasurementRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var measurements: BodyMeasurements
    public var updatedAt: Date

    public init(_ measurements: BodyMeasurements, updatedAt: Date = Date()) {
        id = measurements.id
        self.measurements = measurements
        self.updatedAt = updatedAt
    }
}

/// A progress photo, for the person's own comparison. Never analysed for body fat.
public struct ProgressPhoto: Codable, Hashable, Sendable, Identifiable {
    public enum Pose: String, Codable, Sendable, CaseIterable { case front, side, back }

    public var id: UUID
    public var day: Day
    public var pose: Pose
    /// JPEG, already downscaled.
    public var jpeg: Data
    public var updatedAt: Date

    public init(id: UUID = UUID(), day: Day, pose: Pose, jpeg: Data, updatedAt: Date = Date()) {
        self.id = id
        self.day = day
        self.pose = pose
        self.jpeg = jpeg
        self.updatedAt = updatedAt
    }
}

public struct MobilityRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var result: MobilityResult
    public var updatedAt: Date

    public init(_ result: MobilityResult, updatedAt: Date = Date()) {
        id = result.id
        self.result = result
        self.updatedAt = updatedAt
    }
}

public struct BenchmarkRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var result: BenchmarkResult
    public var updatedAt: Date

    public init(_ result: BenchmarkResult, updatedAt: Date = Date()) {
        id = result.id
        self.result = result
        self.updatedAt = updatedAt
    }
}
