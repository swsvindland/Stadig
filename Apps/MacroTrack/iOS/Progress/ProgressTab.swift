import Charts
import NutritionEngine
import SwiftUI
import SystemCore

/// The weight trend, intake against target, and the habit. With room, the cards sit side by side,
/// the charts are wider with one range for both, and the vitamins and minerals are a table.
struct ProgressTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var range = 60

    var body: some View {
        NavigationStack {
            ScrollView {
                if let analysis = model.analysis {
                    if sizeClass == .compact { list(analysis) } else { board(analysis) }
                }
            }
            .background(.pageBackground)
            .navigationTitle("Progress")
            .toolbar {
                if sizeClass != .compact {
                    ToolbarItem(placement: .principal) {
                        Picker("Range", selection: $range) {
                            ForEach(ChartRange.allCases) { Text($0.label).tag($0.days) }
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                        .help("How far back the charts go")
                        .accessibilityIdentifier("progress.range")
                    }
                }
                ToolbarItem(placement: .barTrailing) {
                    Button {
                        model.showWeighIn = true
                    } label: {
                        Label("Weigh In", systemImage: "scalemass")
                    }
                    .help("Record a weigh-in")
                    .accessibilityIdentifier("progress.weighIn")
                }
            }
        }
    }

    func list(_ analysis: MacroAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            WeightCard(trend: analysis.trend, weeklyChange: analysis.weeklyChange, range: $range)
            IntakeCard(analysis: analysis)
            QualityCard(report: analysis.quality, fiber: analysis.micros.reading("fiber"))
            NutrientsCard(report: analysis.micros)
            DisciplineCard(analysis: analysis)
        }
        .padding()
        .readableWidth()
    }

    func board(_ analysis: MacroAnalysis) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow {
                WeightCard(trend: analysis.trend, weeklyChange: analysis.weeklyChange, range: $range, chartHeight: 280, showsRange: false)
                    .gridCellColumns(2)
            }
            GridRow {
                IntakeCard(analysis: analysis, days: range, chartHeight: 220)
                VStack(spacing: 16) {
                    QualityCard(report: analysis.quality, fiber: analysis.micros.reading("fiber"))
                    DisciplineCard(analysis: analysis)
                }
            }
            GridRow {
                NutrientTableCard(report: analysis.micros).gridCellColumns(2)
            }
        }
        .padding(20)
        .frame(maxWidth: 1180)
        .frame(maxWidth: .infinity)
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

/// Target adherence on logged days, and how many days are logged at all.
struct DisciplineCard: View {
    let analysis: MacroAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Discipline").font(.headline)
            DisciplineGauge(score: analysis.discipline)
            Text(analysis.discipline.note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let rate = analysis.loggingRate {
                Label(
                    "Logged \(Format.percent(rate)) of days in the last four weeks. Unlogged days are unknown, not misses.",
                    systemImage: "calendar"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .card()
    }
}

/// Scale readings as dots, the trend as a line: the line is what's real.
struct WeightCard: View {
    @Environment(AppModel.self) private var model
    let trend: WeightTrend
    let weeklyChange: Double?
    @Binding var range: Int
    var chartHeight: CGFloat = 200
    /// The card's own range picker; off where the screen has one for every chart.
    var showsRange = true

    var body: some View {
        let unit = model.units.weight
        let start = model.today.adding(days: -range)
        let points = trend.points.filter { $0.day >= start }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weight trend").font(.headline)
                    if let latest = trend.latest {
                        Text(Format.weight(latest.trend, unit: unit)).font(.title.weight(.bold).monospacedDigit())
                            .accessibilityIdentifier("progress.trendWeight")
                    }
                }
                Spacer()
                if let weeklyChange {
                    Text(Format.weeklyChange(weeklyChange, unit: unit)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if points.count >= 2 {
                Chart {
                    ForEach(points, id: \.day) { p in
                        if let scale = p.scale {
                            PointMark(x: .value("Day", p.day.date()), y: .value("Scale", unit.fromKilograms(scale)))
                                .symbolSize(18)
                                .foregroundStyle(.secondary.opacity(0.5))
                        }
                        LineMark(x: .value("Day", p.day.date()), y: .value("Trend", unit.fromKilograms(p.trend)))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Color.accentColor)
                            .lineStyle(StrokeStyle(lineWidth: 3))
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: chartHeight)
                if showsRange {
                    Picker("Range", selection: $range) {
                        Text("1M").tag(30)
                        Text("2M").tag(60)
                        Text("6M").tag(182)
                        Text("1Y").tag(365)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("progress.range")
                }
            } else {
                Text("Weigh in each morning and the trend appears after a few days.").font(.subheadline).foregroundStyle(.secondary)
            }
            if !trend.outliers.isEmpty {
                Label(
                    "\(trend.outliers.count) reading\(trend.outliers.count == 1 ? "" : "s") far from the days around \(trend.outliers.count == 1 ? "it" : "them") left out as likely misreads.",
                    systemImage: "exclamationmark.circle"
                )
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }
}

/// The last four weeks (or `days`) of calories against the target, unlogged days left blank.
struct IntakeCard: View {
    let analysis: MacroAnalysis
    var days = 28
    var chartHeight: CGFloat = 170

    var body: some View {
        let today = Day.today
        let days = (0..<self.days).map { today.adding(days: -(self.days - 1) + $0) }
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Chart {
                ForEach(days, id: \.self) { day in
                    if let n = analysis.intakeByDay[day] {
                        BarMark(x: .value("Day", day.date(), unit: .day), y: .value("kcal", n.kcal))
                            .foregroundStyle(analysis.usable[day] != nil ? Color.accentColor : Color.accentColor.opacity(0.35))
                    }
                }
                if let kcal = analysis.targets.kcal {
                    RuleMark(y: .value("Target", kcal)).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                RuleMark(y: .value("Maintenance", analysis.maintenance.kcal)).foregroundStyle(.orange.opacity(0.7))
            }
            .frame(height: chartHeight)
            HStack(spacing: 14) {
                legend(Color.accentColor, "Complete day")
                legend(Color.accentColor.opacity(0.35), "Partial")
                legend(.orange, "Maintenance")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .card()
    }

    var title: String {
        switch days {
        case 28: "Calories, last 4 weeks"
        case ...45: "Calories, last month"
        case ...100: "Calories, last 2 months"
        case ...200: "Calories, last 6 months"
        default: "Calories, last year"
        }
    }

    func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(text)
        }
    }
}
