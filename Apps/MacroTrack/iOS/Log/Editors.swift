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

    enum Field: CaseIterable { case kcal, protein, carbs, fat, name }

    var body: some View {
        Form {
            Section {
                row("Calories", $kcal, "kcal", .kcal)
                row("Protein", $protein, "g", .protein)
            } footer: {
                Text(model.quickAddNote)
            }
            Section("Optional") {
                row("Carbs", $carbs, "g", .carbs)
                row("Fat", $fat, "g", .fat)
                TextField("Name", text: $name).focused($focus, equals: .name).accessibilityIdentifier("quickAdd.name")
            }
        }
        .navigationTitle("Quick add")
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                // A number pad has no key for the next field.
                if let next {
                    Button("Next") { focus = next }
                        .font(.headline)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .accessibilityIdentifier("quickAdd.next")
                }
                Button {
                    model.quickAdd(name: name, nutrients: nutrients)
                    close()
                } label: {
                    Text("Add \(Format.kcal(nutrients.kcal))").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .primaryAction()
                .accessibilityIdentifier("quickAdd.add")
                .disabled(nutrients.kcal <= 0 && nutrients.protein <= 0)
            }
            .padding(.horizontal)
        }
        .onAppear { focus = .kcal }
    }

    /// The field after the one being typed in.
    var next: Field? {
        guard let focus, let index = Field.allCases.firstIndex(of: focus), index + 1 < Field.allCases.count else { return nil }
        return Field.allCases[index + 1]
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

/// Change an entry's amount or time, or delete it, on the amount panel. With `saveTo` it edits a
/// food of a saved meal instead: only its amount, handed back rather than logged.
struct EntryEditor: View {
    @Environment(\.dismiss) private var dismiss
    let entry: FoodEntry
    /// Set where the editor sits beside the log (an inspector) rather than in a sheet: what closes it.
    var close: (() -> Void)?
    var saveTo: ((FoodEntry) -> Void)?
    /// Whether it can be picked out to take elsewhere; see `AmountPanel.canTake`.
    var canTake = true

    var body: some View {
        if let close {
            AmountPanel(request: .edit(entry), saveTo: saveTo, canTake: canTake, close: close)
        } else {
            AmountPanel(request: .edit(entry), saveTo: saveTo, canTake: canTake, close: { dismiss() })
                .amountSheet(editing: true)
        }
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
                            // A pointer has no swipe.
                            .contextMenu {
                                Button(w.excluded ? "Use" : "Ignore", systemImage: w.excluded ? "checkmark.circle" : "eye.slash") {
                                    model.setExcluded(!w.excluded, weighIn: w)
                                }
                                if case .manual = w.source {
                                    Button("Delete", systemImage: "trash", role: .destructive) { model.delete(weighIn: w) }
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
    static func nudged(_ value: String, by direction: Double, in unit: WeightUnit) -> String {
        let step = unit == .kg ? 0.1 : 0.2
        return Format.editable(max(0, (Format.parse(value) ?? 0) + direction * step), digits: 1)
    }

    func nudge(_ direction: Double) -> some View {
        Button {
            value = Self.nudged(value, by: direction, in: model.units.weight)
        } label: {
            Image(systemName: direction < 0 ? "minus" : "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 52, height: 52)
                .background(Color.accentColor.opacity(0.14), in: .circle)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
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
