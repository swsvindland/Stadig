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
    /// Your shape, opened from the header (and by `-yourShape` in DEBUG).
    @State private var showShape = false
    /// A score opened from Your shape beside Strength, on a wide screen.
    @State private var shownStat: StatKind?
    /// History and a session in it, opened by `-history` and `-sessionDetail` in DEBUG.
    @State private var showHistory = false
    @State private var shownSession: SessionRecord?

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
            .ownHeader()
            #if os(iOS)
            // Every width draws its own header over Strength.
            .toolbarVisibility(.hidden, for: .navigationBar)
            #endif
            .sessionResumeToolbar()
            .navigationDestination(isPresented: $showShape) {
                if let analysis = model.analysis { YourShapePage(analysis: analysis) }
            }
            .navigationDestination(item: $shownStat) { stat in ScoreDetailPage(stat: stat) }
            #if DEBUG
            .navigationDestination(isPresented: $showHistory) { HistoryView() }
            .navigationDestination(item: $shownSession) { record in SessionDetail(record: record) }
            .onAppear {
                guard !sizeClass.isWide else { return }
                if LaunchOptions.current.has("-yourShape") { showShape = true }
                if LaunchOptions.current.has("-history") { showHistory = true }
                if LaunchOptions.current.has("-sessionDetail") { shownSession = model.sessions.max { $0.start < $1.start } }
            }
            #endif
        }
    }

    /// The phone's single column, as the design has it: Strength large with each lift under it, the
    /// other scores in a row that opens Your shape, then your ratings and History as rows.
    private func column(_ analysis: LiftAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(analysis)
            StrengthCard(analysis: analysis, line: model.stats.first { $0.stat == .strength })
            Button {
                showShape = true
            } label: {
                OtherScores(lines: model.stats)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("progress.otherScores")
            RowCard {
                NavigationLink {
                    RatingsPage(trust: analysis.trust)
                } label: {
                    LinkRowLabel(title: "Your ratings", caption: "\(analysis.trust.label) · \(analysis.trust.evidenceCount) checks so far")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("progress.ratings")
                NavigationLink {
                    HistoryView()
                } label: {
                    LinkRowLabel(title: "History", caption: "\(model.sessions.count) sessions · \(model.activities.count) activities")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("progress.history")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .readableWidth()
    }

    private func header(_ analysis: LiftAnalysis) -> some View {
        PageHeader(eyebrow: blockLine(analysis), title: "Progress") {
            CircleIconButton(symbol: "hexagon", label: "Your shape", identifier: "progress.shape") { showShape = true }
        }
    }

    /// "Upper / lower · week 2 of 4".
    private func blockLine(_ analysis: LiftAnalysis) -> String? {
        guard let mesocycle = analysis.mesocycle, let block = analysis.block else { return nil }
        let week = min(block.weeksTotal, max(1, block.start.days(until: model.today) / 7 + 1))
        return "\(mesocycle.split.label) · week \(week) of \(block.weeksTotal)"
    }

    /// The phone's Progress laid out for width: Strength with each lift, your ratings and History on
    /// the left; Your shape, the six scores as one figure with a row each, beside it.
    private func wide(_ analysis: LiftAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(analysis)
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    StrengthCard(analysis: analysis, line: model.stats.first { $0.stat == .strength })
                    RowCard {
                        NavigationLink {
                            RatingsPage(trust: analysis.trust)
                        } label: {
                            LinkRowLabel(title: "Your ratings", caption: "\(analysis.trust.label) · \(analysis.trust.evidenceCount) checks so far")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("progress.ratings")
                        Button {
                            model.tab = .history
                        } label: {
                            LinkRowLabel(title: "History", caption: "\(model.sessions.count) sessions · \(model.activities.count) activities")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("progress.history")
                    }
                }
                .frame(maxWidth: .infinity)
                YourShape(lines: model.stats, earlier: model.earlierShape, analysis: analysis) { stat in
                    switch stat {
                    case .strength, .vitality: break
                    case .physique: model.tab = .body
                    default: shownStat = stat
                    }
                }
                .card(padding: 16)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: 1180)
        .frame(maxWidth: .infinity)
    }
}

/// Strength: the overall score large on a ruler marked with the levels, how far to the next, and
/// every lift on the same ruler, the weakest flagged, each opening its exercise.
struct StrengthCard: View {
    @Environment(AppModel.self) private var model
    let analysis: LiftAnalysis
    /// Strength as Your shape has it: how far it moved this month is the chip beside the level, or
    /// its trend before there's a month to measure.
    var line: StatLine?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 14) {
                if let overall = analysis.strength.overall {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Strength").eyebrow()
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(Int(overall.rounded()))").numeral(76, weight: .heavy).foregroundStyle(Ink.text)
                                Text(StrengthStandards.level(for: overall)).font(.title3.weight(.bold)).foregroundStyle(Ink.text)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        Spacer(minLength: 8)
                        if let change = line?.change {
                            ScoreChangeChip(change: change).padding(.bottom, 6)
                        } else if let trend = line.flatMap({ TrendWord($0.trend) }) {
                            TrendChip(trend: trend).padding(.bottom, 6)
                        }
                    }
                    LevelRuler(score: overall)
                    if let next = nextLevel(overall) {
                        let points = Text(next.points).foregroundStyle(Ink.text).fontWeight(.semibold)
                        let fastest = Text(next.fastest.map { " \($0)" } ?? "").foregroundStyle(Ink.text2).fontWeight(.medium)
                        Text("\(points)\(fastest)")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Strength").eyebrow()
                    Text("Scores appear once the main lifts have working weights: usually in the first two weeks.")
                        .font(.subheadline).foregroundStyle(Ink.text2)
                }
            }
            .padding(.top, 2)
            .card()
            VStack(alignment: .leading, spacing: 6) {
                CardTitle("By lift", detail: "Score from your best estimated max")
                // Strongest first, so the weakest, flagged, ends the list; what isn't scored yet after.
                VStack(spacing: 0) {
                    ForEach(StrengthCategory.allCases.sorted { (analysis.strength[$0]?.score ?? -1) > (analysis.strength[$1]?.score ?? -1) }) {
                        category in
                        liftRow(category)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.cardBackground, in: .rect(cornerRadius: 22, style: .continuous))
        }
    }

    @ViewBuilder
    private func liftRow(_ category: StrengthCategory) -> some View {
        if let score = analysis.strength[category] {
            NavigationLink {
                PushedExerciseDetail(exerciseID: score.exerciseID)
            } label: {
                scoredRow(category, score: score)
            }
            .buttonStyle(.plain)
            .hoverHighlight()
            .accessibilityIdentifier("progress.lift")
        } else {
            HStack {
                Text(category.label).font(.subheadline).foregroundStyle(Ink.text2)
                Spacer()
                Text("Not scored yet").font(.caption).foregroundStyle(Ink.text3)
            }
            .frame(minHeight: 33)
        }
    }

    private func scoredRow(_ category: StrengthCategory, score: CategoryScore) -> some View {
        let weakest = analysis.strength.weakest?.category == category
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(category.label).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text).lineLimit(1).minimumScaleFactor(0.8)
                if weakest { Text("Weakest").font(.caption.weight(.semibold)).foregroundStyle(Ink.ok) }
            }
            .frame(width: 112, alignment: .leading)
            Ruler(value: score.score / 100, color: weakest ? Ink.ok : .accentColor)
            Text("\(Int(score.score.rounded()))").numeral(20).foregroundStyle(weakest ? Ink.ok : Ink.text).frame(width: 30, alignment: .trailing)
        }
        .frame(minHeight: weakest ? 44 : 33)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(category.label): score \(Int(score.score.rounded())), \(score.level), \(Format.weight(score.oneRepMaxKg, unit: model.gym.unit)) estimated\(weakest ? ", weakest" : "")"
        )
    }

    /// "3 points to Intermediate." and "Overhead press gets you there fastest."
    private func nextLevel(_ overall: Double) -> (points: String, fastest: String?)? {
        let target = (overall / 20).rounded(.down) * 20 + 20
        guard target <= 100 else { return nil }
        let points = max(1, Int((target - overall).rounded(.up)))
        let name = StrengthStandards.level(for: target)
        let fastest = analysis.strength.priorities.first?.reason ?? analysis.strength.weakest.map { "\($0.category.label) gets you there fastest." }
        return ("\(points) \(points == 1 ? "point" : "points") to \(name).", fastest)
    }
}

