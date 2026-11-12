import Charts
import ExerciseLibrary
import HubEngine
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
            #if os(iOS)
            // The phone draws its own header over Your shape.
            .toolbarVisibility(sizeClass.isWide ? .automatic : .hidden, for: .navigationBar)
            #endif
            .toolbar {
                if sizeClass.isWide { SettingsToolbarItem(identifier: "progress.settings") }
            }
            .sessionResumeToolbar()
        }
    }

    /// The phone's single column: Your shape, then each score's own card.
    private func column(_ analysis: LiftAnalysis) -> some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 16) {
                header
                YourShape(lines: model.stats, analysis: analysis) { stat in
                    if stat == .physique {
                        model.tab = .body
                    } else {
                        withAnimation { proxy.scrollTo(stat, anchor: .top) }
                    }
                }
                StrengthCard(analysis: analysis).id(StatKind.strength)
                LiftTrendCard(analysis: analysis)
                DisciplineCard(score: analysis.discipline).id(StatKind.discipline)
                EnduranceCard(analysis: analysis.endurance).id(StatKind.endurance)
                AgilityCard(analysis: analysis.agility).id(StatKind.agility)
                RatingsCard(trust: analysis.trust)
                historyRow
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .readableWidth()
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Progress").eyebrow()
                Text("Your shape").font(.largeTitle.bold()).tracking(-1).foregroundStyle(Ink.text)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            #if !os(macOS)
            Button {
                model.showSettings = true
            } label: {
                CircleIcon(symbol: "gearshape")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("progress.settings")
            #endif
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }

    private var historyRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                HistoryView()
            } label: {
                historyLink
            }
            .buttonStyle(.plain)
            .hoverHighlight()
            .accessibilityIdentifier("progress.history")
        }
    }

    /// The stats in a grid, and each lift's trend as a list beside a large chart.
    private func wide(_ analysis: LiftAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            YourShape(lines: model.stats, analysis: analysis, open: { stat in if stat == .physique { model.tab = .body } }, sideBySide: true)
                .card(padding: 20)
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
            Text("History").font(.headline).foregroundStyle(Ink.text)
            Spacer()
            Text("\(model.sessions.count) sessions · \(model.activities.count) activities").font(.subheadline).foregroundStyle(Ink.text2)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Ink.text3)
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
                                    .foregroundStyle(change > 0 ? Ink.good : Ink.text2)
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

/// Strength: the overall score large on a ruler marked with the levels, how far to the next, and
/// every lift on the same ruler, the weakest flagged.
struct StrengthCard: View {
    @Environment(AppModel.self) private var model
    let analysis: LiftAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Strength").eyebrow()
                if let overall = analysis.strength.overall {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(Int(overall.rounded()))").numeral(64, weight: .heavy).foregroundStyle(Ink.text)
                        Text(StrengthStandards.level(for: overall)).font(.title3.weight(.bold)).foregroundStyle(Ink.text)
                    }
                    .accessibilityElement(children: .combine)
                    LevelRuler(score: overall)
                    if let next = nextLevel(overall) {
                        Text(next).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text).fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Scores appear once the main lifts have working weights: usually in the first two weeks.")
                        .font(.subheadline).foregroundStyle(Ink.text2)
                }
            }
            .card()
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("By lift").font(.headline).foregroundStyle(Ink.text)
                    Spacer()
                    Text("Score from your best estimated max").font(.caption).foregroundStyle(Ink.text2)
                }
                .padding(.bottom, 6)
                ForEach(StrengthCategory.allCases) { category in
                    liftRow(category)
                }
                Text(
                    "Scored from estimated one-rep maxes against bodyweight-relative standards. Beginner 20 · novice 40 · intermediate 60 · advanced 80 · elite 100."
                )
                .font(.caption).foregroundStyle(Ink.text2)
                .padding(.top, 8)
            }
            .card()
        }
    }

    @ViewBuilder
    private func liftRow(_ category: StrengthCategory) -> some View {
        if let score = analysis.strength[category] {
            let weakest = analysis.strength.weakest?.category == category
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(category.label).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text).lineLimit(1).minimumScaleFactor(0.8)
                    if weakest { Text("Weakest").font(.caption.weight(.semibold)).foregroundStyle(Ink.ok) }
                }
                .frame(width: 112, alignment: .leading)
                Ruler(value: score.score / 100, color: weakest ? Ink.ok : .accentColor)
                Text("\(Int(score.score.rounded()))").numeral(20).foregroundStyle(weakest ? Ink.ok : Ink.text).frame(width: 30, alignment: .trailing)
            }
            .frame(minHeight: weakest ? 44 : 34)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(category.label): score \(Int(score.score.rounded())), \(score.level), \(Format.weight(score.oneRepMaxKg, unit: model.gym.unit)) estimated\(weakest ? ", weakest" : "")"
            )
        } else {
            HStack {
                Text(category.label).font(.subheadline).foregroundStyle(Ink.text2)
                Spacer()
                Text("Not scored yet").font(.caption).foregroundStyle(Ink.text3)
            }
            .frame(minHeight: 34)
        }
    }

    /// "3 points to Intermediate. Overhead press gets you there fastest."
    private func nextLevel(_ overall: Double) -> String? {
        let target = (overall / 20).rounded(.down) * 20 + 20
        guard target <= 100 else { return nil }
        let points = max(1, Int((target - overall).rounded(.up)))
        let name = StrengthStandards.level(for: target)
        let fastest = analysis.strength.priorities.first?.reason ?? analysis.strength.weakest.map { "\($0.category.label) gets you there fastest." }
        return "\(points) \(points == 1 ? "point" : "points") to \(name).\(fastest.map { " \($0)" } ?? "")"
    }
}

