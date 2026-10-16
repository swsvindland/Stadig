import SwiftUI
import FoodDatabase
import FoodIntelligence
import NutritionEngine
import SystemCore

/// Point at a barcode; the food opens with the usual portion ready to add. Codes the catalog
/// doesn't know become a food from the label, read live as the camera moves over it (or from a
/// photo), kept for next time.
struct BarcodeLogView: View {
    @Environment(AppModel.self) private var model
    @Binding var portion: PortionRequest?
    @Binding var mode: LogMode
    @State private var scanning = true
    @State private var manual = ""
    @State private var missing: String?
    @State private var capturingLabel = false
    @State private var readingLabel = false
    @State private var label: LabelResult?
    @State private var error: String?
    /// A supplement the scan found: taken from here, or added to the stack.
    @State private var supplement: Supplement?
    /// A fresh live scan each time one is returned to.
    @State private var scanID = UUID()

    var body: some View {
        Group {
            if let supplement {
                SupplementFoundView(supplement: supplement) {
                    self.supplement = nil
                    scanning = true
                }
            } else if let label {
                LabelReviewView(result: label, barcode: missing) { food in
                    portion = PortionRequest(food: food, source: .label, closeAfterAdd: true)
                }
            } else if readingLabel {
                ProgressView("Reading the label…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let missing {
                notFound(missing)
            } else if LiveLabelScanner.isAvailable && scanning {
                LiveLabelScanner(kind: .food, lookup: lookup) { outcome in finish(outcome) }
                    .id(scanID)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Menu {
                                Button("Type the barcode", systemImage: "keyboard") { scanning = false }
                                Button("Photograph the label", systemImage: "camera") { capturingLabel = true }
                                Button("Search by name", systemImage: "magnifyingglass") { mode = .search }
                            } label: {
                                Image(systemName: "ellipsis")
                            }
                            .accessibilityLabel("Other ways")
                        }
                    }
            } else {
                manualEntry
            }
        }
        .navigationTitle("Scan")
        // Back from the portion: scan the next thing.
        .onChange(of: portion) { _, now in if now == nil { scanID = UUID() } }
        .fullScreenCover(isPresented: $capturingLabel) {
            CameraPicker { image in
                capturingLabel = false
                if let image { read(image) }
            }
            .ignoresSafeArea()
        }
    }

    var manualEntry: some View {
        Form {
            Section {
                TextField("Barcode number", text: $manual)
                    .keyboardType(.numberPad)
                    .font(.title3.monospacedDigit())
                    .onSubmit { handle(manual) }
                Button("Look up") { handle(manual) }.disabled(manual.count < 6)
            } footer: {
                if !LiveCamera.isAvailable { Text("The camera scanner isn't available here, so type the digits under the barcode.") }
            }
        }
    }

    func notFound(_ code: String) -> some View {
        ContentUnavailableView {
            Label("Not in the food database", systemImage: "barcode")
        } description: {
            Text("Photograph the nutrition label and it's saved as your own food, so this barcode works next time.")
        } actions: {
            if CameraPicker.isAvailable {
                Button("Photograph the label") { capturingLabel = true }.primaryAction()
            }
            Button("Search by name") { mode = .search }
            Button("Scan again") {
                missing = nil
                scanning = true
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
        }
    }

    func handle(_ code: String, symbology: Barcode.Symbology? = nil) {
        let digits = code.filter(\.isNumber)
        guard !digits.isEmpty else { return }
        if let outcome = lookup(digits, symbology) {
            finish(outcome)
        } else {
            missing = digits
        }
    }

    /// What a barcode is: the person's supplement, a supplement label, or a food.
    func lookup(_ digits: String, _ symbology: Barcode.Symbology?) -> LiveScanOutcome? {
        let food = model.food(barcode: digits, symbology: symbology)
        if let own = model.ownSupplement(barcode: digits, symbology: symbology) { return .supplement(own) }
        if let facts = model.supplementFacts(barcode: digits, symbology: symbology), model.isSupplement(facts, food: food) {
            return .supplement(Supplement(facts: facts))
        }
        return food.map(LiveScanOutcome.food)
    }

    func finish(_ outcome: LiveScanOutcome) {
        switch outcome {
        case .food(let food):
            portion = PortionRequest(food: food, source: .barcode, closeAfterAdd: true)
        case .supplement(let found):
            supplement = found
        case .label(let result, let barcode):
            missing = barcode
            label = result
        case .supplementLabel(let facts, _):
            supplement = Supplement(facts: facts)
        }
    }

    func read(_ image: UIImage) {
        guard let cg = image.prepared(maxDimension: 2000) else { return }
        readingLabel = true
        Task {
            defer { readingLabel = false }
            do {
                let result = try await model.ai.readLabel(photo: cg)
                if result.reading == nil {
                    error = "Couldn't read that label. Try again flat and in good light, or search by name."
                } else {
                    label = result
                }
            } catch {
                self.error = MealAIMessages.text(for: error)
            }
        }
    }
}

