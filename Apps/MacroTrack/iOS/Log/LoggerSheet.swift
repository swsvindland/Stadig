import FoodDatabase
import NutritionEngine
import SwiftUI
import SystemCore

/// The logger as a sheet: it holds the navigation and the search field around `LoggerContent`, and
/// Done closes it. Logging keeps it open (with Undo) so a meal of several foods is a few taps.
struct LoggerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let start: LogMode
    @State private var session: LoggerSession
    @FocusState private var searchFocused: Bool

    init(start: LogMode) {
        self.start = start
        _session = State(initialValue: LoggerSession(mode: start))
    }

    var body: some View {
        @Bindable var session = session
        NavigationStack {
            Group {
                if session.mode == .search {
                    content
                        .searchable(text: $session.query, placement: .alwaysShown, prompt: "Search foods")
                        // The search is active whenever the logger is (the keyboard stays up for the
                        // next food), and by default an active search hides the bar with the title.
                        .searchPresentationToolbarBehavior(.avoidHidingContent)
                        .searchFocused($searchFocused)
                        .autocorrectionDisabled()
                        .noAutocapitalization()
                        .onAppear { if session.portion == nil { searchFocused = true } }
                } else {
                    content
                }
            }
            .inlineTitle()
            .navigationDestination(item: $session.openMeal) { id in
                SavedMealView(mealID: id) {
                    session.openMeal = nil
                    session.query = ""
                }
            }
            .sheet(item: $session.portion, onDismiss: { session.focusSearch() }) { request in
                LoggerAmount(session: session, request: request)
            }
        }
        .onAppear {
            model.ai.prewarm()
            #if DEBUG
            SampleData.seedReview(session, model)
            #endif
        }
        // Done, or a swipe down: nobody's left to read for.
        .onDisappear { session.stopRead() }
        .onChange(of: session.focusRequest) { _, _ in searchFocused = true }
        .onChange(of: session.blurRequest) { _, _ in searchFocused = false }
        .onChange(of: session.openMeal) { _, meal in if meal == nil { searchFocused = true } }
        // Asked for another way, the root presents that one's sheet in this one's place, and a
        // camera opening here would land on a sheet on its way out.
        .onChange(of: model.loggerRequest) { _, request in if request.mode == start { session.go(to: start) } }
    }

    var content: some View { LoggerContent(session: session, covered: session.portion != nil, done: { dismiss() }) }
}

/// The amount panel, as the logger opens it: an added food goes back to the search for the next
/// one, and a review's food goes back to the review.
struct LoggerAmount: View {
    let session: LoggerSession
    let request: AmountRequest

    var body: some View {
        panel.amountSheet(editing: false)
    }

    var panel: some View {
        AmountPanel(
            request: request,
            picked: { count, unit in
                guard case .pick(let item, _, _) = request.purpose, let index = session.review?.items.firstIndex(where: { $0.id == item }) else {
                    return
                }
                session.review?.items[index].count = count
                session.review?.items[index].unit = unit
            },
            foodCorrected: { session.useCorrection($0) },
            finished: {
                guard case .add = request.purpose else { return }
                session.backToSearch()
            },
            close: { session.portion = nil }
        )
    }
}

/// The logger as a pane beside the Log tab, where there's room: not over the day, so each food added
/// lands in sight, and an hour's + aims it at that hour. The amount takes its place, and goes back
/// to it. It has its own search field, since a pane isn't where a window's search field goes.
struct LoggerPane: View {
    @Environment(AppModel.self) private var model
    /// A food's being changed over it. It stays alive under there, out of sight and out of reach.
    let covered: Bool
    @State private var session: LoggerSession
    @FocusState private var searchFocused: Bool

    init(start: LogMode, covered: Bool = false) {
        self.covered = covered
        _session = State(initialValue: LoggerSession(mode: start))
    }

