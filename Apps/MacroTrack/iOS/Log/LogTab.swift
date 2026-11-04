import FoodDatabase
import MealPlanner
import NutritionEngine
import SwiftUI
import SystemCore

extension AppModel {
    /// What the bar names as where a food goes: today says nothing, another day says which.
    var logTargetTitle: String {
        selectedDay == today ? "Log food" : "Log to \(Format.day(selectedDay, style: .dateTime.weekday(.abbreviated)))"
    }
}

/// A day hour by hour: every hour has a +, an hour with nothing in it is thin, and the week and
/// what's left stay pinned on top. It opens on the hour it is, or on another day's first food. With
/// room (iPad, the Mac, Vision Pro) each food has its macros in fixed columns.
struct LogTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var editing: FoodEntry?
    @State private var choosingDay = false
    /// Whether the first layout has gone to the opening hour. Coming back from another tab leaves
    /// the list where it was.
    @State private var anchored = false

    /// The Mac reports no size class: it always has room.
    var wide: Bool { sizeClass != .compact }
    var day: Day { model.selectedDay }

    var body: some View {
        let groups = DayHours.groups(on: day, entries: model.allEntries(on: day))
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    // A section's header: it pins, and it's laid out with the rows, so its columns
                    // are theirs on every platform.
                    Section {
                        ForEach(groups) { group in
                            HourRows(group: group, wide: wide, editing: $editing)
                        }
                    } header: {
                        LogHeader(wide: wide).textCase(nil)
                    }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 26)
                .accessibilityIdentifier("log.list")
                .onAppear {
                    guard !anchored else { return }
                    anchored = true
                    anchor(proxy, groups)
                }
                .onChange(of: day) { _, _ in anchor(proxy, groups) }
                .onChange(of: model.logAnchorRequest) { _, _ in anchor(proxy, groups) }
            }
            .inlineTitle()
            .toolbar { toolbar }
            .sheet(item: $editing) { entry in EntryEditor(entry: entry) }
            .sheet(isPresented: $choosingDay) { DayChooser().macSheetSize(width: 360, height: 420) }
        }
    }

    /// To the hour the day opens on. On the Mac the pinned line sits over the list's top row, so an
    /// hour earlier leaves that hour in view.
    func anchor(_ proxy: ScrollViewProxy, _ groups: [HourGroup]) {
        guard let opening = DayHours.opening(groups, now: Date()), let index = groups.firstIndex(of: opening) else { return }
        proxy.scrollTo(groups[Platform.isMac ? max(0, index - 1) : index].id, anchor: .top)
    }

    @ToolbarContentBuilder
    var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Button {
                choosingDay = true
            } label: {
                HStack(spacing: 4) {
                    Text(title).font(.headline)
                    Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
            }
            .accessibilityLabel("\(title). Choose a day")
            .accessibilityIdentifier("log.title")
        }
        ToolbarItemGroup(placement: .barTrailing) {
            if day != model.today {
                Button("Today") { model.showToday() }
                    .help("Back to today (⌘T)")
                    .accessibilityIdentifier("log.backToToday")
            }
            if !wide { SettingsButton(identifier: "log.settings") }
        }
        if wide { LogToolbar() }
    }

    var title: String { day == model.today ? "Today" : Format.day(day, style: .dateTime.weekday(.wide).month().day()) }
}

/// The week and what's left, pinned over the hours.
struct LogHeader: View {
    @Environment(AppModel.self) private var model
    let wide: Bool

    var body: some View {
        VStack(spacing: 6) {
            WeekStrip()
            DaySummaryLine(day: model.selectedDay)
            if wide { LogColumns.header }
        }
        .padding(.vertical, 6)
    }
}