/// The numbers read from a label, to check before saving as a food.
struct LabelReviewView: View {
    @Environment(AppModel.self) private var model
    let result: LabelResult
    let barcode: String?
    let saved: (Food) -> Void
    @State private var name = ""
    @State private var brand = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""

    var body: some View {
        Form {
            Section("Food") {
                TextField("Name", text: $name)
                TextField("Brand", text: $brand)
            }
            Section {
                field("Calories", $kcal, "kcal")
                field("Protein", $protein, "g")
                field("Carbs", $carbs, "g")
                field("Fat", $fat, "g")
            } header: {
                Text(servingTitle)
            } footer: {
                Text(checkNote)
            }
        }
        .navigationTitle("Label")
        .safeAreaInset(edge: .bottom) {
            Button {
                save()
            } label: {
                Text("Save food").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .primaryAction()
            .padding()
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Double(kcal) == nil)
        }
        .onAppear {
            name = result.suggestedName ?? ""
            brand = result.brand ?? ""
            if let n = result.reading?.nutrients {
                kcal = Format.number(n.kcal, digits: 0)
                protein = Format.number(n.protein)
                carbs = Format.number(n.carbs)
                fat = Format.number(n.fat)
            }
        }
    }

    /// What to double-check, in words.
    var checkNote: String {
        guard let reading = result.reading else { return "Check the numbers against the label before saving." }
        var notes: [String] = []
        let core = ["kcal": "calories", "protein": "protein", "carbs": "carbs", "fat": "fat"]
        let missing = reading.missing.compactMap { core[$0] }
        if !missing.isEmpty { notes.append("Couldn't read \(missing.joined(separator: ", ")); fill \(missing.count == 1 ? "it" : "them") in from the label.") }
        if reading.estimatedCalories { notes.append("Calories were worked out from fat, carbs and protein.") }
        if reading.warnings.contains(.caloriesMismatch) { notes.append("Calories don't add up from the macros: one number may be misread.") }
        if reading.warnings.contains(.partOverTotal) { notes.append("A part is more than its total (like sugars over carbs): check those lines.") }
        notes.append("Check the numbers against the label before saving.")
        return notes.joined(separator: " ")
    }

    var servingTitle: String {
        guard let reading = result.reading else { return "Per serving" }
        if let label = reading.servingLabel { return "Per serving (\(label))" }
        if let g = reading.servingGrams { return "Per \(Format.number(g)) g" }
        if let ml = reading.servingMilliliters { return "Per \(Format.number(ml)) ml" }
        return "Per serving"
    }

    func field(_ title: String, _ text: Binding<String>, _ unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
            Text(unit).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
        }
    }

    func save() {
        guard var reading = result.reading else { return }
        func value(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        reading.nutrients.kcal = value(kcal)
        reading.nutrients.protein = value(protein)
        reading.nutrients.carbs = value(carbs)
        reading.nutrients.fat = value(fat)
        let food = reading.food(name: name.trimmingCharacters(in: .whitespaces),
                                brand: brand.trimmingCharacters(in: .whitespaces).isEmpty ? nil : brand, barcode: barcode)
        saved(model.save(customFood: food))
    }
}

/// A scanned supplement: one dose now if it's in the stack, or added to it.
struct SupplementFoundView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let supplement: Supplement
    let scanAgain: () -> Void
    @State private var adding = false

    var body: some View {
        let own = model.supplements.contains { $0.id == supplement.id }
        ContentUnavailableView {
            Label(supplement.name, systemImage: supplement.facts.form.symbol)
        } description: {
            Text([supplement.facts.brand, own ? supplement.scheduleLabel : "A supplement: add it to your stack to tick it off each day."]
                .compactMap { $0 }.joined(separator: "\n"))
        } actions: {
            if own {
                Button("Take \(supplement.facts.amountLabel(supplement.doses.first?.count ?? supplement.facts.servingCount)) now") {
                    model.takeExtra(supplement)
                    dismiss()
                }
                .primaryAction()
                Button("Edit") { adding = true }
            } else {
                Button("Add to my supplements") { adding = true }.primaryAction()
            }
            Button("Scan again", action: scanAgain)
        }
        .navigationTitle("Supplement")
        .sheet(isPresented: $adding) {
            NavigationStack { SupplementEditor(supplement: supplement, isNew: !own) }
        }
    }
}
