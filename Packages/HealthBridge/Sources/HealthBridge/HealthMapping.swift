#if canImport(HealthKit)
import HealthKit
import SystemCore

/// Translation between the System's activity kinds and HealthKit workout types.
public enum HealthMapping {
    /// The activity a Health workout counts as. Types with no close match become `.other`.
    public static func activityType(for workoutType: HKWorkoutActivityType) -> ActivityType {
        switch workoutType {
        case .running, .wheelchairRunPace, .trackAndField: .running
        case .cycling, .handCycling: .cycling
        case .swimming, .waterFitness: .swimming
        case .rowing, .paddleSports: .rowing
        case .walking, .wheelchairWalkPace: .walking
        case .hiking: .hiking
        case .stairClimbing, .stairs, .stepTraining: .stairs
        case .martialArts: .bjj
        case .kickboxing: .muayThai
        case .boxing: .boxing
        case .wrestling: .wrestling
        case .yoga: .yoga
        case .pilates, .barre: .pilates
        case .flexibility, .preparationAndRecovery, .cooldown, .mindAndBody, .taiChi: .mobility
        case .highIntensityIntervalTraining, .crossTraining, .jumpRope: .hiit
        case .climbing: .climbing
        case .soccer, .basketball, .americanFootball, .australianFootball, .baseball, .softball, .cricket,
            .handball, .hockey, .lacrosse, .rugby, .volleyball, .waterPolo, .discSports:
            .teamSport
        case .tennis, .badminton, .squash, .racquetball, .tableTennis, .pickleball: .racquet
        case .cardioDance, .socialDance: .dance
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining: .strength
        default: .other
        }
    }

    /// The Health workout type to record an activity as.
    public static func workoutType(for activity: ActivityType) -> HKWorkoutActivityType {
        switch activity {
        case .running: .running
        case .cycling, .spin: .cycling
        case .swimming: .swimming
        case .rowing: .rowing
        case .walking: .walking
        case .hiking: .hiking
        case .stairs: .stairClimbing
        case .bjj, .judo, .mma: .martialArts
        case .muayThai: .kickboxing
        case .boxing: .boxing
        case .wrestling: .wrestling
        case .yoga, .hotYoga: .yoga
        case .pilates: .pilates
        case .mobility: .flexibility
        case .hiit: .highIntensityIntervalTraining
        case .climbing: .climbing
        case .teamSport: .soccer
        case .racquet: .tennis
        case .dance: .cardioDance
        case .strength: .traditionalStrengthTraining
        case .other: .other
        }
    }
}
#endif
