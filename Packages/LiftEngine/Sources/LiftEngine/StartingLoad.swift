import Foundation
import ExerciseLibrary
import SystemCore

/// A first guess at a working weight for an exercise with no history, so the weight starts near
/// the right place instead of at an empty bar: from the strength standards for scored lifts, else
/// typical ratios to bodyweight for the movement and equipment, scaled for experience and sex.
/// On the light side on purpose; the rating after the first set corrects it.
public enum StartingLoad {
    /// The load to enter (per hand for dumbbells), in kg; nil for bodyweight and band work.
    public static func estimate(_ exercise: Exercise, reps: Int, bodyweightKg: Double?, sex: BiologicalSex,
                                experience: TrainingExperience) -> Double? {
        guard exercise.loadBasis == .external || exercise.loadBasis == .perHand else { return nil }
        let bodyweight = bodyweightKg ?? (sex == .female ? 65 : 80)
        let reps = Double(min(20, max(1, reps)))
        if let mapping = exercise.strength {
            let score: Double = switch experience {
            case .novice: 30
            case .intermediate: 50
            case .experienced: 65
            }
            let reference = StrengthStandards.oneRepMax(for: score, mapping.category, bodyweightKg: bodyweight, sex: sex)
            let load = reference / mapping.factor / (1 + reps / 30) * 0.9
            return OneRepMax.loggedLoad(forEffective: load, basis: exercise.loadBasis, bodyweightKg: bodyweight)
        }
        guard let ratio = tenRepRatio(exercise) else { return nil }
        let level: Double = switch experience {
        case .novice: 0.7
        case .intermediate: 1
        case .experienced: 1.25
        }
        let sexFactor: Double = switch sex {
        case .female: exercise.pattern.isLowerBody ? 0.75 : 0.55
        case .male: 1
        default: 0.85
        }
        // Ratios are for ten reps; Epley moves them to the reps asked for.
        let reach = (1 + 10.0 / 30) / (1 + reps / 30)
        return bodyweight * ratio * level * sexFactor * reach * 0.9
    }

    /// The load for ten reps per kg of bodyweight for an intermediate man, per hand for dumbbells.
    static func tenRepRatio(_ e: Exercise) -> Double? {
        let eq = e.equipment
        let bar = eq == .barbell || eq == .ezBar || eq == .trapBar
        let stack = eq == .machine || eq == .plateLoaded
        let db = eq == .dumbbell || eq == .kettlebell
        let pattern: Double? = switch e.pattern {
        case .horizontalPress: bar || eq == .smith ? 0.65 : db ? 0.25 : stack ? 0.6 : 0.3
        case .inclinePress: bar || eq == .smith ? 0.55 : db ? 0.22 : stack ? 0.5 : 0.25
        case .verticalPress: bar || eq == .smith ? 0.4 : db ? 0.17 : 0.4
        case .chestFly: db ? 0.1 : eq == .cable ? 0.15 : 0.35
        case .horizontalRow: db ? 0.3 : 0.6
        case .verticalPull: 0.65
        case .pullover: db ? 0.25 : 0.3
        case .shrug: db ? 0.35 : 1.0
        case .lateralRaise: stack ? 0.25 : 0.06
        case .frontRaise: bar ? 0.2 : 0.07
        case .rearDeltFly: stack ? 0.25 : 0.05
        case .facePull: 0.25
        case .curl: bar ? 0.3 : db ? 0.12 : 0.25
        case .tricepsExtension: bar ? 0.25 : db ? 0.1 : 0.3
        case .squat: bar ? 0.9 : eq == .smith ? 0.8 : db ? 0.25 : 1.0
        case .lunge: db ? 0.2 : 0.45
        case .legPress: 1.6
        case .hinge: eq == .trapBar ? 1.1 : bar ? 0.75 : db ? 0.3 : 0.3
        case .hipThrust: 1.0
        case .legExtension: 0.45
        case .legCurl: 0.35
        case .backExtension: 0.4
        case .hipAdduction, .hipAbduction: 0.45
        case .calfRaise: db ? 0.25 : bar ? 0.7 : 0.9
        case .crunch: 0.35
        case .wrist: bar ? 0.25 : 0.06
        case .carry: eq == .trapBar ? 1.2 : 0.4
        case .core, .legRaise: eq == .cable ? 0.15 : nil
        default: nil
        }
        if let pattern { return pattern }
        return switch eq {
        case .dumbbell, .kettlebell: 0.15
        case .cable: 0.3
        case .machine: 0.4
        case .plateLoaded: 0.8
        case .barbell, .smith, .ezBar, .trapBar: 0.5
        default: nil
        }
    }
}
