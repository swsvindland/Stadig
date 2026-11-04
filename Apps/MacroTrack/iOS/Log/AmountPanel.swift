import FoodDatabase
import NutritionEngine
import SwiftUI
import SystemCore

/// How much of a food: one small panel for adding it and for changing it later. The amount opens
/// selected, so the first key replaces it; the unit is a tap away, and the usual amount's multiples
/// another. It has no navigation of its own: a host gives it a place, and `close` to leave.
struct AmountPanel: View {
    @Environment(AppModel.self) private var model
    let request: AmountRequest
    /// Hands a changed entry back rather than saving it: a food of a saved meal, which only has an amount.
    var saveTo: ((FoodEntry) -> Void)?
    /// Takes the amount chosen for a `.pick`.
    var picked: ((Double, PortionUnit) -> Void)?
    /// The food's numbers were corrected here, for whoever holds a copy of it.
    var foodCorrected: ((Food) -> Void)?
    /// A food was added or an entry saved.
    var finished: () -> Void = {}
    let close: () -> Void

    @State private var amount = AmountEntry(count: 1, unit: nil)
    @State private var food: Food?
    @State private var date = Date()
    @State private var units: [PortionUnit] = []
    /// The amount as it reopened, so a change of time alone saves the entry's own numbers.
    @State private var original: (unitID: String?, count: Double)?
    @State private var editingFood = false
    @State private var showingNutrients = false
    @FocusState private var keysFocused: Bool
    #if os(macOS)
    @FocusState private var fieldFocused: Bool
    @State private var selection: TextSelection?
    #endif

    var entry: FoodEntry? { request.entry }
    var isEditing: Bool { entry != nil }
    /// Choosing an amount for something else: nothing's logged here.
    var isPicking: Bool {
        if case .pick = request.purpose { return true }
        return false
    }
    /// Saved to a meal: the amount is all there is.
    var isMealFood: Bool { saveTo != nil }

