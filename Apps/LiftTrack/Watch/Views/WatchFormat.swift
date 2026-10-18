import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

/// Numbers as people read them on the wrist. Loads are shown in the gym's unit.
enum WatchFormat {
    static func number(_ value: Double, digits: Int = 2) -> String {
        value.formatted(.number.precision(.fractionLength(0...digits)))
    }

    /// "82.5 kg"; "20 kg each" per hand; bodyweight work "Bodyweight" or "+10 kg"; assisted "20 kg assist".
    static func load(_ kg: Double?, unit: WeightUnit, basis: LoadBasis) -> String {
        guard let kg else { return "Pick a weight" }
        let value = "\(number(unit.fromKilograms(kg))) \(unit.symbol)"
        switch basis {
        case .external: return value
        case .perHand: return "\(value) each"
        case .bodyweightPlus: return kg <= 0 ? "Bodyweight" : "+\(value)"
        case .assisted: return kg <= 0 ? "Bodyweight" : "\(value) assist"
        case .none: return ""
        }
    }

    /// "80 kg × 8", "8 reps", or "45 s" for timed work.
    static func prescription(_ prescription: SetPrescription, exercise: Exercise, unit: WeightUnit, plannedSeconds: Int? = nil) -> String {
        if exercise.timed || exercise.kind != .strength, let seconds = prescription.seconds ?? plannedSeconds {
            guard exercise.loadBasis != .none, exercise.kind == .strength else { return duration(seconds) }
            return "\(load(prescription.loadKg, unit: unit, basis: exercise.loadBasis)) · \(duration(seconds))"
        }
        if exercise.loadBasis == .none { return "\(prescription.targetReps) reps" }
        return "\(load(prescription.loadKg, unit: unit, basis: exercise.loadBasis)) × \(prescription.targetReps)"
    }

    /// A set as it was done, the same way.
    static func logged(_ set: LoggedSet, exercise: Exercise, unit: WeightUnit) -> String {
        if exercise.timed || exercise.kind != .strength, let seconds = set.seconds {
            guard exercise.loadBasis != .none, exercise.kind == .strength else { return duration(seconds) }
            return "\(load(set.loadKg, unit: unit, basis: exercise.loadBasis)) · \(duration(seconds))"
        }
        if exercise.loadBasis == .none { return "\(set.reps) reps" }
        return "\(load(set.loadKg, unit: unit, basis: exercise.loadBasis)) × \(set.reps)"
    }

    /// "1:05".
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    /// "45 s", "5 min", "1:30".
    static func duration(_ seconds: Int) -> String {
        guard seconds >= 60 else { return "\(seconds) s" }
        return seconds % 60 == 0 ? "\(seconds / 60) min" : clock(seconds)
    }

    /// "Warm-up 1 of 2" or "Set 2 of 3": warm-ups and work are counted apart.
    static func setPosition(_ index: Int, in sets: [LiveSet]) -> String {
        let warmup = sets[index].prescription.kind == .warmup
        let group = sets.indices.filter { (sets[$0].prescription.kind == .warmup) == warmup }
        let position = (group.firstIndex(of: index) ?? 0) + 1
        return warmup ? "Warm-up \(position) of \(group.count)" : "Set \(position) of \(group.count)"
    }

    /// What a set asks for, in a few words.
    static func hint(_ prescription: SetPrescription) -> String {
        switch prescription.kind {
        case .warmup: return "Ramp-up set. Keep it easy."
        case .findingWeight:
            return prescription.loadKg == nil
                ? "Pick a weight you think you can do for \(prescription.targetReps)."
                : "Finding your weight. Rate it honestly."
        case .repOut:
            return prescription.stopAtFormBreakdown ? "Rep-out: as many as you can, stop when form breaks." : "Rep-out: as many as you can."
        case .deload: return "Deload: nowhere near failure."
        case .working:
            let reserve = Int(prescription.targetRIR.rounded())
            return reserve == 0 ? "Close to failure." : "Leave about \(reserve) in the tank."
        }
    }
}

extension SetRating {
    /// The rating's colour; it always travels with its symbol and label.
    var tint: Color {
        switch self {
        case .green: .green
        case .orange: .orange
        case .red: .red
        }
    }
}

extension HeartRateZones {
    /// Zone colours as Apple Workout shows them.
    static func tint(for zone: Int) -> Color {
        switch zone {
        case ...1: .blue
        case 2: .green
        case 3: .yellow
        case 4: .orange
        default: .red
        }
    }
}
