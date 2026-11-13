import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

/// After a session: its minutes, sets and load in large numbers against the plan and the last time,
/// what moved, what it taught the app, and Done with what's next. Every set is a row away.
struct SessionSummaryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    let record: SessionRecord

    var body: some View {
        let moved = self.moved
        let learned = self.learned
        let tally = self.tally
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(record.title) · done · \(Format.day(record.day, style: .dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                            .eyebrow(.accentColor)
                        PageTitle("What this session taught us")
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 10)
                    numbers(tally)
                        .padding(.horizontal, 4)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                    if !moved.isEmpty || strengthMove != nil {
                        whatMoved(moved)
                    }
                    if !learned.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(learned.enumerated()), id: \.offset) { index, line in
                                if index > 0 { Rectangle().fill(Ink.hairline).frame(height: 1) }
                                HStack(spacing: 12) {
                                    Circle().fill(line.color).frame(width: 8, height: 8)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(line.title).font(.callout.weight(.semibold)).foregroundStyle(Ink.text)
                                        Text(line.detail).font(.caption).foregroundStyle(Ink.text3)
                                    }
                                    .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.vertical, 8)
                                .frame(minHeight: 52, alignment: .leading)
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .tightCard()
                    }
                    sets
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .readableWidth()
            }
            .background(.pageBackground)
            .safeAreaInset(edge: .bottom) {
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
                            Text(next).font(.caption).foregroundStyle(Ink.text3)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .readableWidth()
                    .background(alignment: .top) {
                        // What scrolls under the foot fades out above Done, as under the design's
                        // tab bar, rather than being cut off at its edge.
                        VStack(spacing: 0) {
                            LinearGradient(colors: [Ink.ground.opacity(0), Ink.ground], startPoint: .top, endPoint: .bottom).frame(height: 28)
                            Ink.ground
                        }
                        .padding(.top, -28)
                        .ignoresSafeArea(edges: .bottom)
                        .allowsHitTesting(false)
                    }
                }
            }
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

    // MARK: The numbers

    private var tally: SessionTally {
        let baseline = model.finishedBaseline?.sessionID == record.id ? model.finishedBaseline : nil
        return SessionTally(record, plannedMinutes: baseline?.plannedMinutes, plannedSets: baseline?.plannedSets, earlier: model.sessions)
    }

    /// Minutes, sets and what was lifted, each with a line on how it went against the plan or the last time.
    private func numbers(_ tally: SessionTally) -> some View {
        HStack(alignment: .top, spacing: 12) {
            stat("\(tally.minutes)", unit: "min", caption: minutesLine(tally))
            stat("\(tally.sets)", unit: nil, caption: setsLine(tally))
            if let lifted = lifted(tally.liftedKg) {
                stat(lifted.value, unit: lifted.unit, caption: liftedLine(tally))
            } else if let rate = model.analysis?.discipline.rate {
                stat(Format.percent(rate), unit: nil, caption: "on plan")
            }
        }
    }

    private func minutesLine(_ tally: SessionTally) -> String {
        guard let under = tally.underPlan else { return tally.minutes == 1 ? "minute" : "minutes" }
        if under == 0 { return "on plan" }
        return under > 0 ? "\(under) under plan" : "\(-under) over plan"
    }

    private func setsLine(_ tally: SessionTally) -> String {
        guard let planned = tally.plannedSets, planned > 0 else { return tally.sets == 1 ? "set" : "sets" }
        return tally.sets >= planned ? "sets · all \(planned) done" : "sets · \(tally.sets) of \(planned)"
    }

    private func liftedLine(_ tally: SessionTally) -> String {
        guard let change = tally.liftedChange else { return "lifted" }
        let percent = Int((change * 100).rounded())
        return percent == 0 ? "lifted · same as last time" : "lifted · \(percent > 0 ? "+" : "−")\(abs(percent))%"
    }

    private func stat(_ value: String, unit: String?, caption: String) -> some View {
        // Close under the numeral: its line is taller than the design's, which sets it at .95.
        VStack(alignment: .leading, spacing: 1) {
            Measure(value: value, unit: unit, size: 44, weight: .heavy)
            Text(caption).font(.caption).foregroundStyle(Ink.text3).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// What was lifted: "6.9 t", or pounds in thousands.
    private func lifted(_ kg: Double) -> (value: String, unit: String)? {
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

    // MARK: What moved

    private func whatMoved(_ moved: [Best]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What moved").eyebrow()
            ForEach(Array(moved.enumerated()), id: \.offset) { index, best in
                if index > 0 { Rectangle().fill(Ink.hairline).frame(height: 1) }
                movedRow(title: best.name, caption: best.caption, before: best.before, after: best.after, unit: model.gym.unit.symbol)
            }
            if let strength = strengthMove {
                if !moved.isEmpty { Rectangle().fill(Ink.hairline).frame(height: 1) }
                movedRow(
                    title: "Strength", caption: strength.caption, before: "\(strength.before)", after: "\(strength.after)", unit: nil)
                VStack(spacing: 6) {
                    GainRuler(from: strength.fromFraction, to: strength.toFraction)
                    HStack {
                        Text("\(strength.lower.name) \(strength.lower.score)")
                        Spacer()
                        Text("+\(strength.after - strength.before) today").foregroundStyle(Ink.words(Ink.good))
                        Spacer()
                        Text("\(strength.upper.name) \(strength.upper.score)")
                    }
                    .font(.system(size: 10, weight: .semibold)).textCase(.uppercase).tracking(0.6).foregroundStyle(Ink.text3)
                    .accessibilityHidden(true)
                }
            }
        }
        .inkCard()
        .accessibilityIdentifier("summary.moved")
    }

    /// The name with before and after on its baseline, and what's behind it under both, so a lift's
    /// three-figure estimates don't squeeze the line onto two.
    private func movedRow(title: String, caption: String, before: String, after: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(Ink.text)
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(before) →").font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(Ink.text3)
                    Measure(value: after, unit: unit, size: 30, weight: .bold)
                }
                .fixedSize()
            }
            Text(caption).font(.caption).foregroundStyle(Ink.text3)
        }
        .accessibilityElement(children: .combine)
    }

    /// Strength before the session and now, when it moved: its level, the one after, and where both
    /// sit between them.
    private var strengthMove: StrengthMove? {
        guard let baseline = model.finishedBaseline, baseline.sessionID == record.id, let earlier = baseline.strength,
            let now = model.analysis?.strength.overall
        else { return nil }
        let before = Int(earlier.rounded())
        let after = Int(now.rounded())
        guard after > before else { return nil }
        let lower = min(80, Int((Double(after) / 20).rounded(.down)) * 20)
        let upper = lower + 20
        let points = upper - after
        return StrengthMove(
            before: before, after: after,
            caption:
                "\(StrengthStandards.level(for: now)) · \(points) \(points == 1 ? "point" : "points") to \(StrengthStandards.level(for: Double(upper)))",
            lower: (StrengthStandards.level(for: Double(max(lower, 1))), lower), upper: (StrengthStandards.level(for: Double(upper)), upper),
            fromFraction: max(0, Double(before - lower) / 20), toFraction: min(1, Double(after - lower) / 20))
    }

    private struct StrengthMove {
        var before: Int
        var after: Int
        var caption: String
        var lower: (name: String, score: Int)
        var upper: (name: String, score: Int)
        var fromFraction: Double
        var toFraction: Double
    }

    /// Every set, a row away: the summary keeps to what it taught.
    @ViewBuilder
    private var sets: some View {
        if !record.exercises.isEmpty || !(record.heat ?? []).isEmpty {
            NavigationLink {
                SessionSetsList(record: record, header: false, heading: (eyebrow: record.title, title: "Every set"))
                    .formPage("Every set")
                    #if os(iOS)
                .toolbarVisibility(.visible, for: .navigationBar)
                    #endif
            } label: {
                LinkRowLabel(
                    title: "Every set",
                    caption:
                        "\(record.workSets.count) work \(record.workSets.count == 1 ? "set" : "sets") across \(record.exercises.count) \(record.exercises.count == 1 ? "exercise" : "exercises")"
                )
                .padding(.vertical, 8)
                .frame(minHeight: 52)
            }
            .buttonStyle(.plain)
            .tightCard()
            .accessibilityIdentifier("summary.sets")
        }
    }

    private struct Best {
        var name: String
        /// What it scores, "Bench press", when it's the lift that score is measured by.
        var short: String?
        /// "Est. 1RM · 70 × 9 best set".
        var caption: String
        var before: String
        var after: String
    }

    /// New best estimates this session, with the set that made each. A lift is named as Progress
    /// names what it scores ("Bench press") when it's the lift that score is measured by, and by its
    /// own name otherwise, or when two would share the name.
    private var moved: [Best] {
        guard let analysis = model.analysis else { return [] }
        let unit = model.gym.unit
        let lifts = record.exercises.compactMap { log -> Best? in
            let exercise = model.catalog.resolve(log.exerciseID)
            let bests = StrengthEstimator.sessionBests(analysis.history[log.exerciseID] ?? [], basis: exercise.loadBasis, trust: analysis.trust)
            guard bests.count >= 2, let last = bests.last, last.day == record.day else { return nil }
            let previous = bests.dropLast().map(\.e1rm).max() ?? 0
            guard last.e1rm > previous * 1.01 else { return nil }
            let best = log.sets.filter { $0.kind.countsAsWork }
                .max {
                    (StrengthEstimator.estimate($0, basis: exercise.loadBasis, trust: analysis.trust) ?? 0)
                        < (StrengthEstimator.estimate($1, basis: exercise.loadBasis, trust: analysis.trust) ?? 0)
                }
            let estimates = Self.estimates(from: previous, to: last.e1rm, unit: unit)
            return Best(
                name: exercise.name, short: exercise.strength.flatMap { $0.factor == 1 ? $0.category.label : nil },
                caption: best.map {
                    "Est. 1RM · \(Format.short(load: $0.loadKg, reps: $0.reps, exercise: exercise, unit: unit).replacingOccurrences(of: "×", with: " × ")) best set"
                } ?? "Est. 1RM",
                before: estimates.before, after: estimates.after)
        }
        return lifts.map { lift in
            var named = lift
            if let short = lift.short, lifts.filter({ $0.short == short }).count == 1 { named.name = short }
            return named
        }
    }

    /// Two estimates as a gym loads them, to the half kilogram or the pound, as the exercise page's
    /// line is; to a tenth where that would make a move look like none.
    static func estimates(from before: Double, to after: Double, unit: WeightUnit) -> (before: String, after: String) {
        let step = unit == .kg ? 0.5 : 1
        let was = (unit.fromKilograms(before) / step).rounded() * step
        let now = (unit.fromKilograms(after) / step).rounded() * step
        guard now > was else { return (Format.number(unit.fromKilograms(before)), Format.number(unit.fromKilograms(after))) }
        return (Format.number(was), Format.number(now))
    }

    private struct Lesson {
        var title: String
        var detail: String
        var color: Color
    }

    /// Plain-language lessons, each a line and what's behind it, with a dot in what it means: rating
    /// checks, misses as data, working weights found.
    private var learned: [Lesson] {
        var lines: [Lesson] = []
        let checks = record.exercises.flatMap { Calibration.observations(sets: $0.sets, exercise: model.catalog.resolve($0.exerciseID)) }
        let counted = "\(checks.count) rating check\(checks.count == 1 ? "" : "s") this session"
        if !checks.isEmpty {
            let right = checks.filter { $0.error == 0 }.count
            if right == checks.count {
                lines.append(Lesson(title: "Your ratings were right on", detail: counted, color: Ink.good))
            } else if checks.contains(where: { $0.error > 0 }) {
                lines.append(
                    Lesson(
                        title: "You had more left than you said", detail: "\(counted) · the next sets push a little to confirm", color: .accentColor))
            } else {
                lines.append(
                    Lesson(title: "You had less left than you said", detail: "\(counted) · estimates stay conservative for now", color: Ink.ok))
            }
        }
        for log in record.exercises {
            let exercise = model.catalog.resolve(log.exerciseID)
            if log.sets.contains(where: { $0.rating == .red }) {
                lines.append(Lesson(title: "\(exercise.name): a missed set", detail: "That's data; next time adjusts", color: Ink.bad))
            }
            if log.sets.contains(where: { $0.kind == .findingWeight }), let working = log.sets.last(where: { $0.rating == .orange }) {
                lines.append(
                    Lesson(
                        title: "\(exercise.name): working weight found",
                        detail: "\(Format.load(working.loadKg, unit: model.gym.unit, basis: exercise.loadBasis)) for \(working.reps)", color: Ink.good
                    ))
            }
        }
        return Array(lines.prefix(6))
    }
}

/// A score's gain on the ruler between two levels: where it was in the accent, today's gain in green.
struct GainRuler: View {
    let from: Double
    let to: Double
    var height: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Ink.track)
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Ink.good).frame(width: max(height * 0.5, width * to))
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.accentColor).frame(width: width * from)
                Path { path in
                    for index in 1..<10 {
                        let x = (width * Double(index) / 10).rounded()
                        path.addRect(CGRect(x: x - 0.75, y: 0, width: 1.5, height: height))
                    }
                }
                .fill(Ink.tick)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// What a finished session is set against, taken as it ends: the plan's minutes and work sets, and
/// Strength before it was saved.
struct SummaryBaseline: Equatable {
    var sessionID: UUID
    var plannedMinutes: Int
    var plannedSets: Int
    var strength: Double?

    init(record: SessionRecord, plan: SessionPlan, strength: Double?) {
        sessionID = record.id
        plannedMinutes = plan.estimatedMinutes
        // The lifting's, as the session's own count is: not the warm-up's drills or the conditioning.
        plannedSets = plan.items.filter(\.isStrength).reduce(0) { $0 + $1.workSets.count }
        self.strength = strength
    }
}
