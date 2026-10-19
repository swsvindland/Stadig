import NutritionEngine
import SwiftUI
import SystemCore

/// The usual foods for this time of day, one tap each: yesterday's meal around now first, then
/// single foods by how often and how recently they're eaten at this hour.
struct LogAgainPage: View {
    @Environment(WristModel.self) private var model
    let today: WristToday

    var body: some View {
        List {
            if let usual = today.sameAsUsual {
                Button {
                    model.log(usual)
                } label: {
                    FoodRow(
                        title: "Same as \(Self.relative(Day(usual.start), today: today.day))",
                        detail: usual.entries.map(\.name).joined(separator: ", "), kcal: usual.nutrients.kcal, symbol: "arrow.clockwise")
                }
                .listItemTint(Color.accentColor.opacity(0.35))
                .accessibilityIdentifier("logAgain.usual")
                .accessibilityLabel(
                    "Log the same as \(Self.relative(Day(usual.start), today: today.day)): \(usual.entries.map(\.name).joined(separator: ", ")), \(WristFormat.kcal(usual.nutrients.kcal))"
                )
            }
            ForEach(Array(today.logAgain.enumerated()), id: \.element.id) { index, item in
                Button {
                    model.log(item)
                } label: {
                    FoodRow(title: item.template.name, detail: item.template.amountLabel, kcal: item.template.nutrients.kcal, symbol: nil)
                }
                .accessibilityIdentifier("logAgain.food.\(index)")
                .accessibilityLabel("Log \(item.template.name), \(item.template.amountLabel), \(WristFormat.kcal(item.template.nutrients.kcal))")
            }
            if today.logAgain.isEmpty, today.sameAsUsual == nil {
                Text("Foods you log show up here, ready to log again with a tap.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("logAgain.empty")
            }
        }
        .navigationTitle("Log Again")
    }

    /// "yesterday", or the weekday for a day earlier in the week.
    static func relative(_ day: Day, today: Day) -> String {
        day.days(until: today) == 1 ? "yesterday" : day.date().formatted(.dateTime.weekday(.wide))
    }
}

struct FoodRow: View {
    let title: String
    let detail: String
    let kcal: Double
    let symbol: String?

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                Text("\(detail) · \(WristFormat.whole(kcal))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: symbol ?? "plus")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
        }
    }
}

/// Water so far against the day's aim (with the fluid in drinks logged as food), and a glass or a
/// bottle with one tap.
struct WaterPage: View {
    @Environment(WristModel.self) private var model
    let water: HydrationDay
    let glasses: [WaterGlass]

    var body: some View {
        let ounces = model.units.weight == .lb
        ScrollView {
            VStack(spacing: 8) {
                ZStack {
                    Ring(fraction: min(1, water.fraction), color: MacroColor.water, lineWidth: 10)
                    VStack(spacing: -2) {
                        Text(WristFormat.volume(water.total, ounces: ounces))
                            .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text("of \(WristFormat.volume(water.target, ounces: ounces))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 18)
                }
                .frame(width: 96, height: 96)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(WristFormat.volume(water.total, ounces: ounces)) of \(WristFormat.volume(water.target, ounces: ounces)) to drink today"
                )
                .accessibilityIdentifier("water.progress")
                HStack(spacing: 6) {
                    ForEach(Array(glasses.enumerated()), id: \.element.id) { index, glass in
                        Button {
                            model.addWater(glass)
                        } label: {
                            VStack(spacing: 0) {
                                Image(systemName: index == 0 ? "drop.fill" : "waterbottle.fill")
                                Text(glass.label).font(.caption2)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .tint(MacroColor.water)
                        .accessibilityIdentifier(index == 0 ? "water.add.glass" : "water.add.bottle")
                        .accessibilityLabel("Add \(glass.label.lowercased()), \(WristFormat.volume(glass.ml, ounces: ounces))")
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Water")
    }
}

/// The doses whose time has come, a tap each to take, and "Take All" for more than one.
struct SupplementsPage: View {
    @Environment(WristModel.self) private var model
    let doses: [DueDose]
    let later: Int

    var body: some View {
        List {
            ForEach(Array(doses.enumerated()), id: \.element.id) { index, dose in
                Button {
                    model.take([dose])
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: dose.dose.time.symbol)
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(dose.supplement.name).font(.headline).lineLimit(2)
                            Text("\(dose.supplement.facts.amountLabel(dose.dose.count)) · \(dose.dose.time.label.lowercased())")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .accessibilityIdentifier("supplements.dose.\(index)")
                .accessibilityLabel(
                    "Take \(dose.supplement.name), \(dose.supplement.facts.amountLabel(dose.dose.count)), \(dose.dose.time.label.lowercased())")
            }
            if doses.count > 1 {
                Button {
                    model.take(doses)
                } label: {
                    Label("Take All", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .listItemTint(Color.accentColor.opacity(0.35))
                .accessibilityIdentifier("supplements.takeAll")
            }
            if doses.isEmpty {
                Label("Nothing due now", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("supplements.none")
            }
            if later > 0 {
                Text("\(later) more later today")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Supplements")
    }
}
