import MealPlanner
import NutritionEngine
import SwiftUI
import SystemCore

extension AppModel {
    /// What a place on the Log tab does with a tap: opens the logger at its time, or, with foods
    /// picked out, takes them there.
    func logOrPlace(at time: Date) {
        if selection.isEmpty {
            aimLogger(at: time)
        } else {
            placeSelection(.starting(time), named: "\(dayName(Day(time))), \(Format.time(time))")
        }
    }

    /// The + of a place on the Log tab, which turns into where the picked-out foods go.
    var placeSymbol: String {
        if selection.isEmpty { return "plus" }
        return selection.intent == .move ? "arrow.right.to.line" : "doc.on.clipboard"
    }

    func placeLabel(at time: Date) -> String {
        let time = Format.time(time)
        if selection.isEmpty { return "Log at \(time)" }
        return selection.intent == .move ? "Move here, \(time)" : "Copy here, \(time)"
    }

    /// The hours the Log tab offers: the person's own, else up to the bedtime set here for caffeine.
    var logHours: ClosedRange<Int> {
        LogHours.window(first: settings.logFirstHour, last: settings.logLastHour, bed: settings.doseTimes?[.bedtime])
    }

    /// The plan's meals in an hour of the selected day.
    func plannedMeals(in group: HourGroup) -> [(meal: PlannedMeal, recipe: PlannedRecipe, plan: MealPlan)] {
        guard let plan = mealPlan(covering: selectedDay) else { return [] }
        return plan.meals(on: selectedDay).compactMap { meal in
            guard Int(meal.slot.hour) == group.hour, let recipe = plan.recipe(meal.recipeID) else { return nil }
            return (meal, recipe, plan)
        }
    }

    /// The selected day as cards: its meals, what's waiting at a time, and the open hours.
    func dayItems(on day: Day) -> [DayItem] {
        let groups = DayHours.groups(on: day, entries: allEntries(on: day))
        let planned = groups.filter { !plannedMeals(in: $0).isEmpty }.map(\.start)
        return DayCards.items(groups, held: catchUp.map(\.time) + planned, now: day == today ? Date() : nil)
    }
}

/// A + big enough for a thumb: a 44 point target around the circle that's seen.
struct LogPlus: View {
    let symbol: String
    let label: String
    let identifier: String
    /// The main way to log from where it sits, filled.
    var solid = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(solid ? Color.white : Color.accentColor)
                .frame(width: 32, height: 32)
                .background(solid ? Color.accentColor : Color.accentColor.opacity(0.15), in: .circle)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// A row that sits on the page between the cards, rather than in one.
private struct OnThePage: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
    }
}

/// One piece of the day on the Log tab.
struct DayItemView: View {
    let item: DayItem
    let gaps: [UUID: MealGap]
    @Binding var editing: FoodEntry?

    var body: some View {
        switch item {
        case .meal(let meal): MealCard(meal: meal, gap: meal.entries.first.flatMap { gaps[$0.id] }, editing: $editing).id(item.id)
        case .held(let group): HeldCards(group: group).id(item.id)
        case .now(let group): NowRow(group: group).id(item.id)
        case .hours(let hours): HourSlots(hours: hours).modifier(OnThePage()).id(item.id)
        }
    }
}

/// A meal: what it's called, when, what it adds up to and its +, then its foods. A tap on the name
/// picks out the meal, and holding it offers what's done with a meal. While foods are picked out,
/// the + takes them into this meal.
struct MealCard: View {
    let meal: Moment
    let gap: MealGap?
    @Binding var editing: FoodEntry?

    var body: some View {
        Section {
            MealHeader(meal: meal, gap: gap)
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 8))
                .listRowSeparator(.hidden)
            ForEach(meal.entries) { LogEntryRow(entry: $0, wide: false, editing: $editing) }
        }
    }
}

struct MealHeader: View {
    @Environment(AppModel.self) private var model
    let meal: Moment
    let gap: MealGap?
    @State private var naming = false

    var body: some View {
        let time = DayCards.addTime(to: meal, now: Date())
        HStack(spacing: 8) {
            Button {
                model.toggleSelection(meal)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline).foregroundStyle(allSelected ? Color.accentColor : .primary).lineLimit(1)
                    Text(detail).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select \(title), \(detail)")
            .accessibilityIdentifier("log.meal")
            .contextMenu {
                Button("Repeat Now", systemImage: "arrow.clockwise") { model.logAgain(meal, at: Date()) }
                    .accessibilityIdentifier("log.hourMenu.repeat")
                MomentMealButton(moment: meal) { naming = true }
                Button("Remove", systemImage: "trash", role: .destructive) { model.delete(entries: meal.entries.map(\.id)) }
                    .accessibilityIdentifier("log.hourMenu.remove")
            }
            if let gap { GapBadge(gap: gap).accessibilityIdentifier("log.gap") }
            LogPlus(symbol: model.placeSymbol, label: addLabel(time), identifier: "log.addToMeal", solid: true) { model.logOrPlace(at: time) }
        }
        .accessibilityElement(children: .contain)
        .saveMealPrompt(isPresented: $naming, entries: meal.entries)
    }

    var title: String { SavedMeals.meal(for: meal.entries, in: model.savedMeals)?.name ?? MealName.of(meal) }

    var detail: String {
        let upcoming = meal.entries.allSatisfy(model.foodLog.isUpcoming)
        return [
            Format.time(meal.start), upcoming ? "later" : nil, Format.kcal(meal.nutrients.kcal), "\(Format.grams(meal.nutrients.protein)) P",
        ].compactMap { $0 }.joined(separator: " · ")
    }

    func addLabel(_ time: Date) -> String { model.selection.isEmpty ? "Add to \(title)" : model.placeLabel(at: time) }

