import Charts
import NutritionEngine
import SwiftUI
import SystemCore

/// The weight trend as the hero, calories against target and maintenance, and the habit, under a
/// way into Your shape (the six scores). Then food quality, meal timing, and the vitamins and
/// minerals. With room, Your shape opens the page, the cards sit side by side, the charts are wider
/// with one range for both, and the vitamins and minerals are a table.
struct ProgressTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var range = 60

    var compact: Bool { sizeClass == .compact }

    var body: some View {
        NavigationStack {
            ScrollView {
                if compact {
                    VStack(alignment: .leading, spacing: 12) {
                        PageHeader(eyebrow: eyebrow, title: "Progress") {
                            CircleIconButton(symbol: "scalemass", label: "Weigh in", identifier: "progress.weighIn") { model.showWeighIn = true }
                        }
                        if let analysis = model.analysis { list(analysis) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .readableWidth()
                } else if let analysis = model.analysis {
                    VStack(alignment: .leading, spacing: 4) {
                        // The charts' one range and the weigh-in, as the page's own controls.
                        WideHeader(eyebrow: eyebrow, title: "Progress") {
                            InkSegmented(options: ChartRange.allCases.map { ($0.days, $0.label) }, selection: $range)
                                .frame(width: 240)
                                .help("How far back the charts go")
                                .accessibilityIdentifier("progress.range")
                            CircleIconButton(symbol: "scalemass", label: "Weigh in", identifier: "progress.weighIn") { model.showWeighIn = true }
                                .help("Record a weigh-in")
                        }
                        board(analysis)
                    }
                    .padding(.top, 12)
                    .frame(maxWidth: 1180)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(.pageBackground)
            .navigationTitle("Progress")
            .widePage(!compact)
            .hidesNavigationBar()
        }
    }

    /// Where the plan is: "Cut, week 1 of 4".
    var eyebrow: String {
        if let phase = model.analysis?.phase { return "\(phase.kind.label), week \(phase.week(on: model.today)) of \(phase.weeks)" }
        if let assessment = model.analysis?.assessment, !assessment.complete {
            return "Assessment, day \(assessment.day) of \(assessment.totalDays)"
        }
        return "Your trend"
    }

    func list(_ analysis: MacroAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            YourShapeRow()
            WeightCard(analysis: analysis, range: $range)
            IntakeCard(analysis: analysis)
            DisciplineCard(analysis: analysis)
            QualityCard(report: analysis.quality, fiber: analysis.micros.reading("fiber"))
            if model.tracksMealTiming { MealTimingCard(report: analysis.mealTiming) }
            NutrientsCard(report: analysis.micros)
        }
    }

    func board(_ analysis: MacroAnalysis) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow {
                YourShapeCard().gridCellColumns(2)
            }
            GridRow {
                WeightCard(analysis: analysis, range: $range, chartHeight: 280, showsRange: false)
                    .gridCellColumns(2)
            }
            GridRow {
                IntakeCard(analysis: analysis, days: range, chartHeight: 220)
                VStack(spacing: 16) {
                    QualityCard(report: analysis.quality, fiber: analysis.micros.reading("fiber"))
                    DisciplineCard(analysis: analysis)
                }
            }
            if model.tracksMealTiming {
                GridRow {
                    MealTimingCard(report: analysis.mealTiming).gridCellColumns(2)
                }
            }
            GridRow {
                NutrientTableCard(report: analysis.micros).gridCellColumns(2)
            }
        }
        .padding([.horizontal, .bottom], 20)
    }
}

/// How far back Progress's charts go, where they share one range.
enum ChartRange: Int, CaseIterable, Identifiable {
    case month = 30, twoMonths = 60, half = 182, year = 365

    var id: Int { rawValue }
    var days: Int { rawValue }

    var label: String {
        switch self {
        case .month: "1M"
        case .twoMonths: "2M"
        case .half: "6M"
        case .year: "1Y"
        }
    }
}

/// Target adherence on logged days as a score over a ruler (the 80% that starts the zone marked),
/// and how many days are logged at all.
struct DisciplineCard: View {
    let analysis: MacroAnalysis

    var body: some View {
        let score = analysis.discipline
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Nutrition discipline").font(.callout.weight(.semibold)).foregroundStyle(Ink.text)
                Spacer()
                Text(score.rate.map { Format.whole($0 * 100) } ?? "–").numeral(30).foregroundStyle(score.rate == nil ? Ink.text3 : Ink.text)
            }
            .accessibilityElement(children: .combine)
            Ruler(value: score.rate ?? 0, color: score.band == .below ? Ink.ok : Ink.good, height: 14, marker: 0.8)
            Text(score.band.map { "\($0.label). \(score.note)" } ?? score.note)
                .font(.caption).foregroundStyle(Ink.text2).fixedSize(horizontal: false, vertical: true)
            if let rate = analysis.loggingRate {
                Text("Logged \(Format.percent(rate)) of days in the last four weeks. Unlogged days are unknown, not misses.")
                    .font(.caption).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
            }
        }
        .inkCard()
        .accessibilityIdentifier("progress.discipline")
    }
}

