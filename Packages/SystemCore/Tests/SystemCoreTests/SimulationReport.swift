import Foundation
import Testing

@testable import SystemCore

/// Prints every simulated lifter's sessions, ratings and calibration evidence, for tuning.
/// Run with `SIM_DEBUG=1 swift test --filter simulationReport`.
@Test(.disabled(if: ProcessInfo.processInfo.environment["SIM_DEBUG"] == nil)) func simulationReport() {
    for lifter in [SimulatedLifter.honestNovice, .sandbagger, .overconfident] {
        var sim = TrainingSimulation(lifter: lifter, slots: SimulatedUserTests.slots)
        sim.run(weeks: 1)
        print("== \(lifter.name) after 1: trust \(sim.trust.score) bias \(sim.trust.bias) obs \(sim.trust.observations.count)")
        sim.run(weeks: 3, from: 1)
        print("== \(lifter.name) after 4: trust \(sim.trust.score) bias \(sim.trust.bias) obs \(sim.trust.observations.count)")
        sim.run(weeks: 8, from: 4)
        print(
            "== \(lifter.name): trust \(sim.trust.score) bias \(sim.trust.bias) obs \(sim.trust.observations.count) verify \(sim.adjustments.filter { $0 == .verify }.count)"
        )
        print(
            "   errors: \(sim.trust.observations.map { "\($0.rating.rawValue.prefix(1))\(String(format: "%.1f", $0.error))\($0.source.rawValue.prefix(1))" }.joined(separator: " "))"
        )
        for ex in [TestExercise.chestPress, .bench, .legExtension] {
            let truth = lifter.trueE1RM(ex.id, week: 12)
            print("   \(ex.name): est \(sim.estimate(ex) ?? 0) true \(truth)")
            let sets = sim.history[ex.id] ?? []
            let byDay = Dictionary(grouping: sets) { Day($0.date) }.sorted { $0.key < $1.key }
            for (day, s) in byDay.prefix(40) {
                print(
                    "     \(day): "
                        + s.map {
                            "\($0.kind.rawValue.prefix(2)) \(String(format: "%.1f", $0.loadKg))x\($0.reps)\($0.rating.map { "-" + $0.rawValue.prefix(1) } ?? "")"
                        }.joined(separator: ", "))
            }
        }
    }
}
