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

    /// Quick add's footer, naming the day the food lands on. That's not always the selected day: just
    /// after midnight, a time picked last night is on the day before.
    var quickAddNote: String {
        "Quick adds count toward \(Format.relative(Day(logDate()), today: today)) but aren't suggested again."
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
    @State private var listWidth: CGFloat = .infinity
    @State private var order = DayOrder.time

    /// The Mac reports no size class: it always has room.
    var wide: Bool { sizeClass != .compact }
    var day: Day { model.selectedDay }
    /// The columns need the room: beside a pane in the Mac's smallest window, the phone's rows fit.
    var showsColumns: Bool { wide && listWidth >= 520 }

    var body: some View {
        let groups = DayHours.groups(on: day, entries: model.allEntries(on: day))
        let listed = showsColumns ? order.listed(model.allEntries(on: day)) : nil
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    // A section's header: it pins, and it's laid out with the rows, so its columns
                    // are theirs on every platform.
                    Section {
                        if let listed {
                            ForEach(listed) { LogEntryRow(entry: $0, wide: true, showsTime: true, editing: editingFood) }
                        } else {
                            ForEach(groups) { group in
                                HourRows(group: group, wide: showsColumns, editing: editingFood)
                            }
                        }
                    } header: {
                        LogHeader(wide: showsColumns).textCase(nil)
                    }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 26)
                .accessibilityIdentifier("log.list")
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.width
                } action: {
                    listWidth = $0
                }
                #if os(macOS)
                .onDeleteCommand { model.deleteSelection() }
                #endif
                .onAppear {
                    guard !anchored else { return }
                    anchored = true
                    anchor(proxy, groups)
                }
                // After a turn of the main thread: the new day's rows aren't in the list yet, and a
                // scroll to a row that isn't there is dropped. A change, not a task: a task would
                // run again on coming back from another tab, which leaves the list where it was.
                .onChange(of: AnchorKey(day: day, request: model.logAnchorRequest)) { _, key in
                    Task {
                        await Task.yield()
                        anchor(proxy, DayHours.groups(on: key.day, entries: model.allEntries(on: key.day)))
                    }
                }
                .onChange(of: order) { _, order in
                    Task {
                        await Task.yield()
                        if let first = order.listed(model.allEntries(on: day))?.first {
                            proxy.scrollTo(first.id, anchor: .top)
                        } else {
                            anchor(proxy, DayHours.groups(on: day, entries: model.allEntries(on: day)))
                        }
                    }
                }
            }
            // Where there's no bar above the tabs for it to swap into.
            .safeAreaInset(edge: .bottom) {
                if wide, !model.selection.isEmpty {
                    SelectionBar().frame(height: 48).floatingGlass(in: .capsule).padding()
                }
            }
            .inlineTitle()
            .toolbar { toolbar }
            .sheet(item: Binding(get: { wide ? nil : editing }, set: { editing = $0 })) { entry in EntryEditor(entry: entry) }
            .sheet(isPresented: $choosingDay) { DayChooser().macSheetSize(width: 360, height: 420) }
            .sideInspector(isPresented: paneOpen, min: 320, ideal: 360, max: 440) { pane }
            // Let go of it, or an Undo of the move would bring the pane back out of nowhere.
            .onChange(of: current == nil) { _, gone in if gone { editing = nil } }
            // Asked for, the logger shows at once, rather than waiting under a food open beside it.
            .onChange(of: model.loggerRequest) { _, _ in if wide { editing = nil } }
        }
    }

    /// A food's amount where there's no pane to put it in, and otherwise in the pane, over the
    /// logger.
    var editingFood: Binding<FoodEntry?> { $editing }

    /// The food being changed as the log has it now, and nil once it's been moved or deleted beside
    /// the pane or on another device: Save would put back the copy that was opened.
    var current: FoodEntry? { editing.flatMap(model.current) }

    /// What's beside the day, where there's room: a food being changed, or the logger.
    var paneOpen: Binding<Bool> {
        Binding(
            get: { wide && (current != nil || model.logger != nil) },
            set: { open in
                if !open {
                    editing = nil
                    model.logger = nil
                } else if anchored, editing == nil, model.logger == nil {
                    // View > Show Inspector, with nothing to show. It can say so twice. Before the day
                    // is on screen this is the inspector setting itself up on launch, not a person.
                    model.openLogger(.search)
                }
            })
    }

    @ViewBuilder
    var pane: some View {
        ZStack {
            if let mode = model.logger {
                // The same one however it's asked for again: it goes where it's asked, and keeps
                // what it can, so a request for the way it's on doesn't lose a review. Under a food
                // being changed rather than in place of it: what's typed, a review and a read under
                // way all come back as they were, and nothing opens the camera again.
                LoggerPane(start: mode, covered: current != nil)
            }
            if let current {
                // A new panel for a new version: its amount and time are read once, as it opens.
                EntryEditor(entry: current, close: { editing = nil })
                    .padding(.top, 8)
                    .id(FoodVersion(id: current.id, updatedAt: current.updatedAt))
            }
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
            if showsColumns { sortMenu }
            if !wide { SettingsButton(identifier: "log.settings") }
        }
        if wide { LogToolbar() }
    }

    /// What the column headers did when the log was a table, which can't be headers over hours.
    var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $order) {
                ForEach(DayOrder.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .help("Sort the day's food")
        .accessibilityIdentifier("log.sort")
    }

    var title: String { day == model.today ? "Today" : Format.day(day, style: .dateTime.weekday(.wide).month().day()) }
}

