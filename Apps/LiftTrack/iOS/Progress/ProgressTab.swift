import Charts
import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

/// The stats this app can measure honestly: Strength, Endurance, Agility, training Discipline,
/// and how far your ratings can be believed. No overall level, no streaks.
struct ProgressTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        NavigationStack {
            ScrollView {
                if let analysis = model.analysis {
                    if sizeClass.isWide {
                        wide(analysis)
                    } else {
                        column(analysis)
                    }
                }
            }
            .accessibilityIdentifier("progress.screen")
            .background(.pageBackground)
            .navigationTitle("Progress")
            .toolbar {
                SettingsToolbarItem(identifier: "progress.settings")
            }
            .sessionResumeToolbar()
        }
    }

    /// The phone's single column, unchanged.
    private func column(_ analysis: LiftAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            StrengthCard(analysis: analysis)
            LiftTrendCard(analysis: analysis)
            DisciplineCard(score: analysis.discipline)
            EnduranceCard(analysis: analysis.endurance)
            AgilityCard(analysis: analysis.agility)
            RatingsCard(trust: analysis.trust)
            NavigationLink {
                HistoryView()
            } label: {
                historyLink
            }
            .buttonStyle(.plain)
            .hoverHighlight()
            .accessibilityIdentifier("progress.history")
        }
        .padding()
        .readableWidth()
    }

    /// The stats in a grid, and each lift's trend as a list beside a large chart.
    private func wide(_ analysis: LiftAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)], spacing: 16) {
                StrengthCard(analysis: analysis)
                DisciplineCard(score: analysis.discipline)
                EnduranceCard(analysis: analysis.endurance)
                AgilityCard(analysis: analysis.agility)
                RatingsCard(trust: analysis.trust)
                Button {
                    model.tab = .history
                } label: {
                    historyLink
                }
                .buttonStyle(.plain)
                .hoverHighlight()
                .accessibilityIdentifier("progress.history")
            }
            LiftTrendsPanel(analysis: analysis)
        }
        .padding()
        .frame(maxWidth: 1400)
        .frame(maxWidth: .infinity)
    }

    private var historyLink: some View {
        HStack {
            Label("History", systemImage: "clock.arrow.circlepath").font(.headline)
            Spacer()
            Text("\(model.sessions.count) sessions · \(model.activities.count) activities").font(.subheadline).foregroundStyle(
                .secondary)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .card()
    }
}

/// Every lift with a trend, beside the chosen one's estimated one-rep max over time: large, with
/// its current estimate, the change and any stall.
struct LiftTrendsPanel: View {
    @Environment(AppModel.self) private var model
    let analysis: LiftAnalysis
    @State private var selection: String?
    @State private var lifts: [LiftTrendsPanel.Lift] = []

    struct Lift: Identifiable, Hashable {
        var id: String
        var name: String
        var points: [ExerciseRecord.Point]
        var current: Double?
        var change: Double?
        var scored: Bool
    }

