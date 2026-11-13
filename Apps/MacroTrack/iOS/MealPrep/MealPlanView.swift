import MealPlanner
import NutritionEngine
import SwiftUI
import SystemCore

extension Format {
    /// What to buy: "1.4 kg", "450 g", "1.5 L"; pounds, ounces and cups for imperial.
    static func shopping(_ grams: Double, liquid: Bool, unit: WeightUnit) -> String {
        if liquid {
            if unit == .lb { return "\(number((grams / 240 * 2).rounded() / 2)) cups" }
            return grams >= 1000 ? "\(number(grams / 1000)) L" : "\(Int(grams)) ml"
        }
        if unit == .lb {
            let ounces = grams / 28.35
            return ounces >= 16 ? "\(number(ounces / 16)) lb" : "\(Int(ounces.rounded())) oz"
        }
        return grams >= 1000 ? "\(number(grams / 1000)) kg" : "\(Int(grams)) g"
    }

    /// A container's amount: grams, with ounces for imperial.
    static func portion(_ grams: Double, unit: WeightUnit) -> String {
        unit == .lb && grams >= 30 ? "\(Int(grams)) g (\(number(grams / 28.35)) oz)" : "\(Int(grams)) g"
    }

    /// "1 h 55 min".
    static func duration(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h\(minutes % 60 == 0 ? "" : " \(minutes % 60) min")"
    }

    /// "today", "tomorrow", or "Sunday".
    static func prepDay(_ day: Day, today: Day) -> String {
        switch today.days(until: day) {
        case 0: "today"
        case 1: "tomorrow"
        case 2..<7: Self.day(day, style: .dateTime.weekday(.wide))
        default: Self.day(day)
        }
    }

    /// "0:15" from the start.
    static func clock(_ minute: Int) -> String { String(format: "%d:%02d", minute / 60, minute % 60) }

    /// "Mon–Wed" for days in a row, else "Mon, Wed".
    static func span(_ days: [Day]) -> String {
        let sorted = Array(Set(days)).sorted()
        guard let first = sorted.first, let last = sorted.last else { return "" }
        if first == last { return first.weekday.short }
        if first.days(until: last) == sorted.count - 1 { return "\(first.weekday.short)–\(last.weekday.short)" }
        return sorted.map(\.weekday.short).joined(separator: ", ")
    }
}

extension MealSlot {
    var symbol: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .snack: "carrot"
        case .dinner: "moon.stars"
        }
    }
}

/// A week's meal plan: the dishes and days, the grocery list, and prep day.
struct MealPlanView: View {
    enum Page: String, CaseIterable, Identifiable {
        case week = "Week", groceries = "Groceries", prep = "Prep"
        var id: String { rawValue }