    var body: some View {
        @Bindable var session = session
        NavigationStack {
            Group {
                if let request = session.portion {
                    LoggerAmount(session: session, request: request).panel
                } else {
                    VStack(spacing: 0) {
                        if session.mode == .search { searchField }
                        LoggerContent(session: session, covered: covered, done: { model.logger = nil })
                    }
                }
            }
            .inlineTitle()
            .navigationDestination(item: $session.openMeal) { id in
                SavedMealView(mealID: id) {
                    session.openMeal = nil
                    session.query = ""
                }
            }
        }
        .opacity(covered ? 0 : 1)
        .disabled(covered)
        .accessibilityHidden(covered)
        .onAppear {
            model.ai.prewarm()
            #if DEBUG
            SampleData.seedReview(session, model)
            #endif
            searchFocused = true
        }
        .onDisappear { session.stopRead() }
        .onChange(of: covered) { _, covered in searchFocused = !covered && session.portion == nil }
        .onChange(of: session.focusRequest) { _, _ in searchFocused = true }
        .onChange(of: session.blurRequest) { _, _ in searchFocused = false }
        .onChange(of: session.portion) { _, request in if request == nil { searchFocused = true } }
        .onChange(of: model.loggerRequest) { _, request in if let mode = request.mode { session.go(to: mode) } }
    }

    var searchField: some View {
        @Bindable var session = session
        return TextField("Search foods", text: $session.query)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .noAutocapitalization()
            .focused($searchFocused)
            // Return logs the best match, as the Foods screen's does.
            .onSubmit { session.pressedReturn(model) }
            .accessibilityIdentifier("logger.search")
            .overlay(alignment: .trailing) {
                if !session.query.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill") {
                        session.query = ""
                        session.focusSearch()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 6)
                    .accessibilityIdentifier("logger.clearSearch")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
    }
}

/// Every way to log, in one place: search, scan, a photo, a description and quick add, each
/// returning to the search. It holds no navigation, search field or toolbar of its own: a host gives
/// it those, so a sheet and a pane can each show it. The meal so far, the time, the other ways to log
/// and Done sit together at the bottom, in reach of a thumb and above the keyboard.
struct LoggerContent: View {
    @Environment(AppModel.self) private var model
    let session: LoggerSession
    /// An amount or a food is over it: a toast's few seconds would run out unseen.
    var covered = false
    let done: () -> Void

    var body: some View {
        method
            .safeAreaInset(edge: .bottom) { bottom }
            .task(id: session.query) { await session.search(model) }
    }

    @ViewBuilder
    var method: some View {
        switch session.mode {
        case .search: SearchLogView(session: session)
        case .scan: BarcodeLogView(session: session, covered: covered)
        case .camera, .photoLibrary: PhotoLogView(useCamera: session.mode == .camera, session: session)
        case .describe: DescribeLogView(session: session)
        case .quickAdd: QuickAddView(close: { session.backToSearch() })
        }
    }

    /// Hidden while something's typed, when the room is the results'.
    var showsRibbon: Bool { session.mode != .search || session.query.trimmingCharacters(in: .whitespaces).isEmpty }

