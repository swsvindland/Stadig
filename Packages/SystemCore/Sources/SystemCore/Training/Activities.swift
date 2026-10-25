import Foundation

/// The stats of the System. Technique and Craft are shelved; Social is never scored. There is no
/// overall level: each stat moves only on real-world outcomes.
public enum StatKind: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable, Identifiable {
    case strength, physique, endurance, vitality, agility, discipline, intelligence, wisdom

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .strength: "Strength"
        case .physique: "Physique"
        case .endurance: "Endurance"
        case .vitality: "Vitality"
        case .agility: "Agility"
        case .discipline: "Discipline"
        case .intelligence: "Intelligence"
        case .wisdom: "Wisdom"
        }
    }

    public var symbol: String {
        switch self {
        case .strength: "dumbbell.fill"
        case .physique: "figure.arms.open"
        case .endurance: "heart.fill"
        case .vitality: "bed.double.fill"
        case .agility: "figure.flexibility"
        case .discipline: "calendar.badge.checkmark"
        case .intelligence: "brain.head.profile"
        case .wisdom: "book.closed.fill"
        }
    }
}

/// Training that happens outside Stadig Lift: imported from Health, declared on a schedule, or
/// logged by hand. Each kind has a default fatigue cost, refined from feedback over time.
public enum ActivityType: String, CaseIterable, Codable, Sendable, Identifiable {
    case running, cycling, spin, swimming, rowing, walking, hiking, stairs
    case bjj, muayThai, boxing, wrestling, judo, mma
    case yoga, hotYoga, pilates, mobility
    case hiit, climbing, teamSport, racquet, dance, strength, other

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .running: "Running"
        case .cycling: "Cycling"
        case .spin: "Spin class"
        case .swimming: "Swimming"
        case .rowing: "Rowing"
        case .walking: "Walking"
        case .hiking: "Hiking"
        case .stairs: "Stairs"
        case .bjj: "BJJ"
        case .muayThai: "Muay Thai"
        case .boxing: "Boxing"
        case .wrestling: "Wrestling"
        case .judo: "Judo"
        case .mma: "MMA"
        case .yoga: "Yoga"
        case .hotYoga: "Hot yoga"
        case .pilates: "Pilates"
        case .mobility: "Mobility"
        case .hiit: "HIIT"
        case .climbing: "Climbing"
        case .teamSport: "Team sport"
        case .racquet: "Racquet sport"
        case .dance: "Dance"
        case .strength: "Other strength training"
        case .other: "Other"
        }
    }

    public var symbol: String {
        switch self {
        case .running: "figure.run"
        case .cycling, .spin: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        case .rowing: "figure.rower"
        case .walking: "figure.walk"
        case .hiking: "figure.hiking"
        case .stairs: "figure.stair.stepper"
        case .bjj, .judo, .wrestling: "figure.wrestling"
        case .muayThai, .mma: "figure.kickboxing"
        case .boxing: "figure.boxing"
        case .yoga, .hotYoga: "figure.yoga"
        case .pilates: "figure.pilates"
        case .mobility: "figure.flexibility"
        case .hiit: "figure.highintensity.intervaltraining"
        case .climbing: "figure.climbing"
        case .teamSport: "figure.soccer"
        case .racquet: "figure.tennis"
        case .dance: "figure.dance"
        case .strength: "figure.strengthtraining.functional"
        case .other: "figure.mixed.cardio"
        }
    }

    public var isMartialArt: Bool { [.bjj, .muayThai, .boxing, .wrestling, .judo, .mma].contains(self) }

    /// A watch can't be worn: logged by hand after class.
    public var usuallyWatchFree: Bool { isMartialArt || [.hotYoga, .spin].contains(self) }

    /// RPE on a typical day, 1–10.
    public var typicalIntensity: Int {
        switch self {
        case .walking, .yoga, .mobility, .pilates: 3
        case .hiking, .hotYoga, .dance, .stairs: 5
        case .running, .cycling, .swimming, .rowing, .climbing, .racquet, .strength, .other: 6
        case .spin, .teamSport, .judo, .boxing: 7
        case .bjj, .muayThai, .wrestling, .mma, .hiit: 8
        }
    }

    /// Fatigue for an hour at typical intensity, in the same units as a lifting session's sets
    /// (one hard set of a heavy compound is about 1 systemic unit).
    public var hourlyFatigue: FatigueLoad {
        switch self {
        case .running: FatigueLoad(systemic: 4, local: [.legs: 5])
        case .cycling: FatigueLoad(systemic: 3, local: [.legs: 4])
        case .spin: FatigueLoad(systemic: 3.5, local: [.legs: 4.5])
        case .swimming: FatigueLoad(systemic: 3, local: [.pull: 3, .push: 2])
        case .rowing: FatigueLoad(systemic: 3.5, local: [.pull: 3, .legs: 3])
        case .walking: FatigueLoad(systemic: 0.5, local: [.legs: 0.5])
        case .hiking: FatigueLoad(systemic: 2, local: [.legs: 3])
        case .stairs: FatigueLoad(systemic: 3, local: [.legs: 4])
        case .bjj, .wrestling, .judo: FatigueLoad(systemic: 6, local: [.pull: 3, .core: 3, .legs: 2])
        case .muayThai, .mma: FatigueLoad(systemic: 6, local: [.legs: 4, .push: 2, .core: 2])
        case .boxing: FatigueLoad(systemic: 5, local: [.push: 3, .legs: 2])
        case .yoga, .mobility, .pilates: FatigueLoad(systemic: 0.5, local: [.core: 1])
        case .hotYoga: FatigueLoad(systemic: 1.5, local: [.core: 1, .legs: 1])
        case .hiit: FatigueLoad(systemic: 5, local: [.legs: 3, .push: 1.5])
        case .climbing: FatigueLoad(systemic: 3, local: [.pull: 5])
        case .teamSport: FatigueLoad(systemic: 5, local: [.legs: 4])
        case .racquet: FatigueLoad(systemic: 3.5, local: [.legs: 2.5, .push: 1])
        case .dance: FatigueLoad(systemic: 2, local: [.legs: 2])
        case .strength: FatigueLoad(systemic: 4, local: [.push: 2, .pull: 2, .legs: 2])
        case .other: FatigueLoad(systemic: 3, local: [:])
        }
    }

    /// Which stats an hour of this feeds, and how much.
    public var statCredit: [StatKind: Double] {
        switch self {
        case .running, .cycling, .spin, .swimming, .rowing, .stairs, .hiit: [.endurance: 1]
        case .walking, .hiking: [.endurance: 0.5, .vitality: 0.3]
        case .bjj, .muayThai, .boxing, .wrestling, .judo, .mma: [.endurance: 1, .agility: 0.2]
        case .yoga, .hotYoga, .mobility: [.agility: 1]
        case .pilates: [.agility: 0.6, .strength: 0.2]
        case .climbing: [.strength: 0.4, .endurance: 0.4, .agility: 0.2]
        case .teamSport, .racquet, .dance: [.endurance: 0.8, .agility: 0.2]
        case .strength: [.strength: 0.5]
        case .other: [.endurance: 0.5]
        }
    }

    /// What it loosens, for mobility credit.
    public var mobilityCredit: [MobilityTarget] {
        switch self {
        case .yoga, .hotYoga: [.hips, .hamstrings, .shoulders, .thoracicSpine]
        case .mobility: MobilityTarget.allCases
        case .pilates: [.hips, .thoracicSpine]
        default: []
        }
    }
}

