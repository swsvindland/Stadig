import FoodDatabase
import MealPlanner
import NutritionEngine
import SwiftUI
import SystemCore

extension AppModel {
    /// Quick add's footer, naming the day the food lands on. That's not always the selected day: just
    /// after midnight, a time picked last night is on the day before.
    var quickAddNote: String {
        "Quick adds count toward \(Format.relative(Day(logDate()), today: today)) but aren't suggested again."
    }
}

/// A day as its meals, in cards, with the open hours between them a tap each from logging at them
/// and a past day's usual meals in dashes where they'd go. The week and what's left stay pinned on
/// top. It opens on the hour it is, or on another day's first meal. With room (iPad, the Mac, Vision
/// Pro) it's hour by hour instead, with each food's macros in fixed columns. Under a past day is its
/// foot: how complete it was, its doses and its drinks.
struct LogTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var textSize
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
    var showsColumns: Bool { wide && LogColumns.fit(width: listWidth, textSize: textSize) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Group {
                    if showsColumns { hoursList } else { cardsList }
                }
                .environment(\.defaultMinListRowHeight, 26)
                .accessibilityIdentifier("log.list")
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.width
                } action: {
                    listWidth = $0
                }
                .onDeleteKey(selection: model.selection.ids) { model.deleteSelection() }
                .onAppear {
                    guard !anchored else { return }
                    anchored = true
                    anchor(proxy, day)
                    // Before its first layout the list only estimates its rows, and a scroll past
                    // what it's estimated stops short: at 10 PM, an evening's hours were still off
                    // the bottom of the screen. So again, on what it's laid out.
                    Task {
                        await Task.yield()
                        anchor(proxy, day)
                    }
                }
                // After a turn of the main thread: the new day's rows aren't in the list yet, and a
                // scroll to a row that isn't there is dropped. A change, not a task: a task would
                // run again on coming back from another tab, which leaves the list where it was.
                .onChange(of: AnchorKey(day: day, request: model.logAnchorRequest)) { _, key in
                    Task {
                        await Task.yield()
                        anchor(proxy, key.day)
                    }
                }
                .onChange(of: order) { _, order in
                    Task {
                        await Task.yield()
                        if let first = order.listed(model.allEntries(on: day))?.first {
                            proxy.scrollTo(first.id, anchor: .top)
                        } else {
                            anchor(proxy, day)
                        }
                    }
                }
            }
            // With room, the phone's composer at the foot of the day, beside the pane rather than
            // under it, logging to the day on screen; the selection's bar takes its place while foods
            // are picked out. Not while the pane has the logger, which is the composer opened bigger.
            // A phone's is the tab's (RootView).
            .tabComposer(.log, isEnabled: wide && (model.logger == nil || !model.selection.isEmpty))
            .sheet(item: Binding(get: { wide ? nil : editing }, set: { editing = $0 })) { entry in EntryEditor(entry: entry) }
            .sheet(isPresented: $choosingDay) { DayChooser().macSheetSize(width: 360, height: 500) }
            .debugSheet("day") { choosingDay = true }
            .notesWork(editing != nil || choosingDay, covering: choosingDay || (editing != nil && !wide))
            .sideInspector(isPresented: paneOpen, min: 320, ideal: 360, max: 440) { pane }
            // The title, the day and its buttons are the page's own, over the day, as on a phone.
            // Outside the inspector, which would bring an empty bar back over the day.
            .hidesNavigationBar()
            .inkGround()
            // Let go of it, or an Undo of the move would bring the pane back out of nowhere.
            .onChange(of: current == nil) { _, gone in if gone { editing = nil } }
            // Asked for, the logger shows at once, rather than waiting under a food open beside it.
            .onChange(of: model.loggerRequest) { _, _ in if wide { editing = nil } }
        }
    }

    /// The day as its meals, in the same cards as Today and Plan. The header sits over the list
    /// rather than in it: an inset list's section headers don't pin.
    var cardsList: some View {
        let gaps = model.gapsBefore(on: day)
        let now = day == model.today ? Date() : nil
        return List {
            ForEach(model.dayItems(on: day)) { item in
                DayItemView(item: item, gaps: gaps, now: now, editing: editingFood)
            }
            foot
        }
        .insetGroupedList()
        .sectionSpacing(12)
        .contentMargins(.top, 4, for: .scrollContent)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                PageHeader(eyebrow: eyebrow, title: "Log") {
                    HStack(spacing: 8) {
                        if day != model.today {
                            // The word whole at any size, rather than broken over two lines.
                            Button("Today") { model.showToday() }
                                .buttonStyle(.ghost)
                                .lineLimit(1)
                                .fixedSize()
                                .accessibilityIdentifier("log.backToToday")
                        }
                        CircleIconButton(symbol: "calendar", label: "Choose a day", identifier: "log.title") { choosingDay = true }
                    }
                }
                LogHeader(wide: false)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
            .background(.pageBackground)
        }
    }

    /// The day on screen, over the title: "Thu, Nov 12".
    var eyebrow: String { Format.day(day, style: .dateTime.weekday(.abbreviated).month(.abbreviated).day()) }

    /// The day hour by hour, with each food's macros in columns, or sorted by one of them. The header
    /// sits over the list here too: a section's header has nothing behind it on iPad, so the hours
    /// scroll through it. Its columns line up with the rows' by the gutter they share.
    var hoursList: some View {
        let groups = DayHours.groups(on: day, entries: model.allEntries(on: day))
        let listed = order.listed(model.allEntries(on: day))
        let gaps = model.gapsBefore(on: day)
        return List {
            Section {
                if let listed {
                    ForEach(listed) { LogEntryRow(entry: $0, wide: true, showsTime: true, order: order, editing: editingFood) }
                        .logColumnRow()
                } else {
                    ForEach(groups) { group in
                        HourRows(group: group, gaps: group.gaps(gaps), wide: true, editing: editingFood)
                    }
                }
            }
            foot
        }
        .listStyle(.plain)
        // The page's colour behind the rows too, or the header's a band of another shade.
        .scrollContentBackground(.hidden)
        .background(.pageBackground)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                PageHeader(eyebrow: eyebrow, title: "Log") { wideButtons }
                    .padding(.horizontal, -4)
                LogHeader(wide: true)
            }
            .padding(.horizontal, LogColumns.gutter)
            .background(.pageBackground)
            .overlay(alignment: .bottom) { Rectangle().fill(Ink.hairline).frame(height: 1) }
        }
    }

    /// The wide page's round buttons: back to today, the sort, any day, and the logger's pane.
    @ViewBuilder
    var wideButtons: some View {
        if day != model.today {
            Button("Today") { model.showToday() }
                .buttonStyle(.ghost)
                .help("Back to today (⌘T)")
                .accessibilityIdentifier("log.backToToday")
        }
        if showsColumns { sortMenu }
        CircleIconButton(symbol: "calendar", label: "Choose a day", identifier: "log.title") { choosingDay = true }
            .help("Choose a day")
        CircleIconButton(symbol: "magnifyingglass", label: "Log Food", identifier: "toolbar.logFood") { model.openLogger(.search) }
            .help("Find a food to log (⌘L)")
    }

    /// Today has today's foot, and a day ahead hasn't happened yet.
    @ViewBuilder
    var foot: some View {
        if day < model.today {
            DayStateSection(day: day).textCase(nil)
            TodayMore(day: day).textCase(nil)
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

    /// Built only where there's room. On an iPhone the inspector is never shown, but SwiftUI still
    /// builds its content: a logger there was a second, hidden scanner beside the sheet's, and the
    /// two setting up the same camera at once hung it (a white scanner, and a dead photo camera
    /// until the app was quit).
    @ViewBuilder
    var pane: some View {
        if wide { paneContent }
    }

    var paneContent: some View {
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

    /// To the hour the day opens on, just under what's pinned.
    func anchor(_ proxy: ScrollViewProxy, _ day: Day) {
        guard showsColumns else {
            if let opening = DayCards.opening(model.dayItems(on: day)) { proxy.scrollTo(opening.id, anchor: .top) }
            return
        }
        guard let opening = DayHours.opening(DayHours.groups(on: day, entries: model.allEntries(on: day)), now: Date()) else { return }
        proxy.scrollTo(opening.id, anchor: .top)
    }

    /// What the column headers did when the log was a table, which can't be headers over hours.
    var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $order) {
                ForEach(DayOrder.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            CircleIcon(symbol: order == .time ? "arrow.up.arrow.down" : "arrow.up.arrow.down.circle.fill")
        }
        .circleMenuStyle()
        .help("Sort the day's food")
        .accessibilityLabel("Sort")
        // The icon fills to say a sort other than by time is on: said in words.
        .accessibilityValue(order.title)
        .accessibilityIdentifier("log.sort")
    }
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
        VStack(spacing: wide ? 6 : 12) {
            // A week's days at the width a phone gives them: across a wide window they'd drift apart.
            WeekStrip().frame(maxWidth: wide ? 520 : .infinity).frame(maxWidth: .infinity, alignment: .leading)
            DaySummaryLine(day: model.selectedDay, wide: wide)
            if wide { LogColumns.header }
        }
        .padding(.vertical, wide ? 6 : 0)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("log.header")
    }
}

