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
    /// On today, the time it is, which decides the hours offered first.
    let now: Date?
    @Binding var editing: FoodEntry?

    var body: some View {
        switch item {
        case .meal(let meal): MealCard(meal: meal, gap: meal.entries.first.flatMap { gaps[$0.id] }, editing: $editing).id(item.id)
        case .held(let group): HeldCards(group: group).id(item.id)
        case .now(let group): NowRow(group: group).id(item.id)
        case .hours(let hours): HourSlots(hours: hours, now: now).modifier(OnThePage()).id(item.id)
        }
    }
}

/// A meal: what it's called and when, its protein, carbs and fat, what it adds up to and its menu,
/// then its foods. A tap on the name picks out the meal, and the menu (or holding the name) has
/// adding to it and what's done with a meal. While foods are picked out, the menu's place is a
/// button that takes them into this meal.
struct MealCard: View {
    let meal: Moment
    let gap: MealGap?
    @Binding var editing: FoodEntry?

    var body: some View {
        Section {
            MealHeader(meal: meal, gap: gap)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 6))
                .listRowSeparatorTint(Ink.hairline)
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            ForEach(meal.entries) { entry in
                LogEntryRow(entry: entry, wide: false, editing: $editing)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparatorTint(Ink.hairline)
            }
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
        HStack(alignment: .top, spacing: 6) {
            Button {
                model.toggleSelection(meal)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(
                        "\(Text(title).font(.callout.weight(.semibold)).foregroundStyle(allSelected ? Color.accentColor : Ink.text)) \(Text(when).font(.caption.monospacedDigit()).foregroundStyle(Ink.text3))"
                    )
                    .lineLimit(1)
                    HStack(spacing: 10) {
                        MacroDot(macro: .protein, grams: meal.nutrients.protein)
                        if model.settings.showAllMacros {
                            MacroDot(macro: .carbs, grams: meal.nutrients.carbs)
                            MacroDot(macro: .fat, grams: meal.nutrients.fat)
                        }
                        if let gap { GapBadge(gap: gap).accessibilityIdentifier("log.gap") }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select \(title), \(detail)")
            .accessibilityIdentifier("log.meal")
            .contextMenu { actions(time) }
            Measure(value: Format.whole(meal.nutrients.kcal), unit: "kcal", size: 20)
                .foregroundStyle(Ink.text)
            if model.selection.isEmpty {
                Menu {
                    actions(time)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Ink.text3)
                        .frame(width: 40, height: 30)
                        .contentShape(.rect)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .accessibilityLabel("\(title) options")
                .accessibilityIdentifier("log.mealMenu")
            } else {
                LogPlus(symbol: model.placeSymbol, label: model.placeLabel(at: time), identifier: "log.addToMeal", solid: true) {
                    model.logOrPlace(at: time)
                }
                .padding(.vertical, -7)
            }
        }
        .accessibilityElement(children: .contain)
        .saveMealPrompt(isPresented: $naming, entries: meal.entries)
    }

    @ViewBuilder
    func actions(_ time: Date) -> some View {
        Button("Add to \(title)", systemImage: "plus") { model.logOrPlace(at: time) }
            .accessibilityIdentifier("log.addToMeal")
        Button(allSelected ? "Deselect" : "Select to Move or Copy", systemImage: "checkmark.circle") { model.toggleSelection(meal) }
        Button("Repeat Now", systemImage: "arrow.clockwise") { model.logAgain(meal, at: Date()) }
            .accessibilityIdentifier("log.hourMenu.repeat")
        MomentMealButton(moment: meal) { naming = true }
        Button("Remove", systemImage: "trash", role: .destructive) { model.delete(entries: meal.entries.map(\.id)) }
            .accessibilityIdentifier("log.hourMenu.remove")
    }

    var title: String { SavedMeals.meal(for: meal.entries, in: model.savedMeals)?.name ?? MealName.of(meal) }

    /// Its time, and that it's still to come.
    var when: String {
        let upcoming = meal.entries.allSatisfy(model.foodLog.isUpcoming)
        return upcoming ? "\(Format.time(meal.start)) · later" : Format.time(meal.start)
    }

    var detail: String {
        [when, Format.kcal(meal.nutrients.kcal), "\(Format.grams(meal.nutrients.protein)) protein"].joined(separator: ", ")
    }

    var allSelected: Bool { meal.entries.allSatisfy { model.selection.ids.contains($0.id) } }
}

/// A macro's grams beside its colour's dot: "● 62 P".
struct MacroDot: View {
    let macro: Macro
    let grams: Double

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(macro.color).frame(width: 6, height: 6)
            Text("\(Format.whole(grams)) \(macro.label.prefix(1))").font(.caption.monospacedDigit()).foregroundStyle(Ink.text3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Format.whole(grams)) grams \(macro.label.lowercased())")
    }
}

