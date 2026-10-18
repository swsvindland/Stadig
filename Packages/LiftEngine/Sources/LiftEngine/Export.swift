import ExerciseLibrary
import Foundation
import SystemCore

/// A table for CSV export: your data, portable.
public struct ExportTable: Sendable {
    public var name: String
    public var header: [String]
    public var rows: [[String]]
}

public enum Export {
    static func number(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }

    static func date(_ date: Date) -> String { date.ISO8601Format() }

    public static func tables(_ state: LiftState) -> [ExportTable] {
        let catalog = state.catalog
        let sets = ExportTable(
            name: "sets",
            header: [
                "session_id", "session_start", "session", "exercise_id", "exercise", "set", "kind", "load_kg", "reps", "target_reps",
                "rating", "bodyweight_kg", "rest_before_s", "hr_peak", "hr_drop_60s", "seconds",
            ],
            rows: state.sessions.sorted { $0.start < $1.start }.flatMap { session in
                session.exercises.flatMap { log in
                    log.sets.enumerated().map { index, set in
                        // The set's own exercise: a log saved before mid-exercise swaps were split holds two.
                        [
                            session.id.uuidString, date(session.start), session.title, set.exerciseID, catalog.resolve(set.exerciseID).name,
                            String(index + 1), set.kind.rawValue, number(set.loadKg), String(set.reps), set.targetReps.map(String.init) ?? "",
                            set.rating?.label ?? "", number(set.bodyweightKg), set.restBeforeSeconds.map(String.init) ?? "",
                            number(set.heartRatePeak), number(set.heartRateDrop60), set.seconds.map(String.init) ?? "",
                        ]
                    }
                }
            })
        let sessions = ExportTable(
            name: "sessions",
            header: [
                "session_id", "start", "end", "title", "planned", "deload", "work_sets", "conditioning_min", "soreness", "joint_pain",
                "energy", "device", "avg_hr",
            ],
            rows: state.sessions.sorted { $0.start < $1.start }.map { s in
                [
                    s.id.uuidString, date(s.start), date(s.end), s.title, s.planned ? "yes" : "no", s.deload ? "yes" : "no",
                    String(s.workSets.count), String(s.conditioning.map(\.minutes).reduce(0, +)), s.feedback.map { String($0.soreness) } ?? "",
                    s.feedback?.jointPain.map(\.rawValue).joined(separator: ";") ?? "", s.feedback.map { String($0.energy) } ?? "", s.device,
                    number(s.averageHeartRate),
                ]
            })
        let activities = ExportTable(
            name: "outside-activities",
            header: [
                "id", "start", "type", "minutes", "intensity", "source", "avg_hr", "distance_m", "class", "sparring_rounds",
                "rounds_before_gassed", "note",
            ],
            rows: state.activities.sorted { $0.start < $1.start }.map { a in
                let source =
                    switch a.source {
                    case .health(_, let name): "Health (\(name))"
                    case .manual: "Manual"
                    case .declared: "Declared"
                    }
                return [
                    a.id.uuidString, date(a.start), a.type.label, String(a.minutes), String(a.intensity), source, number(a.averageHeartRate),
                    number(a.distanceMeters), a.martialArts?.classType.label ?? "", a.martialArts.map { String($0.sparringRounds) } ?? "",
                    a.martialArts?.roundsBeforeGassed.map(String.init) ?? "", a.note,
                ]
            })
        let measurements = ExportTable(
            name: "measurements",
            // arm_cm, thigh_cm and calf_cm are readings from before both sides were measured.
            header: [
                "day", "weight_kg", "body_fat_pct", "neck_cm", "shoulders_cm", "chest_cm", "waist_navel_cm", "waist_narrowest_cm",
                "hips_cm", "glutes_cm", "arm_left_cm", "arm_right_cm", "thigh_left_cm", "thigh_right_cm", "calf_left_cm", "calf_right_cm",
                "arm_cm", "thigh_cm", "calf_cm", "note",
            ],
            rows: state.measurements.sorted { $0.day < $1.day }.map { m in
                [
                    m.day.iso, number(m.weightKg), number(m.bodyFatPercent), number(m.neckCm), number(m.shouldersCm), number(m.chestCm),
                    number(m.waistCm), number(m.naturalWaistCm), number(m.hipsCm), number(m.glutesCm), number(m.armLeftCm), number(m.armRightCm),
                    number(m.thighLeftCm), number(m.thighRightCm), number(m.calfLeftCm), number(m.calfRightCm), number(m.armCm),
                    number(m.thighCm), number(m.calfCm), m.note,
                ]
            })
        let tests = ExportTable(
            name: "tests",
            header: ["day", "test", "value", "unit", "painful"],
            rows: state.mobility.sorted { $0.day < $1.day }.map {
                [$0.day.iso, $0.test.label, number($0.value), $0.test.unit, $0.painful ? "yes" : "no"]
            }
                + state.benchmarks.sorted { $0.day < $1.day }.map { b in
                    let unit =
                        switch b.benchmark.measure {
                        case .timeSeconds: "s"
                        case .distanceMeters: "m"
                        case .floors: "floors"
                        }
                    return [b.day.iso, b.benchmark.label, number(b.value), unit, ""]
                })
        return [sessions, sets, activities, measurements, tests]
    }
}