/// The six scores as one figure, with where they stood a few months ago dashed behind it, and each in
/// a row: its number, the app that measures it, a line on what moves it, and how far it moved this
/// month (its trend, before there's a month to measure). A score Stadig Macro measures waits for it,
/// said plainly.
struct YourShape: View {
    let lines: [StatLine]
    /// The scores as they stood a few months ago, dashed behind (`AppModel.earlierShape`).
    var earlier: EarlierShape?
    let analysis: LiftAnalysis
    let open: (StatKind) -> Void

    private var macroSetUp: Bool { lines.contains { $0.apps.contains(.macroTrack) } }

    /// The figure beside its rows rather than over them, where there's room.
    var sideBySide = false

    var body: some View {
        let axes = ScoreShape.axes(lines, earlier: earlier)
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
                .frame(maxWidth: sideBySide ? 380 : 320)
                .frame(maxWidth: .infinity)
            if let earlier { ShapeLegend(earlier: earlier) }
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

    @ViewBuilder
    private func row(_ stat: StatKind, line: StatLine?) -> some View {
        if stat == .vitality, line?.score == nil, !macroSetUp {
            // Stadig Macro measures it: nothing here to open, but where to get it.
            HStack(spacing: 12) {
                rowContent(stat, line: line)
                Link("Get it", destination: Self.macroPage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("progress.getMacro")
            }
            .frame(minHeight: 54)
        } else {
            button(stat, line: line)
        }
    }

    /// Stadig Macro's page on the site.
    static let macroPage = URL(string: "https://stadig.dev/macro")!

    private func button(_ stat: StatKind, line: StatLine?) -> some View {
        Button {
            open(stat)
        } label: {
            rowContent(stat, line: line)
                .frame(minHeight: 54)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stat.label)
        .accessibilityValue("\(line.map(ScoresCard.spoken) ?? "Not measured yet"). \(caption(stat, line: line))")
        .accessibilityIdentifier("progress.score\(stat.rawValue.identifierSuffix)")
    }

    private func rowContent(_ stat: StatKind, line: StatLine?) -> some View {
        let score = line?.score
        let apps = line.map { $0.apps.isEmpty ? [$0.app] : $0.apps } ?? [.liftTrack]
        return HStack(spacing: 12) {
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
            if let change = line?.change {
                ScoreChangeLabel(change: change)
            } else if let line, score != nil, let trend = TrendWord(line.trend) {
                Text(trend.text).font(.caption.weight(.semibold)).foregroundStyle(trend.color)
            }
        }
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
    @Environment(\.horizontalSizeClass) private var sizeClass
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
        // Month by month, newest first, as the sessions came.
        let months = Dictionary(grouping: entries) { Calendar.current.dateInterval(of: .month, for: $0.date)?.start ?? $0.date }
            .sorted { $0.key > $1.key }
        List {
            if !sizeClass.isWide {
                FormHeading(
                    eyebrow: "Progress", title: "History",
                    detail: entries.isEmpty ? nil : "\(model.sessions.count) sessions · \(model.activities.count) activities")
            }
            ForEach(months, id: \.key) { month, entries in
                Section {
                    ForEach(entries) { entry in
                        switch entry {
                        case .session(let session):
                            NavigationLink {
                                SessionDetail(record: session)
                            } label: {
                                row(
                                    date: session.start, symbol: "dumbbell", title: session.title,
                                    caption:
                                        "\(Self.time(session.start)) · \(session.minutes) min · \(session.workSets.count) sets\(session.device == Platform.deviceName ? "" : " · \(session.device)")"
                                )
                            }
                            .swipeActions { Button("Delete", role: .destructive) { model.delete(session: session.id) } }
                            .contextMenu { Button("Delete", systemImage: "trash", role: .destructive) { model.delete(session: session.id) } }
                            .accessibilityIdentifier("history.session")
                        case .activity(let log):
                            row(
                                date: log.start, symbol: log.type.symbol, title: log.type.label,
                                caption: "\(Self.time(log.start)) · \(log.minutes) min · effort \(log.intensity)\(sourceLabel(log))"
                            )
                            .swipeActions { Button("Delete", role: .destructive) { model.delete(activity: log.id) } }
                            .contextMenu { Button("Delete", systemImage: "trash", role: .destructive) { model.delete(activity: log.id) } }
                            .accessibilityIdentifier("history.activity")
                        }
                    }
                } header: {
                    SectionEyebrow(month.formatted(.dateTime.month(.wide).year()), detail: "\(entries.count)")
                }
                .inkRows()
            }
        }
        .inkList()
        .detailPage(title: "History", wide: sizeClass.isWide)
        .overlay {
            if entries.isEmpty {
                EmptyCard(symbol: "clock", title: "Nothing yet", detail: "Sessions and outside activities show here.").padding(16)
            }
        }
    }

    /// A session or an activity: its day as Plan's week names days, what it was, when and how much,
    /// and what kind it was, quietly.
    private func row(date: Date, symbol: String, title: String, caption: String) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(date.formatted(.dateTime.weekday(.abbreviated))).eyebrow()
                Text(date.formatted(.dateTime.day())).numeral(20).foregroundStyle(Ink.text)
            }
            .frame(width: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(Ink.text)
                Text(caption).font(.caption.monospacedDigit()).foregroundStyle(Ink.text3)
            }
            Spacer(minLength: 8)
            Image(systemName: symbol).font(.footnote).foregroundStyle(Ink.text3).accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// "17:30", in the person's own clock.
    private static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func sourceLabel(_ log: ActivityLog) -> String {
        if case .health(_, let name) = log.source { return " · \(name)" }
        return ""
    }
}

struct SessionDetail: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let record: SessionRecord