    var bottom: some View {
        VStack(spacing: 8) {
            // Over the meal it just changed, where the eye already is after a tap on +.
            if !covered, !model.toastCovered { ToastSlot() }
            VStack(spacing: 8) {
                MealTray()
                LogTimeBar()
                methodsRow
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
        .animation(.snappy, value: model.toast)
    }

    var methodsRow: some View {
        HStack(spacing: 8) {
            if showsRibbon { MethodRibbon(session: session) } else { Spacer(minLength: 0) }
            Button(action: done) {
                Text("Done").font(.headline).padding(.horizontal, 18).frame(minHeight: 44).contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .hoverHighlight()
            // Over a scrolling list, as the bars above it are: clear glass alone lets the rows read through.
            .background(Color.cardBackground.opacity(0.75), in: .capsule)
            .floatingGlass(in: .capsule)
            .accessibilityIdentifier("logger.done")
        }
    }
}

/// The other ways to log.
struct MethodRibbon: View {
    @Environment(AppModel.self) private var model
    let session: LoggerSession

    var body: some View {
        HStack(spacing: 4) {
            chip("Search", "magnifyingglass", .search)
            chip("Scan", "barcode.viewfinder", .scan)
            if model.ai.canSeePhotos || waiting(on: .camera, .photoLibrary) { chip("Photo", "camera", .camera) }
            if model.ai.canDescribe || waiting(on: .describe) { chip("Describe", "text.bubble", .describe) }
            chip("Quick add", "plus.forwardslash.minus", .quickAdd)
        }
        .padding(2)
        .frame(maxWidth: .infinity)
        .background(Color.cardBackground.opacity(0.75), in: .capsule)
        .floatingGlass(in: .capsule)
    }

    /// A review left unlogged is reached through its way of logging, even if the model has gone.
    func waiting(on ways: LogMode...) -> Bool { session.review.map { ways.contains($0.mode) } ?? false }

    func chip(_ title: String, _ symbol: String, _ target: LogMode) -> some View {
        let current = session.mode == target || (target == .camera && session.mode == .photoLibrary)
        return Button {
            session.mode = target
        } label: {
            Image(systemName: symbol)
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(current ? Color.accentColor.opacity(0.2) : .clear, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityLabel(title)
        .accessibilityAddTraits(current ? .isSelected : [])
        .accessibilityIdentifier("logger.mode.\(target.rawValue)")
    }
}

/// When the foods being logged were eaten: now, a little while ago, or any time of the day.
enum LogTime {
    /// Minutes ago offered as one tap.
    static let recent = [30, 60, 120]

    @MainActor
    static func label(_ model: AppModel) -> String {
        let date = model.logDate()
        if model.selectedDay != model.today { return "\(Format.day(model.selectedDay, style: .dateTime.weekday(.abbreviated))) \(Format.time(date))" }
        guard let picked = model.loggerTime else { return "Now" }
        let minutes = Int((Date().timeIntervalSince(picked) / 60).rounded())
        if let match = recent.first(where: { abs($0 - minutes) <= 2 }) { return ago(match) }
        return time(model)
    }

    /// The time foods will be logged at, with its day when that isn't the day being looked at
    /// ("Sat 11:30 PM"), so a time that lands on another day says so.
    @MainActor
    static func time(_ model: AppModel) -> String {
        let date = model.logDate()
        guard Day(date) != model.selectedDay else { return Format.time(date) }
        return "\(Format.day(Day(date), style: .dateTime.weekday(.abbreviated))) \(Format.time(date))"
    }

    /// How far back a time picked ahead of the clock can still mean last night.
    static let lastNight: TimeInterval = 6 * 3600

    /// A time picked on the wheel for today means today, even if that's later on: 7 PM picked at
    /// noon is this evening, and so is 6:30 PM picked at 6 AM. Only a real last night is yesterday:
    /// 11:30 PM picked just after midnight.
    static func nearest(_ picked: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        guard picked > now, let yesterday = calendar.date(byAdding: .day, value: -1, to: picked) else { return picked }
        return now.timeIntervalSince(yesterday) <= lastNight ? yesterday : picked
    }

    static func ago(_ minutes: Int) -> String { minutes < 60 ? "\(minutes) min ago" : "\(minutes / 60) h ago" }

    /// The same, short enough for a row of chips.
    static func short(_ minutes: Int) -> String { minutes < 60 ? "\(minutes)m ago" : "\(minutes / 60)h ago" }
}

/// The time choice under a search, where the thumb is.
struct LogTimeBar: View {
    @Environment(AppModel.self) private var model
    @State private var picking = false

    var body: some View {
        HStack(spacing: 6) {
            if model.selectedDay == model.today {
                chip("Now", selected: model.loggerTime == nil) { model.loggerTime = nil }
                ForEach(LogTime.recent, id: \.self) { minutes in
                    chip(LogTime.short(minutes), selected: LogTime.label(model) == LogTime.ago(minutes)) {
                        model.loggerTime = Date().addingTimeInterval(-Double(minutes) * 60)
                    }
                }
            } else if usual.isEmpty {
                Text(Format.day(model.selectedDay, style: .dateTime.weekday(.wide))).font(.subheadline.weight(.medium)).padding(.leading, 8)
                Spacer(minLength: 0)
            } else {
                // Catching up a day: the times this person usually eats, so "noon, then 3, then 7"
                // is a tap each, with the search's suggestions following.
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(usual, id: \.self) { time in
                            chip(Format.time(time), selected: model.loggerTime == time) { model.loggerTime = time }
                                .accessibilityIdentifier("logger.usualTime")
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            Button {
                picking = true
            } label: {
                Group {
                    if let custom {
                        Label(custom, systemImage: "clock").labelStyle(.titleAndIcon)
                    } else {
                        Image(systemName: "clock")
                    }
                }
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(custom != nil ? Color.accentColor.opacity(0.2) : Color.clear, in: .capsule)
            }
            .buttonStyle(.plain)
            .hoverHighlight()
            .accessibilityLabel("Pick a time")
            .accessibilityIdentifier("logger.pickTime")
        }
        .padding(6)
        .floatingGlass(in: Capsule(), interactive: false)
        .sheet(isPresented: $picking) { TimePickerSheet().macSheetSize(width: 340, height: 360) }
    }

    /// A past day's usual times, as chips.
    var usual: [Date] { model.selectedDay == model.today ? [] : model.usualLogTimes() }

    /// A time picked on the wheel rather than with a chip.
    var custom: String? {
        guard model.loggerTime != nil || model.selectedDay != model.today else { return nil }
        if let picked = model.loggerTime, usual.contains(picked) { return nil }
        let label = LogTime.label(model)
        return LogTime.recent.map(LogTime.ago).contains(label) ? nil : LogTime.time(model)
    }

    func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(selected ? Color.accentColor.opacity(0.2) : Color.clear, in: .capsule)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Any time of the selected day, on a wheel.
struct TimePickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var time = Date()

    var body: some View {
        let usual = model.usualLogTimes()
        NavigationStack {
            VStack(spacing: 8) {
                // The times this person usually eats (today's up to now), a tap each: lunch at 12:30
                // without winding the wheel back from 9 PM.
                if !usual.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(usual, id: \.self) { time in
                                Button(Format.time(time)) {
                                    model.loggerTime = time
                                    dismiss()
                                }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .accessibilityIdentifier("timePicker.usual")
                            }
                        }
                        .padding(.horizontal)
                    }
                    .scrollIndicators(.hidden)
                }
                DatePicker("Eaten at", selection: $time, displayedComponents: .hourAndMinute)
                    .timeOfDayPickerStyle()
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
            }
            .navigationTitle(model.selectedDay == model.today ? "Eaten at" : "Eaten \(Format.day(model.selectedDay)) at")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("timePicker.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let picked = model.onSelectedDay(time)
                        model.loggerTime = model.selectedDay == model.today ? LogTime.nearest(picked) : picked
                        dismiss()
                    }
                    .accessibilityIdentifier("timePicker.done")
                }
            }
        }
        .presentationDetents([.height(usual.isEmpty ? 300 : 352)])
        .onAppear { time = model.logDate() }
    }
}

/// Search as you type: saved meals and personal foods first, the last portion pre-filled, + logs in
/// one tap. While the AI's review is finding a food, what's picked goes there instead.
struct SearchLogView: View {
    @Environment(AppModel.self) private var model
    let session: LoggerSession

    var query: String { session.query }
    var results: [FoodMatch] { session.results }

    var body: some View {
        List {
            if session.finding != nil {
                Section {
                    HStack {
                        Text("Pick a food for your meal").font(.subheadline.weight(.medium))
                        Spacer()
                        Button("Back to the meal") { session.stopFinding() }
                            .font(.subheadline)
                            .accessibilityIdentifier("logger.backToReview")
                    }
                }
            }
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                // Saved meals and Log Again follow the time being logged at: lunch for noon, even
                // when it's caught up at 9 PM. A usual moment that is a saved meal is in My Meals.
                // Finding a food for a review, only what's one food can be its answer.
                if session.finding == nil, let usual = model.loggerUsual, SavedMeals.meal(for: usual.entries, in: model.savedMeals) == nil {
                    Section("Same as \(Format.relative(Day(usual.start), today: model.today))") {
                        UsualMomentRow(moment: usual)
                    }
                }
                let suggested = session.finding == nil ? model.loggerMeals : []
                if !suggested.isEmpty {
                    Section("My meals") {
                        ForEach(suggested.prefix(20)) { suggestion in
                            mealRow(suggestion.meal)
                        }
                    }
                }
                let again = model.loggerLogAgain.filter { session.finding == nil || $0.template.foodID != nil }
                if !again.isEmpty {
                    Section(model.timedSuggestions == nil ? "Log again" : "Log again for \(LogTime.time(model))") {
                        ForEach(again.prefix(12)) { item in
                            RecentRow(item: item, add: { addAgain(item) }, open: { open(item) })
                        }
                    }
                }
                let favorites = model.personal.filter(\.favorite)
                if !favorites.isEmpty {
                    Section("Favorites") {
                        ForEach(favorites.prefix(20), id: \.food.id) { p in
                            FoodRow(food: p.food, personal: p, add: { quickAdd(p.food) }, open: { open(p.food) })
                        }
                    }
                }
                let mine = model.customFoods.map(\.food)
                if !mine.isEmpty {
                    Section("My foods") {
                        ForEach(mine.prefix(30)) { food in
                            FoodRow(food: food, personal: model.personalFood(food.id), add: { quickAdd(food) }, open: { open(food) })
                        }
                    }
                }
            } else if results.isEmpty && meals.isEmpty && !session.searching {
                ContentUnavailableView {
                    Label("No matches", systemImage: "magnifyingglass")
                } description: {
                    Text("Try fewer words, scan the barcode, or describe it.")
                } actions: {
                    Button("Describe “\(query)”") { session.mode = .describe }
                    Button("Quick add calories") { session.mode = .quickAdd }.accessibilityIdentifier("logger.noMatchesQuickAdd")
                }
                .listRowBackground(Color.clear)
            } else if meals.isEmpty {
                foodResults
            } else {
                Section("My meals") {
                    ForEach(meals) { mealRow($0) }
                }
                Section("Foods") { foodResults }
            }
        }
        .insetGroupedList()
        // The time bar's usual times take the weekday's place there on a day being caught up.
        .navigationTitle(model.selectedDay == model.today ? "" : Format.day(model.selectedDay, style: .dateTime.weekday(.wide)))
    }

    /// Saved meals with what's typed: the person's own handful, so no need to wait for the catalog,
    /// and read afresh each time, so a meal changed or deleted on its screen isn't logged as it was.
    var meals: [SavedMeal] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return text.isEmpty || session.finding != nil ? [] : SavedMeals.matching(text, in: model.loggerMeals.map(\.meal))
    }

