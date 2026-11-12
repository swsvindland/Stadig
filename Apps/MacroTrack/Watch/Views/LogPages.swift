import NutritionEngine
import SwiftUI
import SystemCore

/// The usual foods for this time of day, a face each: yesterday's meal around now first, then
/// single foods by how often and how recently they're eaten at this hour. The Digital Crown moves
/// from one to the next (and on to the next page after the last); Log, or Double Tap, logs the one
/// in view at its usual amount.
struct LogAgainPage: View {
    @Environment(WristModel.self) private var model
    let today: WristToday
    /// This page is the one showing: Double Tap logs only a food that's in view.
    let showing: Bool
    /// The face in view; nil until the crown moves, which is the first.
    @State private var shown: String?

    static let usualID = "usual"

    var body: some View {
        let ids = (today.sameAsUsual == nil ? [] : [Self.usualID]) + today.logAgain.map(\.id)
        let first = ids.first
        // A face logged away (the list moves on after a log) leaves the first one current.
        let current = shown.flatMap { ids.contains($0) ? $0 : nil } ?? first
        Group {
            if first == nil {
                ScrollView {
                    Text("Foods you log show up here, ready to log again with a tap.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("logAgain.empty")
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if let usual = today.sameAsUsual {
                            let when = Self.relative(Day(usual.start), today: today.day)
                            let names = usual.entries.map { FoodLabel.title($0.name) }.joined(separator: ", ")
                            FoodFace(
                                eyebrow: "Same as \(when)", marker: usual.entries.prefix(3).map { FoodMarker.of($0.name) }.joined(),
                                amount: "\(usual.entries.count)", unit: usual.entries.count == 1 ? "food" : "foods", title: names,
                                nutrients: usual.nutrients, left: today.kcal.left, active: showing && current == Self.usualID,
                                identifier: "logAgain.usual",
                                label: "Log the same as \(when): \(names), \(WristFormat.kcal(usual.nutrients.kcal))"
                            ) {
                                model.log(usual)
                            }
                            .id(Self.usualID)
                        }
                        ForEach(Array(today.logAgain.enumerated()), id: \.element.id) { index, item in
                            let food = item.template
                            let amount = Self.amount(food.amountLabel)
                            FoodFace(
                                eyebrow: "Usually now", marker: FoodMarker.of(food.name), amount: amount.value, unit: amount.unit,
                                title: FoodLabel.short(food.name), nutrients: food.nutrients, left: today.kcal.left,
                                active: showing && current == item.id, identifier: "logAgain.food.\(index)",
                                label: "Log \(FoodLabel.short(food.name)), \(food.amountLabel), \(WristFormat.kcal(food.nutrients.kcal))"
                            ) {
                                model.log(item)
                            }
                            .id(item.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $shown)
                // A face reaches the foot of the screen, so the next one doesn't show under its Log.
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .navigationTitle("Log Again")
    }

    /// "yesterday", or the weekday for a day earlier in the week.
    static func relative(_ day: Day, today: Day) -> String {
        day.days(until: today) == 1 ? "yesterday" : day.date().formatted(.dateTime.weekday(.wide))
    }

    /// "170 g" as the number and its unit, set apart; a label that isn't a number and a word
    /// ("2 large · 92 g") is said whole.
    static func amount(_ label: String) -> (value: String, unit: String?) {
        let words = label.split(separator: " ")
        guard words.count == 2, Double(words[0].replacingOccurrences(of: ",", with: "")) != nil else { return (label, nil) }
        return (String(words[0]), String(words[1]))
    }
}

/// One food (or meal) to log again, filling the screen: what it is and how much, big, then its
/// calories and protein, and Log at the foot with what's left after it. Double Tap logs it while
/// it's the face in view.
struct FoodFace: View {
    let eyebrow: String
    let marker: String
    let amount: String
    let unit: String?
    let title: String
    let nutrients: Nutrients
    let left: Double?
    let active: Bool
    let identifier: String
    let label: String
    let log: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(eyebrow)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.tint)
                .lineLimit(1)
            HStack(alignment: .center, spacing: 8) {
                Text(marker)
                    .font(.title3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.12), in: .rect(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(amount)
                        .font(.system(size: unit == nil ? 22 : 34, weight: .bold).monospacedDigit())
                        .tracking(-0.8)
                    if let unit { Text(unit).font(.footnote.weight(.semibold)).foregroundStyle(.secondary) }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            }
            Text(title)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text("\(WristFormat.kcal(nutrients.kcal)) · \(WristFormat.grams(nutrients.protein)) protein")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Button(action: log) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Log").font(.headline)
                    Spacer(minLength: 4)
                    if let left {
                        let after = left - nutrients.kcal
                        Text("\(WristFormat.whole(abs(after))) \(after <= -1 ? "over" : "left")").font(.footnote.monospacedDigit())
                    }
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Color.accentColor, in: .rect(cornerRadius: 23, style: .continuous))
                .contentShape(.rect(cornerRadius: 23))
            }
            .buttonStyle(.plain)
            .handGestureShortcut(.primaryAction, isEnabled: active)
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(label)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
        .containerRelativeFrame(.vertical)
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("Water today")
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(.tint)
                    Text(WristFormat.volume(water.total, ounces: ounces))
                        .font(.system(size: 34, weight: .bold).monospacedDigit())
                        .tracking(-1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    WristRuler(fraction: water.fraction, color: MacroColor.water)
                    Text("of \(WristFormat.volume(water.target, ounces: ounces))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
