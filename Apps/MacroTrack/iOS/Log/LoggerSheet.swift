import FoodDatabase
import NutritionEngine
import SwiftUI
import SystemCore

/// The logger as a sheet, on a phone: it holds the navigation around `LoggerContent`, and Done
/// closes it. Logging keeps it open (with Undo) so a meal of several foods is a few taps. It's the
/// composer opened (`LoggerComposer.swift`): the ink ground, Today's typing header at the top, the
/// matches rising to the composer's field at the foot.
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
            LoggerContent(session: session, covered: session.portion != nil, searchFocused: $searchFocused, composer: true, done: { dismiss() })
                .hidesNavigationBar()
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
        .loggerGround()
        .onAppear {
            model.ai.prewarm()
            // Words typed on Today that matched nothing: searched here (a description takes its own).
            if session.mode == .search, let text = model.takeLoggerText() { session.query = text }
            #if DEBUG
            SampleData.seedReview(session, model)
            #endif
            if session.mode == .search, session.portion == nil { searchFocused = true }
        }
        // Done, or a swipe down: nobody's left to read for.
        .onDisappear { session.stopRead() }
        .onChange(of: session.focusRequest) { _, _ in searchFocused = true }
        .onChange(of: session.blurRequest) { _, _ in searchFocused = false }
        .onChange(of: session.openMeal) { _, meal in if meal == nil { searchFocused = true } }
        // Asked for another way, the root presents that one's sheet in this one's place, and a
        // camera opening here would land on a sheet on its way out.
        .onChange(of: model.loggerRequest) { _, request in if request.mode == start { session.go(to: start) } }
        .onChange(of: model.foodsChanged) { _, _ in session.refreshFoods(model) }
    }
}

extension View {
    /// The logger's sheet on the ink ground, as the screens it opens from are, rather than the
    /// system's lighter grey. Vision Pro keeps its glass.
    func loggerGround() -> some View {
        #if os(visionOS)
        return self
        #else
        return presentationBackground(Ink.ground)
        #endif
    }
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
/// to it.
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
                    LoggerContent(session: session, covered: covered, searchFocused: $searchFocused, done: { model.logger = nil })
                }
            }
            .inkGround()
            .hidesNavigationBar()
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
        .onChange(of: model.foodsChanged) { _, _ in session.refreshFoods(model) }
    }
}

/// Every way to log, in one place: search, scan, a photo, a description and quick add, each
/// returning to the search. It holds no navigation of its own: a host gives it that, so a sheet and
/// a pane can each show it. On a phone (`composer`) it's the composer opened: Today's typing header
/// under where the foods go and Done, and at the foot the meal so far, the time and the composer's
/// field, whose camera and microphone are the other ways (`LoggerComposer.swift`). In the pane its
/// header is the search field (or the way's name) and Done, for a pointer and a keyboard, and the
/// meal so far, the time and the ways to log sit together at the bottom.
struct LoggerContent: View {
    @Environment(AppModel.self) private var model
    let session: LoggerSession
    /// An amount or a food is over it: a toast's few seconds would run out unseen.
    var covered = false
    var searchFocused: FocusState<Bool>.Binding
    /// The phone's: the field at the foot and the matches rising to it, as Today's composer.
    var composer = false
    let done: () -> Void

