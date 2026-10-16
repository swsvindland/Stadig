import SwiftUI
import FoodDatabase
import NutritionEngine
import SystemCore

extension Format {
    /// "2,150 mg", "3.2 µg", "14 g".
    static func nutrient(_ value: Double, _ unit: NutrientUnit) -> String {
        let digits = value >= 10 ? 0 : (value >= 1 ? 1 : 2)
        return "\(value.formatted(.number.precision(.fractionLength(0...digits)))) \(unit.symbol)"
    }

    /// A catalog name short enough for a sentence: "Potatoes, baked" from "Potatoes, baked, flesh, without salt".
    static func shortName(_ food: Food) -> String { shortName(food.name) }

    /// The same, from an entry's name.
    static func shortName(_ name: String) -> String {
        name.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.prefix(2).joined(separator: ", ")
    }
}

extension NutrientReading.Status {
    var color: Color {
        switch self {
        case .low, .high: .orange
        case .ok: .green
        case .unknown: .secondary
        }
    }
}

/// One nutrient against its target: a bar with the target marked, and the numbers.
struct NutrientBar: View {
    let reading: NutrientReading

    var body: some View {
        let unit = reading.nutrient.unit
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(reading.nutrient.label).font(.subheadline.weight(.medium))
                Spacer()
                Text(value).font(.caption.monospacedDigit()).foregroundStyle(reading.status == .unknown ? .secondary : .primary)
                if let target = reading.target {
                    Text("/ \(Format.nutrient(target, unit))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            GeometryReader { proxy in
                let w = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.14))
                    if let f = reading.fraction {
                        Capsule().fill(reading.status.color.gradient).frame(width: max(5, w * min(1, f / 1.5)))
                    }
                    // The target, two-thirds along, so going over shows.
                    Rectangle().fill(Color.primary.opacity(0.35)).frame(width: 1.5).offset(x: w / 1.5)
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(reading.nutrient.label): \(value)\(reading.target.map { " of \(Format.nutrient($0, unit))" } ?? ""), \(statusWords)")
    }

    var value: String {
        switch reading.status {
        case .unknown: "not enough data"
        default: (reading.daily.map { "≈ \(Format.nutrient($0, reading.nutrient.unit))" }) ?? Format.nutrient(reading.measured, reading.nutrient.unit)
        }
    }

    var statusWords: String {
        switch reading.status {
        case .low: "low"
        case .high: "over"
        case .ok: "fine"
        case .unknown: "unknown"
        }
    }
}

