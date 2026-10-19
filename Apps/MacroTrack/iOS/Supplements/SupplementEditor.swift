import FoodDatabase
import NutritionEngine
import SwiftUI
import SystemCore

/// A supplement's label and when it's taken: the name, the serving, each Supplement Facts line
/// (with what it counts as), and one or more doses with their days.
struct SupplementEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var supplement: Supplement
    let isNew: Bool
    /// The Supplement Facts lines being edited, each with an identity of its own: rows keyed by
    /// position would leave a focused field writing into the next line, or past the end, after
    /// a swipe-delete.
    @State private var lines: [Line]
    @State private var confirmingDelete = false
    @State private var showAllLines = false

    private struct Line: Identifiable {
        let id = UUID()
        var ingredient: SupplementIngredient
    }

    init(supplement: Supplement, isNew: Bool) {
        _supplement = State(initialValue: supplement)
        _lines = State(initialValue: supplement.facts.ingredients.map { Line(ingredient: $0) })
        self.isNew = isNew
    }

    static let units = [
        "capsule", "softgel", "tablet", "caplet", "gummy", "chewable", "lozenge", "scoop", "packet", "tsp", "tbsp", "g",
        "ml", "drop", "spray", "serving",
    ]
    static let lineUnits = ["mg", "mcg", "g", "IU", "mcg DFE", "mcg RAE", "kcal", "CFU", "billion CFU", "ml"]

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $supplement.facts.name)
                TextField("Brand", text: Binding(get: { supplement.facts.brand ?? "" }, set: { supplement.facts.brand = $0.isEmpty ? nil : $0 }))
            } footer: {
                if supplement.facts.source == .dsld {
                    Text("Label from the NIH Dietary Supplement Label Database. Check it against your bottle; recipes change.")
                } else if supplement.facts.source == .label {
                    Text("Read from the label. Check each line against it.")
                }
            }

            doses

            Section {
                HStack {
                    Text("Serving")
                    Spacer()
                    TextField("1", value: $supplement.facts.servingCount, format: .number)
                        .fieldKeyboard(.decimal).multilineTextAlignment(.trailing).frame(width: 60)
                    Picker("Unit", selection: $supplement.facts.unit) {
                        ForEach(Self.units + (Self.units.contains(supplement.facts.unit) ? [] : [supplement.facts.unit]), id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                // The first ten, or all of them: shown always starts at the first line, so a delete's
                // offsets are the lines' own.
                let shown = showAllLines || lines.count <= 12 ? lines : Array(lines.prefix(10))
                ForEach(shown) { line in
                    LineEditor(ingredient: binding(line.id), units: Self.lineUnits)
                }
                .onDelete { lines.remove(atOffsets: $0) }
                if shown.count < lines.count {
                    Button("Show all \(lines.count) lines") { showAllLines = true }
                }
                Button("Add a line", systemImage: "plus") {
                    lines.append(Line(ingredient: SupplementIngredient(name: "", amount: nil, unit: "mg")))
                    showAllLines = true
                }
            } header: {
                Text("Supplement Facts")
            } footer: {
                Text(countedSummary)
            }

            if !isNew {
                Section {
                    Toggle("Paused", isOn: $supplement.paused)
                    Button("Remove from my supplements", role: .destructive) { confirmingDelete = true }
                } footer: {
                    Text("Paused supplements stay here with their history but aren't due on Today.")
                }
            }
        }
        .navigationTitle(isNew ? "Add supplement" : supplement.name)
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Add" : "Save") {
                    model.save(supplement: tidied)
                    dismiss()
                }
                .disabled(supplement.facts.name.trimmingCharacters(in: .whitespaces).isEmpty || supplement.doses.isEmpty)
            }
        }
        .confirmationDialog("Remove \(supplement.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                model.delete(supplement: supplement.id)
                dismiss()
            }
        } message: {
            Text("Doses already taken keep counting on their days.")
        }
    }

    /// Each line read again in case its name or unit changed, and only the ones Macro Track tracks
    /// kept: nothing else would count for anything.
    var tidied: Supplement {
        var s = supplement
        s.facts.name = s.facts.name.trimmingCharacters(in: .whitespacesAndNewlines)
        s.facts.ingredients = lines.map(\.ingredient).filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.amount != nil }
            .map { SupplementIngredient(name: $0.name, amount: $0.amount, unit: $0.unit) }
            .filter(\.isTracked)
        if s.facts.servingCount <= 0 { s.facts.servingCount = 1 }
        return s
    }

    /// A line by its identity: an edit committed after the line was deleted goes nowhere, rather
    /// than into whichever line took its place.
    private func binding(_ id: UUID) -> Binding<SupplementIngredient> {
        Binding(
            get: { lines.first { $0.id == id }?.ingredient ?? SupplementIngredient(name: "", amount: nil, unit: "mg") },
            set: { value in if let index = lines.firstIndex(where: { $0.id == id }) { lines[index].ingredient = value } })
    }

    var countedSummary: String {
        let amounts = tidied.facts.amounts
        let counted = Micronutrients.all.compactMap { info in amounts[info.key].map { "\(Format.nutrient($0, info.unit)) \(Format.inSentence(info))" }
        }
        let kcal = tidied.facts.nutrients.map { $0.kcal >= 1 ? ["\(Format.whole($0.kcal)) kcal"] : [] } ?? []
        guard !counted.isEmpty || !kcal.isEmpty else {
            return "Nothing on this label is a nutrient Macro Track tracks, so doses are ticked off but add no numbers."
        }
        return "Each serving counts as " + (kcal + counted).joined(separator: ", ") + "."
    }

    // MARK: Doses

    var doses: some View {
        Section {
            ForEach($supplement.doses) { $dose in
                DoseEditor(dose: $dose, unit: supplement.facts.unit, facts: supplement.facts)
            }
            .onDelete { supplement.doses.remove(atOffsets: $0) }
            Button("Add a time", systemImage: "plus") {
                let used = Set(supplement.doses.map(\.time))
                let next = DoseTime.allCases.first { !used.contains($0) } ?? .evening
                supplement.doses.append(
                    Dose(
                        time: next, count: supplement.doses.last?.count ?? supplement.facts.servingCount,
                        days: supplement.doses.last?.days ?? .everyDay))
            }
        } header: {
            Text("When you take it")
        } footer: {
            if supplement.doses.contains(where: { $0.days == .trainingDays || $0.days == .restDays }) {
                Text("Training days are the days your shared schedule trains, and any day Lift Track logs a session.")
            }
        }
    }
}

