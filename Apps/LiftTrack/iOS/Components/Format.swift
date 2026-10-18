import ExerciseLibrary
import Foundation
import LiftEngine
import SystemCore

/// Numbers as people read them: loads in the gym's unit, lengths in the person's.
enum Format {
    static func number(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(0...digits)))
    }

    /// "82.5 kg"; bodyweight exercises read "Bodyweight" or "+10 kg", assisted "−20 kg assist".
    static func load(_ kg: Double?, unit: WeightUnit, basis: LoadBasis = .external) -> String {
        guard let kg else { return "Pick a weight" }
        let value = number(unit.fromKilograms(kg), digits: 2)
        switch basis {
        case .bodyweightPlus: return kg <= 0 ? "Bodyweight" : "+\(value) \(unit.symbol)"
        case .assisted: return kg <= 0 ? "Bodyweight" : "\(value) \(unit.symbol) assist"
        case .none: return ""
        case .perHand: return "\(value) \(unit.symbol) each"
        case .external: return "\(value) \(unit.symbol)"
        }
    }

    static func weight(_ kg: Double?, unit: WeightUnit) -> String {
        guard let kg else { return "—" }
        return "\(number(unit.fromKilograms(kg))) \(unit.symbol)"
    }

    static func length(_ cm: Double?, unit: LengthUnit) -> String {
        guard let cm else { return "—" }
        return "\(number(unit.fromCentimetres(cm))) \(unit.symbol)"
    }

    /// "82.5 kg × 5", or "45 s" for timed work.
    static func set(_ prescription: SetPrescription, exercise: Exercise, unit: WeightUnit) -> String {
        if let seconds = prescription.seconds, exercise.timed || exercise.kind != .strength { return duration(seconds) }
        if exercise.loadBasis == .none { return "\(prescription.targetReps) reps" }
        return "\(load(prescription.loadKg, unit: unit, basis: exercise.loadBasis)) × \(prescription.targetReps)"
    }

    static func logged(_ set: LoggedSet, exercise: Exercise, unit: WeightUnit) -> String {
        if let seconds = set.seconds, exercise.timed || exercise.kind != .strength { return duration(seconds) }
        if exercise.loadBasis == .none { return "\(set.reps) reps" }
        return "\(load(set.loadKg, unit: unit, basis: exercise.loadBasis)) × \(set.reps)"
    }

    /// "190°F" or "88°C".
    static func temperature(_ celsius: Double, fahrenheit: Bool) -> String {
        fahrenheit ? "\(Int((celsius * 9 / 5 + 32).rounded()))°F" : "\(Int(celsius.rounded()))°C"
    }

    static func duration(_ seconds: Int) -> String {
        if seconds >= 60 {
            let m = seconds / 60
            let s = seconds % 60
            return s == 0 ? "\(m) min" : "\(m):\(String(format: "%02d", s))"
        }
        return "\(seconds) s"
    }

    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    static func day(_ day: Day, style: Date.FormatStyle = .dateTime.weekday(.abbreviated).month(.abbreviated).day()) -> String {
        day.date().formatted(style)
    }

    static func range(_ range: DayRange) -> String {
        "\(day(range.start, style: .dateTime.month(.abbreviated).day())) – \(day(range.end, style: .dateTime.month(.abbreviated).day()))"
    }

    static func percent(_ value: Double) -> String { value.formatted(.percent.precision(.fractionLength(0))) }

    static func rir(_ value: Double) -> String {
        value == 0 ? "to failure" : "\(number(value)) in reserve"
    }

    static func benchmark(_ value: Double, _ benchmark: EnduranceBenchmark) -> String {
        switch benchmark.measure {
        case .timeSeconds: clock(Int(value))
        case .distanceMeters: "\(number(value, digits: 0)) m"
        case .floors: "\(number(value, digits: 0)) floors"
        }
    }

    static func mobility(_ value: Double, _ test: MobilityTest) -> String {
        switch test.measure {
        case .quality: MobilityTest.qualityLabels[clamp(Int(value), 0, 3)]
        case .seconds: "\(number(value, digits: 0)) s"
        case .centimetres: "\(number(value)) cm"
        }
    }
}
