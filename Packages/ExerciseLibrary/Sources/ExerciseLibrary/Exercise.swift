import Foundation
import SystemCore

/// What an entry in the library is for.
public enum ExerciseKind: String, Codable, Sendable, CaseIterable {
    /// Loaded strength and hypertrophy work.
    case strength
    /// Cardio for the conditioning block and benchmarks.
    case conditioning
    /// Targeted mobility drills: the limiter slot, warm-up openers, finishers.
    case mobility
    /// Dynamic warm-up moves.
    case warmup
    /// Static stretches for the optional cool-down.
    case stretch
}

/// Fixtures beyond the equipment list that an exercise needs: a bench, a rack, a bar to hang from.
public enum Apparatus: String, Codable, Sendable, CaseIterable {
    case bench, rack, pullUpBar, dipStation, box, landmine, gluteHamBench, backExtensionBench

    public var label: String {
        switch self {
        case .bench: "Bench"
        case .rack: "Rack with safeties"
        case .pullUpBar: "Pull-up bar"
        case .dipStation: "Dip station"
        case .box: "Box or step"
        case .landmine: "Landmine"
        case .gluteHamBench: "Glute-ham bench"
        case .backExtensionBench: "Back extension bench"
        }
    }
}

/// Default rest in seconds, by training goal.
public struct RestDefaults: Hashable, Codable, Sendable {
    public var strength: Int
    public var hypertrophy: Int

    public init(strength: Int, hypertrophy: Int) {
        self.strength = strength
        self.hypertrophy = hypertrophy
    }
}

/// Default rep ranges, by training goal.
public struct RepDefaults: Hashable, Codable, Sendable {
    public var strength: RepRange
    public var hypertrophy: RepRange

    public init(strength: RepRange, hypertrophy: RepRange) {
        self.strength = strength
        self.hypertrophy = hypertrophy
    }
}

/// How a conditioning entry is done.
public struct ConditioningSpec: Hashable, Codable, Sendable {
    public enum Style: String, Codable, Sendable {
        /// Steady Zone 2–3.
        case steady
        /// Work and rest intervals, Zone 4–5 on the work.
        case intervals
    }

    public var style: Style
    public var zones: ClosedRange<Int>
    /// For intervals: work and rest seconds per round.
    public var workSeconds: Int?
    public var restSeconds: Int?

    public init(style: Style, zones: ClosedRange<Int>, workSeconds: Int? = nil, restSeconds: Int? = nil) {
        self.style = style
        self.zones = zones
        self.workSeconds = workSeconds
        self.restSeconds = restSeconds
    }
}

/// One library entry. Ids are stable kebab-case and never renamed or reused: history refers to them.
public struct Exercise: ExerciseTraits, Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var name: String
    public var aliases: [String]
    public var kind: ExerciseKind
    public var pattern: MovementPattern
    public var equipment: Equipment
    /// Extra fixtures needed beyond the equipment.
    public var apparatus: [Apparatus]
    /// In order of importance; weight 1 for a primary mover, 0.5 for a secondary.
    public var muscles: [MuscleShare]
    public var joints: [JointLoad]
    public var fatigue: FatigueProfile
    public var safetyTier: SafetyTier
    /// Set only for free-weight variants with a known ratio to the category's reference lift.
    public var strength: StrengthMapping?
    public var loadBasis: LoadBasis
    /// Trained one side at a time.
    public var unilateral: Bool
    public var reps: RepDefaults
    public var rest: RestDefaults
    public var restRole: RestRole
    /// For mobility drills and stretches: what they loosen. For other work: what it also helps.
    public var mobilityTargets: [MobilityTarget]
    /// Held or done for time rather than counted.
    public var timed: Bool
    /// The default duration of one set, for timed work.
    public var seconds: Int?
    public var conditioning: ConditioningSpec?
    /// One short technique cue.
    public var cue: String
    public var custom: Bool

    public init(id: String, name: String, aliases: [String] = [], kind: ExerciseKind = .strength, pattern: MovementPattern,
                equipment: Equipment, apparatus: [Apparatus] = [], muscles: [MuscleShare], joints: [JointLoad],
                fatigue: FatigueProfile, safetyTier: SafetyTier, strength: StrengthMapping? = nil, loadBasis: LoadBasis = .external,
                unilateral: Bool = false, reps: RepDefaults, rest: RestDefaults, restRole: RestRole = .accessory,
                mobilityTargets: [MobilityTarget] = [], timed: Bool = false, seconds: Int? = nil,
                conditioning: ConditioningSpec? = nil, cue: String = "", custom: Bool = false) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.kind = kind
        self.pattern = pattern
        self.equipment = equipment
        self.apparatus = apparatus
        self.muscles = muscles
        self.joints = joints
        self.fatigue = fatigue
        self.safetyTier = safetyTier
        self.strength = strength
        self.loadBasis = loadBasis
        self.unilateral = unilateral
        self.reps = reps
        self.rest = rest
        self.restRole = restRole
        self.mobilityTargets = mobilityTargets
        self.timed = timed
        self.seconds = seconds
        self.conditioning = conditioning
        self.cue = cue
        self.custom = custom
    }

    enum CodingKeys: String, CodingKey {
        case id, name, aliases, kind, pattern, equipment, apparatus, muscles, joints, fatigue, safetyTier, strength, loadBasis
        case unilateral, reps, rest, restRole, mobilityTargets, timed, seconds, conditioning, cue, custom
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        kind = try c.decodeIfPresent(ExerciseKind.self, forKey: .kind) ?? .strength
        pattern = try c.decode(MovementPattern.self, forKey: .pattern)
        equipment = try c.decode(Equipment.self, forKey: .equipment)
        apparatus = try c.decodeIfPresent([Apparatus].self, forKey: .apparatus) ?? []
        muscles = try c.decodeIfPresent([MuscleShare].self, forKey: .muscles) ?? []
        joints = try c.decodeIfPresent([JointLoad].self, forKey: .joints) ?? []
        fatigue = try c.decode(FatigueProfile.self, forKey: .fatigue)
        safetyTier = try c.decode(SafetyTier.self, forKey: .safetyTier)
        strength = try c.decodeIfPresent(StrengthMapping.self, forKey: .strength)
        loadBasis = try c.decodeIfPresent(LoadBasis.self, forKey: .loadBasis) ?? .external
        unilateral = try c.decodeIfPresent(Bool.self, forKey: .unilateral) ?? false
        reps = try c.decode(RepDefaults.self, forKey: .reps)
        rest = try c.decode(RestDefaults.self, forKey: .rest)
        restRole = try c.decodeIfPresent(RestRole.self, forKey: .restRole) ?? .accessory
        mobilityTargets = try c.decodeIfPresent([MobilityTarget].self, forKey: .mobilityTargets) ?? []
        timed = try c.decodeIfPresent(Bool.self, forKey: .timed) ?? false
        seconds = try c.decodeIfPresent(Int.self, forKey: .seconds)
        conditioning = try c.decodeIfPresent(ConditioningSpec.self, forKey: .conditioning)
        cue = try c.decodeIfPresent(String.self, forKey: .cue) ?? ""
        custom = try c.decodeIfPresent(Bool.self, forKey: .custom) ?? false
    }
}