/// One dose: the time of day, how many, and which days.
private struct DoseEditor: View {
    @Binding var dose: Dose
    let unit: String
    let facts: SupplementFacts
    @State private var choosingDays = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker(selection: $dose.time) {
                    ForEach(DoseTime.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                } label: {
                    EmptyView()
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
                Stepper(value: $dose.count, in: step...max(step, 50), step: step) {
                    Text(facts.amountLabel(dose.count)).font(.subheadline.monospacedDigit())
                }
                .fixedSize()
            }
            Menu {
                Button("Every day") { dose.days = .everyDay }
                Button("Training days") { dose.days = .trainingDays }
                Button("Rest days") { dose.days = .restDays }
                Button("Every other day") { dose.days = .everyOtherDay(from: .today) }
                Button("Choose days…") { choosingDays = true }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                    Text(dose.days.label)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 2)
        .sheet(isPresented: $choosingDays) { WeekdayPicker(days: $dose.days).macSheetSize(width: 380, height: 440) }
    }

    /// Half a scoop or teaspoon; whole pills.
    var step: Double { ["scoop", "tsp", "tbsp", "g", "ml", "packet", "serving"].contains(unit) ? 0.5 : 1 }
}

private struct WeekdayPicker: View {
    @Binding var days: DoseDays
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<Weekday> = []

    var body: some View {
        NavigationStack {
            List(Weekday.allCases) { day in
                Button {
                    if chosen.contains(day) { chosen.remove(day) } else { chosen.insert(day) }
                } label: {
                    HStack {
                        Text(day.name)
                        Spacer()
                        if chosen.contains(day) { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("Days")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        days = chosen.count == 7 ? .everyDay : .weekdays(chosen.sorted())
                        dismiss()
                    }
                    .disabled(chosen.isEmpty)
                }
            }
            .onAppear {
                if case .weekdays(let list) = days { chosen = Set(list) } else { chosen = Set(Weekday.allCases) }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A Supplement Facts line: its name, amount and unit, and what Macro Track counts it as.
private struct LineEditor: View {
    @Binding var ingredient: SupplementIngredient
    let units: [String]

    var body: some View {
        let read = ingredient.amount.flatMap { SupplementIngredients.read(name: ingredient.name, amount: $0, unit: ingredient.unit) }
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Name", text: $ingredient.name, prompt: Text("Name")).font(.subheadline)
                TextField("Amount", value: $ingredient.amount, format: .number, prompt: Text("0"))
                    .fieldKeyboard(.decimal).multilineTextAlignment(.trailing).frame(width: 70).font(.subheadline.monospacedDigit())
                Picker("Unit", selection: $ingredient.unit) {
                    ForEach(units + (units.contains(ingredient.unit) ? [] : [ingredient.unit]), id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            // The Mac's form would put each field's name beside it; the line reads as one row.
            .macLabelsHidden()
            if let read {
                if let note = note(read) { Text(note).font(.caption2).foregroundStyle(.secondary) }
            } else if !ingredient.name.trimmingCharacters(in: .whitespaces).isEmpty, ingredient.amount != nil {
                Text("Not something Macro Track tracks, so it won't be kept").font(.caption2).foregroundStyle(.orange)
            }
        }
    }

    func note(_ read: (key: String, value: Double)) -> String? {
        if let info = Micronutrients.info(read.key) {
            let printed = ingredient.unit == info.unit.symbol || (ingredient.unit == "mcg" && info.unit == .µg)
            return printed ? "Counts as \(Format.inSentence(info))" : "Counts as \(Format.nutrient(read.value, info.unit)) \(Format.inSentence(info))"
        }
        switch read.key {
        case "epa", "dha", "dpa", "ala", "otherOmega3": return "Part of omega-3"
        case "protein", "carbs", "fat", "sugar": return "Counts toward your macros"
        default: return nil
        }
    }
}
