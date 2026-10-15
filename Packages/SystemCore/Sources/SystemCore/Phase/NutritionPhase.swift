import Foundation

/// Nutrition phases are parameterised: a kind, a rate and a planned length. Macro Track decides
/// and publishes the current one; Lift Track uses it when present, and otherwise asks a one-tap
/// question it trusts less.
public enum PhaseKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case cut, miniCut, maintenance, dietBreak, reverseDiet, recomp, leanBulk

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .cut: "Cut"
        case .miniCut: "Mini-cut"
        case .maintenance: "Maintenance"
        case .dietBreak: "Diet break"
        case .reverseDiet: "Reverse diet"
        case .recomp: "Recomp"
        case .leanBulk: "Lean bulk"
        }
    }

    public enum Energy: String, Codable, Sendable { case deficit, maintenance, surplus }

    public var energy: Energy {
        switch self {
        case .cut, .miniCut: .deficit
        case .maintenance, .dietBreak, .recomp: .maintenance
        case .reverseDiet, .leanBulk: .surplus
        }
    }

    /// Typical bodyweight change per week as a fraction (−0.005 is 0.5% a week).
    public var typicalRate: Double {
        switch self {
        case .cut: -0.005
        case .miniCut: -0.0075
        case .maintenance, .dietBreak, .recomp: 0
        case .reverseDiet: 0.001
        case .leanBulk: 0.0025
        }
    }
}

public enum PhaseSource: String, Codable, Sendable {
    /// Decided by Macro Track from intake and weigh-ins.
    case macroTrack
    /// The one-tap question in Lift Track.
    case selfReported
    /// Nothing known: maintenance assumptions.
    case assumed

    /// How much a decision may lean on it.
    public var weight: Double {
        switch self {
        case .macroTrack: 1
        case .selfReported: 0.6
        case .assumed: 0.4
        }
    }
}

public struct NutritionPhase: Hashable, Codable, Sendable {
    public var kind: PhaseKind
    public var ratePerWeek: Double
    public var plannedWeeks: Int?
    public var start: Day?
    public var source: PhaseSource

    public init(kind: PhaseKind, ratePerWeek: Double? = nil, plannedWeeks: Int? = nil, start: Day? = nil, source: PhaseSource) {
        self.kind = kind
        self.ratePerWeek = ratePerWeek ?? kind.typicalRate
        self.plannedWeeks = plannedWeeks
        self.start = start
        self.source = source
    }

    public static let assumedMaintenance = NutritionPhase(kind: .maintenance, source: .assumed)

    /// How the phase changes training expectations.
    public var effects: PhaseEffects {
        switch kind.energy {
        case .deficit:
            PhaseEffects(volumeTolerance: kind == .miniCut ? 0.75 : 0.85, maxLoadStepsPerSession: 1, stallsExpected: true,
                         protectCompounds: true, blockLengthAdjustment: kind == .miniCut ? -2 : -1)
        case .maintenance:
            PhaseEffects(volumeTolerance: 1, maxLoadStepsPerSession: 1, stallsExpected: false, protectCompounds: false,
                         blockLengthAdjustment: 0)
        case .surplus:
            PhaseEffects(volumeTolerance: kind == .reverseDiet ? 1 : 1.1, maxLoadStepsPerSession: 2, stallsExpected: false,
                         protectCompounds: false, blockLengthAdjustment: 1)
        }
    }
}

public struct PhaseEffects: Hashable, Codable, Sendable {
    /// Multiplies weekly set targets.
    public var volumeTolerance: Double
    /// How far load may climb from one session to the next.
    public var maxLoadStepsPerSession: Int
    /// A stall during a deficit is expected, not a plateau.
    public var stallsExpected: Bool
    /// Hold heavy compounds and trim elsewhere first.
    public var protectCompounds: Bool
    /// Weeks added to (or taken from) the default loading block.
    public var blockLengthAdjustment: Int
}

/// Lift Track's one-tap question when Macro Track isn't there to say.
public enum SelfReportedPhase: String, CaseIterable, Codable, Sendable, Identifiable {
    case cutting, maintaining, bulking, notSure

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .cutting: "Cutting"
        case .maintaining: "Maintaining"
        case .bulking: "Bulking"
        case .notSure: "Not sure"
        }
    }

    public var phase: NutritionPhase {
        switch self {
        case .cutting: NutritionPhase(kind: .cut, source: .selfReported)
        case .maintaining: NutritionPhase(kind: .maintenance, source: .selfReported)
        case .bulking: NutritionPhase(kind: .leanBulk, source: .selfReported)
        case .notSure: .assumedMaintenance
        }
    }
}

public enum PhaseResolver {
    /// Macro Track's phase wins; then the person's answer; then maintenance assumptions.
    public static func current(published: NutritionPhase?, selfReported: SelfReportedPhase?) -> NutritionPhase {
        if let published { return published }
        return selfReported?.phase ?? .assumedMaintenance
    }
}
