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
    /// Whether Move and Copy are offered. They hand the food to the Log tab's bar and hours, so
    /// they're no use over the logger, where neither can be reached.
    var canTake = true
    /// Takes the amount chosen for a `.pick`.
    var picked: ((Double, PortionUnit) -> Void)?
    /// The food's numbers were corrected here, for whoever holds a copy of it.
    var foodCorrected: ((Food) -> Void)?
    /// A food was added or an entry saved.
    var finished: () -> Void = {}
    let close: () -> Void

    @State private var draft = AmountDraft()
    @State private var date = Date()
    @State private var editingFood = false
    @FocusState private var keysFocused: Bool
    #if os(macOS)
    @FocusState private var fieldFocused: Bool
    @State private var selection: TextSelection?
    #endif

    private var amount: AmountEntry {
        get { draft.amount }
        nonmutating set { draft.amount = newValue }
    }
    var food: Food? { draft.food }
    var units: [PortionUnit] { draft.units }
    var nutrients: Nutrients { draft.nutrients }
    var entry: FoodEntry? { request.entry }
    var isEditing: Bool { entry != nil }
    /// Choosing an amount for something else: nothing's logged here.
    var isPicking: Bool {
        if case .pick = request.purpose { return true }
        return false
    }
    /// Saved to a meal: the amount is all there is.
    var isMealFood: Bool { saveTo != nil }

    var body: some View {
        VStack(spacing: 14) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    quantity
                    if let unit = amount.unit {
                        let count = amount.count ?? 0
                        AmountRuler(
                            value: count, most: max(amount.base * 2.5, FoodUnits.step(for: unit) * 10), step: FoodUnits.step(for: unit),
                            label: FoodUnits.label(count: count, unit: unit)
                        ) { amount.choose($0) }
                    }
                    choices
                    unitRow
                    numbers
                    if isEditing, !isMealFood {
                        timeRow
                        if canTake { takeRow }
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            if Platform.usesAmountKeypad { keypad }
            primary
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 10)
        .inkGround()
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

    /// The food as the design's open card has it: its marker, name and where its numbers are from,
    /// with its round buttons beside.
    var header: some View {
        HStack(alignment: .top, spacing: 8) {
            Group {
                if let food {
                    FoodHeader(food: food, corrected: model.isCorrected(food.id), nameFont: .headline).lineLimit(2)
                } else if let entry {
                    HStack(alignment: .top, spacing: 12) {
                        FoodTile(name: entry.name, size: TileSize.header, fill: Ink.raised)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.name).font(.headline).foregroundStyle(Ink.text).lineLimit(2)
                            if let brand = entry.brand { Text(brand).font(.subheadline).foregroundStyle(Ink.text2).lineLimit(1) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                if let food {
                    if !isMealFood, amount.unit != nil { EditFoodButton { editingFood = true }.buttonStyle(.plain) }
                    if !isEditing, !isPicking { FavoriteButton(foodID: food.id).buttonStyle(.plain) }
                }
                Button(action: close) { CircleIcon(symbol: "xmark") }
                    .buttonStyle(.plain)
                    .hoverHighlight()
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel(isEditing ? "Cancel" : "Close")
                    .accessibilityIdentifier(isEditing ? "entryEditor.cancel" : "portion.close")
            }
        }
    }

    /// The amount in big numerals between − and +, as the design's open food has it. The numeral
    /// is the keypad's: it opens selected, so the first key replaces it.
    var quantity: some View {
        HStack(spacing: 8) {
            step("Less", "minus", up: false)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                quantityField
                Text(amount.unit?.label ?? entry.map { "× \($0.amountLabel)" } ?? "")
                    .font(.title3.weight(.semibold)).foregroundStyle(Ink.text2).lineLimit(1).minimumScaleFactor(0.6)
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            step("More", "plus", up: true)
        }
    }

    func step(_ label: String, _ symbol: String, up: Bool) -> some View {
        Button {
            amount.nudge(up: up)
        } label: {
            Image(systemName: symbol).font(.title3.weight(.semibold)).foregroundStyle(Ink.text)
                .frame(width: 48, height: 48).background(Ink.raised, in: .circle).contentShape(.circle)
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .hoverHighlight()
        .accessibilityLabel(label)
        .accessibilityIdentifier("amount.\(symbol)")
    }

    @ViewBuilder
    var quantityField: some View {
        #if os(macOS)
        TextField("Amount", text: Binding(get: { amount.text }, set: { amount.type($0) }), selection: $selection)
            .textFieldStyle(.plain)
            .numeral(48)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 180)
            .focused($fieldFocused)
            .accessibilityIdentifier("amount.quantity")
            .onSubmit(save)
        #else
        Text(amount.display())
            .numeral(48)
            .foregroundStyle(Ink.text)
            .padding(.horizontal, 6)
            .background(amount.isSelected ? Color.accentColor.opacity(0.22) : .clear, in: .rect(cornerRadius: 10))
            .contentTransition(.numericText())
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
                HStack(spacing: 6) {
                    ForEach(units) { unit in
                        let on = amount.unit?.id == unit.id
                        Button {
                            amount.change(to: unit)
                        } label: {
                            InkChip(title: unit.label, selected: on)
                        }
                        .buttonStyle(.plain)
                        .hoverHighlight()
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .accessibilityIdentifier("portion.unit")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    /// Half to double the usual amount, as chips; Delete beside them when it's logged already.
    var choices: some View {
        HStack(spacing: 6) {
            if let unit = amount.unit {
                ForEach(AmountChoices.quick(base: amount.base, unit: unit), id: \.self) { value in
                    choice(AmountChoices.label(value, unit: unit), value: value)
                }
            } else {
                ForEach(AmountChoices.multipliers, id: \.self) { value in
                    choice(AmountChoices.label(multiplier: value), value: value)
                }
            }
            Spacer(minLength: 4)
            if isEditing, !isMealFood, let entry {
                Button("Delete") {
                    model.delete(entries: [entry.id])
                    close()
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Ink.bad)
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .accessibilityIdentifier("entryEditor.delete")
            }
        }
    }

    func choice(_ title: String, value: Double) -> some View {
        Button {
            amount.choose(value)
        } label: {
            InkChip(title: title, selected: amount.count.map { abs($0 - value) < 0.001 } ?? false)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityIdentifier("portion.quick")
    }

    /// What the amount comes to, and the food's vitamins and minerals folded under it.
    var numbers: some View {
        VStack(alignment: .leading, spacing: 12) {
            NutrientSummary(nutrients: nutrients).accessibilityIdentifier("amount.summary")
            if let food, let fold = draft.foldAmount {
                // At no amount too, or it would fold up as the last digit's deleted.
                PortionNutrients(food: food, count: fold.count, unit: fold.unit)
                    .tint(Ink.text2)
            }
        }
        .inkCard(padding: 16, radius: 22)
    }

    var timeRow: some View {
        DatePicker("Eaten", selection: $date)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Ink.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.cardBackground, in: .rect(cornerRadius: 18, style: .continuous))
            .accessibilityIdentifier("entryEditor.eaten")
    }

    /// Picks the food out on the Log tab to take it somewhere: another day, or an hour's arrow.
    var takeRow: some View {
        HStack(spacing: 8) {
            take("Move", symbol: "arrow.right", intent: .move)
            take("Copy", symbol: "doc.on.doc", intent: .copy)
        }
    }

    func take(_ title: String, symbol: String, intent: LogSelection.Intent) -> some View {
        Button {
            model.take(draft, at: date, intent: intent)
            close()
        } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity)
        }
        .buttonStyle(.ghost)
        .disabled(amount.count == nil)
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
        key(glyph, id: glyph, key: .fraction(glyph), quiet: true).disabled(amount.unit?.isFine ?? false)
    }

    /// A key of the design's keypad: the raised grey, the numeral in the text's colour; the
    /// fractions quieter, beside the digits.
    func key(_ title: String, id: String, key: AmountEntry.Key, label: String? = nil, quiet: Bool = false) -> some View {
        AmountKey(title: title, quiet: quiet) { amount.press(key) }
            .accessibilityLabel(label ?? title)
            .accessibilityIdentifier("amount.key.\(id)")
    }

    var primary: some View {
        Button(action: save) {
            Text(primaryTitle).font(.headline).lineLimit(1).frame(maxWidth: .infinity)
        }
        .primaryAction().controlSize(.large)
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
        guard !draft.isOpen else { return }
        keysFocused = Platform.usesAmountKeypad
        draft = model.draft(for: request)
        if let entry { date = entry.date }
        #if os(macOS)
        fieldFocused = true
        selection = TextSelection(range: amount.text.startIndex..<amount.text.endIndex)
        #endif
    }

    func save() {
        guard let count = amount.count else { return }
        if let updated = model.edited(draft, at: date) {
            if let saveTo { saveTo(updated) } else { model.update(updated) }
        } else if isPicking, let unit = amount.unit {
            picked?(count, unit)
        } else if let food, let unit = amount.unit, case .add(let source) = request.purpose {
            model.log([model.entry(for: food, count: count, unit: unit, source: source)])
        }
        finished()
        close()
    }

    func use(_ corrected: Food) {
        draft.use(corrected)
        foodCorrected?(corrected)
    }
}

extension View {
    /// A small sheet for the amount panel: all of it in view on a phone, with room to grow, and
    /// room for the time when it's changing an entry.
    func amountSheet(editing: Bool) -> some View {
        presentationDetents([.height(editing ? 840 : 760), .large])
            .presentationDragIndicator(.visible)
            .loggerGround()
            .macSheetSize(width: 440, height: 560)
    }
}

/// One key of the amount's keypad.
private struct AmountKey: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    var quiet = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.title3.weight(quiet ? .medium : .semibold).monospacedDigit())
                .foregroundStyle(quiet ? Ink.text2 : Ink.text)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Ink.raised, in: .rect(cornerRadius: 12, style: .continuous))
                .opacity(isEnabled ? 1 : 0.35)
                .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .hoverHighlight()
    }
}