/// Five days back, today and tomorrow: a tap each, with a dot on a day with food.
struct WeekStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 2) {
            ForEach(-5...1, id: \.self) { offset in
                dayButton(model.today.adding(days: offset))
            }
        }
    }

    func dayButton(_ day: Day) -> some View {
        let selected = day == model.selectedDay
        return Button {
            if day == model.today { model.showToday() } else { model.selectedDay = day }
        } label: {
            VStack(spacing: 2) {
                Text(Format.day(day, style: .dateTime.weekday(.narrow))).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                Text(Format.day(day, style: .dateTime.day()))
                    .font(.subheadline.weight(selected ? .bold : .regular).monospacedDigit())
                    .frame(width: 32, height: 32)
                    .background(selected ? Color.accentColor.opacity(0.22) : .clear, in: .circle)
                    .overlay {
                        if day == model.today { Circle().strokeBorder(Color.accentColor, lineWidth: 1) }
                    }
                Circle()
                    .fill(model.allEntries(on: day).isEmpty ? .clear : Color.accentColor)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        // Tomorrow opens with future days.
        .disabled(day > model.today)
        .accessibilityLabel(Format.day(day, style: .dateTime.weekday(.wide).month().day()))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("log.day")
    }
}

/// What's left against that day's targets, with what's logged for later beside it. On a past day
/// being caught up, the whole usual day a tap away.
struct DaySummaryLine: View {
    @Environment(AppModel.self) private var model
    let day: Day

    var body: some View {
        let intake = model.dayIntake(on: day)
        let targets = model.targets(on: day)
        let missing = model.catchUp
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Text(left(intake, targets)).font(.subheadline.weight(.semibold).monospacedDigit())
                if let protein = targets?.protein {
                    Text("\(Format.grams(max(0, protein - intake.eaten.protein))) protein left").font(.subheadline.monospacedDigit()).foregroundStyle(
                        Macro.protein.color)
                }
                Spacer(minLength: 0)
                if intake.later.kcal > 0 {
                    Text("\(Format.kcal(intake.later.kcal)) later").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("log.left")
            if missing.count > 1 {
                Button {
                    model.catchUpAll()
                } label: {
                    Label(
                        "Log all \(missing.count) · \(Format.kcal(missing.map(\.latest.nutrients.kcal).reduce(0, +)))",
                        systemImage: "plus.circle"
                    )
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .hoverHighlight()
                .accessibilityIdentifier("catchUp.logAll")
            }
        }
    }

    func left(_ intake: DayIntake, _ targets: DailyTargets?) -> String {
        guard let kcal = targets?.kcal else { return "\(Format.kcal(intake.eaten.kcal)) eaten" }
        let left = kcal - intake.eaten.kcal
        return left >= 0 ? "\(Format.kcal(left)) left" : "\(Format.kcal(-left)) over"
    }
}

/// Fixed macro columns, the same in the header and every row. A sort of the day is in the Sort menu:
/// the column headers are labels, since the grid is in time order.
enum LogColumns {
    static let width: CGFloat = 56

    static var header: some View {
        HStack(spacing: 0) {
            Text("Food")
            Spacer()
            cells(["kcal", "P", "C", "F"])
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    static func cells(_ values: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Text(value).frame(width: width, alignment: .trailing).monospacedDigit()
            }
        }
    }
}

/// One hour of the day: its label and +, what's usual or planned then, its foods, and the foods to
/// log again if it's the hour it is.
struct HourRows: View {
    @Environment(AppModel.self) private var model
    let group: HourGroup
    let wide: Bool
    @Binding var editing: FoodEntry?

    var body: some View {
        HourHeader(group: group)
            .id(group.id)
            // Thin: a whole day of hours fits in a couple of scrolls.
            .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 8))
            .listRowSeparator(group.entries.isEmpty ? .hidden : .automatic)
        ForEach(usual) { CatchUpRow(usual: $0) }
        ForEach(planned, id: \.meal.id) { PlannedMealRow(meal: $0.meal, recipe: $0.recipe, plan: $0.plan) }
        ForEach(group.entries) { entry in
            LogEntryRow(entry: entry, wide: wide, editing: $editing)
        }
        if isNow, !model.logAgain.isEmpty { LogAgainChips() }
    }

    var isNow: Bool { model.selectedDay == model.today && group.start <= Date() && Date() < group.end }

    /// The usual times of a past day still to catch up, in their hours.
    var usual: [UsualMeal] { model.catchUp.filter { group.start <= $0.time && $0.time < group.end } }

    /// The plan's meals for this hour.
    var planned: [(meal: PlannedMeal, recipe: PlannedRecipe, plan: MealPlan)] {
        guard let plan = model.mealPlan(covering: model.selectedDay) else { return [] }
        return plan.meals(on: model.selectedDay).compactMap { meal in
            guard Int(meal.slot.hour) == group.hour, let recipe = plan.recipe(meal.recipeID) else { return nil }
            return (meal, recipe, plan)
        }
    }
}

