import MealPlanner
import NutritionEngine
import SwiftUI
import SystemCore

/// What to plan this week: which meals to prep, the diet, what to leave out, and when.
struct MealPlanSetup: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// The plan made, for a screen that shows it.
    var made: ((MealPlan) -> Void)?
    @State private var preferences = PlanPreferences()
    @State private var tomorrow = false
    @State private var request = ""
    @State private var working = false
    @State private var loaded = false
    /// Reading the request and making the plan; cancelled with the sheet, so a cancelled sheet
    /// can't still replace the week that's there.
    @State private var planning: Task<Void, Never>?

    /// Things people commonly leave out, as the words the planner reads.
    static let leaveOut: [(word: String, label: String)] = [
        ("fish", "Fish"), ("shellfish", "Shellfish"), ("pork", "Pork"), ("beef", "Beef"), ("dairy", "Dairy"), ("eggs", "Eggs"),
        ("gluten", "Gluten"), ("nuts", "Nuts"), ("peanuts", "Peanuts"), ("soy", "Soy"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(MealSlot.allCases) { slot in
                        Toggle(
                            isOn: Binding(
                                get: { preferences.slots.contains(slot) },
                                set: { on in
                                    if on { preferences.slots.insert(slot) } else { preferences.slots.remove(slot) }
                                })
                        ) {
                            Label(slot.label, systemImage: slot.symbol)
                        }
                    }
                } header: {
                    Text("Prep which meals?")
                } footer: {
                    Text("The rest are yours, with room kept for them in your targets.")
                }

                Section("Diet") {
                    Picker("Diet", selection: $preferences.diet) {
                        ForEach(PlanPreferences.Diet.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Leave out") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(Self.leaveOut, id: \.word) { item in
                            let on = preferences.avoid.contains(item.word)
                            Button {
                                if on { preferences.avoid.remove(item.word) } else { preferences.avoid.insert(item.word) }
                            } label: {
                                Text(item.label).font(.subheadline).frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .tint(on ? .orange : .secondary)
                            .accessibilityValue(on ? "Left out" : "")
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    TextField("More spicy, no salmon, cheaper…", text: $request, axis: .vertical)
                } header: {
                    Text("Anything else?")
                } footer: {
                    Text("Read on this iPhone with Apple Intelligence when it can.")
                }

                Section("Start") {
                    Picker("Start", selection: $tomorrow) {
                        Text(
                            "\(Format.day(model.planStart(tomorrow: false), style: .dateTime.weekday(.wide).month().day())), prep \(Format.prepDay(model.planStart(tomorrow: false).adding(days: -1), today: model.today))"
                        )
                        .tag(false)
                        Text("Tomorrow, prep today").tag(true)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("Plan a week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        planning?.cancel()
                        dismiss()
                    }
                    .accessibilityIdentifier("mealPlanSetup.cancel")
                }
            }
            .onDisappear { planning?.cancel() }
            .safeAreaInset(edge: .bottom) {
                Button {
                    make()
                } label: {
                    HStack {
                        if working { ProgressView() }
                        Text(working ? "Planning…" : "Make my plan").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .primaryAction()
                .disabled(preferences.slots.isEmpty || working)
                .accessibilityIdentifier("mealPlanSetup.make")
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                preferences = model.lastPlanPreferences
                // Wishes are for one week; what's left out carries over.
                preferences.want = []
                if model.planStart(tomorrow: false).days(until: model.today) <= -6 { tomorrow = false }
            }
        }
    }

    func make() {
        working = true
        planning = Task {
            var preferences = preferences
            let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                let change = await PlanAssistant().read(text, allowCloud: model.settings.allowCloudAI)
                preferences = change.applied(to: preferences)
            }
            // The reader answers even when cancelled, so check before replacing anything.
            guard !Task.isCancelled else { return }
            let plan = model.makeMealPlan(preferences: preferences, start: model.planStart(tomorrow: tomorrow))
            working = false
            made?(plan)
            dismiss()
        }
    }
}

/// Meal prep on the Plan tab: a way in, or this week's plan at a glance.
struct MealPrepCard: View {
    @Environment(AppModel.self) private var model
    @State private var showSetup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Meal prep").font(.headline)
                Spacer()
                if let plan = model.mealPlan {
                    Text(
                        plan.start > model.today
                            ? "Prep \(Format.prepDay(plan.prepDay, today: model.today))"
                            : "Week of \(Format.day(plan.start, style: .dateTime.month(.abbreviated).day()))"
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let plan = model.mealPlan {
                let guide = PrepGuide.make(for: plan)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(plan.recipes) { recipe in
                        Label(recipe.title, systemImage: (recipe.slots.first ?? .lunch).symbol).font(.subheadline).lineLimit(1)
                    }
                }
                Text("\(guide.containers) containers, about \(Format.duration(guide.minutes)) of prep.").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    link("Week", .week, plan)
                    link("Groceries", .groceries, plan)
                    link("Prep", .prep, plan)
                }
            } else {
                Text("A week of meals sized to your targets, with the grocery list and a timed prep: an hour or two on Sunday and the week is done.")
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Plan a week") { showSetup = true }.primaryAction()
                    .accessibilityIdentifier("mealPrep.planWeek")
            }
        }
        .card()
        .sheet(isPresented: $showSetup) { MealPlanSetup() }
    }

    func link(_ title: String, _ page: MealPlanView.Page, _ plan: MealPlan) -> some View {
        NavigationLink {
            MealPlanView(planID: plan.id, page: page)
        } label: {
            Text(title).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
        }
        .secondaryAction()
    }
}