/// The six scores as one figure, and each in a row: its number, the app that measures it, a line on
/// what moves it, and its trend. A score Stadig Macro measures waits for it, said plainly.
struct YourShape: View {
    let lines: [StatLine]
    let analysis: LiftAnalysis
    let open: (StatKind) -> Void

    private var macroSetUp: Bool { lines.contains { $0.apps.contains(.macroTrack) } }

    /// The figure beside its rows rather than over them, where there's room.
    var sideBySide = false

    var body: some View {
        let axes = ScoreShape.axes(lines)
        let waiting = axes.contains { $0.score == nil && $0.stat == .vitality } && !macroSetUp
        VStack(alignment: .leading, spacing: 10) {
            Text(
                waiting
                    ? "Five scores so far. The sixth is measured by Stadig Macro."
                    : "Six scores, one figure. It grows where you do the work."
            )
            .font(.subheadline).foregroundStyle(Ink.text2)
            .padding(.horizontal, 4)
            if sideBySide {
                HStack(alignment: .center, spacing: 32) {
                    figure(axes, waiting: waiting).frame(maxWidth: 400)
                    rows.frame(maxWidth: 520)
                }
            } else {
                figure(axes, waiting: waiting)
                rows.padding(.top, 4)
            }
        }
    }

    private func figure(_ axes: [ScoreShape.Axis], waiting: Bool) -> some View {
        VStack(spacing: 10) {
            ScoreShape(axes: axes)
                // Its corner labels sit at a fixed distance from the figure, so past this size they
                // run into it and off the screen; each score is in the rows below at full size.
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
                .frame(maxWidth: 380)
                .frame(maxWidth: .infinity)
            if waiting {
                HStack(spacing: 6) {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 1))
                        path.addLine(to: CGPoint(x: 16, y: 1))
                    }
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .frame(width: 16, height: 2)
                    Text("Waiting on Stadig Macro").font(.caption).foregroundStyle(Ink.text2)
                }
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            }
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(ScoreShape.order.enumerated()), id: \.element) { index, stat in
                if index > 0 { Rectangle().fill(Ink.hairline).frame(height: 1) }
                row(stat, line: lines.first { $0.stat == stat })
            }
        }
        .padding(.horizontal, 4)
    }

    private func row(_ stat: StatKind, line: StatLine?) -> some View {
        let score = line?.score
        let apps = line.map { $0.apps.isEmpty ? [$0.app] : $0.apps } ?? [.liftTrack]
        return Button {
            // Stadig Macro measures Vitality: nothing here to open until it's set up.
            if score != nil || stat != .vitality { open(stat) }
        } label: {
            HStack(spacing: 12) {
                Text(score.map(String.init) ?? "–").numeral(20).foregroundStyle(score == nil ? Ink.text3 : Ink.text)
                    .frame(width: 40, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(stat.label).font(.body.weight(.semibold)).foregroundStyle(score == nil ? Ink.text2 : Ink.text)
                        SourceChip(apps: apps)
                    }
                    Text(caption(stat, line: line)).font(.caption).foregroundStyle(Ink.text2).lineLimit(1)
                }
                Spacer(minLength: 4)
                if let line, score != nil, let trend = TrendWord(line.trend) {
                    Text(trend.text).font(.caption.weight(.semibold)).foregroundStyle(trend.color)
                }
            }
            .frame(minHeight: 54)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stat.label)
        .accessibilityValue("\(score.map(String.init) ?? "Not measured yet"). \(caption(stat, line: line))")
        .accessibilityIdentifier("progress.score\(stat.rawValue.identifierSuffix)")
    }

    /// One line on what moves the score, from what the app knows.
    private func caption(_ stat: StatKind, line: StatLine?) -> String {
        switch stat {
        case .strength:
            if let weakest = analysis.strength.weakest { return "\(weakest.category.label) is the limiter" }
        case .agility:
            if let limiter = analysis.agility.limiter { return "\(limiter.label) is the limiter" }
        case .endurance:
            if analysis.endurance.engineLagging { return "Under an hour of easy cardio a week" }
            return "\(Int(analysis.endurance.weeklyConditioningMinutes)) min of cardio a week"
        case .vitality:
            if line?.score == nil, !macroSetUp { return "Measured by Stadig Macro. Also free." }
        case .discipline:
            if let line, line.score != nil, !macroSetUp { return "\(line.label). Nutrition joins with Stadig Macro" }
        case .physique:
            if line?.score == nil { return "Tape your waist on Body to measure it" }
        default:
            break
        }
        guard let line, line.isKnown else { return "Not measured yet" }
        return line.label
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
        // Worked out once a render, not for each use below.
        let options = self.options
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
                        .foregroundStyle(Color.accentColor)
                    PointMark(x: .value("Day", point.day.date()), y: .value("e1RM", model.gym.unit.fromKilograms(point.e1rm)))
                        .symbolSize(24)
                        .foregroundStyle(Color.accentColor)
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
            Text("Training discipline").eyebrow().accessibilityAddTraits(.isHeader)
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
            // As Strength's card: the eyebrow, the score large, a ruler under it.
            Text("Endurance").eyebrow().accessibilityAddTraits(.isHeader)
            if let score = analysis.score {
                Text("\(Int(score.rounded()))").numeral(44, weight: .heavy).foregroundStyle(Ink.text)
                    .accessibilityLabel("Score \(Int(score.rounded()))")
                Ruler(value: score / 100, height: 10, divisions: 5).padding(.bottom, 4)
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
                Text("Agility").eyebrow().accessibilityAddTraits(.isHeader)
                Spacer()
                if let limiter = analysis.limiter { Pill(text: "Limiter: \(limiter.label)", color: Ink.ok) }
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
                        ScoreBar(score: result.score, highlight: analysis.limiterTest == test)
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
            Text("Your ratings").eyebrow().accessibilityAddTraits(.isHeader)
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
        .inkList()
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
        .inkList()
    }
}