    var body: some View {
        SessionSetsList(
            record: record, header: false,
            heading: sizeClass.isWide
                ? nil
                : (eyebrow: "History · \(record.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))", title: record.title)
        )
        .detailPage(title: record.title, wide: sizeClass.isWide)
    }
}

/// A finished session's feedback, sets, conditioning and heat.
struct SessionSetsList: View {
    @Environment(AppModel.self) private var model
    let record: SessionRecord
    /// Its title and when, at the top: for the inspector, where there's no navigation title.
    let header: Bool
    /// A phone page's own heading over the list: where it was opened from and its title.
    var heading: (eyebrow: String, title: String)?

    private static let energies = ["Drained", "Low", "OK", "Good", "Great"]
    private static let soreness = ["None", "A little", "Sore", "Very"]

    var body: some View {
        List {
            if let heading { FormHeading(eyebrow: heading.eyebrow, title: heading.title) }
            if header || heading != nil {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        if header {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.start.formatted(date: .abbreviated, time: .shortened)).eyebrow()
                                Text(record.title).font(.title3.bold()).foregroundStyle(Ink.text)
                            }
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 28) {
                            figure(Measure(value: "\(record.minutes)", unit: "min", size: 44, weight: .heavy), "minutes")
                            figure(Measure(value: "\(record.workSets.count)", size: 44, weight: .heavy), "work sets")
                            if record.device != Platform.deviceName || header {
                                figure(Text(record.device).font(.callout.weight(.semibold)).foregroundStyle(Ink.text), "recorded on")
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                // On the ground, as the summary's numbers are, not in a card of their own.
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            }
            if let feedback = record.feedback {
                Section {
                    ValueRow(title: "Energy", value: Self.energies[min(max(feedback.energy, 1), 5) - 1])
                    ValueRow(title: "Coming in", value: feedback.soreness == 0 ? "Not sore" : Self.soreness[min(max(feedback.soreness, 0), 3)])
                    ValueRow(
                        title: "Joint pain", value: feedback.jointPain.isEmpty ? "None" : feedback.jointPain.map(\.label).joined(separator: ", "))
                } header: {
                    Text("How it felt").eyebrow()
                }
            }
            ForEach(record.exercises) { log in
                let exercise = model.catalog.resolve(log.exerciseID)
                Section {
                    ForEach(Array(log.sets.enumerated()), id: \.element.id) { index, set in
                        HStack(spacing: 12) {
                            Text(badge(index, in: log.sets))
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Ink.text2)
                                .frame(width: 26, height: 26)
                                .overlay { Circle().strokeBorder(Ink.track, lineWidth: 1.5) }
                                .accessibilityHidden(true)
                            // As the session's own list sets them: the number large, its unit small.
                            SetValue(
                                load: set.loadKg, reps: set.reps, seconds: set.seconds, plus: false, exercise: exercise, unit: model.gym.unit,
                                quiet: set.kind == .warmup)
                            Spacer(minLength: 8)
                            if let rating = set.rating {
                                HStack(spacing: 6) {
                                    RatingMark(rating: rating)
                                    Text(rating.label).font(.caption).foregroundStyle(Ink.text2)
                                }
                            } else if set.kind != .warmup {
                                Text(set.kind.label).font(.caption).foregroundStyle(Ink.text3)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text(exercise.name).font(.callout.weight(.semibold)).foregroundStyle(Ink.text).textCase(nil)
                }
            }
            ForEach(record.conditioning, id: \.exerciseID) { c in
                Section {
                    ValueRow(title: "Done", value: "\(c.minutes) min\(c.averageHeartRate.map { " · avg \(Int($0)) bpm" } ?? "")")
                } header: {
                    Text(model.catalog.resolve(c.exerciseID).name).font(.callout.weight(.semibold)).foregroundStyle(Ink.text).textCase(nil)
                }
            }
            ForEach(Array((record.heat ?? []).enumerated()), id: \.offset) { _, heat in
                Section {
                    HStack {
                        Text(
                            "\(Format.number(heat.minutes)) min\(heat.temperatureC.map { " at \(Format.temperature($0, fahrenheit: model.fahrenheit))" } ?? "")"
                        )
                        .font(.callout.weight(.semibold).monospacedDigit()).foregroundStyle(Ink.text)
                        Spacer()
                        RatingMark(rating: heat.rating)
                    }
                } header: {
                    Text(model.catalog.resolve(heat.exerciseID).name).font(.callout.weight(.semibold)).foregroundStyle(Ink.text).textCase(nil)
                }
            }
        }
        .inkRows()
        .inkList()
    }

    /// A number with what it counts under it, as the summary's are.
    private func figure(_ value: some View, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            value
            Text(label).font(.caption).foregroundStyle(Ink.text3)
        }
        .accessibilityElement(children: .combine)
    }

    /// "W" for a warm-up, then 1, 2, 3 for the rest, as the session numbers them.
    private func badge(_ index: Int, in sets: [LoggedSet]) -> String {
        if sets[index].kind == .warmup { return "W" }
        return "\(sets[...index].filter { $0.kind != .warmup }.count)"
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
            if short {
                // The exercise page's scale: each level's name set against the tick that ends its
                // fifth, in the scale's small capitals.
                HStack(spacing: 0) {
                    ForEach(Self.levels, id: \.self) { level in
                        ScaleLabel(level == "Intermediate" ? "Intermed." : level)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .accessibilityHidden(true)
            } else {
                labels
            }
        }
    }

    /// Each level's name centred on the line where it starts, the one reached in the text colour.
    private var labels: some View {
        GeometryReader { geometry in
            ForEach(Array(Self.levels.enumerated()), id: \.offset) { index, level in
                let reached = StrengthStandards.level(for: score) == level
                let name = level
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

    /// "7 to Intermediate": the points to the next level, or nil at Elite.
    static func next(_ score: Double) -> String? {
        let target = (score / 20).rounded(.down) * 20 + 20
        guard target <= 100 else { return nil }
        return "\(max(1, Int((target - score).rounded(.up)))) to \(StrengthStandards.level(for: target))"
    }
}

/// The other three scores Stadig Lift measures, each over a slim ruler: the row under Strength that
/// opens Your shape.
struct OtherScores: View {
    let lines: [StatLine]

    private static let shown: [StatKind] = [.endurance, .agility, .discipline]

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(Self.shown, id: \.self) { stat in
                let line = lines.first { $0.stat == stat }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(stat.label).font(.caption).foregroundStyle(Ink.text3).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 2)
                        if let change = line?.change {
                            ScoreChangeLabel(change: change)
                        } else if let line, line.score != nil, let trend = TrendWord(line.trend) {
                            Text(trend.text).font(.caption).foregroundStyle(trend.color).lineLimit(1)
                        }
                    }
                    Text(line?.score.map(String.init) ?? "–").numeral(30).foregroundStyle(line?.score == nil ? Ink.text3 : Ink.text)
                    Ruler.thin(Double(line?.score ?? 0) / 100)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(stat.label)
                .accessibilityValue(line.map(ScoresCard.spoken) ?? "Not measured yet")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.cardBackground, in: .rect(cornerRadius: 22, style: .continuous))
        .contentShape(.rect)
        .accessibilityElement(children: .contain)
        .accessibilityHint("Opens Your shape")
    }
}

/// Your shape, pushed from Progress: the six scores as one figure and a row each. A row opens what's
/// behind it: Strength is Progress itself, Physique is Body, and the others their own page.
struct YourShapePage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    let analysis: LiftAnalysis
    @State private var detail: StatKind?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if !sizeClass.isWide { DetailHeader(eyebrow: "Progress", title: "Your shape") }
                YourShape(lines: model.stats, earlier: model.earlierShape, analysis: model.analysis ?? analysis) { stat in
                    switch stat {
                    case .strength: dismiss()
                    case .physique: model.tab = .body
                    case .vitality: break
                    default: detail = stat
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .readableWidth()
        }
        .background(.pageBackground)
        .detailPage(title: "Your shape", wide: sizeClass.isWide)
        .navigationDestination(item: $detail) { stat in ScoreDetailPage(stat: stat) }
        .accessibilityIdentifier("progress.shapePage")
    }
}

/// One score's own page, from Your shape: Endurance, Agility or training Discipline in full.
struct ScoreDetailPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let stat: StatKind

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !sizeClass.isWide { DetailHeader(eyebrow: "Your shape", title: stat.label) }
                if let analysis = model.analysis {
                    switch stat {
                    case .endurance: EnduranceCard(analysis: analysis.endurance)
                    case .agility: AgilityCard(analysis: analysis.agility)
                    case .discipline: DisciplineCard(score: analysis.discipline)
                    default: EmptyView()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .readableWidth()
        }
        .background(.pageBackground)
        .detailPage(title: stat.label, wide: sizeClass.isWide)
    }
}

/// How far your ratings can be believed, from Progress's row.
struct RatingsPage: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let trust: TrustState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !sizeClass.isWide { DetailHeader(eyebrow: "Progress", title: "Your ratings") }
                RatingsCard(trust: trust)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .readableWidth()
        }
        .background(.pageBackground)
        .detailPage(title: "Your ratings", wide: sizeClass.isWide)
    }
}
