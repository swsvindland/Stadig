import SwiftUI
import FoodDatabase
import NutritionEngine
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
                TextField("Name", text: $name).focused($focus, equals: .name)
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
            .padding()
            .disabled(nutrients.kcal <= 0 && nutrients.protein <= 0)
        }
        .onAppear { focus = .kcal }
    }

    var nutrients: Nutrients {
        func v(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        let p = v(protein), c = v(carbs), f = v(fat)
        let k = v(kcal) > 0 ? v(kcal) : p * 4 + c * 4 + f * 9
        return Nutrients(kcal: k, protein: p, carbs: c, fat: f)
    }

    func row(_ title: String, _ text: Binding<String>, _ unit: String, _ field: Field) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100)
                .focused($focus, equals: field)
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
                            .keyboardType(.decimalPad)
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .onChange(of: countText) { _, text in if let v = FoodUnits.parseCount(text), v > 0 { count = v } }
                        if let food {
                            let units = FoodUnits.units(for: food)
                            Picker("Unit", selection: Binding(get: { unit?.id ?? units.first?.id ?? "" },
                                                              set: { id in unit = units.first { $0.id == id } })) {
                                ForEach(units) { Text($0.label).tag($0.id) }
                            }
                            .labelsHidden()
                        } else {
                            Text("× \(entry.amountLabel)").foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    NutrientSummary(nutrients: nutrients)
                }
                Section {
                    Picker("Meal", selection: $entry.meal) {
                        ForEach(MealSlot.allCases) { Text($0.label).tag($0) }
                    }
                    DatePicker("Time", selection: $entry.date)
                }
                Section {
                    Button("Delete", role: .destructive) {
                        model.delete(entries: [entry.id])
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
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
        if let id = entry.foodID, let found = model.food(id: id) {
            food = found
            let units = FoodUnits.units(for: found)
            unit = units.first { $0.id == entry.unitID } ?? FoodUnits.suggested(for: found).unit
            count = entry.count ?? 1
        } else {
            count = 1
        }
        countText = Format.number(count, digits: 2)
    }

    func save() {
        var updated = entry
        if let food, let unit {
            updated.nutrients = FoodUnits.nutrients(food, count: count, unit: unit)
            updated.amountLabel = FoodUnits.entryLabel(for: food, count: count, unit: unit, estimate: entry.isEstimate)
            updated.grams = FoodUnits.amount(count, unit)
            updated.unitID = unit.id
            updated.count = count
        } else if count != 1 {
            updated.nutrients = entry.nutrients.scaled(count)
            updated.amountLabel = "\(Format.number(count, digits: 2)) × \(entry.amountLabel)"
            updated.grams = entry.grams.map { $0 * count }
        }
        model.update(updated)
    }
}

/// A weigh-in, with the last few to check or ignore.
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
                    HStack {
                        TextField(model.latestWeighIn.map { Format.number(model.units.weight.fromKilograms($0.kg)) } ?? "0.0", text: $value)
                            .keyboardType(.decimalPad)
                            .font(.largeTitle.weight(.semibold).monospacedDigit())
                            .focused($focused)
                        Text(model.units.weight.symbol).font(.title2).foregroundStyle(.secondary)
                    }
                    DatePicker("When", selection: $date, in: ...Date())
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let kg { model.weighIn(kg: kg, date: date) }
                        dismiss()
                    }
                    .disabled(kg == nil)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }

    var kg: Double? {
        guard let v = Double(value.replacingOccurrences(of: ",", with: ".")), v > 20 else { return nil }
        return model.units.weight.toKilograms(v)
    }
}
