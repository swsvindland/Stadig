import FoodDatabase
import NutritionEngine
import SwiftUI
import SystemCore

/// Calories and protein when that's all there is: a restaurant guess, a snack on the go.
struct QuickAddView: View {
    @Environment(AppModel.self) private var model
    let close: () -> Void
    @State private var name = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @FocusState private var focus: Field?

    enum Field { case kcal, protein, carbs, fat, name }

    var body: some View {
        Form {
            Section {
                row("Calories", $kcal, "kcal", .kcal)
                row("Protein", $protein, "g", .protein)
            } footer: {
                Text("Quick adds count toward today but aren't suggested again.")
            }
            Section("Optional") {
                row("Carbs", $carbs, "g", .carbs)
                row("Fat", $fat, "g", .fat)
                TextField("Name", text: $name).focused($focus, equals: .name).accessibilityIdentifier("quickAdd.name")
            }
        }
        .navigationTitle("Quick add")
        .safeAreaInset(edge: .bottom) {
            Button {
                model.quickAdd(name: name, nutrients: nutrients)
                close()
            } label: {
                Text("Add \(Format.kcal(nutrients.kcal))").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .primaryAction()
            .accessibilityIdentifier("quickAdd.add")
            .padding()
            .disabled(nutrients.kcal <= 0 && nutrients.protein <= 0)
        }
        .onAppear { focus = .kcal }
    }

    var nutrients: Nutrients {
        func v(_ s: String) -> Double { Format.parse(s) ?? 0 }
        let p = v(protein)
        let c = v(carbs)
        let f = v(fat)
        let k = v(kcal) > 0 ? v(kcal) : p * 4 + c * 4 + f * 9
        return Nutrients(kcal: k, protein: p, carbs: c, fat: f)
    }

    func row(_ title: String, _ text: Binding<String>, _ unit: String, _ field: Field) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text).fieldKeyboard(.decimal).multilineTextAlignment(.trailing).frame(width: 100)
                .focused($focus, equals: field)
                .accessibilityIdentifier("quickAdd.\(field)")
            Text(unit).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
        }
    }
}

/// Change an entry's amount, meal or time; or delete it.
struct EntryEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var entry: FoodEntry
    @State private var count: Double = 1
    @State private var countText = "1"
    @State private var unit: PortionUnit?
    @State private var food: Food?
    /// The amount as it reopened, so a change of time alone saves the entry's own numbers.
    @State private var original: (unitID: String?, count: Double)?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name).font(.headline)
                        if let brand = entry.brand { Text(brand).font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
                Section("Amount") {
                    HStack {
                        TextField("Amount", text: $countText)
                            .fieldKeyboard(.decimal)
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .accessibilityIdentifier("entryEditor.amount")
                            .onChange(of: countText) { _, text in
                                // Text this view wrote already says the count; reading it back would round it.
                                guard text != self.text(for: count), let v = Format.parse(text), v > 0 else { return }
                                count = v
                            }
                        if let food {
                            let units = FoodUnits.units(for: food)
                            Picker(
                                "Unit",
                                selection: Binding(
                                    get: { unit?.id ?? units.first?.id ?? "" },
                                    set: { id in
                                        guard let next = units.first(where: { $0.id == id }) else { return }
                                        // Keep the amount: 150 g becomes 5.3 oz, not 150 oz.
                                        if let old = unit, old.id != next.id {
                                            let converted = FoodUnits.convert(count, from: old, to: next)
                                            if converted.isFinite { count = converted }
                                        }
                                        unit = next
                                        countText = text(for: count)
                                    })
                            ) {
                                ForEach(units) { Text($0.label).tag($0.id) }
                            }
                            .labelsHidden()
                            .accessibilityIdentifier("entryEditor.unit")
                        } else {
                            Text("× \(entry.amountLabel)").foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    NutrientSummary(nutrients: nutrients)
                }
                Section {
                    DatePicker("Eaten", selection: $entry.date).accessibilityIdentifier("entryEditor.eaten")
                }
                Section {
                    Button("Delete", role: .destructive) {
                        model.delete(entries: [entry.id])
                        dismiss()
                    }
                    .accessibilityIdentifier("entryEditor.delete")
                }
            }
            .navigationTitle("Edit")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("entryEditor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .accessibilityIdentifier("entryEditor.save")
                }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.medium, .large])
    }

    var nutrients: Nutrients {
        if let food, let unit { return FoodUnits.nutrients(food, count: count, unit: unit) }
        return entry.nutrients.scaled(count)
    }

    func load() {
        guard original == nil else { return }
        if let id = entry.foodID, let found = model.food(id: id) {
            food = found
            // In the unit it was logged in while that still holds the amount logged, else the
            // food's basis counting that amount: a catalog update can reorder or reword portions.
            let reopened = FoodUnits.logged(for: found, unitID: entry.unitID, count: entry.count, amount: entry.grams)
            unit = reopened.unit
            count = reopened.count
        } else {
            count = 1
        }
        countText = text(for: count)
        original = (unit?.id, count)
    }

    /// A count as the amount field shows it: "1½" slices, "1500" ml, never grouped.
    func text(for count: Double) -> String { unit.map { FoodUnits.format(count, $0) } ?? Format.editable(count) }

    /// Whether the amount was changed, rather than only the time.
    var amountChanged: Bool {
        guard let original else { return true }
        return unit?.id != original.unitID || abs(count - original.count) > 1e-9
    }

    func save() {
        var updated = entry
        guard amountChanged else {
            model.update(updated)
            return
        }
        if let food, let unit {
            let amount = FoodUnits.amount(count, unit)
            var micros = FoodUnits.micros(food, count: count, unit: unit)
            // What the entry knew beyond the food scales with the amount: a drink's typical
            // caffeine (the catalog didn't list it) and its fluid.
            let ratio = entry.grams.flatMap { $0 > 0 ? amount / $0 : nil }
            if micros["caffeine"] == nil, let mg = entry.micros?["caffeine"], let ratio { micros["caffeine"] = mg * ratio }
            updated.nutrients = FoodUnits.nutrients(food, count: count, unit: unit)
            updated.micros = micros
            updated.fluid = entry.fluid.map { fluid in ratio.map { fluid * $0 } ?? fluid }
            updated.amountLabel = FoodUnits.entryLabel(for: food, count: count, unit: unit, estimate: entry.isEstimate)
            updated.grams = amount
            updated.unitID = unit.id
            updated.count = count
        } else if count != 1 {
            updated.nutrients = entry.nutrients.scaled(count)
            updated.micros = entry.micros?.mapValues { $0 * count }
            updated.fluid = entry.fluid.map { $0 * count }
            updated.amountLabel = "\(Format.number(count, digits: 2)) × \(entry.amountLabel)"
            updated.grams = entry.grams.map { $0 * count }
        }
        model.update(updated)
    }
}

