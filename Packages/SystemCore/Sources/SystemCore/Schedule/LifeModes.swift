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
}

public struct LifeModePeriod: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var kind: LifeModeKind
    public var start: Day
    /// Nil while open-ended (an injury or illness until marked better).
    public var end: Day?
    public var createdBy: AppID
    public var updatedAt: Date

    public init(id: UUID = UUID(), kind: LifeModeKind, start: Day, end: Day? = nil, createdBy: AppID, updatedAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.createdBy = createdBy
        self.updatedAt = updatedAt
    }

    public func contains(_ day: Day) -> Bool { day >= start && (end.map { day <= $0 } ?? true) }

    public func range(openUntil day: Day) -> DayRange { DayRange(start, end ?? max(start, day)) }
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
        for period in periods {
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