    var foodResults: some View {
        ForEach(results) { match in
            FoodRow(
                food: match.food, personal: model.personalFood(match.food.id), add: { quickAdd(match.food) }, open: { open(match.food) })
        }
    }

    func mealRow(_ meal: SavedMeal) -> some View {
        SavedMealRow(
            meal: meal,
            add: {
                model.log(meal)
                session.query = ""
                session.focusSearch()
            },
            open: {
                session.blurSearch()
                session.openMeal = meal.id
            })
    }

    /// The + button.
    func quickAdd(_ food: Food) { session.add(food, model) }

    func open(_ food: Food) {
        guard session.finding == nil else {
            session.use(food)
            return
        }
        session.blurSearch()
        session.portion = .add(food, source: .search)
    }

    func open(_ item: LogAgainItem) {
        if let id = item.template.foodID, let food = model.food(id: id) {
            open(food)
        } else if session.finding == nil {
            model.logAgain(item)
        }
    }

    /// The + on Log again: the same food and amount, or the food being found for the review.
    func addAgain(_ item: LogAgainItem) {
        guard session.finding != nil else {
            model.logAgain(item)
            return
        }
        if let food = item.template.foodID.flatMap(model.food(id:)) { session.use(food) }
    }
}

/// A catalog food: name, the portion it would log, and a one-tap add.
struct FoodRow: View {
    let food: Food
    let personal: PersonalFood?
    let add: () -> Void
    let open: () -> Void

