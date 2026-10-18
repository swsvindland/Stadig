import FoodDatabase
import NutritionEngine
import SwiftUI
import SystemCore

/// A food and portion to confirm, and whether the logger closes after adding it.
struct PortionRequest: Identifiable, Hashable {
    var food: Food
    var source: EntrySource
    var closeAfterAdd = false
    var id: String { food.id }
}

/// Every way to log, in one sheet that opens straight on the way chosen. Logging keeps the sheet
/// open (with Undo) so a meal of several foods is a few taps; Done closes it.
struct LoggerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var mode: LogMode
    @State private var query = ""
    @State private var portion: PortionRequest?

    init(start: LogMode) { _mode = State(initialValue: start) }

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if mode != .search { ToolbarItem(placement: .principal) { TimeMenu() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.accessibilityIdentifier("logger.done")
                    }
                }
                .navigationDestination(item: $portion) { request in
                    PortionView(request: request) { closeAfter in
                        portion = nil
                        query = ""
                        if closeAfter || request.closeAfterAdd { dismiss() }
                    }
                }
        }
        .toastOverlay(bottomPadding: mode == .search ? 150 : 24)
        .onAppear { model.ai.prewarm() }
    }

    @ViewBuilder
    var content: some View {
        switch mode {
        case .search:
            SearchLogView(query: $query, mode: $mode, portion: $portion)
        case .scan:
            BarcodeLogView(portion: $portion, mode: $mode)
        case .camera, .photoLibrary:
            PhotoLogView(useCamera: mode == .camera, mode: $mode, query: $query, close: { dismiss() })
        case .describe:
            DescribeLogView(mode: $mode, query: $query, close: { dismiss() })
        case .quickAdd:
            QuickAddView(close: { dismiss() })
        }
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

    /// A time picked on the wheel for today, on the day nearest now: 11:30 PM picked just after
    /// midnight is last night, 7 PM picked at noon is this evening.
    static func nearest(_ picked: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        guard picked > now, let yesterday = calendar.date(byAdding: .day, value: -1, to: picked) else { return picked }
        return now.timeIntervalSince(yesterday) < picked.timeIntervalSince(now) ? yesterday : picked
    }

    static func ago(_ minutes: Int) -> String { minutes < 60 ? "\(minutes) min ago" : "\(minutes / 60) h ago" }

    /// The same, short enough for a row of chips.
    static func short(_ minutes: Int) -> String { minutes < 60 ? "\(minutes)m ago" : "\(minutes / 60)h ago" }
}

/// The time choice in the logger's title: now, a recent time, or any time.
struct TimeMenu: View {
    @Environment(AppModel.self) private var model
    @State private var picking = false

    var body: some View {
        Menu {
            if model.selectedDay == model.today {
                Button("Now") { model.loggerTime = nil }
                ForEach(LogTime.recent, id: \.self) { minutes in
                    Button(LogTime.ago(minutes)) { model.loggerTime = Date().addingTimeInterval(-Double(minutes) * 60) }
                }
            }
            Button("Pick a time…", systemImage: "clock") { picking = true }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "clock").font(.subheadline)
                Text(LogTime.label(model)).font(.headline)
                Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
        }
        .accessibilityLabel("Eaten: \(LogTime.label(model))")
        .accessibilityIdentifier("logger.time")
        .sheet(isPresented: $picking) { TimePickerSheet() }
    }
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
            } else {
                Text(Format.day(model.selectedDay, style: .dateTime.weekday(.wide))).font(.subheadline.weight(.medium)).padding(.leading, 8)
                Spacer(minLength: 0)
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
            .accessibilityLabel("Pick a time")
            .accessibilityIdentifier("logger.pickTime")
        }
        .padding(6)
        .floatingGlass(in: Capsule(), interactive: false)
        .sheet(isPresented: $picking) { TimePickerSheet() }
    }

    /// A time picked on the wheel rather than with a chip.
    var custom: String? {
        guard model.loggerTime != nil || model.selectedDay != model.today else { return nil }
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
    }
}