/// The amount as a ruler to drag (`.tapewrap`): from nothing to `most`, ticked, with a thumb at the
/// amount, snapped to the unit's step. Across sets it; up and down is the page's, to scroll.
struct AmountRuler: View {
    let value: Double
    let most: Double
    let step: Double
    /// The amount in words, for VoiceOver.
    let label: String
    let set: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let fraction = most > 0 ? min(1, max(0, value / most)) : 0
            ZStack(alignment: .leading) {
                Ruler(value: fraction, height: 28)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Ink.text)
                    .frame(width: 8, height: 46)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Ink.surface).padding(-3))
                    .offset(x: min(width - 8, max(0, fraction * width - 4)))
                    .animation(.snappy(duration: 0.4), value: fraction)
            }
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .simultaneousGesture(
                DragGesture(minimumDistance: 6).onChanged { drag in
                    guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                    pick(drag.location.x / width)
                }
            )
            .onTapGesture { location in pick(location.x / width) }
        }
        .frame(height: 46)
        .accessibilityElement()
        .accessibilityLabel("Amount")
        .accessibilityValue(label)
        .accessibilityAdjustableAction { direction in
            set(snapped(value + (direction == .increment ? step : -step)))
        }
        .accessibilityIdentifier("amount.ruler")
    }

    func pick(_ x: Double) { set(snapped(min(1, max(0, x)) * most)) }

    /// To the unit's step, never below one step.
    func snapped(_ amount: Double) -> Double { max(step, (amount / step).rounded() * step) }
}