    var body: some View {
        Group {
            if composer {
                method
                    .frame(maxHeight: .infinity)
                    .safeAreaInset(edge: .top, spacing: 0) { LoggerTop(session: session, done: done) }
                    .safeAreaInset(edge: .bottom, spacing: 0) { LoggerFoot(session: session, covered: covered, searchFocused: searchFocused) }
            } else {
                VStack(spacing: 0) {
                    LoggerHeader(session: session, searchFocused: searchFocused, done: done)
                    method.frame(maxHeight: .infinity)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { bottom }
            }
        }
        .task(id: session.query) { await session.search(model) }
        .inkGround()
    }

    @ViewBuilder
    var method: some View {
        switch session.mode {
        case .search: SearchLogView(session: session, fromBottom: composer)
        case .scan: BarcodeLogView(session: session, covered: covered)
        case .camera, .photoLibrary: PhotoLogView(useCamera: session.mode == .camera, session: session)
        case .describe: DescribeLogView(session: session)
        case .quickAdd: QuickAddView(draft: session.quickAddDraft, close: { session.backToSearch() })
        }
    }

    /// Hidden while something's typed, when the room is the suggestions'.
    var showsRibbon: Bool { session.mode != .search || session.query.trimmingCharacters(in: .whitespaces).isEmpty }

    var bottom: some View {
        VStack(spacing: 8) {
            // Over the meal it just changed, where the eye already is after a tap on +.
            if !covered, !model.toastCovered { ToastSlot() }
            VStack(spacing: 10) {
                MealTray()
                LogTimeBar()
                methodsRow
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
            // Solid ink under the bars, down to the screen's foot: nothing of the list or a form
            // shows through between them. Not faded over what's above, which is often a way of
            // logging's own button (Add, Log, Find foods).
            .background(Color.pageBackground.ignoresSafeArea(edges: .bottom))
        }
        .animation(.snappy, value: model.toast)
    }

    @ViewBuilder
    var methodsRow: some View {
        if showsRibbon {
            MethodRibbon(session: session)
        } else if !session.completions.isEmpty, session.quickAddPart == nil {
            // In the ribbon's place: over the keyboard, under the thumb that's typing.
            SearchCompletionChips(options: session.completions, pick: session.complete)
        }
    }
}

/// The pane's top: the search field while searching (Return logs the best match), else the way of
/// logging's name under the day it logs to; Done beside them as a round button, as a page's header
/// has its buttons.
struct LoggerHeader: View {
    @Environment(AppModel.self) private var model
    let session: LoggerSession
    var searchFocused: FocusState<Bool>.Binding
    let done: () -> Void

    var body: some View {
        let searching = session.mode == .search
        VStack(alignment: .leading, spacing: 6) {
            if !searching || model.selectedDay != model.today {
                Text(day).eyebrow().lineLimit(1).padding(.horizontal, 4)
            }
            HStack(spacing: 10) {
                if searching {
                    LoggerSearchField(session: session, focused: searchFocused)
                } else {
                    PageTitle(session.mode.title, size: 28).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4)
                }
                CircleIconButton(symbol: "xmark", label: "Done", identifier: "logger.done", action: done)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    /// The day foods go to: "Today", or the day being caught up.
    var day: String {
        model.selectedDay == model.today ? "Today" : Format.day(model.selectedDay, style: .dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

/// The pane's search, as the composer's capsule: on the surface with a hairline, the accent's line
/// while typing. Return logs the best match, as the composer's does, and the keyboard stays.
struct LoggerSearchField: View {
    @Environment(AppModel.self) private var model
    @Bindable var session: LoggerSession
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.body.weight(.medium)).foregroundStyle(Ink.text3).accessibilityHidden(true)
            TextField("Search foods", text: $session.query, prompt: Text("Search foods").foregroundStyle(Ink.text3))
                .font(.body)
                .foregroundStyle(Ink.text)
                .focused(focused)
                .autocorrectionDisabled()
                .noAutocapitalization()
                .onSubmit {
                    session.pressedReturn(model)
                    focused.wrappedValue = true
                }
                .accessibilityIdentifier("logger.search")
            if !session.query.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") {
                    session.query = ""
                    session.focusSearch()
                }
                .labelStyle(.iconOnly)
                .font(.body)
                .foregroundStyle(Ink.text3)
                .frame(width: 40, height: 44)
                .contentShape(.rect)
                .buttonStyle(.plain)
                .accessibilityIdentifier("logger.clearSearch")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .frame(height: 50)
        .composerCapsule(focused: focused.wrappedValue)
    }
}

/// The other ways to log in the pane, as the design's segmented control (`.seg`): the one on lifted
/// onto the card colour. A phone has them on its field instead (`LoggerWays`).
struct MethodRibbon: View {
    @Environment(AppModel.self) private var model
    let session: LoggerSession

    var body: some View {
        HStack(spacing: 0) {
            segment("Search", .search)
            segment("Scan", .scan)
            if model.ai.canSeePhotos || waiting(on: .camera, .photoLibrary) { segment("Photo", .camera) }
            if model.ai.canDescribe || waiting(on: .describe) { segment("Describe", .describe) }
            segment("Quick add", .quickAdd)
        }
        .padding(3)
        .background(Ink.raised, in: .rect(cornerRadius: 13, style: .continuous))
        .animation(.snappy(duration: 0.2), value: session.mode)
    }

    /// A review left unlogged is reached through its way of logging, even if the model has gone.
    func waiting(on ways: LogMode...) -> Bool { session.review.map { ways.contains($0.mode) } ?? false }

    func segment(_ title: String, _ target: LogMode) -> some View {
        let current = session.mode == target || (target == .camera && session.mode == .photoLibrary)
        return Button {
            session.mode = target
        } label: {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(current ? Ink.text : Ink.text2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background {
                    if current {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Ink.surface)
                            .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
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

/// A choice as the design's chip (`.chip`): the raised grey, or the text's colour when it's the one.
struct InkChip: View {
    let title: String
    var symbol: String?
    var selected = false

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol) }
            Text(title)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(selected ? Ink.ground : Ink.text2)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(selected ? Ink.text : Ink.raised, in: .capsule)
        .contentShape(.capsule)
    }
}

/// The time choice under a search, where the thumb is.
struct LogTimeBar: View {
    @Environment(AppModel.self) private var model
    @State private var picking = false

    var body: some View {
        Group {
            if model.selectedDay == model.today {
                // Side by side while they fit. A chip won't shrink, so in a pane with a time picked
                // they'd widen the bar, and everything stacked with it, past the pane's edges.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        recentChips
                        Spacer(minLength: 0)
                        clock
                    }
                    HStack(spacing: 6) {
                        ScrollView(.horizontal) {
                            HStack(spacing: 6) { recentChips }
                        }
                        .scrollIndicators(.hidden)
                        .fadesAtTrailingEdge()
                        clock
                    }
                }
            } else {
                HStack(spacing: 6) {
                    otherDayTimes
                    clock
                }
            }
        }
        .sheet(isPresented: $picking) { TimePickerSheet().macSheetSize(width: 340, height: 460) }
        .debugSheet("time") { picking = true }
    }

    /// Today: now, and a little while ago.
    @ViewBuilder
    var recentChips: some View {
        chip("Now", selected: model.loggerTime == nil) { model.loggerTime = nil }
        ForEach(LogTime.recent, id: \.self) { minutes in
            chip(LogTime.short(minutes), selected: LogTime.label(model) == LogTime.ago(minutes)) {
                model.loggerTime = Date().addingTimeInterval(-Double(minutes) * 60)
            }
        }
    }

    /// Another day: its name, or the times to catch up on.
    @ViewBuilder
    var otherDayTimes: some View {
        if usual.isEmpty {
            Text(Format.day(model.selectedDay, style: .dateTime.weekday(.wide))).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
                .padding(.leading, 4)
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
            .fadesAtTrailingEdge()
        }
    }

    /// Any other time. It stays in sight beside chips that scroll: it's where a picked time shows.
    var clock: some View {
        Button {
            picking = true
        } label: {
            if let custom {
                InkChip(title: custom, symbol: "clock", selected: true)
            } else {
                Image(systemName: "clock").font(.footnote.weight(.semibold)).foregroundStyle(Ink.text2)
                    .frame(width: 32, height: 32).background(Ink.raised, in: .circle).contentShape(.circle)
            }
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityLabel("Pick a time")
        .accessibilityIdentifier("logger.pickTime")
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
        Button(action: action) { InkChip(title: title, selected: selected) }
            .buttonStyle(.plain)
            .hoverHighlight()
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension View {
    /// A row of chips that scrolls fades out at its end, where it runs under the clock, rather than
    /// being cut through a chip.
    fileprivate func fadesAtTrailingEdge() -> some View {
        mask {
            LinearGradient(
                stops: [.init(color: .black, location: 0.85), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing)
        }
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
            VStack(alignment: .leading, spacing: 12) {
                SheetHeading(eyebrow: "Logging", title: model.selectedDay == model.today ? "Eaten at" : "Eaten \(Format.day(model.selectedDay)) at")
                    .padding(.horizontal, 16)
                // The times this person usually eats (today's up to now), a tap each: lunch at 12:30
                // without winding the wheel back from 9 PM.
                if !usual.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(usual, id: \.self) { time in
                                Button {
                                    model.loggerTime = time
                                    dismiss()
                                } label: {
                                    InkChip(title: Format.time(time))
                                }
                                .buttonStyle(.plain)
                                .hoverHighlight()
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
                    .card(padding: 8)
                    .padding(.horizontal, 16)
                Spacer(minLength: 0)
            }
            .inkSheet {
                SheetBar(label: "Cancel", identifier: "timePicker.cancel") { dismiss() }
            } foot: {
                SheetFoot {
                    Button {
                        let picked = model.onSelectedDay(time)
                        model.loggerTime = model.selectedDay == model.today ? LogTime.nearest(picked) : picked
                        dismiss()
                    } label: {
                        Text("Done").frame(maxWidth: .infinity)
                    }
                    .primaryAction()
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("timePicker.done")
                }
            }
        }
        .presentationDetents([.height(usual.isEmpty ? 470 : 520)])
        .onAppear { time = model.logDate() }
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

    /// The same amount of the food with new numbers (or the catalog's again), as a food being added
    /// takes them (`AmountDraft.use`). Its units are the same ones, but calories hold a different
    /// amount now, and a food corrected to no calories can't be counted in them.
    mutating func use(_ corrected: Food) {
        guard let old = unit else { return }
        let units = FoodUnits.units(for: corrected)
        guard let next = units.first(where: { $0.id == old.id }) ?? units.first(where: { $0.id == corrected.basis.rawValue }), next != old else {
            return
        }
        let converted = FoodUnits.convert(count, from: old, to: next)
        self = PortionAmount(count: converted.isFinite ? converted : count, unit: next)
    }

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
                    Button {
                        amount.count = value
                        amount.text = FoodUnits.format(value, current)
                    } label: {
                        InkChip(title: AmountChoices.label(value, unit: current), selected: abs(amount.count - value) < 0.001)
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight()
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
        HStack(alignment: .top, spacing: 12) {
            FoodTile(name: food.name, size: TileSize.header, fill: Ink.raised)
            VStack(alignment: .leading, spacing: 3) {
                Text(food.name).font(nameFont).foregroundStyle(Ink.text)
                if let brand = food.brand, brand.lowercased() != food.name.lowercased() {
                    Text(brand).font(.subheadline).foregroundStyle(Ink.text2)
                }
                Text(corrected ? "Your numbers, corrected from \(Self.sourceLabel(food))" : Self.sourceLabel(food))
                    .font(.caption).foregroundStyle(Ink.text3)
                    .accessibilityIdentifier("food.source")
                FoodQualityTags(processing: food.processing, fermented: food.fermented ?? Fermented.isFermented(food.name))
            }
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
            CircleIcon(symbol: model.isFavorite(foodID) ? "star.fill" : "star")
        }
        .accessibilityLabel(model.isFavorite(foodID) ? "Remove from favorites" : "Add to favorites")
        .accessibilityIdentifier("portion.favorite")
        .help(model.isFavorite(foodID) ? "Remove from favorites" : "Add to favorites")
    }
}

/// Calories big, macros beside: the calories as a numeral with its unit, and each macro's grams in
/// its colour over its name, as Today's "g left" are.
struct NutrientSummary: View {
    let nutrients: Nutrients

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            // One line, whatever the room: a narrow inspector broke "1,155" over two.
            Measure(value: Format.whole(nutrients.kcal), unit: "kcal", size: 30)
                .layoutPriority(1)
            Spacer(minLength: 4)
            macro("Protein", nutrients.protein, .protein)
            macro("Carbs", nutrients.carbs, .carbs)
            macro("Fat", nutrients.fat, .fat)
        }
        .accessibilityElement(children: .combine)
    }

    func macro(_ label: String, _ value: Double, _ macro: Macro) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(Format.grams(value)).numeral(17, weight: .bold).foregroundStyle(macro.color)
            Text(label).font(.caption).foregroundStyle(Ink.text3)
        }
        .frame(minWidth: 52, alignment: .trailing)
    }
}
