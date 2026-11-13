import MealPlanner
import NutritionEngine
import SwiftUI
import SystemCore

/// The Meal Plan as a sidebar destination: this week's plan, or a way to make one.
struct MealPlanTab: View {
    @Environment(AppModel.self) private var model
    @State private var showSetup = false

    var body: some View {
        NavigationStack {
            if let plan = model.mealPlan {
                MealPlanView(planID: plan.id).id(plan.id)
            } else {
                ContentUnavailableView {
                    Label("No meal plan", systemImage: "takeoutbag.and.cup.and.straw")
                } description: {
                    Text(
                        "A week of meals sized to your targets, with the grocery list and a timed prep: an hour or two on Sunday and the week is done."
                    )
                } actions: {
                    Button("Plan a Week") { showSetup = true }
                        .primaryAction()
                        .accessibilityIdentifier("mealPlan.planWeek")
                }
                .navigationTitle("Meal Plan")
            }
        }
        .sheet(isPresented: $showSetup) { MealPlanSetup().macSheetSize(width: 560, height: 680) }
    }
}

/// A week's plan with room for it: the days by meal in a grid, the dishes, and the grocery list and
/// prep day beside them rather than behind a picker.
struct MealPlanBoard<Request: View, Header: View>: View {
    @Environment(AppModel.self) private var model
    let plan: MealPlan
    let request: Request
    /// The page's header, over the week.
    let header: Header

    init(plan: MealPlan, request: Request, @ViewBuilder header: () -> Header) {
        self.plan = plan
        self.request = request
        self.header = header()
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                week.frame(minWidth: 440, maxWidth: .infinity)
                Divider()
                if proxy.size.width >= 1120 {
                    List {
                        groceriesHeader
                        GroceryPage(plan: plan)
                    }
                    .insetGroupedList()
                    .frame(width: 300)
                    .accessibilityIdentifier("mealPlan.groceries")
                    Divider()
                    List {
                        prepHeader
                        PrepPage(plan: plan)
                    }
                    .insetGroupedList()
                    .frame(width: 320)
                    .accessibilityIdentifier("mealPlan.prep")
                } else {
                    List {
                        groceriesHeader
                        GroceryPage(plan: plan)
                        prepHeader
                        PrepPage(plan: plan)
                    }
                    .insetGroupedList()
                    .frame(width: 320)
                    .accessibilityIdentifier("mealPlan.groceries")
                }
            }
        }
    }

    var groceriesHeader: some View {
        Section { Label("Groceries", systemImage: "cart").font(.title3.weight(.semibold)).listRowBackground(Color.clear) }
    }

    /// Prep day's title, and counter mode: the steps one at a time, big, for the iPad on the counter.
    var prepHeader: some View {
        Section {
            HStack(spacing: 12) {
                Label("Prep day", systemImage: "timer").font(.title3.weight(.semibold))
                Spacer(minLength: 8)
                Button(model.prepRun?.planID == plan.id ? "Back to prep" : "Start prep") { model.startPrep(plan) }
                    .primaryAction()
                    .accessibilityIdentifier("mealPlan.startCounter")
            }
            .listRowBackground(Color.clear)
        }
    }

    var week: some View {
        let swappable = Set(model.swappableRecipes(in: plan))
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                VStack(alignment: .leading, spacing: 8) {
                    request
                    let day = plan.planned(on: plan.start)
                    Text(
                        "\(Format.kcal(day.kcal)) and \(Format.grams(day.protein)) protein planned a day, sized to \(Format.kcal(plan.targets.kcal)) and \(Format.grams(plan.targets.protein))."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    ForEach(plan.unplanned(on: plan.start), id: \.slot) { open in
                        Label(
                            "\(open.slot.label) is yours: about \(Format.kcal(open.room.kcal)), \(Format.grams(open.room.protein)) protein",
                            systemImage: open.slot.symbol
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .card()
                WeekGrid(plan: plan, swappable: swappable)
                SectionHeader(title: "Dishes", detail: "\(plan.recipes.count)")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                    ForEach(plan.recipes) { recipe in
                        RecipeRow(recipe: recipe, swap: swappable.contains(recipe.id) ? { model.swap(recipe.id, in: plan) } : nil)
                            .card(padding: 14, radius: 18)
                    }
                }
            }
            .padding()
        }
        .background(.pageBackground)
    }
}

