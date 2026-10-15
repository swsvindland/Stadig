import SwiftUI
import ExerciseLibrary
import LiftEngine
import SystemCore

/// After a session: what happened, what it taught the app, and what it changes next time.
struct SessionSummaryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let record: SessionRecord

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 20) {
                        stat("\(record.minutes)", "minutes")
                        stat("\(record.workSets.count)", "sets")
                        if let rate = model.analysis?.discipline.rate { stat(Format.percent(rate), "on plan") }
                    }
                    .card()
                    if !learned.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What this session taught us").font(.headline)
                            ForEach(learned, id: \.self) { line in
                                Label(line, systemImage: "circle.fill").labelStyle(BulletLabelStyle()).font(.subheadline)
                            }
                        }
                        .card()
                    }
                    ForEach(record.exercises) { log in
                        let exercise = model.catalog.resolve(log.exerciseID)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(exercise.name).font(.headline)
                            ForEach(log.sets.filter { $0.kind.countsAsWork }) { set in
                                HStack {
                                    Text(Format.logged(set, exercise: exercise, unit: model.gym.unit)).monospacedDigit()
                                    Spacer()
                                    RatingMark(rating: set.rating)
                                }
                                .font(.subheadline)
                            }
                        }
                        .card()
                    }
                }
                .padding()
                .readableWidth()
            }
            .background(.pageBackground)
            .navigationTitle(record.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Plain-language notes: new bests, rating checks, misses as data.
    private var learned: [String] {
        guard let analysis = model.analysis else { return [] }
        var lines: [String] = []
        let checks = record.exercises.flatMap { Calibration.observations(sets: $0.sets, exercise: model.catalog.resolve($0.exerciseID)) }
        if !checks.isEmpty {
            let right = checks.filter { $0.error == 0 }.count
            if right == checks.count {
                lines.append("\(checks.count) rating check\(checks.count == 1 ? "" : "s"): right on.")
            } else if checks.contains(where: { $0.error > 0 }) {
                lines.append("A rating check showed you had more left than you said. The next sets push a little to confirm.")
            } else {
                lines.append("A rating check showed you had less left than you said. Estimates stay conservative for now.")
            }
        }
        for log in record.exercises {
            let exercise = model.catalog.resolve(log.exerciseID)
            let history = analysis.history[log.exerciseID] ?? []
            let bests = StrengthEstimator.sessionBests(history, basis: exercise.loadBasis, trust: analysis.trust)
            if bests.count >= 2, let last = bests.last, last.day == record.day {
                let previous = bests.dropLast().map(\.e1rm).max() ?? 0
                if last.e1rm > previous * 1.01 {
                    lines.append("\(exercise.name): a new best estimate (\(Format.weight(last.e1rm, unit: model.gym.unit)) for one rep).")
                }
            }
            if log.sets.contains(where: { $0.rating == .red }) {
                lines.append("\(exercise.name): a missed set. That's data; next time adjusts.")
            }
            if log.sets.contains(where: { $0.kind == .findingWeight }), let working = log.sets.last(where: { $0.rating == .orange }) {
                lines.append("\(exercise.name): working weight found at \(Format.load(working.loadKg, unit: model.gym.unit, basis: exercise.loadBasis)).")
            }
        }
        return Array(lines.prefix(6))
    }
}
