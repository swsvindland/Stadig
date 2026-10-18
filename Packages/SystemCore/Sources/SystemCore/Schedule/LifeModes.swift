import Foundation

// Life modes: vacation, crunch, injury and illness. They're system-wide: set in any app, honoured
// by all of them. A life mode never counts as failure.

public enum FoodControl: String, CaseIterable, Codable, Sendable, Identifiable {
    case cooking, mixed, eatingOut

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .cooking: "Cooking"
        case .mixed: "Mixed"
        case .eatingOut: "Eating out"
        }
    }
}

/// Crunch mode's three dials, for work travel, demo crunches, exams and family emergencies.
public struct CrunchDials: Hashable, Codable, Sendable {
    /// Minutes realistically free for a session; 0 means nothing.
    public var minutesAvailable: Int
    public var equipment: EquipmentAccess
    public var food: FoodControl
    /// Discipline is measured against the reduced plan unless the person exempts the period.
    public var exemptFromDiscipline: Bool

    public init(minutesAvailable: Int = 20, equipment: EquipmentAccess = .hotelGym, food: FoodControl = .mixed,
                exemptFromDiscipline: Bool = false) {
        self.minutesAvailable = max(0, minutesAvailable)
        self.equipment = equipment
        self.food = food
        self.exemptFromDiscipline = exemptFromDiscipline
    }
}

public enum BodySide: String, CaseIterable, Codable, Sendable {
    case left, right, both

    public var label: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .both: "Both"
        }
    }
}

public enum InjurySeverity: String, CaseIterable, Codable, Sendable, Identifiable, Comparable {
    case mild, moderate, severe

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .mild: "Mild"
        case .moderate: "Moderate"
        case .severe: "Severe"
        }
    }

    /// Exercises that stress the injured joint at or above this are filtered out.
    public var excludedFrom: JointStress {
        switch self {
        case .mild: .high
        case .moderate: .moderate
        case .severe: .low
        }
    }

    /// Weeks to ramp affected lifts back to full load after the injury is marked better.
    public var reentryWeeks: Int {
        switch self {
        case .mild: 1
        case .moderate: 2
        case .severe: 4
        }
    }

    public static func < (a: InjurySeverity, b: InjurySeverity) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

public struct InjuredPart: Hashable, Codable, Sendable {
    public var joint: Joint
    public var side: BodySide

    public init(_ joint: Joint, side: BodySide = .both) {
        self.joint = joint
        self.side = joint.isPaired ? side : .both
    }

    public var label: String { side == .both || !joint.isPaired ? joint.label : "\(side.label) \(joint.label.lowercased())" }
}

public struct Injury: Hashable, Codable, Sendable {
    public var parts: [InjuredPart]
    public var severity: InjurySeverity
    public var note: String
    /// Exercises the person added back or took out by hand, overriding the filter.
    public var allowed: [String]
    public var removed: [String]

    public init(parts: [InjuredPart], severity: InjurySeverity, note: String = "", allowed: [String] = [], removed: [String] = []) {
        self.parts = parts
        self.severity = severity
        self.note = note
        self.allowed = allowed
        self.removed = removed
    }

    public var joints: Set<Joint> { Set(parts.map(\.joint)) }

    /// Whether an exercise is off the table while this injury is active.
    public func excludes(_ exercise: some ExerciseTraits) -> Bool {
        if allowed.contains(exercise.id) { return false }
        if removed.contains(exercise.id) { return true }
        return exercise.joints.contains { joints.contains($0.joint) && $0.stress >= severity.excludedFrom }
    }

    /// Whether it touches the injured area at all (for the re-entry ramp).
    public func affects(_ exercise: some ExerciseTraits) -> Bool {
        exercise.joints.contains { joints.contains($0.joint) }
    }

    /// The person's tap on an exercise in the overrides list: one that's set aside (by the filter or
    /// by hand) is allowed back, and one that's allowed is set aside. An exercise is in at most one
    /// of the lists, once, however many times it's tapped.
    public mutating func toggleOverride(for exerciseID: String, currentlyExcluded: Bool) {
        allowed.removeAll { $0 == exerciseID }
        removed.removeAll { $0 == exerciseID }
        if currentlyExcluded { allowed.append(exerciseID) } else { removed.append(exerciseID) }
    }

    public mutating func toggleOverride(for exercise: some ExerciseTraits) {
        toggleOverride(for: exercise.id, currentlyExcluded: excludes(exercise))
    }

    public var summary: String { "\(parts.map(\.label).joined(separator: ", ")), \(severity.label.lowercased())" }
}