/// Five days back, today and tomorrow: a tap each, with a dot on a day with food. The day on
/// screen sits on the card colour; today's date is in the accent when another day is.
struct WeekStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 4) {
            ForEach(-5...1, id: \.self) { offset in
                dayButton(model.today.adding(days: offset))
            }
        }
    }

    func dayButton(_ day: Day) -> some View {
        let selected = day == model.selectedDay
        let logged = !model.allEntries(on: day).isEmpty
        return Button {
            if day == model.today { model.showToday() } else { model.selectedDay = day }
        } label: {
            VStack(spacing: 5) {
                Text(Format.day(day, style: .dateTime.weekday(.narrow))).font(.caption2.weight(.semibold)).foregroundStyle(Ink.text3)
                Text(Format.day(day, style: .dateTime.day()))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(selected ? Ink.text : day == model.today ? Color.accentColor : Ink.text2)
                Circle()
                    .fill(logged ? Color.accentColor : .clear)
                    .frame(width: 8, height: 8)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(selected ? Ink.surface : .clear, in: .rect(cornerRadius: 12, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityLabel(Format.day(day, style: .dateTime.weekday(.wide).month().day()))
        .accessibilityValue(logged ? "Logged" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("log.day")
    }
}

/// What's left against that day's targets in a line ("1,601 kcal · 102 g protein left") over a thin
/// ruler of the day's calories, with what's logged for later beside it. With room, each macro under
/// it when carbs and fat are shown. On a past day being caught up, the whole usual day a tap away.
struct DaySummaryLine: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    let day: Day
    var wide = false

    var body: some View {
        let intake = model.dayIntake(on: day)
        let targets = model.targets(on: day)
        let missing = model.catchUp
        let counted = counted(intake)
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 7) {
                line(intake, counted: counted, targets: targets)
                if let kcal = targets?.kcal, kcal > 0 {
                    Ruler.thin(counted.kcal / kcal)
                }
                if wide, model.settings.showAllMacros {
                    HStack(spacing: 10) {
                        MacroBar(macro: .protein, eaten: counted.protein, target: targets?.protein)
                        MacroBar(macro: .carbs, eaten: counted.carbs, target: targets?.carbs)
                        MacroBar(macro: .fat, eaten: counted.fat, target: targets?.fat)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                }
            }
            .padding(.horizontal, wide ? 0 : 4)
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
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                }
                .hoverHighlight()
                .accessibilityIdentifier("catchUp.logAll")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Calories and protein left as numerals with their units, as the canvas has them; calories
    /// eaten (or planned) where there's no calorie target.
    func line(_ intake: DayIntake, counted: Nutrients, targets: DailyTargets?) -> some View {
        let later = day == model.today && intake.later.kcal > 0 ? intake.later.kcal : nil
        let kcal: (value: Double, unit: String)
        if let target = targets?.kcal {
            let left = target - counted.kcal
            kcal = (abs(left), left >= 0 ? (targets?.protein == nil ? "kcal left" : "kcal") : "kcal over")
        } else {
            kcal = (counted.kcal, day > model.today ? "kcal planned" : "kcal eaten")
        }
        let calories = Measure(value: Format.whole(kcal.value), unit: kcal.unit, size: 20)
        let protein = targets?.protein.map { protein in
            let left = protein - counted.protein
            return Measure(value: Format.whole(abs(left)), unit: left >= 0 ? "g protein left" : "g protein over", size: 20)
        }
        let line = HStack(alignment: .firstTextBaseline, spacing: 5) {
            calories
            if let protein {
                Text("·").font(.callout).foregroundStyle(Ink.text3).accessibilityHidden(true)
                protein
            }
            if let later {
                Text("· \(Format.whole(later)) later").font(.caption.monospacedDigit()).foregroundStyle(Ink.text3)
            }
        }
        .lineLimit(1)
        return Group {
            if typeSize.isAccessibilitySize {
                // On a line where it fits whole, else a number to a line, rather than shrunk and cut.
                ViewThatFits(in: .horizontal) {
                    line
                    VStack(alignment: .leading, spacing: 2) {
                        calories
                        protein
                        if let later { Text("\(Format.whole(later)) later").font(.caption.monospacedDigit()).foregroundStyle(Ink.text3) }
                    }
                }
            } else {
                line.minimumScaleFactor(0.75)
            }
        }
        .foregroundStyle(Ink.text)
    }

    func counted(_ intake: DayIntake) -> Nutrients { intake.counted(on: day, today: model.today) }
}

/// Fixed macro columns, the same in the header and every row. A sort of the day is in the Sort menu:
/// the column headers are labels, since the grid is in time order.
enum LogColumns {
    static let width: CGFloat = 56
    /// From the list's edges to the first and last columns, in the header and every row.
    static let gutter: CGFloat = 16

    /// A row's insets, for that gutter.
    static func rowInsets(vertical: CGFloat = 6) -> EdgeInsets {
        let side = gutter - Platform.listRowMargin
        return EdgeInsets(top: vertical, leading: side, bottom: vertical, trailing: side)
    }

    /// Whether the columns can show. They need the room, so beside a pane in the Mac's smallest
    /// window the phone's rows take over, and at accessibility sizes no scale factor saves them.
    static func fit(width: CGFloat, textSize: DynamicTypeSize) -> Bool { width >= 520 && !textSize.isAccessibilitySize }

    static var header: some View {
        HStack(spacing: 0) {
            Text("Food")
            Spacer()
            cells(["kcal", "P", "C", "F"])
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    /// `spoken` is what VoiceOver reads for each, where it isn't what's shown: a row's numbers mean
    /// nothing without their names.
    static func cells(_ values: [String], spoken: [String]? = nil) -> some View {
        HStack(spacing: 0) {
            ForEach(values.indices, id: \.self) { index in
                Text(values[index])
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: width, alignment: .trailing)
                    .monospacedDigit()
                    .accessibilityLabel(spoken?[index] ?? values[index])
            }
        }
    }
}

extension View {
    /// A row of the hours, on the page like the header over it, to the gutter they share.
    func logColumnRow(vertical: CGFloat = 6) -> some View {
        listRowInsets(LogColumns.rowInsets(vertical: vertical)).listRowBackground(Color.clear)
    }
}

/// One hour of the day: its label and +, what's usual or planned then, its foods, and the foods to
/// log again if it's the hour it is.
struct HourRows: View {
    @Environment(AppModel.self) private var model
    let group: HourGroup
    /// The gap before each meal that starts in this hour.
    let gaps: [MealGap]
    let wide: Bool
    @Binding var editing: FoodEntry?

    var body: some View {
        HourHeader(group: group, gaps: gaps)
            .id(group.id)
            // Thin: a whole day of hours fits in a couple of scrolls.
            .logColumnRow(vertical: 1)
            .listRowSeparator(group.entries.isEmpty ? .hidden : .automatic)
        Group {
            ForEach(usual) { CatchUpRow(usual: $0) }
            ForEach(planned, id: \.meal.id) { PlannedMealRow(meal: $0.meal, recipe: $0.recipe, plan: $0.plan) }
            ForEach(group.entries) { entry in
                LogEntryRow(entry: entry, wide: wide, editing: $editing)
            }
            if isNow, !model.logAgainChips.isEmpty { LogAgainChips() }
        }
        .logColumnRow()
    }

    var isNow: Bool { model.selectedDay == model.today && group.start <= Date() && Date() < group.end }

    /// The usual times of a past day still to catch up, in their hours.
    var usual: [UsualMeal] { model.catchUp.filter { group.start <= $0.time && $0.time < group.end } }

    /// The plan's meals for this hour.
    var planned: [(meal: PlannedMeal, recipe: PlannedRecipe, plan: MealPlan)] { model.plannedMeals(in: group) }
}

/// An hour's label, the gap before a meal that starts in it, what it adds up to, and its +. A tap
/// on the label picks out the hour's foods, and holding it offers what's done with a meal. While
/// foods are picked out, the + takes them here.
struct HourHeader: View {
    @Environment(AppModel.self) private var model
    let group: HourGroup
    let gaps: [MealGap]
    @State private var naming = false

    var body: some View {
        let kcal = group.entries.map(\.nutrients.kcal).reduce(0, +)
        HStack(spacing: 8) {
            label
            // Two, when a second meal starts within the hour of the first.
            ForEach(gaps, id: \.self) { GapBadge(gap: $0).accessibilityIdentifier("log.gap") }
            Spacer(minLength: 0)
            if kcal > 0 { Text(Format.kcal(kcal)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            Button(action: add) {
                // To the frame's end: over the last column, however big the target around it.
                Image(systemName: model.placeSymbol).font(.caption.weight(.bold)).frame(width: 36, height: 26, alignment: .trailing)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(model.placeLabel(at: group.start))
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
                    .accessibilityIdentifier("log.hourMenu.repeat")
                MomentMealButton(moment: moment) { naming = true }
                Button("Remove", systemImage: "trash", role: .destructive) { model.delete(entries: group.entries.map(\.id)) }
                    .accessibilityIdentifier("log.hourMenu.remove")
            }
        }
    }

    var allSelected: Bool { group.entries.allSatisfy { model.selection.ids.contains($0.id) } }

    func add() { model.logOrPlace(at: DayHours.addTime(group, now: Date())) }
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
    /// How the day's listed around it, for what's between two clicks.
    var order = DayOrder.time
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
                if wide { columns } else { MealFoodRow(entry: entry) }
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
                .accessibilityIdentifier("log.entry.delete")
        }
        .swipeActions(edge: .leading) {
            Button("Again", systemImage: "arrow.clockwise") {
                model.log([LogAgain.copy(entry, to: model.logDate(), source: .copied)])
            }
            .tint(.accentColor)
            .accessibilityIdentifier("log.entry.again")
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
            model.extendSelection(to: entry, in: order)
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
            FoodTile(name: entry.name, size: TileSize.table, fill: .cardBackground)
            VStack(alignment: .leading, spacing: 1) {
                // How someone would say it, as Today and the phone's cards name it.
                Text(FoodLabel.short(entry.name)).foregroundStyle(Ink.text).lineLimit(1).help(entry.name)
                Text([showsTime ? Format.time(entry.date) : nil, entry.brand, entry.amountLabel].compactMap { $0 }.joined(separator: " · ")).font(
                    .caption
                ).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            LogColumns.cells(
                ["\(entry.isEstimate ? "≈" : "")\(Format.whole(n.kcal))", Format.whole(n.protein), Format.whole(n.carbs), Format.whole(n.fat)],
                spoken: [
                    "\(entry.isEstimate ? "about " : "")\(Format.whole(n.kcal)) calories", "\(Format.whole(n.protein)) grams protein",
                    "\(Format.whole(n.carbs)) grams carbs", "\(Format.whole(n.fat)) grams fat",
                ])
        }
        .setBack(later, opacity: 0.55)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Log again, under the hour it is, in one tap each. The order holds still while they're being
/// tapped: the model takes it once a visit (`logAgainChips`), so a food logged doesn't move the next
/// one out from under a thumb, and the row scrolling away and back doesn't either.
struct LogAgainChips: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(model.logAgainChips) { item in
                    Button {
                        model.logAgain(item)
                    } label: {
                        Text(SavedMeals.shortName(item.template.name))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Ink.text)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background(Ink.raised, in: .capsule)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Log \(item.template.name) again")
                    .accessibilityIdentifier("log.again")
                }
            }
        }
        .scrollIndicators(.hidden)
        .listRowSeparator(.hidden)
    }
}

/// Any day, from the title.
struct DayChooser: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SheetHeading(eyebrow: "Log", title: "Choose a day")
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
                    .padding(.horizontal, 8)
                    .card(padding: 8)
                    .accessibilityIdentifier("log.datePicker")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .inkSheet {
                SheetBar(label: "Cancel", identifier: "dayChooser.cancel") { dismiss() }
            }
        }
        .presentationDetents([.height(560), .large])
    }
}
