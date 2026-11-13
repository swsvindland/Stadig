import FoodDatabase
import NutritionEngine
import SwiftUI
import SystemCore

extension Format {
    /// "2,150 mg", "3.2 µg", "14 g".
    static func nutrient(_ value: Double, _ unit: NutrientUnit) -> String {
        let digits = value >= 10 ? 0 : (value >= 1 ? 1 : 2)
        return "\(value.formatted(.number.precision(.fractionLength(0...digits)))) \(unit.symbol)"
    }

    /// A nutrient's name mid-sentence: "vitamin D", "omega-3", "thiamin (B1)".
    static func inSentence(_ info: NutrientInfo) -> String { info.label.prefix(1).lowercased() + info.label.dropFirst() }

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
        case .low, .high: Ink.ok
        case .ok: Ink.good
        case .unknown: Ink.text3
        }
    }
}

/// One nutrient against its target: its numbers over a thin ruler, the target marked two-thirds
/// along so going over shows.
struct NutrientBar: View {
    let reading: NutrientReading

    var body: some View {
        let unit = reading.nutrient.unit
        let name = Text(reading.nutrient.label).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
        let numbers = HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(reading.status == .unknown ? Ink.text3 : Ink.text)
            if let target = reading.target {
                Text("/ \(Format.nutrient(target, unit))").font(.caption.monospacedDigit()).foregroundStyle(Ink.text3)
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            // The numbers under the name where they don't fit beside it, rather than every word broken.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    name
                    Spacer(minLength: 8)
                    numbers
                }
                VStack(alignment: .leading, spacing: 2) {
                    name
                    numbers
                }
            }
            Ruler(value: (reading.fraction ?? 0) / 1.5, color: reading.status.color, height: 6, divisions: 0, marker: 1 / 1.5)
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
        case .high: reading.overUpper ? "over the safe upper limit" : "over"
        case .ok: "fine"
        case .unknown: "unknown"
        }
    }
}

/// The week's vitamins and minerals on Progress: the ones watched as rulers, under a title that
/// opens every nutrient on a page of its own.
struct NutrientsCard: View {
    let report: MicroReport

    var body: some View {
        let ready = report.days.count >= MicroAnalyst.minimumDays
        VStack(alignment: .leading, spacing: 12) {
            if ready {
                // At the card's head rather than its foot, which is where the composer sits once
                // Progress is scrolled to its end.
                NavigationLink {
                    AllNutrientsView(report: report)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        CardTitle("Vitamins and minerals", detail: "All \(report.readings.count)")
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Ink.text3)
                    }
                    // A fingertip's height to hit, taken back from the card's layout.
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.vertical, -12)
                .accessibilityLabel("Vitamins and minerals, all \(report.readings.count) nutrients")
                .accessibilityIdentifier("progress.allNutrientsLink")
            } else {
                CardTitle("Vitamins and minerals")
                Text("After three complete days of logging, this shows which nutrients are running short, with a food that fixes each.")
                    .font(.subheadline).foregroundStyle(Ink.text2).fixedSize(horizontal: false, vertical: true)
            }
            if ready {
                // Fiber is under food quality.
                ForEach(report.readings.filter { $0.nutrient.watched && $0.nutrient.key != "fiber" }) { NutrientBar(reading: $0) }
                Text(
                    "Daily, from the last \(report.days.count) complete days. Packaged foods often list only what the label must, so a nutrient they skip is shown as unknown rather than low."
                )
                .font(.caption).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }
}

/// The week's vitamins and minerals as a table, where there's room: each nutrient's daily amount
/// against its target, how sure that is, and what supplements add.
struct NutrientTableCard: View {
    let report: MicroReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Vitamins and minerals").font(.callout.weight(.semibold))
                Spacer()
                if !report.days.isEmpty {
                    Text("Daily, last \(report.days.count) complete day\(report.days.count == 1 ? "" : "s")").font(.caption).foregroundStyle(
                        .secondary)
                }
            }
            if report.days.count < MicroAnalyst.minimumDays {
                Text("After three complete days of logging, this shows which nutrients are running short, with a food that fixes each.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("Nutrient")
                        Text("A day").gridColumnAlignment(.trailing)
                        Text("Target").gridColumnAlignment(.trailing)
                        Text("Of target")
                        Text("Supplements").gridColumnAlignment(.trailing)
                        Text("Listed for").gridColumnAlignment(.trailing)
                        Text("Mostly from")
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Divider()
                    ForEach(report.readings) { reading in
                        NutrientTableRow(reading: reading)
                    }
                }
                Text("Packaged foods often list only what the label must, so a nutrient they skip is shown as unknown rather than low.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
        .accessibilityIdentifier("progress.nutrients")
    }
}