/// A food in its card: the name it's said by and its amount, and its calories. The full name and
/// its marker are on its amount panel.
struct MealFoodRow: View {
    @Environment(AppModel.self) private var model
    let entry: FoodEntry

    var body: some View {
        let later = model.foodLog.isUpcoming(entry)
        HStack(spacing: 10) {
            if later { LaterMark() }
            Text(
                "\(Text(FoodLabel.short(entry.name)).foregroundStyle(Ink.text)) \(Text(entry.amountLabel).font(.caption).foregroundStyle(Ink.text3))"
            )
            .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(entry.isEstimate ? "≈" : "")\(Format.whole(entry.nutrients.kcal))")
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(Ink.text)
        }
        .frame(minHeight: 44)
        // Dimmed until its time: it's in the day's log, but it doesn't count yet.
        .setBack(later, opacity: 0.55)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.name), \(entry.amountLabel)\(later ? ", later" : "")")
        .accessibilityValue("\(entry.isEstimate ? "about " : "")\(Format.whole(entry.nutrients.kcal)) calories")
    }
}

/// Open hours, one tap each from logging at them. Folded, a run of them is one quiet row: "Add at"
/// and the few hours most likely wanted (`LogHours.offered`), with More for the rest, so a day with
/// little logged reads as its meals rather than a wall of hours. Opened, every hour is there, those
/// outside the hours set for the Log tab behind Earlier and Later.
struct HourSlots: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    let hours: [HourGroup]
    let now: Date?
    @State private var unfolded = false
    @State private var showsEarly = false
    @State private var showsLate = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        let offered = LogHours.offered(hours, window: model.logHours, now: now)
        // At the accessibility sizes four to a row is all there's room for: the grid, open. A run
        // outside the Log tab's hours is the grid too, which is only its Earlier or Later.
        if unfolded || offered.isEmpty || typeSize.isAccessibilitySize {
            grid
        } else {
            HStack(spacing: 6) {
                Text("Add at").eyebrow().fixedSize()
                    .accessibilityHidden(true)
                ForEach(offered) { slot($0) }
                if offered.count < hours.count {
                    Button {
                        withAnimation(.snappy) { unfolded = true }
                    } label: {
                        Text("More")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Ink.text2)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .contentShape(.rect)
                    }
                    // Plain: borderless takes the tint, which turns grey text a pale green.
                    .buttonStyle(.plain)
                    .accessibilityLabel("More hours")
                    .accessibilityIdentifier("log.moreHours")
                }
            }
        }
    }

    var grid: some View {
        let (earlier, shown, later) = LogHours.split(hours, window: model.logHours)
        return LazyVGrid(columns: columns, spacing: 6) {
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
                .frame(maxWidth: .infinity, minHeight: 40)
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
            configuration.title.font(.footnote.weight(.semibold).monospacedDigit()).foregroundStyle(Ink.text2)
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
                    Text("Now").eyebrow(Color.accentColor)
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
        ForEach(model.plannedMeals(in: group), id: \.meal.id) { planned in
            Section {
                PlanMealCard(meal: planned.meal, recipe: planned.recipe, plan: planned.plan)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 12))
                    // The list's own section corner, so the line isn't clipped where the section's is.
                    .listRowBackground(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Ink.hairline, lineWidth: 1))
            }
        }
    }
}

/// A meal from the week's meal prep where it falls in the day, outlined rather than filled since
/// it isn't eaten yet: which meal, the dish and its numbers, and Log, or a tick once it's logged.
struct PlanMealCard: View {
    @Environment(AppModel.self) private var model
    let meal: PlannedMeal
    let recipe: PlannedRecipe
    let plan: MealPlan

    var body: some View {
        let n = recipe.nutrients
        let note = PlannedMealRow.note(meal, recipe: recipe)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(meal.slot.label) · From your plan").eyebrow()
                Text(recipe.title).font(.callout.weight(.semibold)).foregroundStyle(Ink.text).lineLimit(2)
                Text("\(Format.kcal(n.kcal)) · \(Format.grams(n.protein)) protein\(note)")
                    .font(.caption).foregroundStyle(Ink.text3).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if model.isLogged(meal, in: plan) {
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Ink.good).accessibilityLabel("Logged")
            } else {
                Button("Log") { model.logPlanned(meal, in: plan) }
                    .buttonStyle(.solid)
                    .frame(minWidth: 72)
                    .accessibilityLabel("Log \(recipe.title)")
                    .accessibilityIdentifier("mealPrep.logMeal")
            }
        }
        .accessibilityElement(children: .contain)
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