/// An hour's label, what it adds up to, and its +.
struct HourHeader: View {
    @Environment(AppModel.self) private var model
    let group: HourGroup

    var body: some View {
        let kcal = group.entries.map(\.nutrients.kcal).reduce(0, +)
        HStack(spacing: 8) {
            Text(group.start.formatted(.dateTime.hour())).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if kcal > 0 { Text(Format.kcal(kcal)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            Button {
                model.openLogger(.search, at: DayHours.addTime(group, now: Date()))
            } label: {
                Image(systemName: "plus").font(.caption.weight(.bold)).frame(width: 36, height: 26).contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Log at \(Format.time(group.start))")
            .accessibilityIdentifier("log.add.\(group.hour)")
        }
        // Contain, or the identifier goes on the + inside it too, over its own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("log.hour.\(group.hour)")
    }
}

/// A food in its hour: a tap opens its amount, and a swipe deletes it or logs it again.
struct LogEntryRow: View {
    @Environment(AppModel.self) private var model
    let entry: FoodEntry
    let wide: Bool
    @Binding var editing: FoodEntry?

    var body: some View {
        Button {
            editing = entry
        } label: {
            if wide { columns } else { EntryRow(entry: entry) }
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityIdentifier("log.entry")
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete", systemImage: "trash", role: .destructive) { model.delete(entries: [entry.id]) }
        }
        .swipeActions(edge: .leading) {
            Button("Again", systemImage: "arrow.clockwise") {
                model.log([LogAgain.copy(entry, to: model.logDate(), source: .copied)])
            }
            .tint(.accentColor)
        }
        .contextMenu {
            Button("Log Again", systemImage: "arrow.clockwise") { model.log([LogAgain.copy(entry, to: model.logDate(), source: .copied)]) }
            Button("Delete", systemImage: "trash", role: .destructive) { model.delete(entries: [entry.id]) }
        }
    }

    var columns: some View {
        let later = model.foodLog.isUpcoming(entry)
        let n = entry.nutrients
        return HStack(spacing: 8) {
            if later { LaterMark() }
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).lineLimit(1)
                Text([entry.brand, entry.amountLabel].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            LogColumns.cells([
                "\(entry.isEstimate ? "≈" : "")\(Format.whole(n.kcal))", Format.whole(n.protein), Format.whole(n.carbs), Format.whole(n.fat),
            ])
        }
        .opacity(later ? 0.55 : 1)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Log again, under the hour it is, in one tap each. The order holds still while they're being
/// tapped: it's taken once a visit, so a food logged doesn't move the next one out from under a thumb.
struct LogAgainChips: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var chips: [LogAgainItem] = []

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(chips) { item in
                    Button {
                        model.logAgain(item)
                    } label: {
                        Text(SavedMeals.shortName(item.template.name)).font(.subheadline).lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .accessibilityLabel("Log \(item.template.name) again")
                    .accessibilityIdentifier("log.again")
                }
            }
        }
        .scrollIndicators(.hidden)
        .listRowSeparator(.hidden)
        .onAppear(perform: refresh)
        .onChange(of: model.tab) { _, _ in refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { refresh() } }
    }

    func refresh() { chips = Array(model.logAgain.prefix(10)) }
}

/// Any day, from the title.
struct DayChooser: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker(
                "Day",
                selection: Binding(
                    get: { model.selectedDay.date() },
                    set: { date in
                        model.selectedDay = min(Day(date), model.today)
                        dismiss()
                    }),
                in: ...model.today.date(), displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding()
            .accessibilityIdentifier("log.datePicker")
            .navigationTitle("Choose a day")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(460)])
    }
}