/// Fatigue as the core counts it: a systemic number plus local cost per body region.
public struct FatigueLoad: Hashable, Codable, Sendable {
    public var systemic: Double
    public var local: [Muscle.Region: Double]

    public init(systemic: Double = 0, local: [Muscle.Region: Double] = [:]) {
        self.systemic = systemic
        self.local = local
    }

    public static let zero = FatigueLoad()

    public static func + (a: FatigueLoad, b: FatigueLoad) -> FatigueLoad {
        FatigueLoad(systemic: a.systemic + b.systemic, local: a.local.merging(b.local, uniquingKeysWith: +))
    }

    public func scaled(_ factor: Double) -> FatigueLoad {
        FatigueLoad(systemic: systemic * factor, local: local.mapValues { $0 * factor })
    }

    public var totalLocal: Double { local.values.reduce(0, +) }
}

public enum ActivitySource: Codable, Hashable, Sendable {
    /// Imported from Apple Health, by the sample's UUID so it's never imported twice.
    case health(UUID, sourceName: String)
    case manual
    /// Logged against a recurring declaration ("BJJ Tue/Thu").
    case declared(UUID)
}

public enum MartialArtsClass: String, CaseIterable, Codable, Sendable, Identifiable {
    case technique, drilling, sparring, openMat, conditioning

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .technique: "Technique"
        case .drilling: "Drilling"
        case .sparring: "Sparring"
        case .openMat: "Open mat"
        case .conditioning: "Conditioning"
        }
    }

    /// Fatigue relative to a typical class.
    public var fatigueFactor: Double {
        switch self {
        case .technique: 0.6
        case .drilling: 0.8
        case .sparring: 1.25
        case .openMat: 1.1
        case .conditioning: 1.2
        }
    }
}