    var body: some View {
        let suggestion = FoodUnits.suggested(
            for: food, lastUnitID: personal?.lastUnitID, lastCount: personal?.lastCount, lastAmount: personal?.lastAmount)
        let n = FoodUnits.nutrients(food, count: suggestion.count, unit: suggestion.unit)
        HStack(spacing: 12) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(food.name).lineLimit(2)
                        if personal?.favorite == true { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                    }
                    Text(
                        [
                            food.brand.flatMap { $0.lowercased() == food.name.lowercased() ? nil : $0 },
                            FoodUnits.label(count: suggestion.count, unit: suggestion.unit),
                            "\(Format.whole(n.kcal)) kcal", "\(Format.grams(n.protein)) P",
                        ].compactMap { $0 }.joined(separator: " · ")
                    )
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .hoverHighlight()
            .accessibilityIdentifier("logger.food")
            Button(action: add) {
                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .hoverHighlight()
            .accessibilityLabel("Add \(FoodUnits.label(count: suggestion.count, unit: suggestion.unit)) of \(food.name)")
            .accessibilityIdentifier("logger.addFood")
        }
    }
}

/// A recently logged food, re-logged as it was.
struct RecentRow: View {
    let item: LogAgainItem
    let add: () -> Void
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.template.name).lineLimit(1)
                    Text(
                        [item.template.brand, item.template.amountLabel, "\(Format.whole(item.template.nutrients.kcal)) kcal"]
                            .compactMap { $0 }.joined(separator: " · ")
                    )
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .hoverHighlight()
            Button(action: add) {
                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .hoverHighlight()
            .accessibilityLabel("Log \(item.template.name) again")
            .accessibilityIdentifier("logger.logAgain")
        }
    }
}