extension DayOrder {
    var title: String {
        switch self {
        case .time: "Time"
        case .calories: "Calories"
        case .protein: "Protein"
        case .carbs: "Carbs"
        case .fat: "Fat"
        }
    }
}

/// A food as it stood when a panel opened it.
private struct FoodVersion: Hashable {
    var id: UUID
    var updatedAt: Date
}

/// What moves the list to a day's opening hour.
private struct AnchorKey: Equatable {
    var day: Day
    var request: Int
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
                    Text("\(Format.grams(max(0, protein - counted(intake).protein))) protein left").font(.subheadline.monospacedDigit())
                        .foregroundStyle(
                            Macro.protein.color)
                }
                Spacer(minLength: 0)
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

    /// What's left is counted from what's been eaten today, with what's coming said beside it, and
    /// from all of a day's food on any other: a planned day is planned against its whole target.
    func counted(_ intake: DayIntake) -> Nutrients { day == model.today ? intake.eaten : intake.all }

    func left(_ intake: DayIntake, _ targets: DailyTargets?) -> String {
        let later = day == model.today && intake.later.kcal > 0 ? " · \(Format.whole(intake.later.kcal)) later" : ""
        guard let kcal = targets?.kcal else { return "\(Format.kcal(counted(intake).kcal)) \(day > model.today ? "planned" : "eaten")\(later)" }
        let left = kcal - counted(intake).kcal
        return (left >= 0 ? "\(Format.kcal(left)) left" : "\(Format.kcal(-left)) over") + later
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

/// An hour's label, what it adds up to, and its +. A tap on the label picks out the hour's foods,
/// and holding it offers what's done with a meal. While foods are picked out, the + takes them here.
struct HourHeader: View {
    @Environment(AppModel.self) private var model
    let group: HourGroup
    @State private var naming = false

    var body: some View {
        let kcal = group.entries.map(\.nutrients.kcal).reduce(0, +)
        HStack(spacing: 8) {
            label
            Spacer(minLength: 0)
            if kcal > 0 { Text(Format.kcal(kcal)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            Button(action: add) {
                Image(systemName: symbol).font(.caption.weight(.bold)).frame(width: 36, height: 26).contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(addLabel)
            .accessibilityIdentifier("log.add.\(group.hour)")
        }
        // Contain, or the identifier goes on the + inside it too, over its own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("log.hour.\(group.hour)")
        .saveMealPrompt(isPresented: $naming, entries: group.entries)
    }

    @ViewBuilder
    var label: some View {
        let title = group.start.formatted(.dateTime.hour())
        if group.entries.isEmpty {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        } else {
            Button {
                model.toggleSelection(group)
            } label: {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(allSelected ? Color.accentColor : .secondary)
                    .frame(minWidth: 44, minHeight: 26, alignment: .leading).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select the foods at \(title)")
            .accessibilityIdentifier("log.hourName.\(group.hour)")
            .contextMenu {
                let moment = Moment(entries: group.entries)
                Button("Repeat Now", systemImage: "arrow.clockwise") { model.logAgain(moment, at: Date()) }
                MomentMealButton(moment: moment) { naming = true }
                Button("Remove", systemImage: "trash", role: .destructive) { model.delete(entries: group.entries.map(\.id)) }
            }
        }
    }

    var allSelected: Bool { group.entries.allSatisfy { model.selection.ids.contains($0.id) } }

    var symbol: String {
        if model.selection.isEmpty { return "plus" }
        return model.selection.intent == .move ? "arrow.right.to.line" : "doc.on.clipboard"
    }

    var addLabel: String {
        let time = Format.time(group.start)
        if model.selection.isEmpty { return "Log at \(time)" }
        return model.selection.intent == .move ? "Move here, \(time)" : "Copy here, \(time)"
    }

    func add() {
        let time = DayHours.addTime(group, now: Date())
        if model.selection.isEmpty {
            model.aimLogger(at: time)
        } else {
            model.placeSelection(.starting(time), named: "\(model.dayName(Day(time))), \(Format.time(time))")
        }
    }
}

/// A food in its hour: a tap opens its amount, a hold picks it out, and a swipe deletes it or logs
/// it again. While foods are picked out a tap picks this one out too, and on the Mac ⌘-click and
/// ⇧-click do. Built the way stage 0's spike found works on `List` rows: every other way to hear a
/// hold stops scrolling from the row or turns the hold into a tap. The release after a hold still
/// reaches the Button, which is what `held` is for.
struct LogEntryRow: View {
    @Environment(AppModel.self) private var model
    let entry: FoodEntry
    let wide: Bool
    /// Out of its hour, in a sorted list, a food says when it was.
    var showsTime = false
    @Binding var editing: FoodEntry?
    /// When a hold picked this out: the tap that lands with its release is swallowed.
    @State private var held: Date?

    var isSelected: Bool { model.selection.ids.contains(entry.id) }

    var body: some View {
        Button(action: tapped) {
            HStack(spacing: 10) {
                if !model.selection.isEmpty {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }
                if wide { columns } else { EntryRow(entry: entry) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                held = Date()
                model.toggleSelection(entry)
            }
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: isSelected ? "Deselect" : "Select") { model.toggleSelection(entry) }
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
        // The Mac's right-click. On a touch screen a hold selects, so a menu there would fight it.
        .macContextMenu {
            Button(isSelected ? "Deselect" : "Select", systemImage: "checkmark.circle") { model.toggleSelection(entry) }
            Button("Log Again", systemImage: "arrow.clockwise") { model.log([LogAgain.copy(entry, to: model.logDate(), source: .copied)]) }
            Button("Delete", systemImage: "trash", role: .destructive) { model.delete(entries: [entry.id]) }
        }
    }

    func tapped() {
        // A finger that slid off after the hold never releases here, so a later tap isn't swallowed.
        if let held, Date().timeIntervalSince(held) < 2 {
            self.held = nil
            return
        }
        held = nil
        if Platform.commandHeld {
            model.toggleSelection(entry)
        } else if Platform.shiftHeld {
            model.extendSelection(to: entry)
        } else if model.selection.isEmpty {
            editing = entry
        } else {
            model.toggleSelection(entry)
        }
    }

    var columns: some View {
        let later = model.foodLog.isUpcoming(entry)
        let n = entry.nutrients
        return HStack(spacing: 8) {
            if later { LaterMark() }
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).lineLimit(1)
                Text([showsTime ? Format.time(entry.date) : nil, entry.brand, entry.amountLabel].compactMap { $0 }.joined(separator: " · ")).font(
                    .caption
                ).foregroundStyle(.secondary)
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
                        model.selectedDay = Day(date)
                        dismiss()
                    }),
                displayedComponents: .date
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