/// The quick post-class log for martial arts, where no wearable can come along.
public struct MartialArtsDetails: Hashable, Codable, Sendable {
    public var classType: MartialArtsClass
    public var sparringRounds: Int
    /// Rounds before feeling gassed; nil when they never did.
    public var roundsBeforeGassed: Int?

    public init(classType: MartialArtsClass, sparringRounds: Int = 0, roundsBeforeGassed: Int? = nil) {
        self.classType = classType
        self.sparringRounds = sparringRounds
        self.roundsBeforeGassed = roundsBeforeGassed
    }
}

public struct ActivityLog: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var type: ActivityType
    public var start: Date
    public var minutes: Int
    /// RPE 1–10.
    public var intensity: Int
    public var source: ActivitySource
    public var averageHeartRate: Double?
    public var distanceMeters: Double?
    public var martialArts: MartialArtsDetails?
    public var note: String

    public init(
        id: UUID = UUID(), type: ActivityType, start: Date, minutes: Int, intensity: Int? = nil,
        source: ActivitySource = .manual, averageHeartRate: Double? = nil, distanceMeters: Double? = nil,
        martialArts: MartialArtsDetails? = nil, note: String = ""
    ) {
        self.id = id
        self.type = type
        self.start = start
        self.minutes = max(1, minutes)
        self.intensity = clamp(intensity ?? type.typicalIntensity, 1, 10)
        self.source = source
        self.averageHeartRate = averageHeartRate
        self.distanceMeters = distanceMeters
        self.martialArts = martialArts
        self.note = note
    }

    public var day: Day { Day(start) }

    /// Fatigue from the activity's default mapping, scaled by duration, intensity and class type.
    public var fatigue: FatigueLoad {
        let hours = Double(minutes) / 60
        let intensityFactor = pow(Double(intensity) / Double(type.typicalIntensity), 1.5)
        let classFactor = martialArts?.classType.fatigueFactor ?? 1
        let sparring = Double(martialArts?.sparringRounds ?? 0) * 0.3
        let base = type.hourlyFatigue.scaled(hours * intensityFactor * classFactor)
        return base + FatigueLoad(systemic: sparring)
    }

    public var statCredit: [StatKind: Double] {
        type.statCredit.mapValues { $0 * Double(minutes) / 60 }
    }
}