/// The week's vitamins and minerals on Progress.
struct NutrientsCard: View {
    let report: MicroReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Vitamins and minerals").font(.headline)
                Spacer()
                if !report.days.isEmpty {
                    Text("Daily, last \(report.days.count) complete day\(report.days.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                }
            }
            if report.days.count < MicroAnalyst.minimumDays {
                Text("After three complete days of logging, this shows which nutrients are running short, with a food that fixes each.")
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                // Fiber is under food quality.
                ForEach(report.readings.filter { $0.nutrient.watched && $0.nutrient.key != "fiber" }) { NutrientBar(reading: $0) }
                NavigationLink {
                    AllNutrientsView(report: report)
                } label: {
                    Text("All nutrients").font(.subheadline.weight(.semibold))
                }
                Text("Packaged foods often list only what the label must, so a nutrient they skip is shown as unknown rather than low.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }
}

/// Every nutrient followed, with why it matters and how much of what was eaten lists it.
struct AllNutrientsView: View {
    let report: MicroReport

    var body: some View {
        List {
            Section {
                ForEach(report.readings) { reading in
                    VStack(alignment: .leading, spacing: 6) {
                        NutrientBar(reading: reading)
                        Text(reading.nutrient.why).font(.caption).foregroundStyle(.secondary)
                        if reading.coverage < 1, reading.coverage > 0 {
                            Text("Listed for \(Format.percent(reading.coverage)) of the calories eaten").font(.caption2).foregroundStyle(.tertiary)
                        }
                        if reading.status != .ok, reading.status != .unknown, !reading.sources.isEmpty {
                            Text("Most from \(reading.sources.prefix(2).joined(separator: " and "))").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } footer: {
                Text("Daily targets are the US National Academies' recommended intakes for your age and sex; fiber is 14 g per 1,000 kcal and saturated fat under 10% of calories. Supplements aren't counted.")
            }
        }
        .navigationTitle("Nutrients")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The week's shortest nutrient (or one over its limit) and the one thing to do about it.
struct NutrientActionRow: View {
    @Environment(AppModel.self) private var model
    let reading: NutrientReading

    var body: some View {
        let low = reading.status == .low
        let fix = model.microFix.flatMap { $0.nutrient.key == reading.nutrient.key ? $0 : nil }
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: low ? "leaf" : "exclamationmark.circle").foregroundStyle(Color.accentColor).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(reading.nutrient.label) has run \(low ? "low" : "high") this week").font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let fix {
                    Text("\(fix.yours ? "Your " : "")\(Format.shortName(fix.food)), \(fix.portion), adds \(Format.nutrient(fix.amount, fix.nutrient.unit)).")
                        .font(.caption.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                } else if !low, !reading.sources.isEmpty {
                    Text("Most came from \(reading.sources.prefix(2).joined(separator: " and ")); a swap there does the most.")
                        .font(.caption.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if let fix {
                Button("Log") {
                    model.log([model.entry(for: fix.food, count: fix.count, unit: fix.unit, source: .search)])
                }
                .buttonStyle(.bordered).buttonBorderShape(.capsule).font(.subheadline)
                .accessibilityLabel("Log \(fix.portion) of \(Format.shortName(fix.food))")
            }
        }
        .contextMenu {
            Button("Not now", systemImage: "eye.slash") { model.hideNutrient(reading.nutrient.key) }
        }
    }

    var detail: String {
        let unit = reading.nutrient.unit
        let amount = reading.daily ?? reading.measured
        let target = reading.target.map { Format.nutrient($0, unit) } ?? "?"
        return "About \(Format.nutrient(amount, unit)) a day of \(reading.nutrient.goal == .atLeast ? "" : "at most ")\(target). \(reading.nutrient.why)"
    }
}

/// A portion's vitamins and minerals, as a share of the day's targets.
struct PortionNutrients: View {
    @Environment(AppModel.self) private var model
    let food: Food
    let count: Double
    let unit: PortionUnit
    @State private var expanded = false

    var body: some View {
        let n = FoodUnits.nutrients(food, count: count, unit: unit)
        let micros = FoodUnits.micros(food, count: count, unit: unit)
        let rows = Micronutrients.all.compactMap { info -> (NutrientInfo, Double, Double?)? in
            let value: Double? = switch info.key {
            case "fiber": n.fiber
            case "sodium": n.sodium
            case "saturatedFat": n.saturatedFat
            default: micros[info.key]
            }
            guard let value else { return nil }
            return (info, value, target(info.key).map { $0 > 0 ? value / $0 : 0 })
        }
        if !rows.isEmpty {
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(rows, id: \.0.key) { info, value, share in
                    HStack {
                        Text(info.label).font(.subheadline)
                        Spacer()
                        Text(Format.nutrient(value, info.unit)).font(.subheadline.monospacedDigit())
                        if let share {
                            Text(Format.percent(share)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                if let sugar = n.sugar {
                    LabeledContent("Sugar", value: Format.nutrient(sugar, .g)).font(.subheadline)
                }
            } label: {
                Text("Vitamins and minerals").font(.subheadline.weight(.medium))
            }
        }
    }

    func target(_ key: String) -> Double? {
        guard let profile = model.profile else { return nil }
        let kcal = model.analysis?.targets.kcal ?? model.analysis?.maintenance.kcal ?? 2000
        return Micronutrients.target(key, sex: profile.sex, age: profile.age(on: model.today), kcal: kcal)
    }
}
