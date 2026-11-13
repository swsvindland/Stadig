import NutritionEngine
import SwiftUI
import SystemCore

/// What's in the meal so far, under the logger's search: the foods a food logged now would join,
/// whether added in this logger or before it opened. A tap opens them to change, take out or save
/// as a meal.
struct MealTray: View {
    @Environment(AppModel.self) private var model
    /// When the next food will be eaten; nil is the logger's time.
    var date: Date?
    @State private var showing = false

    var body: some View {
        let moment = model.mealBeingLogged(at: date)
        // The sheet hangs off a view that stays when the last food is taken out, so it closes itself.
        VStack(spacing: 0) {
            if let moment { tray(moment).transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .animation(.snappy, value: moment?.entries.map(\.id))
        .sheet(isPresented: $showing) { MealSheet(date: date) }
        .notesWork(showing)
    }

    func tray(_ moment: Moment) -> some View {
        let title = MealSheet.title(moment, state: model.saveState(of: moment.entries))
        let names = moment.entries.map { SavedMeals.shortName($0.name) }.joined(separator: ", ")
        return Button {
            showing = true
        } label: {
            HStack(spacing: 12) {
                MealTile(size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text).lineLimit(1)
                    Text(names).font(.caption).foregroundStyle(Ink.text3).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(Format.kcal(moment.nutrients.kcal)).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Ink.text)
                Image(systemName: "chevron.up").font(.caption.weight(.bold)).foregroundStyle(Ink.text3)
            }
            .padding(.leading, 9)
            .padding(.trailing, 14)
            .frame(minHeight: 58)
            // A tile of Today's (`.tile`): the card colour, opaque over the list it sits above.
            .background(Color.cardBackground, in: .rect(cornerRadius: 18, style: .continuous))
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityLabel("\(title): \(moment.entries.map(\.name).joined(separator: ", ")), \(Format.kcal(moment.nutrients.kcal))")
        .accessibilityHint("Shows the foods, to change them or save them as a meal")
        .accessibilityIdentifier("logger.meal")
    }
}

/// A food of a meal as Today's thread sets it, on a card: its marker on the raised grey, its name
/// and amount, and its calories over the macro it's most of.
struct MealEntryRow: View {
    let entry: FoodEntry

    var body: some View {
        let lead = ThreadRow.lead(entry.nutrients)
        HStack(spacing: 12) {
            FoodTile(name: entry.name, size: 40, fill: Ink.raised)
            VStack(alignment: .leading, spacing: 2) {
                Text(FoodLabel.short(entry.name)).font(.body.weight(.medium)).foregroundStyle(Ink.text).lineLimit(1)
                Text(ThreadRow.caption(entry, estimate: false)).font(.caption).foregroundStyle(Ink.text3).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.isEstimate ? "≈" : "")\(Format.whole(entry.nutrients.kcal))").font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Ink.text)
                if let lead {
                    Text("\(Format.whole(lead.grams)) \(lead.letter)").font(.caption.weight(.medium).monospacedDigit()).foregroundStyle(lead.color)
                }
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// The meal being logged: its foods to change or take out, its total, and Save as Meal (or Update,
/// when it's a saved meal with an amount changed).
struct MealSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var date: Date?
    @State private var editing: FoodEntry?

    var body: some View {
        let moment = model.mealBeingLogged(at: date)
        NavigationStack {
            List {
                if let moment {
                    Section {
                        NutrientSummary(nutrients: moment.nutrients)
                    }
                    .inkRows()
                    Section {
                        ForEach(moment.entries) { entry in
                            Button {
                                editing = entry
                            } label: {
                                MealEntryRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                            .hoverHighlight()
                            .accessibilityIdentifier("mealSheet.entry")
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("Delete", systemImage: "trash", role: .destructive) { model.delete(entries: [entry.id]) }
                            }
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) { model.delete(entries: [entry.id]) }
                            }
                        }
                        .inkRows()
                    } footer: {
                        Text("Tap a food to change its amount; swipe to take it out.")
                    }
                } else {
                    ContentUnavailableView("Nothing in this meal", systemImage: "fork.knife", description: Text("Foods you add show here."))
                        .listRowBackground(Color.clear)
                }
            }
            .insetGroupedList()
            // In reach at the sheet's half height, below however many foods.
            .safeAreaInset(edge: .bottom) {
                if let moment { SaveMealBar(entries: moment.entries).padding() }
            }
            .navigationTitle(moment.map { Self.title($0, state: model.saveState(of: $0.entries)) } ?? "This meal")
            .inlineTitle()
            // A sheet of its own: pushed here it's held to this one's half height, where the keypad
            // and Save leave no room for the amount being typed.
            .sheet(item: $editing) { entry in EntryEditor(entry: entry, canTake: false) }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("mealSheet.done")
                }
            }
        }
        // A food's amount covers this too, and its few seconds shouldn't run out behind it. Over the
        // list, clear of the bar at the foot: a toast that's just come here would sit on Save as Meal.
        .toastOverlay(bottomPadding: 92, showing: editing == nil)
        .presentationDetents([.medium, .large])
        .loggerGround()
        .macSheetSize(width: 440, height: 560)
    }

