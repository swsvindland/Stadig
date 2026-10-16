import SwiftUI
import Charts
import NutritionEngine
import SystemCore

/// The weight trend, intake against target, and the habit.
struct ProgressTab: View {
    @Environment(AppModel.self) private var model
    @State private var range = 60

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let analysis = model.analysis {
                        WeightCard(trend: analysis.trend, weeklyChange: analysis.weeklyChange, range: $range)
                        IntakeCard(analysis: analysis)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Discipline").font(.headline)
                            DisciplineGauge(score: analysis.discipline)
                            Text(analysis.discipline.note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            if let rate = analysis.loggingRate {
                                Label("Logged \(Format.percent(rate)) of days in the last four weeks. Unlogged days are unknown, not misses.",
                                      systemImage: "calendar")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .card()
                    }
                }
                .padding()
                .readableWidth()
            }
            .background(.pageBackground)
            .navigationTitle("Progress")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.showWeighIn = true
                    } label: {
                        Image(systemName: "scalemass")
                    }
                    .accessibilityLabel("Weigh in")
                }
            }
        }
    }
}

/// Scale readings as dots, the trend as a line: the line is what's real.
struct WeightCard: View {
    @Environment(AppModel.self) private var model
    let trend: WeightTrend
    let weeklyChange: Double?
    @Binding var range: Int

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
                    }
                }
                Spacer()
                if let weeklyChange { Text(Format.weeklyChange(weeklyChange, unit: unit)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary) }
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
                .frame(height: 200)
                Picker("Range", selection: $range) {
                    Text("1M").tag(30)
                    Text("2M").tag(60)
                    Text("6M").tag(182)
                    Text("1Y").tag(365)
                }
                .pickerStyle(.segmented)
            } else {
                Text("Weigh in each morning and the trend appears after a few days.").font(.subheadline).foregroundStyle(.secondary)
            }
            if !trend.outliers.isEmpty {
                Label("\(trend.outliers.count) reading\(trend.outliers.count == 1 ? "" : "s") far from the days around \(trend.outliers.count == 1 ? "it" : "them") left out as likely misreads.",
                      systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }
}

/// The last four weeks of calories against the target, unlogged days left blank.
struct IntakeCard: View {
    let analysis: MacroAnalysis

    var body: some View {
        let today = Day.today
        let days = (0..<28).map { today.adding(days: -27 + $0) }
        VStack(alignment: .leading, spacing: 12) {
            Text("Calories, last 4 weeks").font(.headline)
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
            .frame(height: 170)
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

    func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(text)
        }
    }
}
