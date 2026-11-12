import Foundation

// The vocabulary of training that both apps share: muscles, joints, equipment,
// movement patterns, safety tiers and fatigue costs. The exercise library tags every exercise with
// these; the core's logic reads only these tags, never exercise names.

/// Muscles tracked for weekly volume. Delts are split because different movements train them.
public enum Muscle: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable, Identifiable, Comparable {
    case chest, lats, upperBack, traps, frontDelts, sideDelts, rearDelts, biceps, triceps, forearms
    case abs, lowerBack, glutes, quads, hamstrings, adductors, calves

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .chest: "Chest"
        case .lats: "Lats"
        case .upperBack: "Upper back"
        case .traps: "Traps"
        case .frontDelts: "Front delts"
        case .sideDelts: "Side delts"
        case .rearDelts: "Rear delts"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .forearms: "Forearms"
        case .abs: "Abs"
        case .lowerBack: "Lower back"
        case .glutes: "Glutes"
        case .quads: "Quads"
        case .hamstrings: "Hamstrings"
        case .adductors: "Adductors"
        case .calves: "Calves"
        }
    }

    public enum Region: String, CaseIterable, Codable, Sendable { case push, pull, legs, core }

    public var region: Region {
        switch self {
        case .chest, .frontDelts, .sideDelts, .triceps: .push
        case .lats, .upperBack, .traps, .rearDelts, .biceps, .forearms: .pull
        case .glutes, .quads, .hamstrings, .adductors, .calves: .legs
        case .abs, .lowerBack: .core
        }
    }

    /// Where the muscle shows up for physique purposes.
    public var physiqueRegion: PhysiqueRegion {
        switch self {
        case .frontDelts, .sideDelts, .rearDelts: .shoulders
        case .chest: .chest
        case .lats, .upperBack, .traps, .lowerBack: .back
        case .biceps, .triceps, .forearms: .arms
        case .abs: .core
        case .glutes: .glutes
        case .quads, .hamstrings, .adductors: .thighs
        case .calves: .calves
        }
    }

    /// Small muscles recover fast; their volume barely touches the Fatigue Budget.
    public var isSmall: Bool {
        [.sideDelts, .rearDelts, .biceps, .triceps, .forearms, .calves, .abs].contains(self)
    }

    public static func < (a: Muscle, b: Muscle) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

/// A muscle an exercise trains and how much it counts: 1 for a primary mover, 0.5 for a secondary.
public struct MuscleShare: Hashable, Codable, Sendable {
    public var muscle: Muscle
    public var weight: Double

    public init(_ muscle: Muscle, _ weight: Double) {
        self.muscle = muscle
        self.weight = weight
    }
}

public enum PhysiqueRegion: String, CaseIterable, Codable, Sendable, Identifiable {
    case shoulders, chest, back, arms, core, glutes, thighs, calves

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .shoulders: "Shoulders"
        case .chest: "Chest"
        case .back: "Back"
        case .arms: "Arms"
        case .core: "Core"
        case .glutes: "Glutes"
        case .thighs: "Thighs"
        case .calves: "Calves"
        }
    }

    public var muscles: [Muscle] { Muscle.allCases.filter { $0.physiqueRegion == self } }
}

public enum Equipment: String, CaseIterable, Codable, Sendable, Identifiable {
    case barbell, ezBar, trapBar, smith, dumbbell, kettlebell, cable, machine, plateLoaded, bodyweight, band
    case rower, bike, stairClimber, treadmill

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .barbell: "Barbell"
        case .ezBar: "EZ bar"
        case .trapBar: "Trap bar"
        case .smith: "Smith machine"
        case .dumbbell: "Dumbbells"
        case .kettlebell: "Kettlebells"
        case .cable: "Cables"
        case .machine: "Machines"
        case .plateLoaded: "Plate-loaded machines"
        case .bodyweight: "Bodyweight"
        case .band: "Bands"
        case .rower: "Rower"
        case .bike: "Bike"
        case .stairClimber: "StairMaster"
        case .treadmill: "Treadmill"
        }
    }

    /// Loaded with plates in pairs.
    public var platePaired: Bool { [.barbell, .ezBar, .trapBar, .smith, .plateLoaded].contains(self) }

    public var isCardio: Bool { [.rower, .bike, .stairClimber, .treadmill].contains(self) }

    /// Machines and cables: a stack or a sled with a stop, so failure is unambiguous and safe.
    public var isMachine: Bool { [.machine, .cable, .plateLoaded, .smith].contains(self) }

    public var isFreeWeight: Bool { [.barbell, .ezBar, .trapBar, .dumbbell, .kettlebell].contains(self) }
}