        /// The page's title on a phone.
        var title: String {
            switch self {
            case .week: "Meal plan"
            case .groceries: "Grocery list"
            case .prep: "Prep day"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The plan shown: the one opened, or the one made from here with "New plan…".
    @State private var planID: UUID
    /// What a phone shows: the week, or the grocery list or prep day opened from it.
    let page: Page
    @State private var showsPrep = false
    @State private var request = ""
    @State private var working = false
    @State private var changed: String?
    @State private var showSetup = false
    @State private var confirmDelete = false

    init(planID: UUID, page: Page = .week) {
        _planID = State(initialValue: planID)
        self.page = page
    }

    var body: some View {
        if let plan = model.mealPlans.first(where: { $0.id == planID }) {
            Group {
                // With room, the week, the groceries and prep day side by side; on a phone, one at a time.
                if sizeClass == .compact {
                    pages(plan)
                } else {
                    MealPlanBoard(plan: plan, request: requestField(plan)) {
                        // With room, the page's own header: counter mode a button away wherever the
                        // prep list has scrolled to (words, not a symbol: nothing says "counter mode"
                        // at a glance), and the plan's options.
                        WideHeader(eyebrow: "Week of \(Format.day(plan.start, style: .dateTime.month(.abbreviated).day()))", title: "Meal plan") {
                            Button(model.prepRun?.planID == plan.id ? "Back to Prep" : "Start Prep") { model.startPrep(plan) }
                                .buttonStyle(.solid)
                                .fixedSize()
                                .accessibilityIdentifier("mealPlan.counter")
                            options(plan) { CircleIcon(symbol: "ellipsis") }
                                .circleMenuStyle()
                        }
                        .padding(.horizontal, -16)
                    }
                }
            }
            .navigationTitle(sizeClass == .compact ? page.title : "Meal plan")
            .inlineTitle()
            .widePage(sizeClass != .compact)
            .hidesNavigationBar(sizeClass != .compact)
            // A phone's plan is a page of its own, as its design has it: neither the tab bar nor the
            // composer, and Start prep at the foot.
            .pushedPage(sizeClass == .compact)
            .hidesTabBar(sizeClass == .compact)
            .toolbar {
                if sizeClass == .compact {
                    ToolbarItem(placement: .barTrailing) {
                        options(plan) { Image(systemName: "ellipsis") }
                    }
                }
            }
            .sheet(isPresented: $showSetup) { MealPlanSetup { planID = $0.id }.macSheetSize(width: 560, height: 680) }
            .confirmationDialog("Delete this week's plan?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete plan", role: .destructive) {
                    model.deleteMealPlan(plan)
                    dismiss()
                }
            } message: {
                Text("Meals already logged from it stay in your log.")
            }
        } else {
            ContentUnavailableView(
                "No meal plan", systemImage: "takeoutbag.and.cup.and.straw",
                description: Text("Plan a week from the Plan tab."))
        }
    }

    /// Other dishes, a new plan, the grocery list to share, and deleting the plan.
    func options(_ plan: MealPlan, @ViewBuilder label: () -> some View) -> some View {
        Menu {
            Button("Other dishes", systemImage: "shuffle") { model.shuffleMealPlan(plan) }
                .disabled(model.swappableRecipes(in: plan).isEmpty)
            Button("New plan…", systemImage: "square.and.pencil") { showSetup = true }
            ShareLink(item: GroceryPage.text(plan, unit: model.units.weight)) {
                Label("Share grocery list", systemImage: "square.and.arrow.up")
            }
            Button("Delete plan", systemImage: "trash", role: .destructive) { confirmDelete = true }
        } label: {
            label()
        }
        .accessibilityLabel("Plan options")
        .accessibilityIdentifier("mealPlan.options")
        // While a request is being read, so the plan it's for can't be deleted or replaced under it.
        .disabled(working)
    }

    /// The week as cards on the ink ground, ending on Start prep, which opens prep day's steps; the
    /// grocery list and prep day are rows that open their own pages.
    func pages(_ plan: MealPlan) -> some View {
        List {
            Group {
                switch page {
                case .week: week(plan)
                case .groceries: GroceryPage(plan: plan, headed: true)
                case .prep: PrepPage(plan: plan, headed: true)
                }
            }
            .listRowBackground(Color.cardBackground)
        }
        .insetGroupedList()
        .sectionSpacing(12)
        .accessibilityIdentifier("mealPlan.page")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if page == .week {
                Button {
                    showsPrep = true
                } label: {
                    Text("Start prep").frame(maxWidth: .infinity)
                }
                .buttonStyle(.solid)
                .controlSize(.large)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(Ink.ground.ignoresSafeArea(edges: .bottom))
                .accessibilityIdentifier("mealPlan.startPrep")
            }
        }
        .navigationDestination(isPresented: $showsPrep) { MealPlanView(planID: plan.id, page: .prep) }
    }