/// What was eaten around the logger's time on another recent day, logged again whole with a tap.
struct UsualMomentRow: View {
    @Environment(AppModel.self) private var model
    let moment: Moment

    var body: some View {
        let name = model.name(of: moment)
        Button {
            model.logAgain(moment)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).lineLimit(1)
                    Text("\(Format.time(moment.start)) · \(moment.entries.count) foods · \(Format.kcal(moment.nutrients.kcal))")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Color.accentColor)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityLabel("Log \(name) again, \(moment.entries.count) foods, \(Format.kcal(moment.nutrients.kcal))")
        .accessibilityIdentifier("logger.sameAsUsual")
    }
}

/// An amount being chosen: the count, its unit, the text being typed and the usual amount the quick
/// choices are halves and multiples of.
struct PortionAmount: Equatable {
    var count: Double = 1
    var text = "1"
    var unit: PortionUnit?
    var base: Double = 1

    init() {}

    init(count: Double, unit: PortionUnit) {
        self.count = count
        self.unit = unit
        base = count
        text = FoodUnits.format(count, unit)
    }

    /// The person's last portion of the food, else its natural one.
    init(suggestedFor food: Food, personal: PersonalFood?) {
        let suggestion = FoodUnits.suggested(
            for: food, lastUnitID: personal?.lastUnitID, lastCount: personal?.lastCount, lastAmount: personal?.lastAmount)
        unit = suggestion.unit
        count = suggestion.count
        base = suggestion.count
        text = FoodUnits.format(suggestion.count, suggestion.unit)
    }

    func unit(for food: Food) -> PortionUnit? { unit ?? FoodUnits.units(for: food).first }

    func nutrients(_ food: Food) -> Nutrients { unit(for: food).map { FoodUnits.nutrients(food, count: count, unit: $0) } ?? .zero }
}

/// The amount field, its unit and the quick choices.
struct AmountFields: View {
    let food: Food
    @Binding var amount: PortionAmount