    /// "Turkey sandwich" once saved, else "12:30 · 3 foods".
    static func title(_ moment: Moment, state: MealSaveState) -> String {
        switch state {
        case .saved(let meal), .changed(let meal): meal.name
        case .new: "\(Format.time(moment.start)) · \(moment.entries.count) \(moment.entries.count == 1 ? "food" : "foods")"
        }
    }
}

/// Save these foods as a meal, update the meal they are with its new amounts, or say they're saved.
struct SaveMealBar: View {
    @Environment(AppModel.self) private var model
    let entries: [FoodEntry]
    @State private var naming = false

    var body: some View {
        Group {
            switch model.saveState(of: entries) {
            case .new where entries.count < 2:
                Text("Add another food to save these as a meal.")
                    .font(.subheadline).foregroundStyle(Ink.text2)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            case .new:
                Button {
                    naming = true
                } label: {
                    Label("Save as Meal", systemImage: "square.and.arrow.down").font(.headline).frame(maxWidth: .infinity)
                }
                .primaryAction().controlSize(.large)
                .accessibilityIdentifier("mealSheet.saveMeal")
            case .changed(let meal):
                HStack {
                    Button {
                        naming = true
                    } label: {
                        Text("Save as New").frame(maxWidth: .infinity)
                    }
                    .secondaryAction().controlSize(.large)
                    .accessibilityIdentifier("mealSheet.saveMeal")
                    Button {
                        model.update(meal, from: entries)
                    } label: {
                        Text("Update \(meal.name)").font(.headline).lineLimit(1).frame(maxWidth: .infinity)
                    }
                    .primaryAction().controlSize(.large)
                    .accessibilityIdentifier("mealSheet.updateMeal")
                }
            case .saved(let meal):
                Label("Saved as \(meal.name)", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium)).foregroundStyle(Ink.text2)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("mealSheet.saved")
            }
        }
        .saveMealPrompt(isPresented: $naming, entries: entries)
    }
}

extension View {
    /// Asks for a name, then saves these foods as a meal. Left blank, it takes the suggested name.
    func saveMealPrompt(isPresented: Binding<Bool>, entries: [FoodEntry]) -> some View {
        modifier(SaveMealPrompt(isPresented: isPresented, entries: entries))
    }
}

private struct SaveMealPrompt: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool
    let entries: [FoodEntry]
    @State private var name = ""

    func body(content: Content) -> some View {
        content.alert("Save as Meal", isPresented: $isPresented) {
            TextField(SavedMeals.suggestedName(entries), text: $name)
                .accessibilityIdentifier("saveMeal.name")
            Button("Save") {
                model.saveMeal(named: name, from: entries)
                name = ""
            }
            .accessibilityIdentifier("saveMeal.save")
            Button("Cancel", role: .cancel) { name = "" }
        } message: {
            Text("A name for these \(entries.count) foods, to log them together next time.")
        }
    }
}

/// A saved meal in the logger: its name, foods and total, and a one-tap add.
struct SavedMealRow: View {
    let meal: SavedMeal
    let add: () -> Void
    let open: () -> Void

    var body: some View {
        LoggerRow(
            title: meal.name, caption: Self.detail(meal),
            addLabel: "Log \(meal.name), \(meal.foods.count) foods, \(Format.kcal(meal.nutrients.kcal))", openIdentifier: "logger.savedMeal",
            addIdentifier: "logger.logMeal", add: add, open: open
        ) {
            MealTile(size: 40)
        }
    }

    /// "5 foods · 405 kcal · 40 g P".
    static func detail(_ meal: SavedMeal) -> String {
        "\(meal.foods.count) foods · \(Format.kcal(meal.nutrients.kcal)) · \(Format.grams(meal.nutrients.protein)) P"
    }

    /// A food's name up to its first comma, for a line listing several: "Bread, whole-wheat" is "Bread".
    static func shortName(_ name: String) -> String {
        name.split(separator: ",", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? name
    }
}

/// A saved meal: its foods, each kept or left out this time and each amount changeable, its total,
/// and Log, then Rename and Delete below (in the form rather than the toolbar, which a Mac sheet
/// keeps for its confirmation buttons). Foods are known by their ids, unique in a meal, so a meal
/// changed meanwhile (synced in, or in another window) never gets an edit meant for another food.
struct SavedMealView: View {
    @Environment(AppModel.self) private var model
    let mealID: UUID
    /// When it was eaten, where the screen has its own choice of time (the Foods inspector); nil is
    /// the logger's time.
    var eaten: Binding<EatenAt>?
    /// After logging or deleting.
    var done: () -> Void = {}
    /// The foods left out this time.
    @State private var skipping: Set<UUID> = []
    @State private var editing: FoodEntry?
    @State private var renaming = false
    @State private var name = ""
    @State private var deleting = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Beside the foods (the Foods inspector) rather than pushed in a phone's logger.
    var wide: Bool { sizeClass != .compact }

