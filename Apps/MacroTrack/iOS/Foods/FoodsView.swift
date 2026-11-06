import FoodDatabase
import NutritionEngine
import SwiftUI
import SystemCore

/// Finding and comparing foods where there's room (iPad, the Mac, Vision Pro): a search over every
/// food into a table, sorted by any column at the portion it would log, with that portion and its
/// nutrients in an inspector. Return logs the selected food (or, straight after typing, the best
/// match once the rows for what was typed arrive), and the search field has the cursor on arrival
/// (⌘F puts it back). Meals lists the saved meals instead, each opened in the inspector.
struct FoodsView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var scope: FoodScope = .all
    /// The saved meals in place of the foods, and the one selected.
    @State private var showingMeals = false
    @State private var mealSelection: SavedMeal.ID?
    /// The search's or the scope's rows in their own order, and as the table sorts them.
    @State private var listings: [FoodListing] = []
    @State private var shown: [FoodListing] = []
    @State private var searching = false
    /// Where what's typed might be heading, in the order to offer them.
    @State private var completions: [String] = []
    @State private var selection: FoodListing.ID?
    /// Which query the rows shown were found for, and a Return waiting for the current one's.
    @State private var searchReturn = FoodSearchReturn()
    @State private var sortOrder = [FoodListingOrder(.relevance)]
    @State private var inspecting = true
    /// The selected food's amount and when it was eaten, as the inspector sets them.
    @State private var amount = PortionAmount()
    @State private var eaten = EatenAt.now
    /// The food `amount` is for.
    @State private var amountFor: String?
    @SceneStorage("foods.columns") private var columns = TableColumnCustomization<FoodListing>()
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if showingMeals {
                    mealList
                } else {
                    VStack(spacing: 8) {
                        SearchCompletionChips(options: completions) { text in
                            query = text
                            searchFocused = true
                        }
                        .padding(.horizontal)
                        table.overlay { empty }
                    }
                }
            }
            .navigationTitle("Foods")
            .searchable(text: $query, prompt: "Search foods")
            .searchFocused($searchFocused)
            .autocorrectionDisabled()
            .noAutocapitalization()
            .onSubmit(of: .search) { returnPressed() }
            .toolbar { toolbar }
            .sideInspector(isPresented: $inspecting, min: 300, ideal: 340, max: 440) { inspector }
        }
        .task(id: SearchKey(query: query, scope: scope, personal: model.personalVersion, meals: showingMeals)) { await search() }
        .onChange(of: sortOrder) { _, order in shown = listings.sorted(using: order) }
        .onChange(of: currentQuery) { _, query in searchReturn.typed(query) }
        .onChange(of: selection) { _, _ in resetAmount() }
        .onAppear { searchFocused = true }
        .onChange(of: model.foodSearchRequest) { _, _ in searchFocused = true }
    }

    // MARK: The table

    var table: some View {
        Table(shown, selection: $selection, sortOrder: $sortOrder, columnCustomization: $columns) {
            TableColumn("Food", sortUsing: FoodListingOrder(.name)) { row in FoodNameCell(listing: row) }
                .width(min: 200, ideal: 300)
                .customizationID("name")
                .disabledCustomizationBehavior(.visibility)
            TableColumn("Portion", sortUsing: FoodListingOrder(.portion, order: .reverse)) { row in
                Text(row.portion).foregroundStyle(.secondary).lineLimit(1).help(row.portion)
            }
            .width(min: 80, ideal: 110)
            .customizationID("portion")
            TableColumn("kcal", sortUsing: FoodListingOrder(.kcal, order: .reverse)) { row in NumberCell(row.nutrients.kcal) }
                .width(min: 50, ideal: 60)
                .customizationID("kcal")
            TableColumn("Protein", sortUsing: FoodListingOrder(.protein, order: .reverse)) { row in
                NumberCell(row.nutrients.protein, unit: "g")
            }
            .width(min: 56, ideal: 64)
            .customizationID("protein")
            TableColumn("Carbs", sortUsing: FoodListingOrder(.carbs, order: .reverse)) { row in NumberCell(row.nutrients.carbs, unit: "g") }
                .width(min: 50, ideal: 60)
                .customizationID("carbs")
            TableColumn("Fat", sortUsing: FoodListingOrder(.fat, order: .reverse)) { row in NumberCell(row.nutrients.fat, unit: "g") }
                .width(min: 46, ideal: 56)
                .customizationID("fat")
            TableColumn("Fiber", sortUsing: FoodListingOrder(.fiber, order: .reverse)) { row in NumberCell(row.nutrients.fiber, unit: "g") }
                .width(min: 46, ideal: 56)
                .customizationID("fiber")
            Group {
                TableColumn("Sugar", sortUsing: FoodListingOrder(.sugar, order: .reverse)) { row in NumberCell(row.nutrients.sugar, unit: "g") }
                    .width(min: 46, ideal: 56)
                    .customizationID("sugar")
                    .defaultVisibility(.hidden)
                TableColumn("Sodium", sortUsing: FoodListingOrder(.sodium, order: .reverse)) { row in
                    NumberCell(row.nutrients.sodium, unit: "mg")
                }
                .width(min: 56, ideal: 70)
                .customizationID("sodium")
                .defaultVisibility(.hidden)
                TableColumn("Processing", sortUsing: FoodListingOrder(.processing)) { row in
                    Text(row.food.processing?.tag ?? "—").foregroundStyle(row.food.processing?.color ?? .secondary).lineLimit(1)
                }
                .width(min: 80, ideal: 110)
                .customizationID("processing")
                .defaultVisibility(.hidden)
                TableColumn("Source", sortUsing: FoodListingOrder(.source)) { row in
                    Text(row.sourceLabel).foregroundStyle(.secondary).lineLimit(1)
                }
                .width(min: 70, ideal: 110)
                .customizationID("source")
                .defaultVisibility(.hidden)
            }
        }
        #if os(macOS)
        // A double-click, or Return, logs it.
        .contextMenu(forSelectionType: FoodListing.ID.self) { ids in
            rowMenu(ids)
        } primaryAction: { ids in
            guard let id = ids.first, let row = shown.first(where: { $0.id == id }) else { return }
            if id == selection { logSelected() } else { quickLog(row) }
        }
        #else
        // A tap selects (a primary action would take the tap instead), and a keyboard's Return logs.
        .contextMenu(forSelectionType: FoodListing.ID.self) { ids in rowMenu(ids) }
        .onKeyPress(.return) {
            guard selection != nil else { return .ignored }
            logSelected()
            return .handled
        }
        #endif
        .accessibilityIdentifier("foods.table")
    }

    @ViewBuilder
    func rowMenu(_ ids: Set<FoodListing.ID>) -> some View {
        if let id = ids.first, let row = shown.first(where: { $0.id == id }) {
            Button("Log \(row.portion)", systemImage: "plus.circle") { quickLog(row) }
            Button(model.isFavorite(id) ? "Remove from Favorites" : "Add to Favorites", systemImage: model.isFavorite(id) ? "star.slash" : "star") {
                model.toggleFavorite(id)
            }
        }
    }

    // MARK: Meals

    /// The saved meals, best for now first, or those matching the search.
    var meals: [SavedMeal] {
        let all = model.mealSuggestions.map(\.meal)
        let text = query.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? all : SavedMeals.matching(text, in: all)
    }

    var mealList: some View {
        let meals = meals
        return List(selection: $mealSelection) {
            ForEach(meals) { meal in
                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.name).lineLimit(1)
                    Text(SavedMealRow.detail(meal)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .tag(meal.id)
                .accessibilityIdentifier("foods.meal")
            }
        }
        #if os(macOS)
        // A double-click logs it, as in the table.
        .contextMenu(forSelectionType: SavedMeal.ID.self) { ids in
            mealMenu(ids)
        } primaryAction: { ids in
            if let id = ids.first, let meal = model.savedMeal(id) { model.log(meal, at: eaten.date(model)) }
        }
        #else
        // A tap selects, to open the meal beside the list.
        .contextMenu(forSelectionType: SavedMeal.ID.self) { ids in mealMenu(ids) }
        #endif
        .overlay {
            if meals.isEmpty {
                if model.savedMeals.isEmpty {
                    ContentUnavailableView(
                        "No meals yet", systemImage: "fork.knife",
                        description: Text(
                            """
                            Foods eaten together can be saved as a meal from the menu on an hour's name in Log, \
                            or from the meal under the logger's search.
                            """))
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .onChange(of: mealSelection) { _, _ in eaten = .now }
        .accessibilityIdentifier("foods.meals")
    }

    @ViewBuilder
    func mealMenu(_ ids: Set<SavedMeal.ID>) -> some View {
        if let id = ids.first, let meal = model.savedMeal(id) {
            Button("Log \(meal.name)", systemImage: "plus.circle") { model.log(meal, at: eaten.date(model)) }
            Button("Delete Meal", systemImage: "trash", role: .destructive) { model.delete(meal: meal) }
        }
    }

    @ViewBuilder
    var empty: some View {
        if shown.isEmpty && !searching {
            let typed = !query.trimmingCharacters(in: .whitespaces).isEmpty
            if typed {
                ContentUnavailableView {
                    Label("No matches", systemImage: "magnifyingglass")
                } description: {
                    Text(scope == .all ? "Try fewer words, type the barcode, or describe it." : "Nothing in \(scope.label) matches. Try All.")
                } actions: {
                    if scope != .all { Button("Search all foods") { scope = .all } }
                    Button("Describe “\(query)”") { model.openLogger(.describe) }
                    Button("Quick add calories") { model.openLogger(.quickAdd) }
                }
            } else {
                ContentUnavailableView(emptyTitle, systemImage: "carrot", description: Text(emptyDetail))
            }
        }
    }

    var emptyTitle: String {
        switch scope {
        case .all, .recent: "Search for a food"
        case .favorites: "No favorites yet"
        case .mine: "No foods of your own yet"
        }
    }

    var emptyDetail: String {
        switch scope {
        case .all, .recent: "Over 3 million foods, offline. The ones you eat come first, at the portion you usually have."
        case .favorites: "Star a food in its details and it's kept here."
        case .mine: "A label read from a photo is kept as your own food, with its barcode."
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Show", selection: showChoice) {
                ForEach(FoodScope.allCases) { Text($0.label).tag($0.rawValue) }
                Text("Meals").tag(Self.mealsChoice)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .accessibilityIdentifier("foods.scope")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                columnToggle("Sugar", "sugar")
                columnToggle("Sodium", "sodium")
                columnToggle("Processing", "processing")
                columnToggle("Source", "source")
            } label: {
                Label("Columns", systemImage: "tablecells")
            }
            .help("Show or hide columns")
            .accessibilityIdentifier("foods.columns")
            Button {
                inspecting.toggle()
            } label: {
                Label(inspecting ? "Hide Details" : "Show Details", systemImage: "sidebar.trailing")
            }
            .help(inspecting ? "Hide the food's details" : "Show the food's details")
            .accessibilityIdentifier("foods.inspector")
        }
    }

    static let mealsChoice = "meals"

    /// The picker's choice: a scope of foods, or the saved meals.
    var showChoice: Binding<String> {
        Binding(
            get: { showingMeals ? Self.mealsChoice : scope.rawValue },
            set: { choice in
                showingMeals = choice == Self.mealsChoice
                if let picked = FoodScope(rawValue: choice) { scope = picked }
            })
    }

    func columnToggle(_ title: String, _ id: String) -> some View {
        Toggle(title, isOn: Binding(get: { columns[visibility: id] == .visible }, set: { columns[visibility: id] = $0 ? .visible : .hidden }))
    }

    // MARK: Inspector

    @ViewBuilder
    var inspector: some View {
        if showingMeals {
            if let id = mealSelection, model.savedMeal(id) != nil {
                // Its own stack, so changing a food's amount pushes there rather than over the list.
                NavigationStack { SavedMealView(mealID: id, eaten: $eaten) }.id(id)
            } else {
                ContentUnavailableView("No meal selected", systemImage: "fork.knife", description: Text("Select a meal to see its foods and log it."))
            }
        } else if let row = selected {
            FoodInspector(listing: row, amount: $amount, eaten: $eaten, log: logSelected)
        } else {
            ContentUnavailableView("No food selected", systemImage: "carrot", description: Text("Select a food to see its portion and nutrients."))
        }
    }

    var selected: FoodListing? { selection.flatMap { id in shown.first { $0.id == id } } }

    var currentQuery: FoodSearchReturn.Query { FoodSearchReturn.Query(text: query.trimmingCharacters(in: .whitespaces), scope: scope) }

    // MARK: Actions

    func search() async {
        // Among the meals, the foods wait: rows arriving would move the selection and reset the
        // time picked for the meal. Back on the foods, the search runs again.
        guard !showingMeals else { return }
        let asked = currentQuery
        let text = asked.text
        let scope = asked.scope
        searching = true
        // A short pause so fast typing doesn't queue a search per keystroke.
        if !text.isEmpty {
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
        }
        let catalog = model.catalog
        let personal = model.personal
        let custom = model.customFoods.map(\.food)
        let corrections = model.corrections
        let found = await Task.detached(priority: .userInitiated) {
            if scope == .all, !text.isEmpty {
                let matches = AppModel.corrected(catalog.search(text, personal: personal, limit: 100), by: corrections)
                return (FoodBrowser.listings(matches, personal: personal, custom: custom), AppModel.completions(for: text, in: matches))
            }
            return (FoodBrowser.listings(scope, query: text, personal: personal, custom: custom), [String]())
        }.value
        guard !Task.isCancelled else { return }
        listings = found.0
        shown = listings.sorted(using: sortOrder)
        let options = found.1
        completions = options
        searching = false
        // The best match is ready for Return, and a Return pressed while these were on their way logs it.
        let next = searchReturn.arrived(asked, rows: shown.map(\.id), selection: selection)
        selection = next.selection
        resetAmount()
        if next.log {
            logSelected()
            return
        }
        // Cancelled by the next key, so the model is only asked once the typing stops.
        if let ranked = await model.rankedCompletions(options, for: text), !Task.isCancelled { completions = ranked }
    }

    /// The selected food's usual portion, eaten now, each time the selection moves to another food.
    func resetAmount() {
        guard let row = selected, row.id != amountFor else { return }
        amount = PortionAmount(count: row.count, unit: row.unit)
        eaten = .now
        amountFor = row.id
    }

    /// Return in the search field: log the selected food, or pick the first match to log next. Rows
    /// still from an earlier query aren't what was typed, so then it waits for the new ones. Among
    /// the meals, the same, at once: they're the person's own, found as they type.
    func returnPressed() {
        if showingMeals {
            if let id = mealSelection, let meal = meals.first(where: { $0.id == id }) {
                model.log(meal, at: eaten.date(model))
            } else {
                mealSelection = meals.first?.id
            }
            return
        }
        switch searchReturn.pressed(currentQuery, hasSelection: selected != nil) {
        case .log: logSelected()
        case .select: selection = shown.first?.id
        case .wait: break
        }
    }

    func logSelected() {
        guard let row = selected, let unit = amount.unit(for: row.food), amount.count > 0 else { return }
        model.log([model.entry(for: row.food, count: amount.count, unit: unit, source: .search, date: eaten.date(model))])
    }

    /// A food that isn't selected, at its usual portion, now.
    func quickLog(_ row: FoodListing) {
        model.log([model.entry(for: row.food, count: row.count, unit: row.unit, source: .search)])
    }

    struct SearchKey: Hashable {
        var query: String
        var scope: FoodScope
        var personal: Int
        var meals: Bool
    }
}

/// When the food was eaten: now, a little while ago, or at a time of the day being logged.
enum EatenAt: Hashable {
    case now
    case minutesAgo(Int)
    case at(Date)

    @MainActor
    func date(_ model: AppModel) -> Date {
        switch self {
        case .now: return model.logDate()
        case .minutesAgo(let minutes): return model.logDate().addingTimeInterval(-Double(minutes) * 60)
        case .at(let time):
            let picked = model.onSelectedDay(time)
            return model.selectedDay == model.today ? LogTime.nearest(picked) : picked
        }
    }
}

/// A food's name and brand, starred when it's a favourite.
struct FoodNameCell: View {
    let listing: FoodListing

    var body: some View {
        HStack(spacing: 6) {
            FoodTile(name: listing.food.name, size: TileSize.table).padding(.trailing, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(listing.food.name).lineLimit(1)
                if let brand = listing.food.brand, brand.lowercased() != listing.food.name.lowercased() {
                    Text(brand).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if listing.favorite {
                Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow).accessibilityLabel("Favorite")
            }
        }
        .help(listing.food.title)
    }
}

/// A number right-aligned in its column: "12 g", or a dash when the food doesn't list it.
struct NumberCell: View {
    let value: Double?
    var unit: String?
    var color: Color?

    init(_ value: Double?, unit: String? = nil, color: Color? = nil) {
        self.value = value
        self.unit = unit
        self.color = color
    }

    var body: some View {
        Text(value.map { "\(Format.whole($0))\(unit.map { " \($0)" } ?? "")" } ?? "—")
            .monospacedDigit()
            .foregroundStyle(value == nil ? AnyShapeStyle(.tertiary) : color.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// The selected food: its amount, every nutrient for that amount, when it was eaten and Log. The
/// pencil corrects its numbers to its package's.
struct FoodInspector: View {
    @Environment(AppModel.self) private var model
    let listing: FoodListing
    @Binding var amount: PortionAmount
    @Binding var eaten: EatenAt
    let log: () -> Void
    @State private var editing = false

    var body: some View {
        let food = listing.food
        let unit = amount.unit(for: food)
        let n = amount.nutrients(food)
        Form {
            Section {
                HStack(alignment: .top) {
                    FoodHeader(food: food, corrected: model.isCorrected(food.id))
                    Spacer(minLength: 8)
                    if unit != nil { EditFoodButton { editing = true }.buttonStyle(.borderless).font(.title3) }
                    FavoriteButton(foodID: food.id).buttonStyle(.borderless).font(.title3)
                }
            }
            Section("Amount") {
                AmountFields(food: food, amount: $amount)
            }
            Section {
                NutrientSummary(nutrients: n)
            }
            Section("Eaten") {
                EatenPicker(eaten: $eaten)
            }
            Section("Nutrients") {
                if let unit { PortionNutrients(food: food, count: amount.count, unit: unit, open: true) }
            }
        }
        .formStyle(.grouped)
        // The search runs again once it's saved (the personal foods change) and lists the food as
        // corrected, at the same amount.
        .sheet(isPresented: $editing) {
            if let unit { FoodEditor(food: food, count: amount.count, unit: unit) { amount.use($0) } }
        }
        .notesWork(editing)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                // The meal this food joins, with what's gone into it so far.
                MealTray(date: eaten.date(model))
                Button(action: log) {
                    Text("Log\(eatenLabel) · \(Format.kcal(n.kcal))").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .primaryAction()
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(unit == nil || amount.count <= 0)
                .help("Log it (⌘Return, or Return in the list)")
                .accessibilityIdentifier("foods.log")
            }
            .padding()
        }
    }

    /// " at 7:30 AM", " on Sat 7:30 AM", or nothing for now today.
    var eatenLabel: String {
        if case .now = eaten, model.selectedDay == model.today { return "" }
        let date = eaten.date(model)
        let day = Day(date) == model.today ? "" : "\(Format.day(Day(date), style: .dateTime.weekday(.abbreviated))) "
        return " at \(day)\(Format.time(date))"
    }
}

/// Now, 30 minutes, an hour or two ago, or a time of the day being logged.
struct EatenPicker: View {
    @Environment(AppModel.self) private var model
    @Binding var eaten: EatenAt
    @State private var time = Date()

    var body: some View {
        Picker("When", selection: choice) {
            Text("Now").tag(0)
            ForEach(LogTime.recent, id: \.self) { Text(LogTime.ago($0)).tag($0) }
            Text("At a time").tag(-1)
        }
        .accessibilityIdentifier("foods.eaten")
        if case .at = eaten {
            DatePicker("At", selection: $time, displayedComponents: .hourAndMinute)
                .onChange(of: time) { _, time in eaten = .at(time) }
        }
        if model.selectedDay != model.today {
            Label("Logs to \(Format.day(model.selectedDay, style: .dateTime.weekday(.wide).month().day()))", systemImage: "clock.arrow.circlepath")
                .font(.footnote).foregroundStyle(.secondary)
            Button("Log to today instead") { model.selectedDay = model.today }.font(.footnote)
        }
    }

    var choice: Binding<Int> {
        Binding(
            get: {
                switch eaten {
                case .now: 0
                case .minutesAgo(let minutes): minutes
                case .at: -1
                }
            },
            set: { value in
                switch value {
                case 0: eaten = .now
                case -1:
                    time = model.logDate()
                    eaten = .at(time)
                default: eaten = .minutesAgo(value)
                }
            })
    }
}
