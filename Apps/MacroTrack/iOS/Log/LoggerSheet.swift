import SwiftUI
import FoodDatabase
import NutritionEngine
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
                    if mode != .search { ToolbarItem(placement: .principal) { MealMenu() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
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

/// Which meal new entries land in; guessed from the time until changed.
struct MealMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let current = model.logSlot().meal
        Menu {
            ForEach(MealSlot.allCases) { slot in
                Button {
                    model.loggerMeal = slot
                } label: {
                    if slot == current { Label(slot.label, systemImage: "checkmark") } else { Text(slot.label) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(current.label).font(.headline)
                if model.selectedDay != model.today {
                    Text(Format.day(model.selectedDay, style: .dateTime.weekday(.abbreviated))).font(.subheadline).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
        }
        .accessibilityLabel("Meal: \(current.label)")
    }
}

/// Which meal the logger adds to, as one row of choices at the bottom.
struct MealPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Picker("Meal", selection: Binding(get: { model.logSlot().meal }, set: { model.loggerMeal = $0 })) {
            ForEach(MealSlot.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(6)
        .floatingGlass(in: Capsule(), interactive: false)
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
                    Button("Quick add calories") { mode = .quickAdd }
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(results) { match in
                    FoodRow(food: match.food, personal: model.personalFood(match.food.id), add: { quickAdd(match.food) },
                            open: { open(match.food) })
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search foods")
        .searchFocused($focused)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .safeAreaInset(edge: .bottom) {
            MealPicker().padding(.horizontal).padding(.bottom, 8)
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
        let catalog = model.catalog, personal = model.personal
        let found = await Task.detached(priority: .userInitiated) { catalog.search(text, personal: personal, limit: 60) }.value
        guard !Task.isCancelled else { return }
        results = found
        searching = false
    }

    /// The + button: the suggested (or last-used) portion, logged now, and the search cleared
    /// for the next food.
    func quickAdd(_ food: Food) {
        let p = model.personalFood(food.id)
        let suggestion = FoodUnits.suggested(for: food, lastUnitID: p?.lastUnitID, lastCount: p?.lastCount)
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
    }
}

/// A catalog food: name, the portion it would log, and a one-tap add.
struct FoodRow: View {
    let food: Food
    let personal: PersonalFood?
    let add: () -> Void
    let open: () -> Void

    var body: some View {
        let suggestion = FoodUnits.suggested(for: food, lastUnitID: personal?.lastUnitID, lastCount: personal?.lastCount)
        let n = FoodUnits.nutrients(food, count: suggestion.count, unit: suggestion.unit)
        HStack(spacing: 12) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(food.name).lineLimit(2)
                        if personal?.favorite == true { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                    }
                    Text([food.brand.flatMap { $0.lowercased() == food.name.lowercased() ? nil : $0 },
                          FoodUnits.label(count: suggestion.count, unit: suggestion.unit),
                          "\(Format.whole(n.kcal)) kcal", "\(Format.grams(n.protein)) P"].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Button(action: add) {
                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(FoodUnits.label(count: suggestion.count, unit: suggestion.unit)) of \(food.name)")
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
                    Text([item.template.brand, item.template.amountLabel, "\(Format.whole(item.template.nutrients.kcal)) kcal"]
                        .compactMap { $0 }.joined(separator: " · "))
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
                }
            }
            Section("Amount") {
                HStack {
                    TextField("Amount", text: $countText)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .focused($countFocused)
                        .onChange(of: countText) { _, text in if let v = FoodUnits.parseCount(text), v > 0 { count = v } }
                    Picker("Unit", selection: Binding(get: { current?.id ?? "" }, set: { id in
                        guard let next = units.first(where: { $0.id == id }), let old = current, next.id != old.id else { return }
                        // Keep the amount: 1 cup becomes 240 g, not 1 g.
                        let amount = FoodUnits.amount(count, old)
                        unit = next
                        count = next.amount > 0 ? quick(amount / next.amount, next) : count
                        base = count
                        countText = Format.number(count, digits: 2)
                    })) {
                        ForEach(units) { Text($0.label).tag($0.id) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                if let current {
                    HStack(spacing: 8) {
                        ForEach([0.5, 1, 1.5, 2], id: \.self) { multiple in
                            let value = quick(base * multiple, current)
                            Button(current.kind == .mass || current.kind == .volume ? FoodUnits.label(count: value, unit: current) : Format.number(value, digits: 2)) {
                                count = value
                                countText = Format.number(value, digits: 2)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .tint(abs(count - value) < 0.001 ? .accentColor : .secondary)
                        }
                    }
                }
            }
            Section {
                NutrientSummary(nutrients: n)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                guard let current else { return }
                model.log([model.entry(for: food, count: count, unit: current, source: request.source)])
                done(false)
            } label: {
                Text("Add to \(model.logSlot().meal.label) · \(Format.kcal(n.kcal))").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .primaryAction()
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
            }
        }
        .onAppear {
            let p = model.personalFood(food.id)
            let suggestion = FoodUnits.suggested(for: food, lastUnitID: p?.lastUnitID, lastCount: p?.lastCount)
            unit = suggestion.unit
            count = suggestion.count
            base = suggestion.count
            countText = Format.number(suggestion.count, digits: 2)
        }
    }

    /// Rounded to what people measure: whole grams and millilitres, quarters of a portion.
    func quick(_ value: Double, _ unit: PortionUnit) -> Double {
        switch unit.kind {
        case .mass, .volume: max(1, (value * unit.amount).rounded() / max(unit.amount, 0.0001))
        default: max(0.25, (value * 4).rounded() / 4)
        }
    }

    func sourceLabel(_ food: Food) -> String {
        switch food.source {
        case .usda: "USDA FoodData Central"
        case .off: "Open Food Facts"
        case .custom: "My food"
        case .recipe: "Recipe"
        case .label: "From a label photo"
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