public enum IllnessKind: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Mild symptoms above the neck, like a small cold: light training is usually fine.
    case aboveNeck
    /// Fever, chest symptoms or body aches: rest.
    case systemic

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .aboveNeck: "Head cold"
        case .systemic: "Properly sick"
        }
    }

    public var detail: String {
        switch self {
        case .aboveNeck: "Mild and above the neck: a stuffy nose, a sore throat. Light training is usually fine."
        case .systemic: "Fever, chest symptoms or body aches. Rest; nothing is expected."
        }
    }
}

public enum LifeModeKind: Hashable, Codable, Sendable {
    /// No logging expected in any app; excluded from Discipline entirely.
    case vacation
    case crunch(CrunchDials)
    case injury(Injury)
    case illness(IllnessKind)

    public var label: String {
        switch self {
        case .vacation: "Vacation"
        case .crunch: "Crunch mode"
        case .injury: "Injury"
        case .illness: "Illness"
        }
    }

    public var symbol: String {
        switch self {
        case .vacation: "airplane"
        case .crunch: "briefcase.fill"
        case .injury: "bandage.fill"
        case .illness: "thermometer.medium"
        }
    }

    /// Injuries and illness can run until marked better; a trip or a crunch has an end.
    public var allowsOpenEnd: Bool {
        switch self {
        case .injury, .illness: true
        case .vacation, .crunch: false
        }
    }
}

public struct LifeModePeriod: Hashable, Codable, Sendable, Identifiable {
    /// The shared container's `core/life-modes.json`. 2 added `deletedAt`: an app that only knows 1
    /// would drop it when it rewrites the file and bring deleted periods back, so it mustn't write.
    public static let schemaVersion = 2

    public var id: UUID
    public var kind: LifeModeKind
    public var start: Day
    /// Nil while open-ended (an injury or illness until marked better).
    public var end: Day?
    public var createdBy: AppID
    public var updatedAt: Date
    /// When it was deleted. A deleted period stays in the lists as a tombstone, so the delete
    /// reaches the other apps and devices and wins over their older copies by `updatedAt`. Nil in
    /// everything written before deletes were shared.
    public var deletedAt: Date?

    public init(id: UUID = UUID(), kind: LifeModeKind, start: Day, end: Day? = nil, createdBy: AppID, updatedAt: Date = Date(),
                deletedAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.createdBy = createdBy
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public var isDeleted: Bool { deletedAt != nil }

    /// The tombstone that replaces it when it's deleted.
    public func deleted(at date: Date = Date()) -> LifeModePeriod {
        var tombstone = self
        tombstone.deletedAt = date
        tombstone.updatedAt = date
        return tombstone
    }

    public func contains(_ day: Day) -> Bool { day >= start && (end.map { day <= $0 } ?? true) }

    public func range(openUntil day: Day) -> DayRange { DayRange(start, end ?? max(start, day)) }

    /// Whether an editor can save it: the end isn't before the start, only an injury or illness is
    /// open-ended, and an injury says where it is.
    public var isValid: Bool {
        if let end, end < start { return false }
        if end == nil, !kind.allowsOpenEnd { return false }
        if case .injury(let injury) = kind, injury.parts.isEmpty { return false }
        return true
    }

    // MARK: Editing

    /// How long a period with no end yet runs when an editor gives it one: a week.
    public static let defaultDays = 7

    /// The end an editor's picker shows: the period's own, else a week from the start, and never
    /// before the start.
    public var editorEnd: Day { max(start, end ?? start.adding(days: Self.defaultDays - 1)) }

    /// What an editor saves, so every app's editor saves the same thing: open-ended only where the
    /// kind allows it, else with the end its picker shows.
    public func edited(openEnded: Bool) -> LifeModePeriod {
        var edited = self
        edited.end = openEnded && kind.allowsOpenEnd ? nil : editorEnd
        return edited
    }

    /// Moves the start, taking an end it passes along rather than leaving it before the start.
    public mutating func moveStart(to day: Day) {
        start = day
        end = end.map { max(day, $0) }
    }

    /// Moves the end, never before the start.
    public mutating func moveEnd(to day: Day) { end = max(start, day) }

    /// The dates put in order when the end was moved before the start (or the start after the end).
    public func normalized() -> LifeModePeriod {
        guard let end, end < start else { return self }
        var period = self
        period.start = end
        period.end = start
        return period
    }

    /// Every app's and device's copies merged: the newest edit of each period wins by `updatedAt`,
    /// a delete included, so tombstones are kept and passed on. On a tie a delete wins, then the
    /// first source. Compared in whole milliseconds, the precision the shared container stores.
    /// Hand the engines `live`.
    public static func merge(_ sources: [[LifeModePeriod]]) -> [LifeModePeriod] {
        var merged: [UUID: LifeModePeriod] = [:]
        for period in sources.joined() {
            if let existing = merged[period.id] {
                let new = milliseconds(period.updatedAt), old = milliseconds(existing.updatedAt)
                guard new > old || (new == old && period.isDeleted && !existing.isDeleted) else { continue }
            }
            merged[period.id] = period
        }
        return merged.values.sorted { ($0.start, $0.id.uuidString) < ($1.start, $1.id.uuidString) }
    }

    /// Kept a Double: a converted Int64 would trap on a corrupt timestamp read from another device.
    private static func milliseconds(_ date: Date) -> Double { (date.timeIntervalSince1970 * 1000).rounded() }
}

public extension Array where Element == LifeModePeriod {
    /// Without the tombstones: the periods that are in force, for the engines and the screens.
    var live: [LifeModePeriod] { filter { !$0.isDeleted } }
}

/// An injury marked better, with the fraction of normal load affected lifts ramp back from.
public struct InjuryRamp: Hashable, Sendable {
    public var injury: Injury
    public var loadFactor: Double
}

/// What life modes mean for a day.
public struct LifeModeEffects: Hashable, Sendable {
    /// Whether any training is expected.
    public var trainingExpected = true
    /// Whether the day is left out of Discipline entirely.
    public var disciplineExempt = false
    /// The time cap for a session, if any.
    public var maxMinutes: Int?
    /// Equipment turned down by crunch mode.
    public var equipment: EquipmentAccess?
    /// Minimum effective dose: short sessions, far fewer sets, compounds kept.
    public var minimumEffectiveDose = false
    /// Light work only (a head cold).
    public var lightOnly = false
    /// The first week back: ease in.
    public var reentry = false
    public var injuries: [Injury] = []
    /// Injuries that have ended recently, ramping affected lifts back.
    public var injuryRamps: [InjuryRamp] = []
    /// Long workdays and travel: counted against the Fatigue Budget.
    public var lifeStress: Double = 0
    public var active: [LifeModePeriod] = []