/// The equipment dial: onboarding asks it, and crunch mode turns it down for a while.
public enum EquipmentAccess: String, CaseIterable, Codable, Sendable, Identifiable {
    case fullGym, homeGym, hotelGym, bodyweightOnly

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .fullGym: "Full gym"
        case .homeGym: "Home gym"
        case .hotelGym: "Hotel gym"
        case .bodyweightOnly: "Bodyweight only"
        }
    }

    public var detail: String {
        switch self {
        case .fullGym: "Barbells, racks with safeties, machines, cables and cardio."
        case .homeGym: "A rack with safeties, a barbell, dumbbells and a pull-up bar."
        case .hotelGym: "Light dumbbells, a bench, maybe a cable or a treadmill."
        case .bodyweightOnly: "A floor and a wall."
        }
    }

    public var equipment: Set<Equipment> {
        switch self {
        case .fullGym: Set(Equipment.allCases)
        case .homeGym: [.barbell, .dumbbell, .bodyweight, .band, .kettlebell]
        case .hotelGym: [.dumbbell, .bodyweight, .band, .cable, .treadmill, .bike]
        case .bodyweightOnly: [.bodyweight, .band]
        }
    }

    /// The heaviest dumbbell to expect, in kg; hotel racks stop early.
    public var dumbbellCapKg: Double? {
        switch self {
        case .fullGym: nil
        case .homeGym: 40
        case .hotelGym: 22.5
        case .bodyweightOnly: 0
        }
    }

    /// A rack with pins or safety arms: barbell lifts can be failed safely.
    public var hasSafeties: Bool { self == .fullGym || self == .homeGym }
}

/// Movement patterns. Strength categories, substitutions and injury filtering all start here.
public enum MovementPattern: String, CaseIterable, Codable, Sendable, Identifiable {
    case horizontalPress, inclinePress, verticalPress, dip, chestFly, horizontalRow, verticalPull, pullover
    case shrug, lateralRaise, frontRaise, rearDeltFly, facePull, curl, tricepsExtension, squat, lunge
    case legPress, hinge, hipThrust, legExtension, legCurl, backExtension, hipAdduction, hipAbduction
    case calfRaise, crunch, legRaise, core, wrist, carry
    case conditioning, mobility, warmup, stretch, recovery

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .horizontalPress: "Flat press"
        case .inclinePress: "Incline press"
        case .verticalPress: "Overhead press"
        case .dip: "Dip"
        case .chestFly: "Chest fly"
        case .horizontalRow: "Row"
        case .verticalPull: "Vertical pull"
        case .pullover: "Pullover"
        case .shrug: "Shrug"
        case .lateralRaise: "Lateral raise"
        case .frontRaise: "Front raise"
        case .rearDeltFly: "Rear delt fly"
        case .facePull: "Face pull"
        case .curl: "Curl"
        case .tricepsExtension: "Triceps extension"
        case .squat: "Squat"
        case .lunge: "Lunge"
        case .legPress: "Leg press"
        case .hinge: "Hinge"
        case .hipThrust: "Hip thrust"
        case .legExtension: "Leg extension"
        case .legCurl: "Leg curl"
        case .backExtension: "Back extension"
        case .hipAdduction: "Hip adduction"
        case .hipAbduction: "Hip abduction"
        case .calfRaise: "Calf raise"
        case .crunch: "Crunch"
        case .legRaise: "Leg raise"
        case .core: "Core"
        case .wrist: "Wrist"
        case .carry: "Carry"
        case .conditioning: "Conditioning"
        case .mobility: "Mobility"
        case .warmup: "Warm-up"
        case .stretch: "Stretch"
        case .recovery: "Recovery"
        }
    }

    /// Big multi-joint movements that anchor a day and take the longest rest.
    public var isCompound: Bool {
        [
            .horizontalPress, .inclinePress, .verticalPress, .dip, .horizontalRow, .verticalPull, .squat, .lunge,
            .legPress, .hinge, .hipThrust, .carry,
        ].contains(self)
    }

    /// Loaded strength work, as opposed to conditioning, mobility, warm-ups and stretches.
    public var isStrength: Bool { ![.conditioning, .mobility, .warmup, .stretch].contains(self) }

    public var isLowerBody: Bool {
        [
            .squat, .lunge, .legPress, .hinge, .hipThrust, .legExtension, .legCurl, .backExtension, .hipAdduction,
            .hipAbduction, .calfRaise,
        ].contains(self)
    }
}

