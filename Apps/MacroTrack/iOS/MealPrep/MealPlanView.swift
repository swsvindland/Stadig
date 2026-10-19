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
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// The plan shown: the one opened, or the one made from here with "New plan…".
    @State private var planID: UUID
    @State private var page: Page
    @State private var request = ""
    @State private var working = false
    @State private var changed: String?
    @State private var showSetup = false
    @State private var confirmDelete = false

    init(planID: UUID, page: Page = .week) {
        _planID = State(initialValue: planID)
        _page = State(initialValue: page)
    }

    var body: some View {
        if let plan = model.mealPlans.first(where: { $0.id == planID }) {
            List {
                Section {
                    Picker("Show", selection: $page) {
                        ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("mealPlan.page")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
                switch page {
                case .week: week(plan)
                case .groceries: GroceryPage(plan: plan)
                case .prep: PrepPage(plan: plan)
                }
            }
            .insetGroupedList()
            .navigationTitle("Week of \(Format.day(plan.start, style: .dateTime.month(.abbreviated).day()))")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .barTrailing) {
                    Menu {
                        Button("Other dishes", systemImage: "shuffle") { model.shuffleMealPlan(plan) }
                            .disabled(model.swappableRecipes(in: plan).isEmpty)
                        Button("New plan…", systemImage: "square.and.pencil") { showSetup = true }
                        ShareLink(item: GroceryPage.text(plan, unit: model.units.weight)) {
                            Label("Share grocery list", systemImage: "square.and.arrow.up")
                        }
                        Button("Delete plan", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Plan options")
                    .accessibilityIdentifier("mealPlan.options")
                    // While a request is being read, so the plan it's for can't be deleted or replaced under it.
                    .disabled(working)
                }
            }
            .sheet(isPresented: $showSetup) { MealPlanSetup { planID = $0.id } }
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

    @ViewBuilder
    func week(_ plan: MealPlan) -> some View {
        Section {
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
        } footer: {
            Text("Swap any dish below with one tap, or say what you'd like in your own words.")
        }

        Section {
            let day = plan.planned(on: plan.start)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Format.kcal(day.kcal)) and \(Format.grams(day.protein)) protein planned a day")
                    .font(.subheadline.weight(.semibold))
                Text("Sized to \(Format.kcal(plan.targets.kcal)) and \(Format.grams(plan.targets.protein)) protein.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(plan.unplanned(on: plan.start), id: \.slot) { open in
                    Label(
                        "\(open.slot.label) is yours: about \(Format.kcal(open.room.kcal)), \(Format.grams(open.room.protein)) protein",
                        systemImage: open.slot.symbol
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
        }

        Section("Dishes") {
            let swappable = Set(model.swappableRecipes(in: plan))
            ForEach(plan.recipes) { recipe in
                RecipeRow(recipe: recipe, swap: swappable.contains(recipe.id) ? { model.swap(recipe.id, in: plan) } : nil)
            }
        }

        Section("Days") {
            ForEach(plan.days, id: \.self) { day in
                VStack(alignment: .leading, spacing: 4) {
                    Text(Format.day(day)).font(.subheadline.weight(.semibold))
                    ForEach(plan.meals(on: day)) { meal in
                        HStack(spacing: 6) {
                            Image(systemName: meal.slot.symbol).foregroundStyle(.secondary).frame(width: 18)
                            Text(plan.recipe(meal.recipeID)?.title ?? "").font(.caption).lineLimit(1)
                            Spacer(minLength: 4)
                            if meal.storage == .freezer {
                                Image(systemName: "snowflake").font(.caption2).foregroundStyle(.cyan).accessibilityLabel("Frozen")
                            }
                            if model.isLogged(meal, in: plan) {
                                Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(.green).accessibilityLabel("Logged")
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
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

    var body: some View {
        let items = Groceries.list(for: plan)
        let unit = model.units.weight
        Section {
            Text("Everything for \(Format.span(plan.days)), to buy before prep on \(Format.day(plan.prepDay, style: .dateTime.weekday(.wide))).")
                .font(.caption).foregroundStyle(.secondary)
        }
        ForEach(Aisle.allCases) { aisle in
            let rows = items.filter { $0.aisle == aisle && !$0.pantry }
            if !rows.isEmpty {
                Section(aisle.label) {
                    ForEach(rows) { row(item: $0, unit: unit) }
                }
            }
        }
        let pantry = items.filter(\.pantry)
        if !pantry.isEmpty {
            Section {
                ForEach(pantry) { row(item: $0, unit: unit) }
            } header: {
                Text("Check you have")
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
                    .foregroundStyle(checked ? Color.accentColor : .secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).strikethrough(checked).foregroundStyle(checked ? .secondary : .primary)
                    if !item.uses.isEmpty, item.uses.count < 3 {
                        Text("For \(item.uses.joined(separator: " and "))").font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                Spacer()
                Text(Self.amount(item, unit: unit)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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

    var body: some View {
        let guide = PrepGuide.make(for: plan)
        let unit = model.units.weight
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("About \(Format.duration(guide.minutes))").font(.title3.weight(.semibold))
                Text("\(Format.day(plan.prepDay, style: .dateTime.weekday(.wide).month().day())) · \(guide.containers) containers")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        Section("Steps") {
            ForEach(guide.steps) { step in
                HStack(alignment: .top, spacing: 12) {
                    Text(Format.clock(step.minute)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(step.title).font(.subheadline.weight(.semibold))
                            if !step.handsOn {
                                Label("\(step.minutes) min", systemImage: "timer").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Text(step.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        }
        Section {
            ForEach(guide.packing) { pack in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(pack.title) × \(pack.servings)").font(.subheadline.weight(.semibold))
                    if pack.madeOnTheDay {
                        Text("Made on the day: \(pack.contents.map { "\(Int($0.grams)) g \($0.name.lowercased())" }.joined(separator: ", ")).")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(
                            "Each: \(pack.contents.map { "\(Format.portion($0.grams, unit: unit)) \($0.name.lowercased())" }.joined(separator: ", "))."
                        )
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if !pack.onTheDay.isEmpty {
                            Text("When eating, add \(pack.onTheDay.map { "\(Int($0.grams)) g \($0.name.lowercased())" }.joined(separator: " and ")).")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 12) {
                            if !pack.fridge.isEmpty { Label("Fridge \(Format.span(pack.fridge))", systemImage: "refrigerator").font(.caption2) }
                            if !pack.freezer.isEmpty { Label("Freezer \(Format.span(pack.freezer))", systemImage: "snowflake").font(.caption2) }
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Containers")
        } footer: {
            Text("Cooked food keeps 3–4 days in the fridge; frozen, it keeps for months. Reheat until steaming hot.")
        }
    }
}
