import NutritionEngine
import SwiftUI
import SystemCore

/// The last week of meal timing on Progress: the gaps between meals by band, the overnight fast,
/// the eating window and the last meal before bed, protein meals while building muscle, the one
/// thing worth changing, and the last few fasts.
struct MealTimingCard: View {
    @Environment(AppModel.self) private var model
    let report: MealTimingReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Meal timing").font(.headline)
                Spacer()
                Text("Last 7 days").font(.caption).foregroundStyle(.secondary)
            }
            if report.hasEnough {
                if report.gapCount > 0 { GapBands(report: report) }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    if let meals = report.mealsPerDay { stat("Meals a day", meals.formatted(.number.precision(.fractionLength(0...1)))) }
                    if let gap = report.typicalGap { stat("Typical gap", Format.duration(gap)) }
                    if let overnight = report.typicalOvernight { stat("Overnight fast", Format.duration(overnight)) }
                    if let window = report.typicalWindow { stat("Eating window", Format.duration(window)) }
                    if let toBed = report.typicalLastMealToBed {
                        stat("Last meal before bed", toBed >= 0 ? Format.duration(toBed) : "\(Format.duration(-toBed)) after")
                    }
                    if let grams = report.proteinPerMeal, let perDay = report.proteinMealsPerDay {
                        stat("Meals with \(Int(grams)) g protein", "\(perDay.formatted(.number.precision(.fractionLength(0...1)))) a day")
                    }
                }
                .font(.subheadline)
                if let advice = report.advice {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(advice.title, systemImage: "lightbulb").font(.subheadline.weight(.semibold))
                        Text(advice.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("progress.mealTimingAdvice")
                }
            } else {
                Text("Three fully logged days show your pattern: the gaps between meals, the overnight fast and when the day's eating ends.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            let fasts = Array(model.pastFasts.prefix(3))
            if !fasts.isEmpty {
                Divider()
                ForEach(fasts) { run in
                    let hours = run.duration(at: run.end ?? Date()) / 3600
                    Label(
                        "\(Format.duration(hours * 3600)) fast · \(Format.day(Day(run.fast.start)))",
                        systemImage: hours >= run.fast.goalHours ? "checkmark.circle.fill" : "timer"
                    )
                    .font(.subheadline)
                }
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progress.mealTiming")
    }

    func stat(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// The week's gaps between meals as one bar split by band, with the count of each.
private struct GapBands: View {
    let report: MealTimingReport

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(GapBand.allCases, id: \.self) { band in
                        let share = report.share(band)
                        if share > 0 {
                            Rectangle().fill(band.barColor)
                                .frame(width: max(4, proxy.size.width * share - 2))
                        }
                    }
                }
                .clipShape(.capsule)
            }
            .frame(height: 10)
            HStack(spacing: 12) {
                ForEach(GapBand.allCases, id: \.self) { band in
                    if let count = report.gapCounts[band], count > 0 {
                        Text("\(band.label) \(count)").font(.caption).foregroundStyle(band.color)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Gaps between meals: "
                + GapBand.allCases.compactMap { band in report.gapCounts[band].map { "\($0) \(band.label)" } }.joined(separator: ", "))
    }
}