/// The trend's weight as the hero, how fast it's moving and what that means for the phase, then
/// the scale's readings as dots and the trend as a line: the line is what's real.
struct WeightCard: View {
    @Environment(AppModel.self) private var model
    let analysis: MacroAnalysis
    @Binding var range: Int
    var chartHeight: CGFloat = 110
    /// The card's own range picker; off where the screen has one for every chart.
    var showsRange = true

    var trend: WeightTrend { analysis.trend }

    var body: some View {
        let unit = model.units.weight
        let start = model.today.adding(days: -range)
        let points = trend.points.filter { $0.day >= start }
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    if let latest = trend.latest {
                        Measure(value: Format.number(unit.fromKilograms(latest.trend)), unit: unit.symbol, size: 76, weight: .heavy)
                            .foregroundStyle(Ink.text)
                            .accessibilityIdentifier("progress.trendWeight")
                    } else {
                        Text("Weight trend").font(.callout.weight(.semibold)).foregroundStyle(Ink.text)
                    }
                    Spacer(minLength: 8)
                    if let change = analysis.weeklyChange {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Format.signed(unit.fromKilograms(change))).numeral(20).foregroundStyle(verdict?.color ?? Ink.text)
                            Text("\(unit.symbol) a week").font(.caption).foregroundStyle(Ink.text3)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                if let sentence {
                    Text(sentence).font(.subheadline).foregroundStyle(Ink.text).fixedSize(horizontal: false, vertical: true)
                }
            }
            if points.count >= 2 {
                chart(points, unit: unit)
                HStack(spacing: 12) {
                    legend(dot: true, "Scale")
                    legend(dot: false, "Trend")
                    Spacer(minLength: 8)
                    if showsRange {
                        InkSegmented(options: ChartRange.allCases.map { ($0.days, $0.label) }, selection: $range)
                            .frame(maxWidth: 196)
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("Range")
                            .accessibilityIdentifier("progress.range")
                    }
                }
            } else {
                Text("Weigh in each morning and the trend appears after a few days.").font(.subheadline).foregroundStyle(Ink.text2)
            }
            if !trend.outliers.isEmpty {
                Text(
                    "\(trend.outliers.count) reading\(trend.outliers.count == 1 ? "" : "s") far from the days around \(trend.outliers.count == 1 ? "it" : "them") left out as likely misreads."
                )
                .font(.caption).foregroundStyle(Ink.text3)
            }
        }
        .inkCard()
    }

    var verdict: PhasePace.Verdict? {
        PhasePace.verdict(weeklyChange: analysis.weeklyChange, phase: analysis.phase, weightKg: trend.latest?.trend ?? analysis.referenceKg)
    }

    /// What the trend means for the phase, in a sentence.
    var sentence: String? {
        guard let latest = trend.latest, analysis.weeklyChange != nil else { return nil }
        let unit = model.units.weight
        guard let phase = analysis.phase else { return "The line is the trend; the dots are the scale's day-to-day swings, mostly water." }
        guard let aim = PhasePace.aim(trendKg: latest.trend, phase: phase, today: model.today) else {
            return verdict == .onPace ? "Holding steady, as maintenance should." : "Drifting: maintenance aims to hold steady."
        }
        let target =
            "\(Format.number(unit.fromKilograms(aim.kg))) \(unit.symbol) by \(Format.day(aim.day, style: .dateTime.month(.abbreviated).day()))"
        switch verdict {
        case .onPace: return "On pace to reach \(target)."
        case .faster: return "Ahead of the plan, which aims for \(target)."
        case .slower: return "Behind the plan, which aims for \(target)."
        case .offCourse: return "Going the wrong way for a \(phase.kind.label.lowercased()): the plan aims for \(target)."
        case nil: return nil
        }
    }

    func chart(_ points: [WeightTrend.Point], unit: WeightUnit) -> some View {
        VStack(spacing: 6) {
            Chart {
                ForEach(points, id: \.day) { p in
                    if let scale = p.scale {
                        PointMark(x: .value("Day", p.day.date()), y: .value("Scale", unit.fromKilograms(scale)))
                            .symbolSize(22)
                            .foregroundStyle(Ink.text3)
                    }
                    LineMark(x: .value("Day", p.day.date()), y: .value("Trend", unit.fromKilograms(p.trend)))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
                if let last = points.last {
                    PointMark(x: .value("Day", last.day.date()), y: .value("Trend", unit.fromKilograms(last.trend)))
                        .symbol {
                            Circle().fill(Color.accentColor).frame(width: 10, height: 10)
                                .overlay { Circle().stroke(Ink.surface, lineWidth: 2.5) }
                        }
                }
            }
            .chartYScale(domain: Self.domain(points.flatMap { [$0.trend] + ($0.scale.map { [$0] } ?? []) }.map(unit.fromKilograms)))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Ink.hairline)
                    AxisValueLabel {
                        if let weight = value.as(Double.self) { Text(Format.number(weight)).font(.caption2).foregroundStyle(Ink.text3) }
                    }
                }
            }
            .frame(height: chartHeight)
            .accessibilityLabel("Weight over the last \(ChartRange(rawValue: range)?.label ?? "\(range) days")")
            if let first = points.first?.day {
                HStack {
                    ScaleLabel(Format.day(first, style: .dateTime.month(.abbreviated).day()))
                    Spacer()
                    ScaleLabel(Format.day(first.adding(days: first.days(until: model.today) / 2), style: .dateTime.month(.abbreviated).day()))
                    Spacer()
                    ScaleLabel("Today")
                }
                .padding(.trailing, 28)
                .accessibilityHidden(true)
            }
        }
    }

    /// Close around the readings, as the canvas draws it: the trend's slope is the story, not zero.
    static func domain(_ values: [Double]) -> ClosedRange<Double> {
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let pad = max(0.2, (high - low) * 0.08)
        return (low - pad)...(high + pad)
    }

    func legend(dot: Bool, _ title: String) -> some View {
        HStack(spacing: 6) {
            if dot {
                Circle().fill(Ink.text3).frame(width: 6, height: 6)
            } else {
                Capsule().fill(Color.accentColor).frame(width: 14, height: 2.5)
            }
            Text(title).font(.caption).foregroundStyle(Ink.text3)
        }
    }
}