    /// "No fish, more spicy": read by Apple's model and applied to the dishes still to come.
    @ViewBuilder
    func requestField(_ plan: MealPlan) -> some View {
        HStack(spacing: 8) {
            TextField("Change something: no fish, more spicy, cheaper…", text: $request)
                .submitLabel(.go)
                .onSubmit { change(plan) }
                .disabled(working)
                .accessibilityIdentifier("mealPlan.request")
            if working {
                ProgressView()
            } else if !request.isEmpty {
                Button("Change") { change(plan) }.buttonStyle(.borderless).fontWeight(.semibold)
                    .accessibilityIdentifier("mealPlan.change")
            }
        }
        if let changed {
            Label(changed, systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    func week(_ plan: MealPlan) -> some View {
        let guide = PrepGuide.make(for: plan)
        let groceries = Groceries.list(for: plan).filter { !$0.pantry }.count
        let prep = Format.prepDay(plan.prepDay, today: model.today)
        Section {
            WeekHeader(plan: plan, containers: guide.containers)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
        }

        Section {
            let swappable = Set(model.swappableRecipes(in: plan))
            ForEach(plan.recipes) { recipe in
                DishRow(recipe: recipe, swap: swappable.contains(recipe.id) ? { model.swap(recipe.id, in: plan) } : nil)
            }
        }

        Section {
            pageRow(
                "Grocery list", symbol: "cart", detail: groceries == 1 ? "1 item" : "\(groceries) items", page: .groceries, plan: plan,
                identifier: "mealPlan.groceryList")
            pageRow(
                "Prep day", symbol: "clock",
                detail: "\(prep.prefix(1).uppercased() + prep.dropFirst()) · \(Format.duration(guide.minutes))", page: .prep, plan: plan,
                identifier: "mealPlan.prepDay")
        }

        Section {
            requestField(plan)
        } footer: {
            Text("Swap any dish above with one tap, or say what you'd like in your own words.").foregroundStyle(Ink.text3)
        }

        Section {
            ForEach(plan.days, id: \.self) { day in
                VStack(alignment: .leading, spacing: 4) {
                    Text(Format.day(day)).font(.subheadline.weight(.semibold)).foregroundStyle(day == model.today ? Color.accentColor : Ink.text)
                    ForEach(plan.meals(on: day)) { meal in
                        HStack(spacing: 6) {
                            Image(systemName: meal.slot.symbol).foregroundStyle(Ink.text3).frame(width: 18)
                            Text(plan.recipe(meal.recipeID)?.title ?? "").font(.caption).foregroundStyle(Ink.text2).lineLimit(1)
                            Spacer(minLength: 4)
                            if meal.storage == .freezer {
                                Image(systemName: "snowflake").font(.caption2).foregroundStyle(Ink.carbs).accessibilityLabel("Frozen")
                            }
                            if model.isLogged(meal, in: plan) {
                                Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(Ink.good).accessibilityLabel("Logged")
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Days").eyebrow()
        }
    }

    /// A row that opens another page: the grocery list, prep day.
    func pageRow(_ title: String, symbol: String, detail: String, page: Page, plan: MealPlan, identifier: String) -> some View {
        NavigationLink {
            MealPlanView(planID: plan.id, page: page)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.body.weight(.light)).foregroundStyle(Ink.text2).frame(width: 22)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
                Spacer(minLength: 8)
                Text(detail).font(.subheadline).foregroundStyle(Ink.text2).lineLimit(1)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .accessibilityIdentifier(identifier)
    }

    func change(_ plan: MealPlan) {
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        working = true
        Task {
            let summary = await model.applyRequest(text, to: plan)
            working = false
            if let summary {
                changed = summary
                request = ""
            } else {
                changed = "Nothing in that matched the plan's foods. Try naming a food or a flavour."
            }
        }
    }
}

/// The week at a glance, over the dishes: when, how many dishes and containers, what they cover
/// and what they're sized to, and the meals left to the person.
private struct WeekHeader: View {
    let plan: MealPlan
    let containers: Int

    var body: some View {
        let day = plan.planned(on: plan.start)
        let slots = Set(plan.meals.map(\.slot)).sorted().map(\.label)
        let range =
            "\(Format.day(plan.start, style: .dateTime.month(.abbreviated).day())) – \(Format.day(plan.end, style: .dateTime.month(.abbreviated).day()))"
        VStack(alignment: .leading, spacing: 6) {
            // Tracked capitals start a point left of the text's frame, which the List cell clips.
            Text("\(when) · \(range)").eyebrow(Color.accentColor).padding(.leading, 2)
            PageTitle(
                "\(plan.recipes.count) \(plan.recipes.count == 1 ? "dish" : "dishes")\n\(containers) \(containers == 1 ? "container" : "containers")"
            )
            Text(
                "\(Self.list(slots)), \(Format.span(plan.days)). Sized to \(Format.kcal(plan.targets.kcal)) and \(Format.grams(plan.targets.protein)) protein a day; \(Format.kcal(day.kcal)) and \(Format.grams(day.protein)) of it planned."
            )
            .font(.subheadline).foregroundStyle(Ink.text2).fixedSize(horizontal: false, vertical: true)
            ForEach(plan.unplanned(on: plan.start), id: \.slot) { open in
                Label(
                    "\(open.slot.label) is yours: about \(Format.kcal(open.room.kcal)), \(Format.grams(open.room.protein)) protein",
                    systemImage: open.slot.symbol
                )
                .font(.caption).foregroundStyle(Ink.text3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mealPlan.summary")
    }

    @Environment(AppModel.self) private var model

    /// Whether it's this week's.
    var when: String {
        if plan.days.contains(model.today) { return "This week" }
        return plan.start > model.today ? "Next week" : "Meal prep"
    }

    /// "Lunch and dinner", "Breakfast, lunch and dinner".
    static func list(_ labels: [String]) -> String {
        guard let last = labels.last else { return "" }
        let words = labels.enumerated().map { $0.offset == 0 ? $0.element : $0.element.lowercased() }
        return labels.count == 1 ? last : "\(words.dropLast().joined(separator: ", ")) and \(words[words.count - 1])"
    }
}

/// A dish on the phone's week: how many containers of it, big; its calories and protein a portion;
/// and Swap while it's still to come. What's in each container is on prep day's page.
private struct DishRow: View {
    let recipe: PlannedRecipe
    let swap: (() -> Void)?

    var body: some View {
        let n = recipe.nutrients
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(recipe.servings)").numeral(30, weight: .heavy).foregroundStyle(Ink.text)
                Text("×").font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text2)
            }
            .frame(width: 44, alignment: .leading)
            .accessibilityLabel("\(recipe.servings) containers")
            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.title).font(.callout.weight(.semibold)).foregroundStyle(Ink.text).fixedSize(horizontal: false, vertical: true)
                Text(
                    "\(Format.kcal(n.kcal)) · \(Text("\(Format.whole(n.protein)) P").foregroundStyle(Ink.protein)) a portion\(recipe.madeOnTheDay ? " · made on the day" : "")"
                )
                .font(.caption.monospacedDigit()).foregroundStyle(Ink.text3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let swap {
                Button(action: swap) {
                    Text("Swap").font(.footnote.weight(.semibold)).foregroundStyle(Ink.text)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Ink.raised, in: .rect(cornerRadius: 14, style: .continuous))
                        .contentShape(.rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Swap \(recipe.title)")
                .accessibilityIdentifier("mealPlan.swap")
            }
        }
        .padding(.vertical, 6)
        .contextMenu {
            if let swap {
                Button("Swap for something else", systemImage: "arrow.triangle.2.circlepath", action: swap)
            }
        }
    }
}

/// A dish: what's in it, its numbers per serving, and a swap while it's still to come (one kept
/// only for the days it was eaten can't be).
struct RecipeRow: View {
    @Environment(AppModel.self) private var model
    let recipe: PlannedRecipe
    let swap: (() -> Void)?

    var body: some View {
        let n = recipe.nutrients
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipe.title).font(.subheadline.weight(.semibold))
                    Text(
                        "\(recipe.servings) × \(recipe.slots.map { $0.label.lowercased() }.joined(separator: " and "))\(recipe.madeOnTheDay ? " · made on the day" : "")"
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let swap {
                    Button(action: swap) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Swap \(recipe.title)")
                    .accessibilityIdentifier("mealPlan.swap")
                }
            }
            Text(
                recipe.items.filter { !$0.onTheDay }.map { "\(Format.portion($0.grams, unit: model.units.weight)) \($0.name.lowercased())" }
                    .joined(separator: " · ")
            )
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            let topping = recipe.items.filter(\.onTheDay)
            if !topping.isEmpty {
                Text("When eating: \(topping.map { "\(Int($0.grams)) g \($0.name.lowercased())" }.joined(separator: ", "))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Text(Format.kcal(n.kcal)).font(.caption.weight(.semibold).monospacedDigit())
                Text(Format.macros(n)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                if recipe.items.contains(where: { $0.fermented == true }) {
                    FoodQualityTags(processing: nil, fermented: true)
                }
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            if let swap {
                Button("Swap for something else", systemImage: "arrow.triangle.2.circlepath", action: swap)
            }
        }
    }
}

/// The shopping list by aisle, ticked off as it goes in the basket.
struct GroceryPage: View {
    @Environment(AppModel.self) private var model
    let plan: MealPlan
    /// With the page's own head: on a phone, where it's a page of its own.
    var headed = false

    var body: some View {
        let items = Groceries.list(for: plan)
        let unit = model.units.weight
        let toBuy = items.filter { !$0.pantry }
        let left = toBuy.count { !plan.checked.contains($0.id) }
        Section {
            if headed {
                PageHead(
                    eyebrow: "Before prep on \(Format.day(plan.prepDay, style: .dateTime.weekday(.wide)))",
                    title: left == 0 ? "All in the basket" : left == toBuy.count ? "\(left) to buy" : "\(left) of \(toBuy.count) to buy",
                    detail: "Everything for \(Format.span(plan.days)). Tap one as it goes in the basket.")
            } else {
                Text("Everything for \(Format.span(plan.days)), to buy before prep on \(Format.day(plan.prepDay, style: .dateTime.weekday(.wide))).")
                    .font(.caption).foregroundStyle(Ink.text3)
            }
        }
        ForEach(Aisle.allCases) { aisle in
            let rows = items.filter { $0.aisle == aisle && !$0.pantry }
            if !rows.isEmpty {
                Section {
                    ForEach(rows) { row(item: $0, unit: unit) }
                } header: {
                    Text(aisle.label).eyebrow()
                }
            }
        }
        let pantry = items.filter(\.pantry)
        if !pantry.isEmpty {
            Section {
                ForEach(pantry) { row(item: $0, unit: unit) }
            } header: {
                Text("Check you have").eyebrow()
            }
        }
    }

    func row(item: GroceryItem, unit: WeightUnit) -> some View {
        let checked = plan.checked.contains(item.id)
        return Button {
            model.toggleGrocery(item.id, in: plan)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(checked ? Color.accentColor : Ink.text3)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.callout.weight(.semibold)).strikethrough(checked).foregroundStyle(checked ? Ink.text3 : Ink.text)
                    if !item.uses.isEmpty, item.uses.count < 3 {
                        Text("For \(item.uses.joined(separator: " and "))").font(.caption2).foregroundStyle(Ink.text3).lineLimit(1)
                    }
                }
                Spacer()
                Text(Self.amount(item, unit: unit)).font(.subheadline.monospacedDigit()).foregroundStyle(Ink.text2)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityLabel("\(item.name), \(Self.amount(item, unit: unit))")
        .accessibilityValue(checked ? "Got it" : "")
    }

    /// "4 heads · 1.2 kg", "2 tubs (500 g)", "1.4 kg".
    static func amount(_ item: GroceryItem, unit: WeightUnit) -> String {
        guard item.grams > 0 else { return "" }
        let weight = Format.shopping(item.grams, liquid: item.liquid, unit: unit)
        guard let count = item.count, let name = item.unit else { return weight }
        if let size = item.size { return "\(count) \(name) (\(size))" }
        return "\(count) \(name) · \(weight)"
    }

    /// The list as text, for Notes or Reminders.
    static func text(_ plan: MealPlan, unit: WeightUnit) -> String {
        let items = Groceries.list(for: plan)
        var lines = ["Groceries for the week of \(Format.day(plan.start))"]
        for aisle in Aisle.allCases {
            let rows = items.filter { $0.aisle == aisle && !$0.pantry }
            guard !rows.isEmpty else { continue }
            lines.append("\n\(aisle.label)")
            lines += rows.map { "- \($0.name): \(amount($0, unit: unit))" }
        }
        let pantry = items.filter(\.pantry)
        if !pantry.isEmpty {
            lines.append("\nCheck you have")
            lines += pantry.map { "- \($0.name)" }
        }
        return lines.joined(separator: "\n")
    }
}

/// Prep day, step by step, then what goes in each container.
struct PrepPage: View {
    @Environment(AppModel.self) private var model
    let plan: MealPlan
    /// With the page's own head: on a phone, where it's a page of its own.
    var headed = false

    var body: some View {
        let guide = PrepGuide.make(for: plan)
        let unit = model.units.weight
        Section {
            if headed {
                PageHead(
                    eyebrow: "Prep day · \(Format.day(plan.prepDay, style: .dateTime.weekday(.wide).month(.abbreviated).day()))",
                    title: "About \(Format.duration(guide.minutes))\n\(guide.containers) containers",
                    detail: "Each step timed from the start; what goes in each container is under them.")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("About \(Format.duration(guide.minutes))").font(.title3.weight(.semibold)).foregroundStyle(Ink.text)
                    Text("\(Format.day(plan.prepDay, style: .dateTime.weekday(.wide).month().day())) · \(guide.containers) containers")
                        .font(.subheadline).foregroundStyle(Ink.text2)
                }
            }
        }
        Section {
            ForEach(guide.steps) { step in
                HStack(alignment: .top, spacing: 12) {
                    Text(Format.clock(step.minute)).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Ink.text3)
                        .frame(width: 34, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(step.title).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
                            if !step.handsOn {
                                Label("\(step.minutes) min", systemImage: "timer").font(.caption2).foregroundStyle(Ink.text3)
                            }
                        }
                        Text(step.detail).font(.caption).foregroundStyle(Ink.text2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Steps").eyebrow()
        }
        Section {
            ForEach(guide.packing) { pack in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(pack.title) × \(pack.servings)").font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
                    if pack.madeOnTheDay {
                        Text("Made on the day: \(pack.contents.map { "\(Int($0.grams)) g \($0.name.lowercased())" }.joined(separator: ", ")).")
                            .font(.caption).foregroundStyle(Ink.text2).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(
                            "Each: \(pack.contents.map { "\(Format.portion($0.grams, unit: unit)) \($0.name.lowercased())" }.joined(separator: ", "))."
                        )
                        .font(.caption).foregroundStyle(Ink.text2).fixedSize(horizontal: false, vertical: true)
                        if !pack.onTheDay.isEmpty {
                            Text("When eating, add \(pack.onTheDay.map { "\(Int($0.grams)) g \($0.name.lowercased())" }.joined(separator: " and ")).")
                                .font(.caption).foregroundStyle(Ink.text2)
                        }
                        HStack(spacing: 12) {
                            if !pack.fridge.isEmpty { Label("Fridge \(Format.span(pack.fridge))", systemImage: "refrigerator").font(.caption2) }
                            if !pack.freezer.isEmpty { Label("Freezer \(Format.span(pack.freezer))", systemImage: "snowflake").font(.caption2) }
                        }
                        .foregroundStyle(Ink.text3)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Containers").eyebrow()
        } footer: {
            Text("Cooked food keeps 3–4 days in the fridge; frozen, it keeps for months. Reheat until steaming hot.")
        }
    }
}

/// A meal plan page's head, as the week's: an eyebrow in the accent, the number that answers the
/// page big, and what it's for. On the ground, at a list's margins.
private struct PageHead: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Tracked capitals start a point left of the text's frame, which the List cell clips.
            Text(eyebrow).eyebrow(Color.accentColor).padding(.leading, 2)
            PageTitle(title)
            Text(detail).font(.subheadline).foregroundStyle(Ink.text2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
    }
}
