import FoodDatabase
import NutritionEngine
import SwiftUI
import SystemCore

extension Processing {
    var color: Color {
        switch self {
        case .whole: .green
        case .culinary: .teal
        case .processed: .yellow
        case .ultraProcessed: .orange
        }
    }

    /// "Whole food", "Ultra-processed": for one food.
    var tag: String { self == .whole ? "Whole food" : label }
}

extension QualityReport.Status {
    var color: Color {
        switch self {
        case .good: .green
        case .fair: .yellow
        case .off: .orange
        case .unknown: .secondary
        }
    }
}

/// How processed a food is, and whether it's fermented, under its name.
struct FoodQualityTags: View {
    let processing: Processing?
    let fermented: Bool

    var body: some View {
        if processing != nil || fermented {
            HStack(spacing: 6) {
                if let processing { tag(processing.tag, processing.color) }
                if fermented { tag("Fermented", .purple) }
            }
            .padding(.top, 2)
        }
    }

    func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.16), in: .capsule)
            .foregroundStyle(color == .yellow ? Color.primary.opacity(0.75) : color)
    }
}

/// The week's calories by NOVA group, as one bar.
struct ProcessingBar: View {
    let report: QualityReport

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(Processing.allCases, id: \.self) { group in
                    let share = report.shares[group] ?? 0
                    if share > 0 {
                        Rectangle().fill(group.color.gradient).frame(width: max(3, (proxy.size.width - 6) * share))
                    }
                }
            }
            .clipShape(.capsule)
        }
        .frame(height: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Processing.allCases.compactMap { g in report.shares[g].map { "\(g.label) \(Format.percent($0))" } }.joined(separator: ", "))
    }
}

/// Whole against ultra-processed, fermented foods and fiber, on Progress.
struct QualityCard: View {
    let report: QualityReport
    let fiber: NutrientReading?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Food quality").font(.callout.weight(.semibold))
                Spacer()
                if !report.days.isEmpty {
                    Text("Last \(report.days.count) complete day\(report.days.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                }
            }
            if report.days.count < QualityAnalyst.minimumDays {
                Text(
                    "After three complete days of logging, this shows how much of what you eat is whole food, how much is ultra-processed, and how often something fermented is in it."
                )
                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                processing
                Divider()
                fermented
                if let fiber, fiber.status != .unknown {
                    Divider()
                    NutrientBar(reading: fiber)
                }
            }
        }
        .card()
    }

    @ViewBuilder var processing: some View {
        if report.known {
            VStack(alignment: .leading, spacing: 10) {
                ProcessingBar(report: report)
                legend
                row(
                    title: "Ultra-processed", value: Format.percent(report.share(.ultraProcessed) ?? 0),
                    aim: "under \(Format.percent(QualityAnalyst.ultraAim))", status: report.ultraStatus)
                if !report.ultraSources.isEmpty, report.ultraStatus != .good {
                    Text(
                        "Most from \(report.ultraSources.prefix(2).map { "\(Format.shortName($0.name)) (\(Format.percent($0.share)))" }.joined(separator: " and "))."
                    )
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if report.ultraStatus != .good {
                    Text("People eat more, and gain more fat, on the same macros when most of it is ultra-processed.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if report.coverage < 0.95 {
                    Text("How processed it is is known for \(Format.percent(report.coverage)) of the calories logged.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        } else {
            Text(
                "Too little of what was logged says how processed it is (\(Format.percent(report.coverage)) of the calories). Foods from the catalogs and barcodes usually do; quick adds and your own foods don't."
            )
            .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    var legend: some View {
        let groups = Processing.allCases.filter { (report.shares[$0] ?? 0) >= 0.005 }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { ForEach(groups, id: \.self) { legendItem($0) } }
            VStack(alignment: .leading, spacing: 4) { ForEach(groups, id: \.self) { legendItem($0) } }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    func legendItem(_ group: Processing) -> some View {
        HStack(spacing: 4) {
            Circle().fill(group.color).frame(width: 8, height: 8)
            Text("\(group.label) \(Format.percent(report.shares[group] ?? 0))").monospacedDigit()
        }
    }

    var fermented: some View {
        VStack(alignment: .leading, spacing: 4) {
            row(
                title: "Fermented foods", value: "\(report.fermentedDays) of \(report.days.count) days",
                aim: "most days", status: report.fermentedStatus)
            Text(
                report.fermentedFoods.isEmpty
                    ? "In a Stanford trial, yogurt, kefir, kimchi or sauerkraut every day made gut bacteria more varied and lowered markers of inflammation."
                    : "From \(report.fermentedFoods.prefix(2).map(Format.shortName).joined(separator: " and "))."
            )
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    func row(title: String, value: String, aim: String, status: QualityReport.Status) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Circle().fill(status.color).frame(width: 8, height: 8)
            Text(title).font(.subheadline.weight(.medium))
            Spacer()
            Text(value).font(.subheadline.monospacedDigit())
            Text("aim \(aim)").font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The week's food-quality action on Today: too much ultra-processed, or too little fermented.
struct QualityActionRow: View {
    enum Kind: String { case ultra, fermented }

    @Environment(AppModel.self) private var model
    let kind: Kind
    let report: QualityReport

    static func hideKey(_ kind: Kind) -> String { "quality.\(kind.rawValue)" }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: kind == .ultra ? "takeoutbag.and.cup.and.straw" : "leaf.circle").foregroundStyle(Color.accentColor).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let advice {
                    Text(advice).font(.caption.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if kind == .fermented, let fix = model.fermentedFix {
                Button("Log") {
                    model.log([model.entry(for: fix.food, count: fix.count, unit: fix.unit, source: .search)])
                }
                .buttonStyle(.bordered).buttonBorderShape(.capsule).font(.subheadline)
                .accessibilityLabel("Log \(fix.portion) of \(Format.shortName(fix.food))")
                .accessibilityIdentifier("qualityAction.log")
            }
        }
        .contextMenu {
            Button("Not now", systemImage: "eye.slash") { model.hideNutrient(Self.hideKey(kind)) }
                .accessibilityIdentifier("qualityAction.notNow")
        }
    }

    var title: String {
        switch kind {
        case .ultra: "\(Format.percent(report.share(.ultraProcessed) ?? 0)) of calories were ultra-processed this week"
        case .fermented:
            report.fermentedDays == 0 ? "Nothing fermented this week" : "Fermented food on \(report.fermentedDays) of \(report.days.count) days"
        }
    }

    var detail: String {
        switch kind {
        case .ultra:
            let top =
                report.ultraSources.first.map { " The most came from \(Format.shortName($0.name)), \(Format.percent($0.share)) of calories." } ?? ""
            return
                "The aim is under \(Format.percent(QualityAnalyst.ultraAim)): on the same macros, people eat more and gain more fat when most of it is ultra-processed.\(top)"
        case .fermented:
            return
                "Yogurt, kefir, kimchi or sauerkraut most days: in a Stanford trial, a daily habit made gut bacteria more varied and lowered markers of inflammation."
        }
    }

    var advice: String? {
        switch kind {
        case .ultra:
            return report.ultraSources.first.map(QualitySwap.advice)
        case .fermented:
            guard let fix = model.fermentedFix else { return nil }
            return "\(fix.yours ? "Your " : "")\(Format.shortName(fix.food)), \(fix.portion), counts for today."
        }
    }
}
