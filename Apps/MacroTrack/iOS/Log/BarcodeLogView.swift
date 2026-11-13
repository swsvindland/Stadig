import FoodDatabase
import FoodIntelligence
import NutritionEngine
import SwiftUI
import SystemCore

/// Point at a barcode; the food opens with the usual portion ready to add. Codes the catalog
/// doesn't know become a food from the label, read live as the camera moves over it (or from a
/// photo), kept for next time.
struct BarcodeLogView: View {
    @Environment(AppModel.self) private var model
    let session: LoggerSession
    /// A food's open over the pane: no camera behind it, reading what it sees for nobody.
    var covered = false
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
                SupplementFoundView(supplement: supplement, took: session.backToSearch) {
                    self.supplement = nil
                    scanning = true
                }
            } else if let label {
                LabelReviewView(result: label, barcode: missing) { food in
                    session.portion = .add(food, source: .label)
                }
            } else if readingLabel {
                ProgressView("Reading the label…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let missing {
                notFound(missing)
            } else if covered {
                Color.clear
            } else if LiveLabelScanner.isAvailable && scanning {
                LiveLabelScanner(kind: .food, lookup: lookup) { outcome in finish(outcome) }
                    .id(scanID)
                    // In the bar, as the supplement scanner has it: over the camera it sat on the
                    // start of the scanner's instructions. The light is at the bar's other end.
                    .toolbar {
                        ToolbarItem(placement: .barLeading) {
                            Menu {
                                Button("Type the barcode", systemImage: "keyboard") { scanning = false }
                                Button("Photograph the label", systemImage: "camera") { capturingLabel = true }
                                Button("Search by name", systemImage: "magnifyingglass") { session.backToSearch() }
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
        .navigationTitle(LiveLabelScanner.isAvailable ? "Scan" : "Barcode")
        // Back from the portion: scan the next thing.
        .onChange(of: session.portion) { _, now in if now == nil { scanID = UUID() } }
        // Wherever the read was started from (the scanner's menu has no message of its own).
        .alert("Couldn't read the label", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
        .cameraCapture(isPresented: $capturingLabel) { photo in
            if let photo { read { await photo.prepared(maxDimension: 2000) } }
        }
    }

    var manualEntry: some View {
        Form {
            Section {
                TextField("Barcode number", text: $manual)
                    .fieldKeyboard(.number)
                    .font(.title3.monospacedDigit())
                    .onSubmit { handle(manual) }
                    .accessibilityIdentifier("barcode.number")
                Button("Look up") { handle(manual) }.disabled(manual.count < 6)
                    .accessibilityIdentifier("barcode.lookUp")
            } footer: {
                if !LiveLabelScanner.isAvailable { Text(ScanWords.typeTheBarcode) }
            }
            // Without the live scanner, a label photo is the other way in: a food with no barcode, or one
            // the catalogs don't know.
            if !LiveLabelScanner.isAvailable {
                Section {
                    labelPhotoChoices
                } footer: {
                    Text("Its numbers are read for you to check, and it's kept as your own food.")
                }
            }
        }
    }

    /// A photo of the nutrition label, from Photos or a file, read the way a camera's is.
    var labelPhotoChoices: some View {
        PhotoChoices(photosTitle: "Read a label from a photo", fileTitle: "Read a label from a file…") { load in
            read {
                guard let data = try await load() else { return nil }
                return await PhotoInput.prepare(data, maxDimension: 2000)
            }
        }
    }

    func notFound(_ code: String) -> some View {
        ContentUnavailableView {
            Label("Not in the food database", systemImage: "barcode")
        } description: {
            Text(
                "\(Camera.isAvailable ? "Photograph" : "Choose a photo of") the nutrition label and it's saved as your own food, so this barcode works next time."
            )
        } actions: {
            if Camera.isAvailable {
                Button("Photograph the label") { capturingLabel = true }.primaryAction()
            } else {
                labelPhotoChoices
            }
            Button("Search by name") { session.backToSearch() }
            Button(LiveLabelScanner.isAvailable ? "Scan again" : "Type another barcode") {
                missing = nil
                error = nil
                scanning = true
            }
        }
    }

    func handle(_ code: String, symbology: Barcode.Symbology? = nil) {
        let digits = code.filter(\.isNumber)
        guard !digits.isEmpty else { return }
        error = nil
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
            session.portion = .add(food, source: .barcode)
        case .supplement(let found):
            supplement = found
        case .label(let result, let barcode):
            missing = barcode
            label = result
        case .supplementLabel(let facts, _):
            supplement = Supplement(facts: facts)
        }
    }

    /// Reads a photo of a label: loaded and downsampled off the main thread, then parsed.
    func read(_ photo: @escaping () async throws -> CGImage?) {
        error = nil
        readingLabel = true
        Task {
            defer { readingLabel = false }
            let prepared: CGImage?
            do {
                prepared = try await photo()
            } catch {
                self.error = "Couldn't load that photo. If it's in iCloud, check your connection and try again."
                return
            }
            guard let cg = prepared else {
                error = "Couldn't open that photo. Try again."
                return
            }
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
    @State private var filled = false
    /// The food a Save made, and the fields it was made from: back from the portion and saved
    /// again unchanged, it's the same food rather than a second copy.
    @State private var lastSave: (food: Food, fields: [String])?

    var body: some View {
        Form {
            Section("Food") {
                FoodNameFields(name: $name, brand: $brand, identifier: "labelFood")
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
                Text("Save food").font(.headline).frame(maxWidth: .infinity)
            }
            .primaryAction().controlSize(.large)
            .padding()
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Format.parse(kcal) == nil)
        }
        .onAppear {
            // Once: this view appears again on the way back from the portion, and the person's
            // corrections must survive that.
            guard !filled else { return }
            filled = true
            name = result.suggestedName ?? ""
            brand = result.brand ?? ""
            if let n = result.reading?.nutrients {
                kcal = Format.editable(n.kcal, digits: 0)
                protein = Format.editable(n.protein, digits: 1)
                carbs = Format.editable(n.carbs, digits: 1)
                fat = Format.editable(n.fat, digits: 1)
            }
        }
    }

    /// What to double-check, in words.
    var checkNote: String {
        guard let reading = result.reading else { return "Check the numbers against the label before saving." }
        var notes: [String] = []
        let core = ["kcal": "calories", "protein": "protein", "carbs": "carbs", "fat": "fat"]
        let missing = reading.missing.compactMap { core[$0] }
        if !missing.isEmpty {
            notes.append("Couldn't read \(missing.joined(separator: ", ")); fill \(missing.count == 1 ? "it" : "them") in from the label.")
        }
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
            TextField("0", text: text, prompt: Text("0")).labelsHidden().fieldKeyboard(.decimal).multilineTextAlignment(.trailing).frame(width: 90)
            Text(unit).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
        }
    }

    func save() {
        guard var reading = result.reading else { return }
        let fields = [name, brand, kcal, protein, carbs, fat]
        if let lastSave, lastSave.fields == fields {
            saved(lastSave.food)
            return
        }
        func value(_ s: String) -> Double { Format.parse(s) ?? 0 }
        reading.nutrients.kcal = value(kcal)
        reading.nutrients.protein = value(protein)
        reading.nutrients.carbs = value(carbs)
        reading.nutrients.fat = value(fat)
        let food = reading.food(
            name: name.trimmingCharacters(in: .whitespaces),
            brand: brand.trimmingCharacters(in: .whitespaces).isEmpty ? nil : brand, barcode: barcode)
        // Corrected after an earlier save: the same food, updated.
        let kept = model.save(customFood: food, replacing: lastSave.flatMap { CustomFoodRecord.recordID(fromFoodID: $0.food.id) })
        lastSave = (kept, fields)
        saved(kept)
    }
}

/// A scanned supplement: one dose now if it's in the stack, or added to it.
struct SupplementFoundView: View {
    @Environment(AppModel.self) private var model
    let supplement: Supplement
    /// A dose was taken. The logger goes back to its search, as with a food, whichever host it's in.
    let took: () -> Void
    let scanAgain: () -> Void
    @State private var adding = false

    var body: some View {
        let own = model.supplements.contains { $0.id == supplement.id }
        ContentUnavailableView {
            Label(supplement.name, systemImage: supplement.facts.form.symbol)
        } description: {
            Text(
                [supplement.facts.brand, own ? supplement.scheduleLabel : "A supplement: add it to your stack to tick it off each day."]
                    .compactMap { $0 }.joined(separator: "\n"))
        } actions: {
            if own {
                Button("Take \(supplement.facts.amountLabel(supplement.doses.first?.count ?? supplement.facts.servingCount)) now") {
                    model.takeExtra(supplement)
                    took()
                }
                .primaryAction()
                .accessibilityIdentifier("supplementFound.take")
                Button("Edit") { adding = true }
            } else {
                Button("Add to my supplements") { adding = true }.primaryAction()
            }
            Button("Scan again", action: scanAgain)
        }
        .navigationTitle("Supplement")
        .sheet(isPresented: $adding) {
            NavigationStack { SupplementEditor(supplement: supplement, isNew: !own) }.macSheetSize(width: 520, height: 640)
        }
    }
}