    var allSelected: Bool { meal.entries.allSatisfy { model.selection.ids.contains($0.id) } }
}

/// A food in its card: its marker, the name it's said by, and its numbers. The full name is on its
/// amount panel.
struct MealFoodRow: View {
    @Environment(AppModel.self) private var model
    let entry: FoodEntry

    var body: some View {
        let later = model.foodLog.isUpcoming(entry)
        let label = FoodLabel.parts(of: entry.name)
        HStack(spacing: 10) {
            if later { LaterMark() }
            FoodTile(name: entry.name)
            VStack(alignment: .leading, spacing: 1) {
                Text(label.title).lineLimit(1)
                Text([entry.amountLabel, entry.brand, label.detail].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(entry.isEstimate ? "≈" : "")\(Format.whole(entry.nutrients.kcal))").monospacedDigit()
                Text("\(Format.grams(entry.nutrients.protein)) P").font(.caption.monospacedDigit()).foregroundStyle(Macro.protein.color)
            }
        }
        // Dimmed until its time: it's in the day's log, but it doesn't count yet.
        .opacity(later ? 0.55 : 1)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Open hours, one tap each from logging at them. Those outside the hours set for the Log tab wait
/// behind Earlier and Later, where a gap would otherwise be mostly hours nobody eats in.
struct HourSlots: View {
    @Environment(AppModel.self) private var model
    let hours: [HourGroup]
    @State private var showsEarly = false
    @State private var showsLate = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        let (earlier, shown, later) = LogHours.split(hours, window: model.logHours)
        LazyVGrid(columns: columns, spacing: 6) {
            if showsEarly {
                ForEach(earlier) { slot($0) }
            } else if !earlier.isEmpty {
                more("Earlier", identifier: "log.earlier") { showsEarly = true }
            }
            ForEach(shown) { slot($0) }
            if showsLate {
                ForEach(later) { slot($0) }
            } else if !later.isEmpty {
                more("Later", identifier: "log.later") { showsLate = true }
            }
        }
    }

    func more(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
        }
        // Plain: borderless takes the tint, which turns secondary text into a pale green.
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    func slot(_ group: HourGroup) -> some View {
        let time = DayHours.addTime(group, now: Date())
        return Button {
            model.logOrPlace(at: time)
        } label: {
            Label(group.start.formatted(.dateTime.hour()), systemImage: model.placeSymbol)
                .labelStyle(SlotLabel())
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(.cardBackground, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(model.placeLabel(at: time))
        .accessibilityIdentifier("log.add.\(group.hour)")
    }
}

private struct SlotLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.caption2.weight(.bold)).foregroundStyle(Color.accentColor)
            configuration.title.font(.subheadline.monospacedDigit()).foregroundStyle(.primary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// The hour it is, on today: the place to log what's being eaten, with Log again's chips under it.
struct NowRow: View {
    @Environment(AppModel.self) private var model
    let group: HourGroup

    var body: some View {
        let time = DayHours.addTime(group, now: Date())
        Section {
            VStack(spacing: 2) {
                HStack(spacing: 8) {
                    Text("Now").font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor)
                    Capsule().fill(Color.accentColor.opacity(0.35)).frame(height: 1)
                    LogPlus(symbol: model.placeSymbol, label: model.placeLabel(at: time), identifier: "log.add.\(group.hour)", solid: true) {
                        model.logOrPlace(at: time)
                    }
                }
                if !model.logAgainChips.isEmpty { LogAgainChips() }
            }
            .modifier(OnThePage())
        }
    }
}

/// What's waiting in an hour: usual meals to catch up, and the plan's meals.
struct HeldCards: View {
    @Environment(AppModel.self) private var model
    let group: HourGroup

    var body: some View {
        ForEach(model.catchUp.filter { group.start <= $0.time && $0.time < group.end }) { usual in
            UsualCard(usual: usual).modifier(OnThePage())
        }
        let planned = model.plannedMeals(in: group)
        if !planned.isEmpty {
            Section {
                ForEach(planned, id: \.meal.id) { PlannedMealRow(meal: $0.meal, recipe: $0.recipe, plan: $0.plan) }
            }
        }
    }
}

/// A meal that isn't logged yet, in dashes where it would go: what's usual at this time, one tap
/// from being logged at it. A tap on the rest logs something else at the time instead.
struct UsualCard: View {
    @Environment(AppModel.self) private var model
    let usual: UsualMeal

    var body: some View {
        let name = model.name(of: usual.latest)
        let time = Format.time(usual.time)
        let when = Format.relative(Day(usual.latest.start), today: model.today)
        // A food alone is under its full name, which is what the logger's "as" needs, not a card.
        let shown = usual.latest.entries.count == 1 ? FoodLabel.parts(of: name).title : name
        HStack(spacing: 8) {
            Button {
                model.aimLogger(at: usual.time)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(MealName.of(usual.latest)) · \(time)").font(.subheadline.weight(.semibold).monospacedDigit())
                    HStack(spacing: 4) {
                        Text(usual.latest.entries.prefix(3).map { FoodMarker.of($0.name) }.joined()).font(.caption).accessibilityHidden(true)
                        Text(shown).font(.caption).lineLimit(1)
                    }
                    Text("Same as \(when) · \(Format.kcal(usual.latest.nutrients.kcal))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Log something else at \(time)")
            .accessibilityIdentifier("catchUp.time")
            LogPlus(symbol: "plus", label: "Log \(name) at \(time), as \(when)", identifier: "catchUp.log", solid: true) { model.catchUp(usual) }
        }
        .padding(.vertical, 8)
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .overlay {
            RoundedRectangle(cornerRadius: 22).strokeBorder(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        }
    }
}