/// The week as days by meal: each cell the dish for that meal, with whether it's logged or frozen,
/// a swap in its context menu and, on the day, a log.
struct WeekGrid: View {
    @Environment(AppModel.self) private var model
    let plan: MealPlan
    let swappable: Set<String>

    var body: some View {
        let slots = MealSlot.allCases.filter { slot in plan.meals.contains { $0.slot == slot } }
        let logged = model.loggedMeals(in: plan)
        Grid(alignment: .topLeading, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Color.clear.frame(width: 1, height: 1).gridCellUnsizedAxes([.horizontal, .vertical])
                ForEach(slots) { slot in
                    Label(slot.label, systemImage: slot.symbol).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            ForEach(plan.days, id: \.self) { day in
                GridRow {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Format.day(day, style: .dateTime.weekday(.abbreviated))).font(.subheadline.weight(.semibold))
                        Text(Format.day(day, style: .dateTime.month(.abbreviated).day())).font(.caption).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(day == model.today ? Color.accentColor : .primary)
                    .frame(width: 64, alignment: .leading)
                    let meals = plan.meals(on: day)
                    ForEach(slots) { slot in
                        if let meal = meals.first(where: { $0.slot == slot }) {
                            MealCell(plan: plan, meal: meal, logged: logged.contains(meal.id), swappable: swappable.contains(meal.recipeID))
                        } else {
                            Text("Yours").font(.caption).foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(.fill.quinary, in: .rect(cornerRadius: 12))
                        }
                    }
                }
            }
        }
        // A container of its own, so each meal keeps its identifier rather than taking the grid's.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mealPlan.week")
    }
}

/// One meal of the week: the dish, logged or frozen, with its swap and its log one click away.
private struct MealCell: View {
    @Environment(AppModel.self) private var model
    let plan: MealPlan
    let meal: PlannedMeal
    let logged: Bool
    let swappable: Bool

    var body: some View {
        let recipe = plan.recipe(meal.recipeID)
        let today = meal.day == model.today
        VStack(alignment: .leading, spacing: 4) {
            Text(recipe?.title ?? "").font(.caption.weight(.medium)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                if let recipe { Text(Format.kcal(recipe.nutrients.kcal)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                if meal.storage == .freezer {
                    Image(systemName: "snowflake").font(.caption2).foregroundStyle(Ink.carbs).accessibilityLabel("Frozen")
                }
                if logged {
                    Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(Ink.good).accessibilityLabel("Logged")
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
        .background(.fill.quaternary, in: .rect(cornerRadius: 12))
        .overlay {
            if today { RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(0.6), lineWidth: 1.5) }
        }
        .contentShape(.rect(cornerRadius: 12))
        .hoverHighlight()
        .help(recipe.map(Self.contents) ?? "")
        .contextMenu {
            if !logged, meal.day <= model.today {
                Button(today ? "Log Now" : "Log on \(Format.day(meal.day, style: .dateTime.weekday(.wide)))", systemImage: "plus.circle") {
                    model.logPlanned(meal, in: plan)
                }
            }
            if swappable, let recipe {
                Button("Swap \(recipe.title)", systemImage: "arrow.triangle.2.circlepath") { model.swap(recipe.id, in: plan) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mealPlan.meal")
    }

    /// What's in the container, for the tooltip.
    static func contents(_ recipe: PlannedRecipe) -> String {
        recipe.items.map { "\(Int($0.grams)) g \($0.name.lowercased())" }.joined(separator: ", ")
    }
}
