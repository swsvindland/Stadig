import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

/// After a session: the hours, sets and load in large numbers, what moved, what it taught the app,
/// every set, and what's next.
struct SessionSummaryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    let record: SessionRecord

    var body: some View {
        let moved = self.moved
        let learned = self.learned
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(record.title) · done · \(Format.day(record.day))").eyebrow(.accentColor)
                        Text("What this session taught us").font(.largeTitle.bold()).tracking(-1).foregroundStyle(Ink.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
                    HStack(alignment: .top, spacing: 12) {
                        stat("\(record.minutes)", unit: nil, caption: record.minutes == 1 ? "minute" : "minutes")
                        stat("\(record.workSets.count)", unit: nil, caption: record.workSets.count == 1 ? "set" : "sets")
                        if let lifted {
                            stat(lifted.value, unit: lifted.unit, caption: "lifted")
                        } else if let rate = model.analysis?.discipline.rate {
                            stat(Format.percent(rate), unit: nil, caption: "on plan")
                        }
                    }
                    .padding(.horizontal, 4)
                    if !moved.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("What moved").eyebrow()
                            ForEach(Array(moved.enumerated()), id: \.offset) { index, best in
                                if index > 0 { Rectangle().fill(Ink.hairline).frame(height: 1) }
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(best.name).font(.body.weight(.semibold)).foregroundStyle(Ink.text)
                                        Text("Est. 1RM").font(.caption).foregroundStyle(Ink.text2)
                                    }
                                    Spacer()
                                    Text("\(best.before) →").font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(Ink.text3)
                                    Measure(value: best.after, unit: model.gym.unit.symbol, size: 28)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .card()
                    }
                    if !learned.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(learned.enumerated()), id: \.offset) { index, line in
                                if index > 0 { Rectangle().fill(Ink.hairline).frame(height: 1) }
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Circle().fill(line.color).frame(width: 8, height: 8)
                                    Text(line.text).font(.subheadline).foregroundStyle(Ink.text).fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.vertical, 12)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.cardBackground, in: .rect(cornerRadius: 18, style: .continuous))
                    }
                    sets
                    if !sizeClass.isWide {
                        VStack(spacing: 10) {
                            Button {
                                dismiss()
                            } label: {
                                Text("Done").frame(maxWidth: .infinity)
                            }
                            .primaryAction()
                            .controlSize(.large)
                            .accessibilityIdentifier("summary.done")
                            if let next = nextLine {
                                Text(next).font(.footnote).foregroundStyle(Ink.text2)
                            }
                        }
                        .padding(.top, 8)
                    }
                }
                .padding()
                .readableWidth()
            }
            .background(.pageBackground)
            .navigationTitle(record.title)
            .inlineTitle()
            #if os(iOS)
            .toolbarVisibility(sizeClass.isWide ? .automatic : .hidden, for: .navigationBar)
            #endif
            .toolbar {
                if sizeClass.isWide {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("summary.done") }
                }
            }
        }
        .sheetFrame()
    }

    /// Every exercise's work sets in a line each, with their ratings.
    private var sets: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(record.exercises.enumerated()), id: \.element.id) { index, log in
                let exercise = model.catalog.resolve(log.exerciseID)
                let work = log.sets.filter { $0.kind.countsAsWork }
                if !work.isEmpty {
                    if index > 0 { Rectangle().fill(Ink.hairline).frame(height: 1) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
                        HStack(spacing: 10) {
                            ForEach(work) { set in
                                HStack(spacing: 4) {
                                    RatingMark(rating: set.rating)
                                    Text(Format.short(load: set.loadKg, reps: set.reps, exercise: exercise, unit: model.gym.unit))
                                        .font(.caption.monospacedDigit()).foregroundStyle(Ink.text2)
                                }
                            }
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                }
            }
            ForEach(Array((record.heat ?? []).enumerated()), id: \.offset) { _, heat in
                Rectangle().fill(Ink.hairline).frame(height: 1)
                HStack {
                    Text(model.catalog.resolve(heat.exerciseID).name).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(
                        "\(Format.number(heat.minutes)) min\(heat.temperatureC.map { " at \(Format.temperature($0, fahrenheit: model.fahrenheit))" } ?? "")"
                    )
                    .font(.caption.monospacedDigit()).foregroundStyle(Ink.text2)
                    RatingMark(rating: heat.rating)
                }
                .padding(.vertical, 10)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.cardBackground, in: .rect(cornerRadius: 18, style: .continuous))
    }

    private func stat(_ value: String, unit: String?, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Measure(value: value, unit: unit, size: 40, weight: .heavy)
            Text(caption).font(.caption).foregroundStyle(Ink.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// What was lifted, every work set's load times its reps: "6.9 t", or pounds in thousands.
    private var lifted: (value: String, unit: String)? {
        let kg = record.workSets.reduce(0.0) { $0 + $1.loadKg * Double($1.reps) }
        guard kg > 0 else { return nil }
        if model.gym.unit == .kg {
            return kg >= 1000 ? (Format.number(kg / 1000), "t") : (Format.number(kg, digits: 0), "kg")
        }
        let pounds = model.gym.unit.fromKilograms(kg)
        return pounds >= 10000 ? (Format.number(pounds / 1000), "k lb") : (Format.number(pounds, digits: 0), "lb")
    }

    /// "Next: Lower B on Friday".
    private var nextLine: String? {
        guard let next = model.analysis?.next else { return nil }
        let when = next.nextDay.map { " on \(Format.day($0, style: .dateTime.weekday(.wide)))" } ?? ""
        return "Next: \(next.day.name)\(when)"
    }

    private struct Best {
        var name: String
        var before: String
        var after: String
    }

    /// New best estimates this session.
    private var moved: [Best] {
        guard let analysis = model.analysis else { return [] }
        let unit = model.gym.unit
        return record.exercises.compactMap { log in
            let exercise = model.catalog.resolve(log.exerciseID)
            let bests = StrengthEstimator.sessionBests(analysis.history[log.exerciseID] ?? [], basis: exercise.loadBasis, trust: analysis.trust)
            guard bests.count >= 2, let last = bests.last, last.day == record.day else { return nil }
            let previous = bests.dropLast().map(\.e1rm).max() ?? 0
            guard last.e1rm > previous * 1.01 else { return nil }
            return Best(
                name: exercise.name, before: Format.number(unit.fromKilograms(previous)), after: Format.number(unit.fromKilograms(last.e1rm)))
        }
    }

    /// Plain-language notes: rating checks, misses as data, working weights found, each with a dot
    /// in what it means.
    private var learned: [(text: String, color: Color)] {
        var lines: [(text: String, color: Color)] = []
        let checks = record.exercises.flatMap { Calibration.observations(sets: $0.sets, exercise: model.catalog.resolve($0.exerciseID)) }
        if !checks.isEmpty {
            let right = checks.filter { $0.error == 0 }.count
            if right == checks.count {
                lines.append(("\(checks.count) rating check\(checks.count == 1 ? "" : "s"): right on.", Ink.good))
            } else if checks.contains(where: { $0.error > 0 }) {
                lines.append(("A rating check showed you had more left than you said. The next sets push a little to confirm.", Color.accentColor))
            } else {
                lines.append(("A rating check showed you had less left than you said. Estimates stay conservative for now.", Ink.ok))
            }
        }
        for log in record.exercises {
            let exercise = model.catalog.resolve(log.exerciseID)
            if log.sets.contains(where: { $0.rating == .red }) {
                lines.append(("\(exercise.name): a missed set. That's data; next time adjusts.", Ink.bad))
            }
            if log.sets.contains(where: { $0.kind == .findingWeight }), let working = log.sets.last(where: { $0.rating == .orange }) {
                lines.append(
                    (
                        "\(exercise.name): working weight found at \(Format.load(working.loadKg, unit: model.gym.unit, basis: exercise.loadBasis)).",
                        Ink.good
                    ))
            }
        }
        return Array(lines.prefix(6))
    }
}