/// The last four weeks (or `days`) of calories as bars, partly logged days on the track, against the
/// target (a solid line) and maintenance (dashed). Unlogged days are left blank.
struct IntakeCard: View {
    @Environment(AppModel.self) private var model
    let analysis: MacroAnalysis
    var days = 28
    var chartHeight: CGFloat = 60

    var body: some View {
        let today = model.today
        let days = (0..<self.days).map { today.adding(days: -(self.days - 1) + $0) }
        VStack(alignment: .leading, spacing: 10) {
            CardTitle("Calories", detail: detail(from: days.first ?? today))
            Chart {
                ForEach(days, id: \.self) { day in
                    if let n = analysis.intakeByDay[day] {
                        BarMark(x: .value("Day", day.date(), unit: .day), y: .value("kcal", n.kcal))
                            .foregroundStyle(analysis.usable[day] != nil ? Color.accentColor : Ink.track)
                            .clipShape(.rect(topLeadingRadius: 3, topTrailingRadius: 3))
                    }
                }
                RuleMark(y: .value("Maintenance", analysis.maintenance.kcal))
                    .foregroundStyle(Ink.text3).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                if let kcal = analysis.targets.kcal {
                    RuleMark(y: .value("Target", kcal)).foregroundStyle(Ink.text).lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: chartHeight)
            .accessibilityLabel("Daily calories, \(title). Fully logged days are filled; partly logged days are grey.")
            HStack {
                legend(dashed: true, "Maintenance \(Format.whole(analysis.maintenance.kcal))")
                Spacer(minLength: 8)
                if let kcal = analysis.targets.kcal { legend(dashed: false, "Target \(Format.whole(kcal))") }
            }
        }
        .inkCard(padding: 16)
    }

    /// When the phase began, if it's in the chart: "Cut began Monday".
    func detail(from first: Day) -> String {
        guard let phase = analysis.phase, phase.start >= first, phase.start <= model.today else { return title }
        let ago = phase.start.days(until: model.today)
        let when =
            switch ago {
            case 0: "today"
            case 1: "yesterday"
            case 2..<7: Format.day(phase.start, style: .dateTime.weekday(.wide))
            default: Format.day(phase.start, style: .dateTime.month(.abbreviated).day())
            }
        return "\(phase.kind.label) began \(when)"
    }

    var title: String {
        switch days {
        case 28: "Last 4 weeks"
        case ...45: "Last month"
        case ...100: "Last 2 months"
        case ...200: "Last 6 months"
        default: "Last year"
        }
    }

    func legend(dashed: Bool, _ text: String) -> some View {
        HStack(spacing: 6) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 1))
                path.addLine(to: CGPoint(x: 14, y: 1))
            }
            .stroke(dashed ? Ink.text3 : Ink.text, style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [3, 2] : []))
            .frame(width: 14, height: 2)
            Text(text).font(.caption.monospacedDigit()).foregroundStyle(Ink.text3)
        }
    }
}
