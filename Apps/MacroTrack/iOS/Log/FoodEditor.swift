import FoodDatabase
import NutritionEngine
import SwiftUI
import SystemCore

/// A food's name and numbers, corrected to what the package in front of the person says. The
/// numbers are typed for the amount on screen; a catalog food keeps them as the person's
/// correction (its barcode, searches and Log Again use them from then on) and one of their own
/// foods is changed in place. Foods already logged keep theirs.
struct FoodEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let food: Food
    /// The amount the numbers are for.
    let count: Double
    let unit: PortionUnit
    /// The food as saved, or the catalog's once a correction is taken away.
    let saved: (Food) -> Void
    @State private var name = ""
    @State private var brand = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    /// The fields as they opened: saved unchanged, nothing is corrected.
    @State private var opened: [String]?

    init(food: Food, count: Double, unit: PortionUnit, saved: @escaping (Food) -> Void) {
        self.food = food
        let amount = Self.amount(food, count: count, unit: unit)
        self.count = amount.count
        self.unit = amount.unit
        self.saved = saved
    }

    /// The amount on screen, unless it's counted in calories, which are what's changing: then 100 g
    /// (or ml), or one serving.
    static func amount(_ food: Food, count: Double, unit: PortionUnit) -> (count: Double, unit: PortionUnit) {
        guard unit.kind == .energy || count <= 0, let basis = FoodUnits.units(for: food).first(where: { $0.id == food.basis.rawValue }) else {
            return (count, unit)
        }
        return (food.basis == .serving ? 1 : 100, basis)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    TextField("Name", text: $name).accessibilityIdentifier("foodEditor.name")
                    TextField("Brand", text: $brand).accessibilityIdentifier("foodEditor.brand")
                }
                Section {
                    field("Calories", $kcal, "kcal", "foodEditor.kcal")
                    field("Protein", $protein, "g", "foodEditor.protein")
                    field("Carbs", $carbs, "g", "foodEditor.carbs")
                    field("Fat", $fat, "g", "foodEditor.fat")
                } header: {
                    Text("Per \(FoodUnits.entryLabel(for: food, count: count, unit: unit))")
                } footer: {
                    Text(note)
                }
                if model.isCorrected(food.id) {
                    Section {
                        Button("Use the numbers from \(Self.catalogName(food))", role: .destructive) {
                            if let original = model.removeCorrection(of: food.id) { saved(original) }
                            dismiss()
                        }
                        .accessibilityIdentifier("foodEditor.removeCorrection")
                    } footer: {
                        Text("Goes back to the numbers the food database has. Foods already logged keep theirs.")
                    }
                }
            }
            .navigationTitle("Edit Food")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("foodEditor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(corrected == nil)
                        .accessibilityIdentifier("foodEditor.save")
                }
            }
            .onAppear(perform: fill)
        }
        .macSheetSize(width: 460, height: 560)
    }

    var note: String {
        if CustomFoodRecord.recordID(fromFoodID: food.id) != nil {
            return "Type what the package says for this amount. Foods already logged keep their numbers."
        }
        return
            "Type what the package says for this amount. They're kept as your numbers for this food: its barcode, searches and Log Again use them from now on. Foods already logged keep theirs."
    }

    /// "USDA", "Open Food Facts": whose numbers a correction stands in for.
    static func catalogName(_ food: Food) -> String {
        switch food.source {
        case .usda: "USDA"
        case .off: "Open Food Facts"
        case .custom, .recipe, .label: "the food database"
        }
    }

    func field(_ title: String, _ text: Binding<String>, _ unit: String, _ identifier: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text)
                .fieldKeyboard(.decimal)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                .accessibilityIdentifier(identifier)
            Text(unit).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
        }
    }

    var fields: [String] { [name, brand, kcal, protein, carbs, fat] }

    /// The food with what's typed; nil without a name or calories, or with a number that isn't one.
    var corrected: Food? {
        let typedName = name.trimmingCharacters(in: .whitespaces)
        let typedBrand = brand.trimmingCharacters(in: .whitespaces)
        // A macro left blank is none, as on a label that doesn't list it.
        func number(_ text: String) -> Double? { text.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : Format.parse(text) }
        guard !typedName.isEmpty, let energy = Format.parse(kcal), let p = number(protein), let c = number(carbs), let f = number(fat),
            var edited = food.correcting(kcal: energy, protein: p, carbs: c, fat: f, count: count, unit: unit)
        else { return nil }
        edited.name = typedName
        edited.brand = typedBrand.isEmpty ? nil : typedBrand
        return edited
    }

    func fill() {
        // Once: a field typed in survives the view appearing again.
        guard opened == nil else { return }
        let n = FoodUnits.nutrients(food, count: count, unit: unit)
        name = food.name
        brand = food.brand ?? ""
        kcal = Format.editable(n.kcal, digits: 0)
        protein = Format.editable(n.protein, digits: 1)
        carbs = Format.editable(n.carbs, digits: 1)
        fat = Format.editable(n.fat, digits: 1)
        opened = fields
    }

    func save() {
        // Unchanged, the numbers as they opened (rounded for typing) aren't made a correction.
        guard fields != opened else {
            dismiss()
            return
        }
        guard let corrected else { return }
        saved(model.saveCorrection(corrected))
        dismiss()
    }
}

/// The pencil beside a food's star: its numbers, corrected to the package's.
struct EditFoodButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "pencil")
        }
        .accessibilityLabel("Edit this food's numbers")
        .accessibilityIdentifier("portion.editFood")
        .help("Edit this food's numbers")
    }
}