    var body: some View {
        if let meal = model.savedMeal(mealID) {
            form(meal)
                .detailPage(title: meal.name, wide: wide)
                .navigationDestination(item: $editing) { food in
                    EntryEditor(
                        entry: food, close: { editing = nil },
                        saveTo: { changed in
                            if let current = model.savedMeal(mealID) { model.replace(food: food.id, in: current, with: changed) }
                        }
                    )
                    .navigationTitle("Amount")
                }
                .alert("Rename Meal", isPresented: $renaming) {
                    TextField("Name", text: $name).accessibilityIdentifier("savedMeal.name")
                    Button("Save") { model.rename(meal, to: name) }
                    Button("Cancel", role: .cancel) {}
                }
                .confirmationDialog("Delete \(meal.name)?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete Meal", role: .destructive) {
                        model.delete(meal: meal)
                        done()
                    }
                } message: {
                    Text("Foods already logged from it stay in your log.")
                }
        } else {
            ContentUnavailableView("No meal", systemImage: "fork.knife", description: Text("This meal was deleted."))
        }
    }

    func form(_ meal: SavedMeal) -> some View {
        let kept = meal.foods.filter { !skipping.contains($0.id) }
        let total = Nutrients.sum(kept.map(\.nutrients))
        return Form {
            if !wide {
                DetailHeader(eyebrow: "Saved meal", title: meal.name)
                    .padding(.top, 6)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
            }
            Section {
                NutrientSummary(nutrients: total)
            }
            .inkRows()
            Section {
                ForEach(meal.foods) { food in
                    row(meal, food)
                }
                .inkRows()
            } header: {
                SectionEyebrow("Foods")
            } footer: {
                Text("Untick a food to leave it out this time. Tap one to change its amount for good.")
            }
            if let eaten {
                Section {
                    EatenPicker(eaten: eaten)
                } header: {
                    SectionEyebrow("Eaten")
                }
                .inkRows()
            }
            Section {
                Button("Rename…", systemImage: "pencil") {
                    name = meal.name
                    renaming = true
                }
                .accessibilityIdentifier("savedMeal.rename")
                Button("Delete Meal", systemImage: "trash", role: .destructive) { deleting = true }
                    .accessibilityIdentifier("savedMeal.delete")
            }
            .inkRows()
        }
        .formStyle(.grouped)
        .inkForm()
        .contentMargins(.top, wide ? nil : 0, for: .scrollContent)
        .safeAreaInset(edge: .bottom) {
            Button {
                model.log(meal, skipping: skipping, at: eaten.map { $0.wrappedValue.date(model) })
                skipping = []
                done()
            } label: {
                Text(logLabel(meal, kept: kept.count, kcal: total.kcal)).font(.headline).frame(maxWidth: .infinity)
            }
            .primaryAction().controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(kept.isEmpty)
            .padding()
            // Opaque on a phone's ink, so the rows scrolling under it don't show through.
            .background {
                if !wide { Ink.ground.ignoresSafeArea(edges: .bottom) }
            }
            .accessibilityIdentifier("savedMeal.log")
        }
    }

    func row(_ meal: SavedMeal, _ food: FoodEntry) -> some View {
        let included = !skipping.contains(food.id)
        return HStack(spacing: 12) {
            Button {
                if included { skipping.insert(food.id) } else { skipping.remove(food.id) }
            } label: {
                Image(systemName: included ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(included ? Color.accentColor : Ink.text3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(included ? "Leave out \(food.name)" : "Include \(food.name)")
            .accessibilityIdentifier("savedMeal.include")
            Button {
                editing = food
            } label: {
                MealEntryRow(entry: food).opacity(included ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .hoverHighlight()
            .accessibilityIdentifier("savedMeal.food")
        }
        .swipeActions(edge: .trailing) {
            Button("Remove", systemImage: "minus.circle", role: .destructive) { model.replace(food: food.id, in: meal, with: nil) }
        }
        .contextMenu {
            Button("Remove from Meal", systemImage: "minus.circle", role: .destructive) { model.replace(food: food.id, in: meal, with: nil) }
        }
    }

    /// "Log 5 foods · 405 kcal", "Log 4 of 5 at Sat 7:30 PM · 300 kcal": the time only when it isn't now.
    func logLabel(_ meal: SavedMeal, kept: Int, kcal: Double) -> String {
        let count = kept == meal.foods.count ? "\(kept) foods" : "\(kept) of \(meal.foods.count)"
        let now: Bool
        if let eaten, case .now = eaten.wrappedValue {
            now = model.selectedDay == model.today
        } else {
            now = eaten == nil && LogTime.label(model) == "Now"
        }
        guard !now else { return "Log \(count) · \(Format.kcal(kcal))" }
        let date = eaten.map { $0.wrappedValue.date(model) } ?? model.logDate()
        let day = Day(date) == model.today ? "" : "\(Format.day(Day(date), style: .dateTime.weekday(.abbreviated))) "
        return "Log \(count) at \(day)\(Format.time(date)) · \(Format.kcal(kcal))"
    }
}