/// Joints and spinal regions an exercise loads. Injury mode filters on these, deterministically.
public enum Joint: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable, Identifiable {
    case neck, shoulder, elbow, wrist, upperBack, lowerBack, hip, knee, ankle

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .neck: "Neck"
        case .shoulder: "Shoulder"
        case .elbow: "Elbow"
        case .wrist: "Wrist"
        case .upperBack: "Upper back"
        case .lowerBack: "Lower back"
        case .hip: "Hip"
        case .knee: "Knee"
        case .ankle: "Ankle"
        }
    }

    /// Paired joints have a left and a right.
    public var isPaired: Bool { ![.neck, .upperBack, .lowerBack].contains(self) }
}

public enum JointStress: Int, Codable, Sendable, Comparable, CaseIterable {
    case low = 1, moderate, high

    public static func < (a: JointStress, b: JointStress) -> Bool { a.rawValue < b.rawValue }

    public var label: String {
        switch self {
        case .low: "Low"
        case .moderate: "Moderate"
        case .high: "High"
        }
    }
}

public struct JointLoad: Hashable, Codable, Sendable {
    public var joint: Joint
    public var stress: JointStress

    public init(_ joint: Joint, _ stress: JointStress) {
        self.joint = joint
        self.stress = stress
    }
}

/// How an exercise may be taken to failure.
public enum SafetyTier: String, Codable, Sendable, CaseIterable, Comparable {
    /// Machines and cables with stops: anyone may rep out to genuine failure from day one.
    case safeToFail
    /// Barbell lifts in a rack with pins set, and deadlifts: for experienced or trusted lifters.
    case failWithSetup
    /// No safe bail-out: never taken to failure.
    case neverToFailure

    public static func < (a: SafetyTier, b: SafetyTier) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }

    public var label: String {
        switch self {
        case .safeToFail: "Safe to fail"
        case .failWithSetup: "Fail with setup"
        case .neverToFailure: "Never to failure"
        }
    }
}

/// Stimulus and fatigue per hard set, after Renaissance Periodization's stimulus-to-fatigue ratio.
/// Systemic fatigue (deadlifts, squats) is slow to clear and shared by everything; local fatigue
/// (arms, delts) is cheap and quick to recover.
public struct FatigueProfile: Hashable, Codable, Sendable {
    /// 0–1; a conventional deadlift is about 1.
    public var systemic: Double
    /// 0–1; muscle and joint cost to the muscles trained.
    public var local: Double
    /// 0–1; how much growth or strength signal a hard set gives its primary muscles.
    public var stimulus: Double
    /// How much more a set taken to failure costs than one stopped short. Deadlifts are high.
    public var failureMultiplier: Double

    public init(systemic: Double, local: Double, stimulus: Double, failureMultiplier: Double = 1.3) {
        self.systemic = systemic
        self.local = local
        self.stimulus = stimulus
        self.failureMultiplier = failureMultiplier
    }