    var body: some View {
        let units = FoodUnits.units(for: food)
        let current = amount.unit(for: food)
        HStack {
            TextField("Amount", text: $amount.text)
                .fieldKeyboard(.decimal)
                .font(.title2.weight(.semibold).monospacedDigit())
                .accessibilityIdentifier("portion.amount")
                .onChange(of: amount.text) { _, text in
                    // Text this view wrote already says the count; reading it back would round it.
                    guard current.map({ text != FoodUnits.format(amount.count, $0) }) ?? true, let v = Format.parse(text), v > 0 else { return }
                    amount.count = v
                }
            Picker(
                "Unit",
                selection: Binding(
                    get: { current?.id ?? "" },
                    set: { id in
                        guard let next = units.first(where: { $0.id == id }), let old = current, next.id != old.id else { return }
                        // Keep the amount: 1 cup becomes 240 g, not 1 g, rounded for the new unit.
                        let converted = FoodUnits.convert(amount.count, from: old, to: next)
                        amount.unit = next
                        if converted.isFinite { amount.count = converted }
                        amount.base = amount.count
                        amount.text = FoodUnits.format(amount.count, next)
                    })
            ) {
                ForEach(units) { Text($0.label).tag($0.id) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .accessibilityIdentifier("portion.unit")
        }
        if let current {
            HStack(spacing: 8) {
                ForEach(AmountChoices.quick(base: amount.base, unit: current), id: \.self) { value in
                    Button(AmountChoices.label(value, unit: current)) {
                        amount.count = value
                        amount.text = FoodUnits.format(value, current)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .choiceTint(abs(amount.count - value) < 0.001)
                    .accessibilityIdentifier("portion.quick")
                }
            }
        }
    }
}

/// A food's name, brand, where its numbers come from and how processed it is.
struct FoodHeader: View {
    let food: Food
    /// The numbers are the person's correction of the catalog's.
    var corrected = false
    var nameFont: Font = .title3.weight(.semibold)

    static func sourceLabel(_ food: Food) -> String {
        switch food.source {
        case .usda: "USDA FoodData Central"
        case .off: "Open Food Facts"
        case .custom: "My food"
        case .recipe: "Recipe"
        case .label: "From its label"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(food.name).font(nameFont)
            if let brand = food.brand, brand.lowercased() != food.name.lowercased() {
                Text(brand).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(corrected ? "Your numbers, corrected from \(Self.sourceLabel(food))" : Self.sourceLabel(food))
                .font(.caption).foregroundStyle(.tertiary)
                .accessibilityIdentifier("food.source")
            FoodQualityTags(processing: food.processing, fermented: food.fermented ?? Fermented.isFermented(food.name))
        }
    }
}

/// A star that keeps a food among the favourites.
struct FavoriteButton: View {
    @Environment(AppModel.self) private var model
    let foodID: String

    var body: some View {
        Button {
            model.toggleFavorite(foodID)
        } label: {
            Image(systemName: model.isFavorite(foodID) ? "star.fill" : "star")
        }
        .accessibilityLabel(model.isFavorite(foodID) ? "Remove from favorites" : "Add to favorites")
        .accessibilityIdentifier("portion.favorite")
        .help(model.isFavorite(foodID) ? "Remove from favorites" : "Add to favorites")
    }
}

/// Calories big, macros beside.
struct NutrientSummary: View {
    let nutrients: Nutrients

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading) {
                // One line, whatever the room: a narrow inspector broke "1,155" over two.
                Text(Format.whole(nutrients.kcal)).font(.title.weight(.bold).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("kcal").font(.caption).foregroundStyle(.secondary)
            }
            .layoutPriority(1)
            Spacer()
            macro("Protein", nutrients.protein, .protein)
            macro("Carbs", nutrients.carbs, .carbs)
            macro("Fat", nutrients.fat, .fat)
        }
        .accessibilityElement(children: .combine)
    }

    func macro(_ label: String, _ value: Double, _ macro: Macro) -> some View {
        VStack(alignment: .trailing) {
            Text(Format.grams(value)).font(.headline.monospacedDigit()).foregroundStyle(macro.color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(minWidth: 58, alignment: .trailing)
    }
}
