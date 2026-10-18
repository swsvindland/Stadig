import SwiftUI
import LiftEngine
import SystemCore

/// Recurring declarations: "BJJ Tue/Thu evenings", "hot yoga Saturdays".
struct OutsideActivitiesEditor: View {
    @Binding var recurring: [RecurringActivity]
    var title: String = "Recurring activities"
    var detail: String = ""
    @State private var editing: RecurringActivity?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.title.bold())
                if !detail.isEmpty { Text(detail).foregroundStyle(.secondary) }
            }
            ForEach(recurring) { item in
                Button { editing = item } label: {
                    HStack {
                        Image(systemName: item.activity.symbol).font(.title3).frame(width: 32)
                        VStack(alignment: .leading) {
                            Text(item.activity.label).font(.headline)
                            Text("\(item.weekdays.map(\.short).joined(separator: ", ")) · \(item.minutes) min · \(item.timeOfDay.label.lowercased())")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .card()
                }
                .buttonStyle(.plain)
            }
            Button {
                editing = RecurringActivity(activity: .bjj, weekdays: [.tuesday, .thursday], minutes: 60)
            } label: {
                Label("Add an activity", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .secondaryAction()
            if recurring.isEmpty {
                Text("None? That's fine. Runs and classes your watch records are picked up from Health anyway.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .sheet(item: $editing) { item in
            RecurringEditor(item: item, isNew: !recurring.contains { $0.id == item.id }) { result in
                if let result {
                    if let i = recurring.firstIndex(where: { $0.id == result.id }) { recurring[i] = result } else { recurring.append(result) }
                } else {
                    recurring.removeAll { $0.id == item.id }
                }
                editing = nil
            }
        }
    }
}

struct RecurringEditor: View {
    @State var item: RecurringActivity
    let isNew: Bool
    /// Nil deletes.
    let done: (RecurringActivity?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("Activity", selection: $item.activity) {
                    ForEach(ActivityType.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                Section("Days") { WeekdayPicker(selection: $item.weekdays) }
                Picker("Time of day", selection: $item.timeOfDay) {
                    ForEach(TimeOfDay.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Stepper("\(item.minutes) minutes", value: $item.minutes, in: 15...240, step: 15)
                Stepper("Effort \(item.intensity) of 10", value: $item.intensity, in: 1...10)
                if !isNew {
                    Button("Remove", role: .destructive) { done(nil) }
                }
            }
            .navigationTitle(isNew ? "New activity" : item.activity.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { done(item) }.disabled(item.weekdays.isEmpty)
                }
            }
        }
    }
}

/// The quick manual log for watch-free sessions: a class, a spin session, hot yoga. Martial arts
/// add class type, sparring rounds and rounds before gassed.
struct ActivityLogSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var type: ActivityType
    @State private var start = Date()
    @State private var minutes = 60
    @State private var intensity: Int
    @State private var classType: MartialArtsClass = .technique
    @State private var rounds = 0
    @State private var gassed: Int?
    @State private var note = ""
    var declared: RecurringActivity?

    init(type: ActivityType = .bjj, declared: RecurringActivity? = nil) {
        _type = State(initialValue: declared?.activity ?? type)
        _intensity = State(initialValue: declared?.intensity ?? type.typicalIntensity)
        _minutes = State(initialValue: declared?.minutes ?? 60)
        self.declared = declared
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Activity", selection: $type) {
                    ForEach(ActivityType.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                DatePicker("When", selection: $start, in: ...Date())
                Stepper("\(minutes) minutes", value: $minutes, in: 5...300, step: 5)
                VStack(alignment: .leading) {
                    Text("Effort: \(intensity) of 10")
                    Slider(value: Binding(get: { Double(intensity) }, set: { intensity = Int($0) }), in: 1...10, step: 1)
                        .accessibilityValue("\(intensity) of 10")
                }
                if type.isMartialArt {
                    Section("Class") {
                        Picker("Type", selection: $classType) {
                            ForEach(MartialArtsClass.allCases) { Text($0.label).tag($0) }
                        }
                        Stepper("\(rounds) sparring rounds", value: $rounds, in: 0...30)
                        if rounds > 0 {
                            Picker("Gassed after", selection: $gassed) {
                                Text("Never").tag(Int?.none)
                                ForEach(1...rounds, id: \.self) { Text("Round \($0)").tag(Int?.some($0)) }
                            }
                        }
                    }
                }
                Section { TextField("Note", text: $note, axis: .vertical) }
                Section {
                    Text("Counts against the same recovery budget as lifting, and toward \(type.statCredit.keys.map(\.label).sorted().joined(separator: " and ")).")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Log activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("logActivity.cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let martial = type.isMartialArt ? MartialArtsDetails(classType: classType, sparringRounds: rounds, roundsBeforeGassed: gassed) : nil
                        let source: ActivitySource = declared.map { .declared($0.id) } ?? .manual
                        model.save(activity: ActivityLog(type: type, start: start, minutes: minutes, intensity: intensity, source: source,
                                                         martialArts: martial, note: note))
                        dismiss()
                    }
                    .accessibilityIdentifier("logActivity.save")
                }
            }
        }
    }
}