    var nutrients: Nutrients {
        let count = amount.count ?? 0
        if let food, let unit = amount.unit { return FoodUnits.nutrients(food, count: count, unit: unit) }
        return entry?.nutrients.scaled(count) ?? .zero
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            ScrollView {
                VStack(spacing: 12) {
                    quantity
                    unitRow
                    choices
                    NutrientSummary(nutrients: nutrients)
                    if isEditing, !isMealFood {
                        timeRow
                        takeRow
                    }
                    if showingNutrients, let food, let unit = amount.unit, let count = amount.count {
                        PortionNutrients(food: food, count: count, unit: unit)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            if Platform.usesAmountKeypad { keypad }
            primary
        }
        .padding(.horizontal)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .focusable(Platform.usesAmountKeypad)
        .focused($keysFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in hardwareKey(press) }
        .onAppear(perform: load)
        .sheet(isPresented: $editingFood) {
            if let food, let unit = amount.unit, let count = amount.count { FoodEditor(food: food, count: count, unit: unit) { use($0) } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("amount.panel")
    }

    var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(food?.name ?? entry?.name ?? "").font(.headline).lineLimit(2)
                if let brand = food?.brand ?? entry?.brand, brand.lowercased() != (food?.name ?? "").lowercased() {
                    Text(brand).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let food {
                if !isMealFood, amount.unit != nil { EditFoodButton { editingFood = true }.buttonStyle(.borderless) }
                if !isEditing, !isPicking { FavoriteButton(foodID: food.id).buttonStyle(.borderless) }
            }
            Button(action: close) {
                Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 30, height: 30).contentShape(.circle)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(isEditing ? "Cancel" : "Close")
            .accessibilityIdentifier(isEditing ? "entryEditor.cancel" : "portion.close")
        }
    }

    @ViewBuilder
    var quantity: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            quantityField
            Text(amount.unit?.label ?? entry.map { "× \($0.amountLabel)" } ?? "")
                .font(.title3).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.insetBackground, in: .rect(cornerRadius: 14))
    }

    @ViewBuilder
    var quantityField: some View {
        #if os(macOS)
        TextField("Amount", text: Binding(get: { amount.text }, set: { amount.type($0) }), selection: $selection)
            .textFieldStyle(.plain)
            .font(.largeTitle.weight(.semibold).monospacedDigit())
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 160)
            .focused($fieldFocused)
            .accessibilityIdentifier("amount.quantity")
            .onSubmit(save)
        #else
        Text(amount.display())
            .font(.largeTitle.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 6)
            .background(amount.isSelected ? Color.accentColor.opacity(0.22) : .clear, in: .rect(cornerRadius: 8))
            .accessibilityElement()
            .accessibilityLabel("Amount")
            .accessibilityValue("\(amount.display()) \(amount.unit?.label ?? "")")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: amount.nudge(up: true)
                case .decrement: amount.nudge(up: false)
                @unknown default: break
                }
            }
            .accessibilityIdentifier("amount.quantity")
        #endif
    }

    @ViewBuilder
    var unitRow: some View {
        if units.count > 1 {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(units) { unit in
                        Button(unit.label) { amount.change(to: unit) }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .choiceTint(amount.unit?.id == unit.id)
                            .accessibilityAddTraits(amount.unit?.id == unit.id ? .isSelected : [])
                            .accessibilityIdentifier("portion.unit")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    var choices: some View {
        HStack(spacing: 8) {
            if let unit = amount.unit {
                ForEach(AmountChoices.quick(base: amount.base, unit: unit), id: \.self) { value in
                    choice(AmountChoices.label(value, unit: unit), value: value)
                }
            } else {
                ForEach(AmountChoices.multipliers, id: \.self) { value in
                    choice(AmountChoices.label(multiplier: value), value: value)
                }
            }
        }
    }

    func choice(_ title: String, value: Double) -> some View {
        Button(title) { amount.choose(value) }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .choiceTint(amount.count.map { abs($0 - value) < 0.001 } ?? false)
            .accessibilityIdentifier("portion.quick")
    }

    var timeRow: some View {
        HStack {
            DatePicker("Eaten", selection: $date).accessibilityIdentifier("entryEditor.eaten")
            if let entry {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    model.delete(entries: [entry.id])
                    close()
                }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("entryEditor.delete")
            }
        }
    }

    /// Picks the food out on the Log tab to take it somewhere: another day, or an hour's arrow.
    var takeRow: some View {
        HStack(spacing: 8) {
            take("Move", symbol: "arrow.right.circle", intent: .move)
            take("Copy", symbol: "doc.on.doc", intent: .copy)
        }
    }

    func take(_ title: String, symbol: String, intent: LogSelection.Intent) -> some View {
        Button(title, systemImage: symbol) {
            guard let entry else { return }
            model.select(entry, intent: intent)
            close()
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("entryEditor.\(title.lowercased())")
    }

    var keypad: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                digit(1)
                digit(2)
                digit(3)
                fraction("½")
            }
            GridRow {
                digit(4)
                digit(5)
                digit(6)
                fraction("¼")
            }
            GridRow {
                digit(7)
                digit(8)
                digit(9)
                fraction("¾")
            }
            GridRow {
                key(Locale.current.decimalSeparator ?? ".", id: "point", key: .point)
                digit(0)
                key("⌫", id: "delete", key: .delete, label: "Delete")
                fraction("⅓")
            }
        }
    }

    func digit(_ value: Int) -> some View { key("\(value)", id: "\(value)", key: .digit(value)) }

    func fraction(_ glyph: String) -> some View {
        key(glyph, id: glyph, key: .fraction(glyph)).disabled(!(amount.unit?.isCounted ?? true))
    }

    func key(_ title: String, id: String, key: AmountEntry.Key, label: String? = nil) -> some View {
        Button {
            amount.press(key)
        } label: {
            Text(title).font(.title2.weight(.medium)).frame(maxWidth: .infinity, minHeight: 46).contentShape(.rect)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(label ?? title)
        .accessibilityIdentifier("amount.key.\(id)")
    }

    var primary: some View {
        Button(action: save) {
            Text(primaryTitle).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .primaryAction()
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier(isEditing ? "entryEditor.save" : "portion.add")
        .disabled(amount.count == nil)
    }

    var primaryTitle: String {
        if isEditing { return "Save · \(Format.kcal(nutrients.kcal))" }
        if isPicking { return "Use · \(Format.kcal(nutrients.kcal))" }
        return "Add\(LogTime.label(model) == "Now" ? "" : " at \(LogTime.time(model))") · \(Format.kcal(nutrients.kcal))"
    }

    /// The Mac has a field of its own; everywhere else, a keyboard's keys go to the keypad.
    func hardwareKey(_ press: KeyPress) -> KeyPress.Result {
        guard Platform.usesAmountKeypad else { return .ignored }
        switch press.key {
        case .delete, .deleteForward:
            amount.press(.delete)
            return .handled
        case .return:
            if amount.count != nil { save() }
            return .handled
        default:
            break
        }
        if let digit = Int(press.characters), (0...9).contains(digit) {
            amount.press(.digit(digit))
            return .handled
        }
        if press.characters == "." || press.characters == "," {
            amount.press(.point)
            return .handled
        }
        return .ignored
    }

    func load() {
        guard original == nil else { return }
        keysFocused = Platform.usesAmountKeypad
        if let entry {
            date = entry.date
            if let id = entry.foodID, let found = model.food(id: id) {
                food = found
                // In the unit it was logged in while that still holds the amount logged, else the
                // food's basis counting that amount: a catalog update can reorder or reword portions.
                let reopened = FoodUnits.logged(for: found, unitID: entry.unitID, count: entry.count, amount: entry.grams)
                amount = AmountEntry(count: reopened.count, unit: reopened.unit)
            }
        } else if case .pick(_, let count, let unit) = request.purpose {
            food = request.food
            amount = AmountEntry(count: count, unit: unit)
        } else if let food = request.food {
            self.food = food
            let personal = model.personalFood(food.id)
            let suggestion = FoodUnits.suggested(
                for: food, lastUnitID: personal?.lastUnitID, lastCount: personal?.lastCount, lastAmount: personal?.lastAmount)
            amount = AmountEntry(count: suggestion.count, unit: suggestion.unit)
        }
        original = (amount.unit?.id, amount.count ?? 1)
        // The one it opened in, then the food's own order, which starts with its natural portions.
        if let food {
            let all = FoodUnits.units(for: food)
            units = amount.unit.map { current in [current] + all.filter { $0.id != current.id } } ?? all
        }
        #if os(macOS)
        fieldFocused = true
        selection = TextSelection(range: amount.text.startIndex..<amount.text.endIndex)
        #endif
    }

    /// Whether the amount was changed, rather than only the time.
    var amountChanged: Bool {
        guard let original else { return true }
        return amount.unit?.id != original.unitID || abs((amount.count ?? 0) - original.count) > 1e-9
    }

    func save() {
        guard let count = amount.count else { return }
        if let entry {
            // A change of time alone keeps the entry's own numbers.
            var updated = amountChanged ? model.rescaled(entry, food: food, unit: amount.unit, count: count) : entry
            updated.date = date
            if let saveTo { saveTo(updated) } else { model.update(updated) }
        } else if isPicking, let unit = amount.unit {
            picked?(count, unit)
        } else if let food, let unit = amount.unit, case .add(let source) = request.purpose {
            model.log([model.entry(for: food, count: count, unit: unit, source: source)])
        }
        finished()
        close()
    }

    /// The food as corrected (or the catalog's again), at the same amount: its units are the same,
    /// but one counted in calories holds a different amount now.
    func use(_ corrected: Food) {
        food = corrected
        if let id = amount.unit?.id, let unit = FoodUnits.units(for: corrected).first(where: { $0.id == id }) { amount.change(to: unit) }
        foodCorrected?(corrected)
    }
}

extension View {
    /// A small sheet for the amount panel: all of it in view on a phone, with room to grow, and
    /// room for the time when it's changing an entry.
    func amountSheet(editing: Bool) -> some View {
        presentationDetents([.height(editing ? 716 : 620), .large])
            .presentationDragIndicator(.visible)
            .macSheetSize(width: 440, height: 520)
    }
}