/// A weigh-in, ready with the last weight so most mornings it's a nudge and Save, with the last
/// few to check or ignore.
struct WeighInSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @State private var date = Date()
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        nudge(-1)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            TextField("0.0", text: $value)
                                .fieldKeyboard(.decimal)
                                .multilineTextAlignment(.center)
                                .font(.largeTitle.weight(.semibold).monospacedDigit())
                                .focused($focused)
                                .accessibilityIdentifier("weighIn.value")
                            Text(model.units.weight.symbol).font(.title3).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        nudge(1)
                    }
                    .padding(.vertical, 4)
                    DatePicker("When", selection: $date, in: ...Date()).accessibilityIdentifier("weighIn.date")
                } footer: {
                    Text("Daily, first thing, after the bathroom and before eating. Single readings are mostly water; the trend is what counts.")
                }
                let recent = model.weighIns.suffix(10).reversed()
                if !recent.isEmpty {
                    Section("Recent") {
                        ForEach(Array(recent)) { w in
                            HStack {
                                Text(Format.day(w.day))
                                Spacer()
                                Text(Format.weight(w.kg, unit: model.units.weight)).monospacedDigit()
                                    .accessibilityIdentifier("weighIn.recent")
                                    .strikethrough(w.excluded)
                                    .foregroundStyle(w.excluded ? .secondary : .primary)
                                if case .health = w.source { Image(systemName: "heart.fill").font(.caption).foregroundStyle(.pink) }
                            }
                            .swipeActions {
                                Button(w.excluded ? "Use" : "Ignore") { model.setExcluded(!w.excluded, weighIn: w) }.tint(.orange)
                                if case .manual = w.source {
                                    Button("Delete", role: .destructive) { model.delete(weighIn: w) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Weigh in")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("weighIn.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let kg { model.weighIn(kg: kg, date: date) }
                        dismiss()
                    }
                    .disabled(kg == nil)
                    .accessibilityIdentifier("weighIn.save")
                }
            }
            .onAppear(perform: prefill)
        }
        .presentationDetents([.medium, .large])
    }

    /// One step lighter or heavier: 0.1 kg, or 0.2 lb.
    func nudge(_ direction: Double) -> some View {
        Button {
            let unit = model.units.weight
            let step = unit == .kg ? 0.1 : 0.2
            let current = Format.parse(value) ?? 0
            value = Format.editable(max(0, current + direction * step), digits: 1)
        } label: {
            Image(systemName: direction < 0 ? "minus" : "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 52, height: 52)
                .background(Color.accentColor.opacity(0.14), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(direction < 0 ? "Lighter" : "Heavier")
        .accessibilityIdentifier(direction < 0 ? "weighIn.lighter" : "weighIn.heavier")
    }

    /// The last weight to start from, and the morning of the day being looked at.
    func prefill() {
        if value.isEmpty, let last = model.latestWeighIn {
            value = Format.editable(model.units.weight.fromKilograms(last.kg), digits: 1)
        }
        if model.selectedDay != model.today {
            date = model.selectedDay.at(hour: 7, minute: 0)
        }
        // With no weight to start from, type one.
        if model.latestWeighIn == nil { focused = true }
    }

    /// The weight typed, while it's one a person could be (the trend's own rule).
    var kg: Double? {
        guard let v = Format.parse(value) else { return nil }
        let kg = model.units.weight.toKilograms(v)
        return Weight.isPlausible(kg: kg) ? kg : nil
    }
}