    var body: some View {
        let unit = model.gym.unit
        VStack(alignment: .leading, spacing: 12) {
            Text("Estimated 1RM").font(.headline)
            if lifts.isEmpty {
                Text("Trends appear after a couple of sessions.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    List(lifts, selection: $selection) { lift in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lift.name).lineLimit(1)
                                if let current = lift.current {
                                    Text(Format.weight(current, unit: unit)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let change = lift.change {
                                Text("\(change >= 0 ? "+" : "")\(Format.percent(change))").font(.caption.monospacedDigit())
                                    .foregroundStyle(change > 0 ? .green : .secondary)
                            }
                        }
                        .tag(lift.id)
                        .accessibilityIdentifier("progress.trendLift")
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(width: 280, height: 360)
                    if let lift = lifts.first(where: { $0.id == selection }) ?? lifts.first {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(lift.name).font(.title3.bold())
                                Spacer()
                                Button("Show in Library", systemImage: "books.vertical") { model.show(inLibrary: lift.id) }
                                    .buttonStyle(.borderless)
                            }
                            Chart(lift.points, id: \.day) { point in
                                LineMark(x: .value("Day", point.day.date()), y: .value("e1RM", unit.fromKilograms(point.e1rm)))
                                    .interpolationMethod(.monotone)
                                PointMark(x: .value("Day", point.day.date()), y: .value("e1RM", unit.fromKilograms(point.e1rm))).symbolSize(30)
                            }
                            .chartYScale(domain: .automatic(includesZero: false))
                            .chartYAxisLabel(unit.symbol)
                            .frame(minHeight: 300)
                            .accessibilityLabel("\(lift.name) estimated one-rep max over time")
                            if let stall = analysis.stalls.first(where: { $0.exerciseID == lift.id }) {
                                Text(
                                    stall.reading == .expectedInDeficit
                                        ? "Flat for \(stall.weeks) weeks: expected in a cut." : "No new best for \(stall.weeks) weeks."
                                )
                                .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .card()
        .task(id: analysis.history.count + model.sessions.count) { lifts = Self.lifts(analysis, catalog: model.catalog) }
    }

    /// Strength lifts done at least twice: the scored lifts first, then by name.
    static func lifts(_ analysis: LiftAnalysis, catalog: ExerciseCatalog) -> [Lift] {
        analysis.history.keys.map { catalog.resolve($0) }
            .filter { $0.kind == .strength }
            .compactMap { exercise -> Lift? in
                let record = ExerciseRecord.of(analysis.history[exercise.id] ?? [], exercise: exercise, trust: analysis.trust)
                guard record.trend.count >= 2 else { return nil }
                return Lift(
                    id: exercise.id, name: exercise.name, points: record.trend, current: record.current, change: record.change,
                    scored: exercise.strength != nil)
            }
            .sorted { ($0.scored ? 0 : 1, $0.name) < ($1.scored ? 0 : 1, $1.name) }
    }
}

/// Every lift category on one scale against bodyweight-relative standards; the weakest stands out.
struct StrengthCard: View {
    @Environment(AppModel.self) private var model
    let analysis: LiftAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Strength", systemImage: StatKind.strength.symbol).font(.headline).foregroundStyle(StatKind.strength.color)
                Spacer()
                if let overall = analysis.strength.overall {
                    Text("\(Int(overall.rounded())) · \(StrengthStandards.level(for: overall))").font(.headline.monospacedDigit())
                }
            }
            if analysis.strength.categories.isEmpty {
                Text("Scores appear once the main lifts have working weights: usually in the first two weeks.").font(.subheadline).foregroundStyle(
                    .secondary)
            }
            ForEach(StrengthCategory.allCases) { category in
                if let score = analysis.strength[category] {
                    let weakest = analysis.strength.weakest?.category == category
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(category.label).font(.subheadline.weight(weakest ? .semibold : .regular))
                            if weakest { Pill(text: "Weakest", color: .orange) }
                            Spacer()
                            Text("\(Format.weight(score.oneRepMaxKg, unit: model.gym.unit)) est. · \(Int(score.score.rounded()))")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        ScoreBar(score: score.score, color: .orange, highlight: weakest)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(category.label): score \(Int(score.score.rounded())), \(score.level)")
                } else {
                    HStack {
                        Text(category.label).font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Text("Not scored yet").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            if let first = analysis.strength.priorities.first {
                Label(first.reason, systemImage: "arrow.up.right.circle").font(.footnote)
            }
            Text(
                "Scored from estimated one-rep maxes against bodyweight-relative standards. Beginner 20 · novice 40 · intermediate 60 · advanced 80 · elite 100."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }
}

/// Estimated one-rep max over time for a scored lift.
struct LiftTrendCard: View {
    @Environment(AppModel.self) private var model
    let analysis: LiftAnalysis
    @State private var exerciseID: String?

    private var options: [Exercise] {
        analysis.history.keys.map { model.catalog.resolve($0) }
            .filter { $0.kind == .strength && (analysis.history[$0.id]?.count ?? 0) >= 2 }
            .sorted { ($0.strength != nil ? 0 : 1, $0.name) < ($1.strength != nil ? 0 : 1, $1.name) }
    }

    var body: some View {
        let selected = exerciseID.flatMap { id in options.first { $0.id == id } } ?? options.first
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Estimated 1RM").font(.headline)
                Spacer()
                if !options.isEmpty {
                    Picker("Exercise", selection: Binding(get: { selected?.id ?? "" }, set: { exerciseID = $0 })) {
                        ForEach(options) { Text($0.name).tag($0.id) }
                    }
                    .pickerStyle(.menu)
                }
            }
            if let selected {
                let points = StrengthEstimator.sessionBests(analysis.history[selected.id] ?? [], basis: selected.loadBasis, trust: analysis.trust)
                Chart(points, id: \.day) { point in
                    LineMark(x: .value("Day", point.day.date()), y: .value("e1RM", model.gym.unit.fromKilograms(point.e1rm)))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Day", point.day.date()), y: .value("e1RM", model.gym.unit.fromKilograms(point.e1rm)))
                        .symbolSize(24)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxisLabel(model.gym.unit.symbol)
                .frame(height: 180)
                .accessibilityLabel("\(selected.name) estimated one-rep max over time")
                if let stall = analysis.stalls.first(where: { $0.exerciseID == selected.id }) {
                    Text(
                        stall.reading == .expectedInDeficit
                            ? "Flat for \(stall.weeks) weeks: expected in a cut." : "No new best for \(stall.weeks) weeks."
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                Text("Trends appear after a couple of sessions.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .card()
    }
}

struct DisciplineCard: View {
    let score: DisciplineScore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Training discipline", systemImage: StatKind.discipline.symbol).font(.headline).foregroundStyle(StatKind.discipline.color)
            DisciplineGauge(score: score)
            Text(
                "\(score.completed) of \(score.planned) planned in the last four weeks\(score.exemptDays > 0 ? ", \(score.exemptDays) days exempt" : "")."
            )
            .font(.subheadline)
            Text(score.note).font(.subheadline).foregroundStyle(.secondary)
            Text("Rest days and deloads are part of the plan. Vacations, illness and exempt crunch days never count.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }
}

struct EnduranceCard: View {
    @Environment(AppModel.self) private var model
    let analysis: EnduranceAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Endurance", systemImage: StatKind.endurance.symbol).font(.headline).foregroundStyle(StatKind.endurance.color)
                Spacer()
                if let score = analysis.score { Text("\(Int(score.rounded()))").font(.headline.monospacedDigit()) }
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("VO₂ max").foregroundStyle(.secondary)
                    Text(analysis.vo2Max.map { Format.number($0) } ?? "From your Watch")
                }
                GridRow {
                    Text("Resting HR").foregroundStyle(.secondary)
                    Text(analysis.restingHeartRate.map { "\(Int($0)) bpm" } ?? "—")
                }
                GridRow {
                    Text("Cardio a week").foregroundStyle(.secondary)
                    Text("\(Int(analysis.weeklyConditioningMinutes)) min")
                }
                if let trend = analysis.heartRateRecoveryTrend {
                    GridRow {
                        Text("Between-set recovery").foregroundStyle(.secondary)
                        Text(trend > 0 ? "Improving" : "Holding")
                    }
                }
                if let latest = analysis.latestBenchmark {
                    GridRow {
                        Text(latest.benchmark.label).foregroundStyle(.secondary)
                        Text(
                            Format.benchmark(latest.value, latest.benchmark)
                                + (analysis.benchmarkChange.map { " (\($0 >= 0 ? "+" : "")\(Format.percent($0)))" } ?? ""))
                    }
                }
            }
            .font(.subheadline)
            if analysis.engineLagging {
                Label("Under an hour of easy cardio a week: the post-lift block leans Zone 2.", systemImage: "arrow.right.circle").font(.footnote)
            }
        }
        .card()
    }
}

struct AgilityCard: View {
    let analysis: AgilityAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Agility", systemImage: StatKind.agility.symbol).font(.headline).foregroundStyle(StatKind.agility.color)
                Spacer()
                if let limiter = analysis.limiter { Pill(text: "Limiter: \(limiter.label)", color: .teal) }
            }
            if analysis.latest.isEmpty {
                Text("Five quick mobility tests set your limiter: the area every session works on for a few minutes.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(MobilityTest.allCases) { test in
                if let result = analysis.latest[test] {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(test.label).font(.subheadline)
                            Spacer()
                            Text(Format.mobility(result.value, test)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        ScoreBar(score: result.score * 1.2, color: .teal, highlight: analysis.limiterTest == test)
                    }
                }
            }
            if !analysis.seePhysio.isEmpty {
                Label(
                    "\(analysis.seePhysio.map(\.label).joined(separator: ", ")): pain or getting worse. See a physio rather than stretching harder.",
                    systemImage: "cross.case"
                ).font(.footnote)
            }
        }
        .card()
    }
}

/// How well ratings match reality. It moves only on evidence: rep-outs and checked pushes.
struct RatingsCard: View {
    let trust: TrustState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Your ratings", systemImage: "hand.tap").font(.headline)
            Text(trust.label).font(.subheadline.weight(.semibold))
            if let tendency = trust.tendency { Text(tendency).font(.subheadline) }
            Text(
                "\(trust.evidenceCount) checks so far. Machines can be taken to failure safely, so they check your Easy and Just right; what they learn applies to free weights too."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }
}

/// Every session and outside activity, newest first.
struct HistoryView: View {
    @Environment(AppModel.self) private var model

    private enum Entry: Identifiable {
        case session(SessionRecord)
        case activity(ActivityLog)

        var id: UUID {
            switch self {
            case .session(let s): s.id
            case .activity(let a): a.id
            }
        }

        var date: Date {
            switch self {
            case .session(let s): s.start
            case .activity(let a): a.start
            }
        }
    }

    var body: some View {
        let entries = (model.sessions.map(Entry.session) + model.activities.map(Entry.activity)).sorted { $0.date > $1.date }
        List {
            ForEach(entries) { entry in
                switch entry {
                case .session(let session):
                    NavigationLink {
                        SessionDetail(record: session)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.title).font(.headline)
                            Text(
                                "\(session.start.formatted(date: .abbreviated, time: .shortened)) · \(session.minutes) min · \(session.workSets.count) sets\(session.device == Platform.deviceName ? "" : " · \(session.device)")"
                            )
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions { Button("Delete", role: .destructive) { model.delete(session: session.id) } }
                    .contextMenu { Button("Delete", systemImage: "trash", role: .destructive) { model.delete(session: session.id) } }
                    .accessibilityIdentifier("history.session")
                case .activity(let log):
                    HStack {
                        Image(systemName: log.type.symbol).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(log.type.label).font(.headline)
                            Text(
                                "\(log.start.formatted(date: .abbreviated, time: .shortened)) · \(log.minutes) min · effort \(log.intensity)\(sourceLabel(log))"
                            )
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions { Button("Delete", role: .destructive) { model.delete(activity: log.id) } }
                    .contextMenu { Button("Delete", systemImage: "trash", role: .destructive) { model.delete(activity: log.id) } }
                    .accessibilityIdentifier("history.activity")
                }
            }
        }
        .navigationTitle("History")
        .overlay { if entries.isEmpty { ContentUnavailableView("Nothing yet", systemImage: "clock") } }
    }

    private func sourceLabel(_ log: ActivityLog) -> String {
        if case .health(_, let name) = log.source { return " · \(name)" }
        return ""
    }
}

struct SessionDetail: View {
    let record: SessionRecord

    var body: some View {
        SessionSetsList(record: record, header: false)
            .navigationTitle(record.title)
    }
}

/// A finished session's feedback, sets, conditioning and heat.
struct SessionSetsList: View {
    @Environment(AppModel.self) private var model
    let record: SessionRecord
    /// Its title and when, at the top: for the inspector, where there's no navigation title.
    let header: Bool

    var body: some View {
        List {
            if header {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.title).font(.title3.bold())
                        Text("\(record.start.formatted(date: .abbreviated, time: .shortened)) · \(record.minutes) min · \(record.device)")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            if let feedback = record.feedback {
                Section("Feedback") {
                    Text(
                        "Soreness \(feedback.soreness)/3 · energy \(feedback.energy)/5\(feedback.jointPain.isEmpty ? "" : " · pain: \(feedback.jointPain.map(\.label).joined(separator: ", "))")"
                    )
                }
            }
            ForEach(record.exercises) { log in
                let exercise = model.catalog.resolve(log.exerciseID)
                Section(exercise.name) {
                    ForEach(log.sets) { set in
                        HStack {
                            Text(set.kind == .warmup ? "Warm-up" : set.kind.label).font(.caption).foregroundStyle(.secondary).frame(
                                width: 90, alignment: .leading)
                            Text(Format.logged(set, exercise: exercise, unit: model.gym.unit)).monospacedDigit()
                            Spacer()
                            RatingMark(rating: set.rating)
                        }
                    }
                }
            }
            ForEach(record.conditioning, id: \.exerciseID) { c in
                Section(model.catalog.resolve(c.exerciseID).name) {
                    Text("\(c.minutes) min\(c.averageHeartRate.map { " · avg \(Int($0)) bpm" } ?? "")")
                }
            }
            ForEach(Array((record.heat ?? []).enumerated()), id: \.offset) { _, heat in
                Section(model.catalog.resolve(heat.exerciseID).name) {
                    HStack {
                        Text(
                            "\(Format.number(heat.minutes)) min\(heat.temperatureC.map { " at \(Format.temperature($0, fahrenheit: model.fahrenheit))" } ?? "")"
                        )
                        Spacer()
                        RatingMark(rating: heat.rating)
                    }
                }
            }
        }
    }
}