    /// Stimulus per unit of fatigue, systemic counted most because it's the scarce budget.
    public var sfr: Double { stimulus / max(0.08, systemic * 0.75 + local * 0.25) }

    public static let none = FatigueProfile(systemic: 0, local: 0, stimulus: 0, failureMultiplier: 1)
}

/// Lift categories scored against bodyweight-relative standards, Symmetric Strength style.
public enum StrengthCategory: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable, Identifiable {
    case squat, floorPull, horizontalPress, inclinePress, verticalPress, verticalPull, horizontalPull

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .squat: "Squat"
        case .floorPull: "Deadlift"
        case .horizontalPress: "Bench press"
        case .inclinePress: "Incline press"
        case .verticalPress: "Overhead press"
        case .verticalPull: "Pull-up"
        case .horizontalPull: "Row"
        }
    }

    public enum Region: String, Codable, Sendable, CaseIterable {
        case lower, upperPush, upperPull

        public var label: String {
            switch self {
            case .lower: "Legs"
            case .upperPush: "Upper-body pushing"
            case .upperPull: "Upper-body pulling"
            }
        }
    }

    public var region: Region {
        switch self {
        case .squat, .floorPull: .lower
        case .horizontalPress, .inclinePress, .verticalPress: .upperPush
        case .verticalPull, .horizontalPull: .upperPull
        }
    }

    public var patterns: [MovementPattern] {
        switch self {
        case .squat: [.squat]
        case .floorPull: [.hinge]
        case .horizontalPress: [.horizontalPress]
        case .inclinePress: [.inclinePress]
        case .verticalPress: [.verticalPress]
        case .verticalPull: [.verticalPull]
        case .horizontalPull: [.horizontalRow]
        }
    }
}

/// How an exercise's logged load counts toward a strength category. Only free-weight variants with
/// a known ratio to the reference lift are mapped; machine weights are never converted, because
/// leverage differs by machine and brand.
public struct StrengthMapping: Hashable, Codable, Sendable {
    public var category: StrengthCategory
    /// The reference lift's estimated 1RM per kg of this exercise's estimated 1RM (effective load).
    public var factor: Double

    public init(_ category: StrengthCategory, factor: Double = 1) {
        self.category = category
        self.factor = factor
    }
}

/// What a logged load means.
public enum LoadBasis: String, Codable, Sendable {
    /// The weight on the bar, the pin or the sled.
    case external
    /// One dumbbell or kettlebell; there may be two.
    case perHand
    /// Load added to the body (belt, vest); the body itself counts.
    case bodyweightPlus
    /// Assistance taken off the body (assisted pull-up machine, band).
    case assisted
    /// No load: timed or counted.
    case none
}

/// Where a mobility drill or test points.
public enum MobilityTarget: String, CaseIterable, Codable, Sendable, Identifiable {
    case hips, ankles, hamstrings, shoulders, thoracicSpine

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .hips: "Hips"
        case .ankles: "Ankles"
        case .hamstrings: "Hamstrings"
        case .shoulders: "Shoulders"
        case .thoracicSpine: "Upper back"
        }
    }
}

/// The traits the core's logic needs from an exercise. The exercise library provides them.
public protocol ExerciseTraits: Sendable {
    var id: String { get }
    var name: String { get }
    var pattern: MovementPattern { get }
    var equipment: Equipment { get }
    var muscles: [MuscleShare] { get }
    var joints: [JointLoad] { get }
    var fatigue: FatigueProfile { get }
    var safetyTier: SafetyTier { get }
    var strength: StrengthMapping? { get }
    var loadBasis: LoadBasis { get }
}

extension ExerciseTraits {
    public func weight(of muscle: Muscle) -> Double { muscles.first { $0.muscle == muscle }?.weight ?? 0 }
    public var primaryMuscles: [Muscle] { muscles.filter { $0.weight >= 1 }.map(\.muscle) }
    public var isCompound: Bool { pattern.isCompound && muscles.count > 1 }
    public func stress(on joint: Joint) -> JointStress? { joints.first { $0.joint == joint }?.stress }
}