/// Any time of the selected day, on a wheel.
struct TimePickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var time = Date()

    var body: some View {
        NavigationStack {
            DatePicker("Eaten at", selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .navigationTitle(model.selectedDay == model.today ? "Eaten at" : "Eaten \(Format.day(model.selectedDay)) at")
                .navigationBarTitleDisplayMode(.inline)
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
        .presentationDetents([.height(300)])
        .onAppear { time = model.logDate() }
    }
}

/// Search as you type: personal foods first, the last portion pre-filled, + logs in one tap.
struct SearchLogView: View {
    @Environment(AppModel.self) private var model
    @Binding var query: String
    @Binding var mode: LogMode
    @Binding var portion: PortionRequest?
    @State private var results: [FoodMatch] = []
    @State private var searching = false
    @FocusState private var focused: Bool

    var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                Section {
                    ModeShortcuts(mode: $mode)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                if !model.logAgain.isEmpty {
                    Section("Log again") {
                        ForEach(model.logAgain.prefix(12)) { item in
                            RecentRow(item: item, open: { open(item) })
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
            } else if results.isEmpty && !searching {
                ContentUnavailableView {
                    Label("No matches", systemImage: "magnifyingglass")
                } description: {
                    Text("Try fewer words, scan the barcode, or describe it.")
                } actions: {
                    Button("Describe “\(query)”") { mode = .describe }
                    Button("Quick add calories") { mode = .quickAdd }.accessibilityIdentifier("logger.noMatchesQuickAdd")
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(results) { match in
                    FoodRow(
                        food: match.food, personal: model.personalFood(match.food.id), add: { quickAdd(match.food) },
                        open: { open(match.food) })
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search foods")
        // The search is active whenever the logger is (the keyboard stays up for the next food), and
        // by default an active search hides the bar with Done in it.
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .searchFocused($focused)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .safeAreaInset(edge: .bottom) {
            LogTimeBar().padding(.horizontal).padding(.bottom, 8)
        }
        .task(id: query) { await search() }
        .onAppear { if portion == nil { focused = true } }
        .onChange(of: portion) { _, request in if request == nil { focused = true } }
    }

    func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            results = []
            return
        }
        searching = true
        // A short pause so fast typing doesn't queue a search per keystroke.
        try? await Task.sleep(for: .milliseconds(90))
        guard !Task.isCancelled else { return }
        let catalog = model.catalog
        let personal = model.personal
        let found = await Task.detached(priority: .userInitiated) { catalog.search(text, personal: personal, limit: 60) }.value
        guard !Task.isCancelled else { return }
        results = found
        searching = false
    }

    /// The + button: the suggested (or last-used) portion, logged now, and the search cleared
    /// for the next food.
    func quickAdd(_ food: Food) {
        let p = model.personalFood(food.id)
        let suggestion = FoodUnits.suggested(for: food, lastUnitID: p?.lastUnitID, lastCount: p?.lastCount, lastAmount: p?.lastAmount)
        model.log([model.entry(for: food, count: suggestion.count, unit: suggestion.unit, source: .search)])
        query = ""
        focused = true
    }

    func open(_ food: Food) {
        focused = false
        portion = PortionRequest(food: food, source: .search)
    }

    func open(_ item: LogAgainItem) {
        if let id = item.template.foodID, let food = model.food(id: id) {
            open(food)
        } else {
            model.logAgain(item)
        }
    }
}

/// Scan, photo, describe and quick add, from the empty search.
struct ModeShortcuts: View {
    @Environment(AppModel.self) private var model
    @Binding var mode: LogMode

    var body: some View {
        HStack(spacing: 8) {
            chip("Scan", "barcode.viewfinder", .scan)
            if model.ai.canSeePhotos { chip("Photo", "camera", .camera) }
            if model.ai.canDescribe { chip("Describe", "text.bubble", .describe) }
            chip("Quick add", "plus.forwardslash.minus", .quickAdd)
        }
    }

    func chip(_ title: String, _ symbol: String, _ target: LogMode) -> some View {
        Button {
            mode = target
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption.weight(.medium)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(.insetBackground, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("logger.mode.\(target.rawValue)")
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
            .accessibilityIdentifier("logger.food")
            Button(action: add) {
                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(FoodUnits.label(count: suggestion.count, unit: suggestion.unit)) of \(food.name)")
            .accessibilityIdentifier("logger.addFood")
        }
    }
}

/// A recently logged food, re-logged as it was.
struct RecentRow: View {
    @Environment(AppModel.self) private var model
    let item: LogAgainItem
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
            Button {
                model.logAgain(item)
            } label: {
                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Log \(item.template.name) again")
            .accessibilityIdentifier("logger.logAgain")
        }
    }
}

/// How much: a count and a unit, with the numbers updating as they change.
struct PortionView: View {
    @Environment(AppModel.self) private var model
    let request: PortionRequest
    let done: (_ closeLogger: Bool) -> Void
    @State private var count: Double = 1
    @State private var countText = "1"
    @State private var unit: PortionUnit?
    /// The usual amount, which the quick choices are halves and multiples of.
    @State private var base: Double = 1
    @FocusState private var countFocused: Bool

    var body: some View {
        let food = request.food
        let units = FoodUnits.units(for: food)
        let current = unit ?? units.first
        let n = current.map { FoodUnits.nutrients(food, count: count, unit: $0) } ?? .zero
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(food.name).font(.title3.weight(.semibold))
                    if let brand = food.brand, brand.lowercased() != food.name.lowercased() {
                        Text(brand).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(sourceLabel(food)).font(.caption).foregroundStyle(.tertiary)
                    FoodQualityTags(processing: food.processing, fermented: food.fermented ?? Fermented.isFermented(food.name))
                }
            }
            Section("Amount") {
                HStack {
                    TextField("Amount", text: $countText)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .focused($countFocused)
                        .accessibilityIdentifier("portion.amount")
                        .onChange(of: countText) { _, text in
                            // Text this view wrote already says the count; reading it back would round it.
                            guard current.map({ text != FoodUnits.format(count, $0) }) ?? true, let v = Format.parse(text), v > 0 else { return }
                            count = v
                        }
                    Picker(
                        "Unit",
                        selection: Binding(
                            get: { current?.id ?? "" },
                            set: { id in
                                guard let next = units.first(where: { $0.id == id }), let old = current, next.id != old.id else { return }
                                // Keep the amount: 1 cup becomes 240 g, not 1 g, rounded for the new unit.
                                let converted = FoodUnits.convert(count, from: old, to: next)
                                unit = next
                                if converted.isFinite { count = converted }
                                base = count
                                countText = FoodUnits.format(count, next)
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
                        ForEach(quickChoices(current), id: \.self) { value in
                            Button(Self.quickChoiceLabel(value, unit: current)) {
                                count = value
                                countText = FoodUnits.format(value, current)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .tint(abs(count - value) < 0.001 ? .accentColor : .secondary)
                            .accessibilityIdentifier("portion.quick")
                        }
                    }
                }
            }
            Section {
                NutrientSummary(nutrients: n)
                if let current { PortionNutrients(food: food, count: count, unit: current) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                guard let current else { return }
                model.log([model.entry(for: food, count: count, unit: current, source: request.source)])
                done(false)
            } label: {
                Text("Add\(LogTime.label(model) == "Now" ? "" : " at \(LogTime.time(model))") · \(Format.kcal(n.kcal))")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .primaryAction()
            .accessibilityIdentifier("portion.add")
            .padding()
            .disabled(current == nil || count <= 0)
        }
        .navigationTitle("Amount")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.toggleFavorite(food.id)
                } label: {
                    Image(systemName: model.isFavorite(food.id) ? "star.fill" : "star")
                }
                .accessibilityLabel(model.isFavorite(food.id) ? "Remove from favorites" : "Add to favorites")
                .accessibilityIdentifier("portion.favorite")
            }
        }
        .onAppear {
            let p = model.personalFood(food.id)
            let suggestion = FoodUnits.suggested(for: food, lastUnitID: p?.lastUnitID, lastCount: p?.lastCount, lastAmount: p?.lastAmount)
            unit = suggestion.unit
            count = suggestion.count
            base = suggestion.count
            countText = FoodUnits.format(suggestion.count, suggestion.unit)
        }
    }

    func quickChoices(_ unit: PortionUnit) -> [Double] { Self.quickChoices(base: base, unit: unit) }

    /// Half, one, one and a half and two of the usual amount, each rounded the way that unit is
    /// measured (quarters of a cup or a portion, tenths of an ounce or a pound, whole grams),
    /// without repeats.
    static func quickChoices(base: Double, unit: PortionUnit) -> [Double] {
        var seen = Set<Double>()
        return [0.5, 1, 1.5, 2].map { FoodUnits.convert(base * $0, from: unit, to: unit) }.filter { $0.isFinite && seen.insert($0).inserted }
    }

    /// A weight or volume with its unit ("0.5 lb", "150 g"), a count of portions on its own.
    static func quickChoiceLabel(_ value: Double, unit: PortionUnit) -> String {
        unit.kind == .mass || unit.kind == .volume ? FoodUnits.label(count: value, unit: unit) : Format.number(value, digits: 2)
    }

    func sourceLabel(_ food: Food) -> String {
        switch food.source {
        case .usda: "USDA FoodData Central"
        case .off: "Open Food Facts"
        case .custom: "My food"
        case .recipe: "Recipe"
        case .label: "From its label"
        }
    }
}

/// Calories big, macros beside.
struct NutrientSummary: View {
    let nutrients: Nutrients

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading) {
                Text(Format.whole(nutrients.kcal)).font(.title.weight(.bold).monospacedDigit())
                Text("kcal").font(.caption).foregroundStyle(.secondary)
            }
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
