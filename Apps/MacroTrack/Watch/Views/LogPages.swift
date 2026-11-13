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
                                nutrients: usual.nutrients, left: today.kcal.left, position: 0, count: ids.count,
                                active: showing && current == Self.usualID,
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
                                position: index + (today.sameAsUsual == nil ? 0 : 1), count: ids.count,
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
                // A face is the whole screen, its Log on the foot, its top line beside the time.
                .ignoresSafeArea()
            }
        }
        .navigationTitle("Log Again")
        .toolbar(.hidden, for: .navigationBar)
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
/// calories and protein, where it is in the list at the edge, and Log across the foot with what's
/// left after it. Double Tap logs it while it's the face in view.
struct FoodFace: View {
    let eyebrow: String
    let marker: String
    let amount: String
    let unit: String?
    let title: String
    let nutrients: Nutrients
    let left: Double?
    let position: Int
    let count: Int
    let active: Bool
    let identifier: String
    let label: String
    let log: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(eyebrow)
                    .faceEyebrow(Color.accentColor)
                    .faceTopLine()
                HStack(alignment: .center, spacing: 10) {
                    Text(marker)
                        .font(.system(size: 26))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(width: 46, height: 46)
                        .background(WristInk.surface, in: .rect(cornerRadius: 14, style: .continuous))
                        .accessibilityHidden(true)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(amount)
                            .faceNumeral(points: (unit == nil ? 24 : 44) * WristFace.scale)
                            .minimumScaleFactor(0.5)
                        if let unit {
                            Text(unit).faceFont(16, weight: .semibold).foregroundStyle(WristInk.text2)
                        }
                    }
                    .lineLimit(1)
                }
                .padding(.top, WristFace.small ? 6 : 11)
                Text(title)
                    .font(.system(size: 23 * min(1, WristFace.scale), weight: .heavy))
                    .tracking(-0.8)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.top, WristFace.small ? 6 : 11)
                Text("\(WristFormat.kcal(nutrients.kcal)) · \(WristFormat.grams(nutrients.protein)) protein")
                    .faceFont(13)
                    .foregroundStyle(WristInk.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 3)
                Spacer(minLength: 2)
            }
            .padding(.horizontal, WristFace.margin)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) { PageDots(position: position, count: count).padding(.top, 52).padding(.trailing, 5) }
            ActionBand(title: "Log", detail: after, doubleTap: active, action: log)
                .accessibilityIdentifier(identifier)
                .accessibilityLabel(label)
        }
        .containerRelativeFrame(.vertical)
    }

    /// "1,455 left" after this food, or "120 over".
    private var after: String? {
        guard let left else { return nil }
        let after = left - nutrients.kcal
        return "\(WristFormat.whole(abs(after))) \(after <= -1 ? "over" : "left")"
    }
}

/// Where a face is among the usual foods: a short column at the edge, this one long.
struct PageDots: View {
    let position: Int
    let count: Int

    var body: some View {
        // Four at most: the window moves on with the faces.
        let shown = min(count, 4)
        let first = min(max(0, position - 1), max(0, count - shown))
        VStack(spacing: 4) {
            ForEach(first..<(first + shown), id: \.self) { index in
                Capsule()
                    .fill(index == position ? WristInk.text : WristInk.text3)
                    .frame(width: 5, height: index == position ? 13 : 5)
            }
        }
        .accessibilityHidden(true)
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