/// Today's planned meals on Today: one tap logs a container as eaten.
struct PlannedMealsSection: View {
    @Environment(AppModel.self) private var model
    let day: Day

    var body: some View {
        if let plan = model.mealPlan(covering: day) {
            let meals = plan.meals(on: day)
            Section {
                ForEach(meals) { meal in
                    if let recipe = plan.recipe(meal.recipeID) {
                        row(meal, recipe, plan)
                    }
                }
                ForEach(plan.unplanned(on: day), id: \.slot) { open in
                    Label(
                        "\(open.slot.label) is yours: about \(Format.kcal(open.room.kcal)), \(Format.grams(open.room.protein)) protein",
                        systemImage: open.slot.symbol
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                NavigationLink {
                    MealPlanView(planID: plan.id)
                } label: {
                    HStack(spacing: 4) {
                        Text("From your plan")
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                    }
                }
            } footer: {
                if let thaw = thawReminder(plan) { Text(thaw) }
            }
        }
    }

    func row(_ meal: PlannedMeal, _ recipe: PlannedRecipe, _ plan: MealPlan) -> some View {
        let logged = model.isLogged(meal, in: plan)
        let n = recipe.nutrients
        return HStack(spacing: 12) {
            Image(systemName: meal.slot.symbol).foregroundStyle(Color.accentColor).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.title).font(.subheadline.weight(.medium)).lineLimit(2)
                Text("\(meal.slot.label) · \(Format.kcal(n.kcal)) · \(Format.grams(n.protein)) protein\(note(meal, recipe))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if logged {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3).accessibilityLabel("Logged")
            } else {
                Button("Log") { model.logPlanned(meal, in: plan) }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule).font(.subheadline)
                    .accessibilityLabel("Log \(recipe.title)")
                    .accessibilityIdentifier("mealPrep.logMeal")
            }
        }
    }

    /// Where the serving is, and what to add when eating it.
    func note(_ meal: PlannedMeal, _ recipe: PlannedRecipe) -> String {
        let topping = recipe.items.filter(\.onTheDay).map { $0.name.lowercased() }
        let add = topping.isEmpty ? "" : " · add \(topping.joined(separator: ", "))"
        switch meal.storage {
        case .fridge: return add
        case .freezer: return " · thawed from the freezer" + add
        case .onTheDay: return recipe.kind == .template && recipe.keeps == 0 ? " · put together now" + add : add
        }
    }

    /// In the evening, the next day's containers to move from the freezer.
    func thawReminder(_ plan: MealPlan) -> String? {
        guard day == model.today, Calendar.current.component(.hour, from: Date()) >= 17 else { return nil }
        let frozen = plan.meals(on: day.adding(days: 1)).filter { $0.storage == .freezer }
        guard !frozen.isEmpty else { return nil }
        return "Tonight: move tomorrow's \(frozen.count == 1 ? "container" : "\(frozen.count) containers") from the freezer to the fridge."
    }
}
