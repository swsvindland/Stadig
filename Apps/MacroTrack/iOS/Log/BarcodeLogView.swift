import FoodDatabase
import FoodIntelligence
import NutritionEngine
import SwiftUI
import SystemCore

/// Point at a barcode; the food lands as a card under the camera with the usual portion on a ruler,
/// logged with one tap while the camera keeps looking for the next (the card opens the full amount
/// for units and the rest). Codes the catalog doesn't know become a food from the label, read live
/// as the camera moves over it (or from a photo), kept for next time.
struct BarcodeLogView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    /// A food a barcode found, with the amount on its card's ruler.
    @State private var found: FoundFood?
    /// What the last food logged from a card left, while the camera looks for the next.
    @State private var logged: String?

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
            } else if LiveScan.isAvailable && scanning {
                LiveLabelScanner(
                    kind: .food, lookup: lookup, finish: finish,
                    menu: {
                        // Over the camera's corner, the light at the other.
                        Button("Type the barcode", systemImage: "keyboard") { scanning = false }
                        Button("Photograph the label", systemImage: "camera") { capturingLabel = true }
                        Button("Search by name", systemImage: "magnifyingglass") { session.backToSearch() }
                    },
                    foot: { reading in foot(reading: reading) }
                )
                .id(scanID)
            } else {
                manualEntry
            }
        }
        // Back from the portion: scan the next thing.
        .onChange(of: session.portion) { _, now in if now == nil { scanID = UUID() } }
        .animation(.snappy, value: found?.food.id)
        .animation(.snappy, value: logged)
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
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .onSubmit { handle(manual) }
                    .accessibilityIdentifier("barcode.number")
                Button("Look up") { handle(manual) }.disabled(manual.count < 6)
                    .accessibilityIdentifier("barcode.lookUp")
            } footer: {
                if !LiveScan.isAvailable { Text(ScanWords.typeTheBarcode) }
            }
            .inkRows()
            // Without the live scanner, a label photo is the other way in: a food with no barcode, or one
            // the catalogs don't know.
            if !LiveScan.isAvailable {
                Section {
                    labelPhotoChoices
                } footer: {
                    Text("Its numbers are read for you to check, and it's kept as your own food.")
                }
                .inkRows()
            }
        }
        .inkForm()
    }

    // MARK: Under the camera

    /// The found food's card, or what the last one left, then the shutter for a plate. While the
    /// label's card is up the shutter steps aside: a label's being read, not a plate.
    @ViewBuilder
    func foot(reading: Bool) -> some View {
        if let found {
            FoundFoodCard(
                found: Binding(get: { self.found ?? found }, set: { self.found = $0 }),
                open: { session.portion = .add(found.food, source: .barcode) },
                log: { log(found) },
                scanAgain: {
                    self.found = nil
                    scanID = UUID()
                }
            )
            .transition(.rise(reduceMotion: reduceMotion))
        } else if let logged, !reading {
            HStack(spacing: 12) {
                Image(systemName: "checkmark").font(.body.weight(.bold)).foregroundStyle(Ink.good)
                VStack(alignment: .leading, spacing: 1) {
                    Text(logged).font(.headline).foregroundStyle(Ink.text)
                    Text("Still scanning. Point at the next one.").font(.caption).foregroundStyle(Ink.text3)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Color.cardBackground, in: .rect(cornerRadius: 26, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("scan.logged")
            .transition(.opacity)
        }
        if found == nil, !reading { shutter }
    }

    /// A photo of the plate, where the device's model can read one; else what to point at.
    var shutter: some View {
        VStack(spacing: 8) {
            if model.ai.canSeePhotos {
                Button {
                    session.mode = .camera
                } label: {
                    Circle().fill(Ink.text).frame(width: 64, height: 64)
                        .padding(4)
                        .overlay(Circle().stroke(Ink.text, lineWidth: 2))
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .hoverHighlight()
                .accessibilityLabel("Snap your plate")
                .accessibilityIdentifier("scan.plate")
            }
            Text(model.ai.canSeePhotos ? "Point at a barcode or label, or snap your plate" : "Point at a barcode or the Nutrition Facts")
                .font(.caption).foregroundStyle(Ink.text3)
        }
        .frame(maxWidth: .infinity)
    }

    func log(_ found: FoundFood) {
        guard model.log([model.entry(for: found.food, count: found.count, unit: found.unit, source: .barcode)]) else { return }
        let left = model.analysis?.targets.kcal.map { $0 - model.dayIntake(on: model.selectedDay).eaten.kcal }
        logged = left.map { $0 >= 0 ? "Logged. \(Format.whole($0)) kcal left" : "Logged. \(Format.whole(-$0)) kcal over" } ?? "Logged"
        self.found = nil
        scanID = UUID()
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
            Button(LiveScan.isAvailable ? "Scan again" : "Type another barcode") {
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
            // The same package again, while its card's up: the amount on the ruler stays.
            guard found?.food.id != food.id else { return }
            let draft = model.draft(for: .add(food, source: .barcode))
            // Typed rather than scanned there's no camera to put a card under: the amount opens.
            guard LiveScan.isAvailable, scanning, let unit = draft.amount.unit, let count = draft.amount.count else {
                session.portion = .add(food, source: .barcode)
                return
            }
            logged = nil
            found = FoundFood(food: food, count: count, unit: unit)
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
            Section {
                FoodNameFields(name: $name, brand: $brand, identifier: "labelFood")
            } header: {
                SectionEyebrow("Food from its label")
            }
            .inkRows()
            Section {
                NumberFieldRow(title: "Calories", text: $kcal, unit: "kcal")
                NumberFieldRow(title: "Protein", text: $protein, unit: "g")
                NumberFieldRow(title: "Carbs", text: $carbs, unit: "g")
                NumberFieldRow(title: "Fat", text: $fat, unit: "g")
            } header: {
                SectionEyebrow(servingTitle)
            } footer: {
                Text(checkNote)
            }
            .inkRows()
        }
        .inkForm()
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
        .sheet(isPresented: $adding) {
            NavigationStack { SupplementEditor(supplement: supplement, isNew: !own, place: .sheet) }.macSheetSize(width: 520, height: 640)
        }
    }
}

/// A food a barcode found, at the amount its card's ruler is on.
struct FoundFood: Equatable {
    var food: Food
    var count: Double
    var unit: PortionUnit
    /// The usual amount, the ruler's scale.
    var usual: Double

    init(food: Food, count: Double, unit: PortionUnit) {
        self.food = food
        self.count = count
        self.unit = unit
        usual = count
    }
}

/// The design's found product, under the camera: the food with its calories and protein for the
/// amount, a ruler to drag the amount, and Log. The food's row opens the full amount (units, the
/// keypad, its numbers); the arrow scans on without it.
struct FoundFoodCard: View {
    @Environment(AppModel.self) private var model
    @Binding var found: FoundFood
    let open: () -> Void
    let log: () -> Void
    let scanAgain: () -> Void

    var body: some View {
        let n = FoodUnits.nutrients(found.food, count: found.count, unit: found.unit)
        let step = FoodUnits.step(for: found.unit)
        let amount = FoodUnits.label(count: found.count, unit: found.unit)
        VStack(alignment: .leading, spacing: 12) {
            Button(action: open) {
                HStack(spacing: 12) {
                    FoodTile(name: found.food.name, size: 40, fill: Ink.raised)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(found.food.name).font(.headline).foregroundStyle(Ink.text).lineLimit(1)
                        Text(caption).font(.caption).foregroundStyle(Ink.text3).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Format.whole(n.kcal)).numeral(20).foregroundStyle(Ink.text).contentTransition(.numericText())
                        Text("\(Format.whole(n.protein)) P").font(.caption.weight(.medium).monospacedDigit()).foregroundStyle(Ink.protein)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens its amount, units and nutrients")
            .accessibilityIdentifier("scan.found")
            AmountRuler(
                value: found.count, most: max(found.usual * 2.5, step * 10), step: step, label: amount
            ) { found.count = $0 }
            HStack(spacing: 8) {
                Button(action: scanAgain) {
                    Image(systemName: "arrow.counterclockwise").frame(width: 24)
                }
                .buttonStyle(.ghost)
                .controlSize(.large)
                .accessibilityLabel("Scan something else")
                .accessibilityIdentifier("scan.again")
                Button(action: log) {
                    Text("Log \(amount)\(LogTime.label(model) == "Now" ? "" : " at \(LogTime.time(model))")").lineLimit(1).frame(maxWidth: .infinity)
                }
                .primaryAction().controlSize(.large)
                .accessibilityIdentifier("scan.log")
            }
        }
        .padding(14)
        .background(Color.cardBackground, in: .rect(cornerRadius: 26, style: .continuous))
        .sensoryFeedback(.selection, trigger: found.count)
    }

    /// "Arla · 1 container (150 g) · logged before".
    var caption: String {
        let brand = found.food.brand.flatMap { $0.lowercased() == found.food.name.lowercased() ? nil : $0 }
        let before = model.personalFood(found.food.id) != nil ? "logged before" : nil
        return [brand, FoodUnits.label(count: FoodUnits.convert(found.usual, from: found.unit, to: found.unit), unit: found.unit), before]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