private struct NutrientTableRow: View {
    let reading: NutrientReading

    var body: some View {
        let unit = reading.nutrient.unit
        GridRow {
            Text(reading.nutrient.label).help(reading.nutrient.why)
            Text(reading.status == .unknown ? "—" : Format.nutrient(reading.daily ?? reading.measured, unit)).monospacedDigit()
            Text(reading.target.map { "\(reading.nutrient.goal == .atLeast ? "" : "≤ ")\(Format.nutrient($0, unit))" } ?? "—")
                .monospacedDigit().foregroundStyle(.secondary)
            HStack(spacing: 8) {
                NutrientFill(reading: reading).frame(width: 90)
                Text(status).font(.caption).foregroundStyle(reading.status.color)
            }
            Text(reading.supplemented > 0 ? Format.nutrient(reading.supplemented, unit) : "—").monospacedDigit()
                .foregroundStyle(reading.supplemented > 0 ? .primary : .tertiary)
            Text(reading.coverage > 0 ? Format.percent(reading.coverage) : "—").monospacedDigit().foregroundStyle(.secondary)
            Text(reading.sources.prefix(2).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    var status: String {
        switch reading.status {
        case .low: "Low"
        case .high: reading.overUpper ? "Over the limit" : "High"
        case .ok: "Fine"
        case .unknown: "Unknown"
        }
    }
}

/// A nutrient's share of its target as a small bar, the target two-thirds along.
private struct NutrientFill: View {
    let reading: NutrientReading

    var body: some View {
        Ruler(value: (reading.fraction ?? 0) / 1.5, color: reading.status.color, height: 6, divisions: 0, marker: 1 / 1.5)
            .accessibilityHidden(true)
    }
}

/// Every nutrient followed, on a page pushed from Progress: what's short first, then what's over,
/// then what's on target and what too little of the food says, each with why it matters and how
/// much of what was eaten lists it.
struct AllNutrientsView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let report: MicroReport

    var body: some View {
        // The Mac reports no size class: it always has room.
        let wide = sizeClass != .compact
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !wide { DetailHeader(eyebrow: "Progress", title: "Nutrients") }
                Text(summary).font(.subheadline).foregroundStyle(Ink.text2).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                ForEach(Self.bands, id: \.title) { band in
                    RowCard(title: band.title, detail: band.detail) {
                        ForEach(report.readings.filter { $0.status == band.status }) { NutrientDetailRow(reading: $0) }
                    }
                }
                Text(
                    "Daily targets are the US National Academies' recommended intakes for your age and sex; fiber is 14 g per 1,000 kcal and saturated fat under 10% of calories. Supplements you tick off count too, and where there's a safe upper limit, going over it is flagged."
                )
                .font(.caption).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, wide ? 16 : 0)
            .padding(.bottom, 24)
            .readableWidth()
        }
        .background(.pageBackground)
        .detailPage(title: "Nutrients", wide: wide)
        .pushedPage()
        .accessibilityIdentifier("progress.allNutrients")
    }

    /// "A day, from the last 7 complete days. The line on each ruler is its target."
    var summary: String {
        let days = report.days.count
        return "A day, from the last \(days) complete day\(days == 1 ? "" : "s"). The line on each ruler is its target."
    }

    /// The page's cards, in the order they matter.
    static let bands: [(title: String, detail: String?, status: NutrientReading.Status)] = [
        ("Running short", "Under 70% of target", .low),
        ("Over", "Past a limit", .high),
        ("On target", nil, .ok),
        ("Not enough data", "Too few foods list it", .unknown),
    ]
}

/// A nutrient on the full list: its ruler, why it matters, and what the numbers rest on.
private struct NutrientDetailRow: View {
    let reading: NutrientReading

