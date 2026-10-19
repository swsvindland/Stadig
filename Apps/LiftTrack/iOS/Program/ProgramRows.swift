import ExerciseLibrary
import Foundation
import LiftEngine
import SystemCore

/// One slot of a block as the Program table shows it, its columns already worked out.
struct ProgramRow: Identifiable, Hashable {
    /// The slot's id: unique across every block, so one selection serves two tables side by side.
    let id: UUID
    let dayID: UUID
    let exerciseID: String
    let exercise: String
    let role: String
    let blockKind: SessionBlockKind
    /// "3·3·4·4 · 2"; conditioning's minutes and zone; empty for drills and the sauna.
    let sets: String
    let reps: String
    let rest: String
    /// "A", "B": slots that share a letter are done as a superset.
    let superset: String
    let why: String
    /// Set aside in Library: today's session swaps it out.
    let setAside: Bool
    let isStrength: Bool
}

/// A day of the block and its rows.
struct ProgramDay: Identifiable, Hashable {
    let id: UUID
    let name: String
    let minutes: Int
    let isNext: Bool
    let rows: [ProgramRow]
}

enum ProgramRows {
    /// Every day of a block and its slots, in the plan's order.
    static func days(of mesocycle: Mesocycle, nextDayID: UUID?, catalog: ExerciseCatalog, avoid: Set<String>) -> [ProgramDay] {
        mesocycle.days.map { day in
            let groups = Array(Set(day.slots.compactMap(\.supersetGroup))).sorted()
            let rows = day.blocks.flatMap { block in
                block.slots.map { slot in
                    row(slot, in: block.kind, day: day, block: mesocycle.block, groups: groups, catalog: catalog, avoid: avoid)
                }
            }
            return ProgramDay(id: day.id, name: day.name, minutes: day.minutes, isNext: day.id == nextDayID, rows: rows)
        }
    }

    static func row(
        _ slot: SlotPlan, in kind: SessionBlockKind, day: PlannedDay, block: TrainingBlock, groups: [Int], catalog: ExerciseCatalog,
        avoid: Set<String>
    ) -> ProgramRow {
        let exercise = catalog.resolve(slot.exerciseID)
        let strength = slot.role == .main || slot.role == .accessory
        // Conditioning's minutes and zone where the sets go: its reps column has nothing to say.
        let reps: String =
            if slot.conditioning != nil {
                ""
            } else if strength {
                slot.repRange.label
            } else if let seconds = slot.seconds {
                Format.duration(seconds)
            } else {
                ""
            }
        let letter = slot.supersetGroup.flatMap { groups.firstIndex(of: $0) }.map { String(UnicodeScalar(UInt8(65 + $0 % 26))) } ?? ""
        var why = slot.reason ?? defaultReason(slot.role)
        if let filler = slot.restFiller { why += " In the rests: \(catalog.resolve(filler).name)." }
        return ProgramRow(
            id: slot.id, dayID: day.id, exerciseID: exercise.id, exercise: exercise.name, role: kind.label, blockKind: kind,
            sets: slot.conditioning?.summary ?? ProgramLayout.summary(ProgramLayout.setsByWeek(slot, block: block)), reps: reps,
            rest: strength && slot.restSeconds > 0 ? Format.duration(slot.restSeconds) : "", superset: letter, why: why,
            setAside: avoid.contains(exercise.id), isStrength: strength)
    }

    /// What a slot is for when the generator gave no reason of its own.
    static func defaultReason(_ role: SlotRole) -> String {
        switch role {
        case .main: "A main lift: the day's heaviest work, progressed first."
        case .accessory: "An accessory: volume for the muscles the main lifts leave short."
        case .mobility: "Your limiter: a few minutes on it every session."
        case .warmup: "Warms up what the day trains."
        case .conditioning: "Conditioning after the lifting."
        case .stretch: "The optional cool-down."
        case .recovery: "Heat after training, outside the session's time."
        }
    }
}