/// A strength score on the ruler in fifths, each level's name under the line where it starts and the
/// one reached in the text colour. Progress's Strength and an exercise's own score use it.
struct LevelRuler: View {
    let score: Double
    var height: CGFloat = 28
    /// "Intermed." for a ruler in a narrow card, as the design's exercise page has it.
    var short = false

    static let levels = ["Beginner", "Novice", "Intermediate", "Advanced", "Elite"]

    var body: some View {
        VStack(spacing: 6) {
            Ruler(value: score / 100, height: height, divisions: 5)
            GeometryReader { geometry in
                ForEach(Array(Self.levels.enumerated()), id: \.offset) { index, level in
                    let reached = StrengthStandards.level(for: score) == level
                    let name = short && level == "Intermediate" ? "Intermed." : level
                    let label = Text(name).font(.system(size: 10, weight: .semibold)).foregroundStyle(reached ? Ink.text : Ink.text3)
                        .fixedSize()
                    if index == Self.levels.count - 1 {
                        label.frame(width: geometry.size.width, alignment: .trailing)
                    } else {
                        label.position(x: geometry.size.width * Double(index + 1) / Double(Self.levels.count), y: 6)
                    }
                }
            }
            .frame(height: 13)
            .accessibilityHidden(true)
        }
    }

    /// "7 to Intermediate": the points to the next level, or nil at Elite.
    static func next(_ score: Double) -> String? {
        let target = (score / 20).rounded(.down) * 20 + 20
        guard target <= 100 else { return nil }
        return "\(max(1, Int((target - score).rounded(.up)))) to \(StrengthStandards.level(for: target))"
    }
}