    public init() {}

    /// The fraction of normal load for an exercise: 1 unless an injury is ramping back.
    public func loadFactor(for exercise: some ExerciseTraits) -> Double {
        injuryRamps.filter { $0.injury.affects(exercise) }.map(\.loadFactor).min() ?? 1
    }

    public func excludes(_ exercise: some ExerciseTraits) -> Bool { injuries.contains { $0.excludes(exercise) } }
}

public enum LifeModes {
    /// The days after a vacation or illness that ease back in.
    public static let reentryDays = 7

    public static func effects(on day: Day, periods: [LifeModePeriod]) -> LifeModeEffects {
        var effects = LifeModeEffects()
        for period in periods where !period.isDeleted {
            if period.contains(day) {
                effects.active.append(period)
                switch period.kind {
                case .vacation:
                    effects.trainingExpected = false
                    effects.disciplineExempt = true
                case .crunch(let dials):
                    effects.minimumEffectiveDose = true
                    effects.maxMinutes = min(effects.maxMinutes ?? .max, dials.minutesAvailable)
                    effects.equipment = dials.equipment
                    if dials.minutesAvailable == 0 { effects.trainingExpected = false }
                    if dials.exemptFromDiscipline { effects.disciplineExempt = true }
                    effects.lifeStress += 1
                case .injury(let injury):
                    effects.injuries.append(injury)
                case .illness(let kind):
                    effects.disciplineExempt = true
                    if kind == .systemic { effects.trainingExpected = false } else { effects.lightOnly = true }
                    effects.lifeStress += kind == .systemic ? 2 : 0.5
                }
            } else if let end = period.end, day > end {
                let since = end.days(until: day)
                switch period.kind {
                case .vacation, .illness:
                    if since <= reentryDays { effects.reentry = true }
                case .injury(let injury):
                    let rampDays = injury.severity.reentryWeeks * 7
                    if since <= rampDays {
                        // From 60% of normal load back to full across the ramp.
                        let factor = 0.6 + 0.4 * Double(since) / Double(rampDays)
                        effects.injuryRamps.append(InjuryRamp(injury: injury, loadFactor: factor))
                    }
                case .crunch:
                    break
                }
            }
        }
        return effects
    }

    /// Days exempt from Discipline in a window.
    public static func exemptDays(in range: DayRange, periods: [LifeModePeriod]) -> Set<Day> {
        Set(range.days.filter { effects(on: $0, periods: periods).disciplineExempt })
    }

    /// Life stress per day, for the Fatigue Budget.
    public static func lifeStress(in range: DayRange, periods: [LifeModePeriod]) -> [Day: Double] {
        var result: [Day: Double] = [:]
        for day in range.days {
            let stress = effects(on: day, periods: periods).lifeStress
            if stress > 0 { result[day] = stress }
        }
        return result
    }
}