    var body: some View {
        let unit = reading.nutrient.unit
        VStack(alignment: .leading, spacing: 6) {
            NutrientBar(reading: reading)
            Text(reading.nutrient.why).font(.caption).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
            if reading.overUpper, let upper = reading.upper {
                Text("Over the safe upper limit of \(Format.nutrient(upper, unit)) a day").font(.caption.weight(.semibold)).foregroundStyle(Ink.bad)
            }
            if !notes.isEmpty {
                Text(notes.joined(separator: " · ")).font(.caption2).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    /// What the number rests on: how much of the food lists it, what supplements add, where most came from.
    var notes: [String] {
        let unit = reading.nutrient.unit
        var notes: [String] = []
        if reading.coverage < 1, reading.coverage > 0 { notes.append("Listed for \(Format.percent(reading.coverage)) of the calories eaten") }
        if reading.supplemented > 0 { notes.append("\(Format.nutrient(reading.supplemented, unit)) a day from supplements") }
        if reading.status != .ok, reading.status != .unknown, !reading.sources.isEmpty {
            notes.append("Most from \(reading.sources.prefix(2).joined(separator: " and "))")
        }
        return notes
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
            Image(systemName: low ? "leaf" : "exclamationmark.circle").foregroundStyle(reading.overUpper ? Ink.ok : Color.accentColor).frame(
                width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(
                    reading.overUpper
                        ? "\(reading.nutrient.label) is over the safe upper limit"
                        : "\(reading.nutrient.label) has run \(low ? "low" : "high") this week"
                )
                .font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let fix {
                    Text(
                        "\(fix.yours ? "Your " : "")\(Format.shortName(fix.food)), \(fix.portion), adds \(Format.nutrient(fix.amount, fix.nutrient.unit))."
                    )
                    .font(.caption.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                } else if reading.overUpper, let source = reading.sources.first {
                    Text("Most is from \(source): take it every other day, or a lower strength.")
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
                .accessibilityIdentifier("nutrientAction.log")
            }
        }
        .contextMenu {
            Button("Not now", systemImage: "eye.slash") { model.hideNutrient(reading.nutrient.key) }
                .accessibilityIdentifier("nutrientAction.notNow")
        }
    }

    var detail: String {
        let unit = reading.nutrient.unit
        let amount = reading.daily ?? reading.measured
        if reading.overUpper, let upper = reading.upper {
            return
                "About \(Format.nutrient(amount, unit)) a day, \(Format.nutrient(reading.supplemented, unit)) of it from supplements. The safe upper limit is \(Format.nutrient(upper, unit))."
        }
        let target = reading.target.map { Format.nutrient($0, unit) } ?? "?"
        return
            "About \(Format.nutrient(amount, unit)) a day of \(reading.nutrient.goal == .atLeast ? "" : "at most ")\(target). \(reading.nutrient.why)"
    }
}

/// A portion's vitamins and minerals, as a share of the day's targets.
struct PortionNutrients: View {
    @Environment(AppModel.self) private var model
    let food: Food
    let count: Double
    let unit: PortionUnit
    /// Every row in view, as a panel of its own (the Foods inspector), rather than folded away.
    var open = false
    @State private var expanded = false

    var body: some View {
        let n = FoodUnits.nutrients(food, count: count, unit: unit)
        let micros = FoodUnits.micros(food, count: count, unit: unit)
        let rows = Micronutrients.all.compactMap { info -> (NutrientInfo, Double, Double?)? in
            let value: Double? =
                switch info.key {
                case "fiber": n.fiber
                case "sodium": n.sodium
                case "saturatedFat": n.saturatedFat
                default: micros[info.key]
                }
            guard let value else { return nil }
            return (info, value, target(info.key).map { $0 > 0 ? value / $0 : 0 })
        }
        if open {
            list(rows, sugar: n.sugar)
        } else if !rows.isEmpty {
            DisclosureGroup(isExpanded: $expanded) {
                list(rows, sugar: n.sugar)
            } label: {
                Text("Vitamins and minerals").font(.subheadline.weight(.medium))
            }
        }
    }

    /// Each nutrient the food lists, with its share of the day's target.
    @ViewBuilder
    func list(_ rows: [(NutrientInfo, Double, Double?)], sugar: Double?) -> some View {
        ForEach(rows, id: \.0.key) { info, value, share in
            HStack {
                Text(info.label).font(.subheadline)
                Spacer()
                Text(Format.nutrient(value, info.unit)).font(.subheadline.monospacedDigit())
                if let share {
                    Text(Format.percent(share)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(
                        width: 44, alignment: .trailing)
                }
            }
        }
        if let sugar {
            LabeledContent("Sugar", value: Format.nutrient(sugar, .g)).font(.subheadline)
        }
        if open, rows.isEmpty, sugar == nil {
            Text("This food lists no vitamins or minerals.").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    func target(_ key: String) -> Double? {
        guard let profile = model.profile else { return nil }
        let kcal = model.analysis?.targets.kcal ?? model.analysis?.maintenance.kcal ?? 2000
        return Micronutrients.target(key, sex: profile.sex, age: profile.age(on: model.today), kcal: kcal)
    }
}
