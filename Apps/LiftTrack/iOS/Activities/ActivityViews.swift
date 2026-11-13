import LiftEngine
import SwiftUI
import SystemCore

/// Recurring declarations: "BJJ Tue/Thu evenings", "hot yoga Saturdays".
struct OutsideActivitiesEditor: View {
    @Binding var recurring: [RecurringActivity]
    var title: String = "Recurring activities"
    var detail: String = ""
    /// Where it sits: onboarding's step heading, or a pushed page's (Settings).
    var style: HeadingStyle = .step
    @State private var editing: RecurringActivity?

    enum HeadingStyle {
        /// Onboarding's question, at 36 points.
        case step
        /// A page in Settings: where it was opened from over its title, on a phone.
        case page(eyebrow: String)
        /// No heading: the Mac's pane has its window's.
        case none
    }

    @ViewBuilder
    private var heading: some View {
        switch style {
        case .step:
            StepHeading(title, detail: detail.isEmpty ? nil : detail)
                .padding(.horizontal, 4)
                .padding(.top, 14)
                .padding(.bottom, 8)
        case .page(let eyebrow):
            SheetHeading(eyebrow: eyebrow, title: title, detail: detail.isEmpty ? nil : detail)
        case .none:
            EmptyView()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading
            RowCard(title: recurring.isEmpty ? nil : "Every week") {
                ForEach(recurring) { item in
                    Button {
                        editing = item
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.activity.symbol).font(.body).foregroundStyle(Color.accentColor).frame(width: 24)
                                .accessibilityHidden(true)
                            LinkRowLabel(
                                title: item.activity.label,
                                caption:
                                    "\(item.weekdays.map(\.short).joined(separator: ", ")) · \(item.minutes) min · \(item.timeOfDay.label.lowercased())"
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight()
                    .accessibilityIdentifier("outside.activity")
                }
            }
            Button {
                editing = RecurringActivity(activity: .bjj, weekdays: [.tuesday, .thursday], minutes: 60)
            } label: {
                Label("Add an activity", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .secondaryAction()
            .controlSize(.large)
            .accessibilityIdentifier("outside.add")
            if recurring.isEmpty {
                Text("None? That's fine. Runs and classes your watch records are picked up from Health anyway.")
                    .font(.caption).foregroundStyle(Ink.text3).padding(.horizontal, 4)
            }
        }
        #if DEBUG
        // `-addActivity` opens a new regular activity's editor, as Add an activity does.
        .onAppear {
            if LaunchOptions.current.has("-addActivity") {
                editing = RecurringActivity(activity: .bjj, weekdays: [.tuesday, .thursday], minutes: 60)
            }
        }
        #endif
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
                FormHeading(
                    eyebrow: isNew ? "Outside the gym · new" : "Outside the gym", title: isNew ? "New activity" : item.activity.label,
                    detail: "Stadig Lift plans around it: it spends the same recovery.")
                Group {
                    Section {
                        Picker("Activity", selection: $item.activity) {
                            ForEach(ActivityType.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                        }
                    }
                    Section {
                        WeekdayPicker(selection: $item.weekdays)
                    } header: {
                        Text("Days").eyebrow()
                    }
                    Section {
                        Picker("Time of day", selection: $item.timeOfDay) {
                            ForEach(TimeOfDay.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        Stepper("\(item.minutes) minutes", value: $item.minutes, in: 15...240, step: 15)
                        Stepper("Effort \(item.intensity) of 10", value: $item.intensity, in: 1...10)
                    }
                }
                .inkRows()
                if !isNew {
                    Section {
                        FormActionRow("Remove", destructive: true, identifier: "recurring.remove") { done(nil) }
                    }
                }
            }
            .inkList()
            .inkSheet {
                SheetBar(label: "Cancel", identifier: "recurring.cancel") { dismiss() }
            } foot: {
                SheetFoot {
                    Button {
                        done(item)
                    } label: {
                        Text("Save").frame(maxWidth: .infinity)
                    }
                    .primaryAction()
                    .keyboardShortcut(.defaultAction)
                    .disabled(item.weekdays.isEmpty)
                    .accessibilityIdentifier("recurring.save")
                }
            }
        }
        .sheetFrame()
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
                FormHeading(
                    eyebrow: "Outside the gym", title: "Log an activity",
                    detail:
                        "Counts against the same recovery budget as lifting, and toward \(type.statCredit.keys.map(\.label).sorted().joined(separator: " and "))."
                )
                Group {
                    Section {
                        Picker("Activity", selection: $type) {
                            ForEach(ActivityType.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                        }
                        DatePicker("When", selection: $start, in: ...Date())
                        Stepper("\(minutes) minutes", value: $minutes, in: 5...300, step: 5)
                    }
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(intensity)").numeral(30)
                                Text("of 10").font(.subheadline).foregroundStyle(Ink.text2)
                                Spacer()
                                Text(effortWord).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text2)
                            }
                            Slider(value: Binding(get: { Double(intensity) }, set: { intensity = Int($0) }), in: 1...10, step: 1)
                                .accessibilityLabel("Effort")
                                .accessibilityValue("\(intensity) of 10")
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Effort").eyebrow()
                    }
                    if type.isMartialArt {
                        Section {
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
                        } header: {
                            Text("Class").eyebrow()
                        }
                    }
                    Section { TextField("Note", text: $note, axis: .vertical) }
                }
                .inkRows()
            }
            .inkList()
            .inkSheet {
                SheetBar(label: "Cancel", identifier: "logActivity.cancel") { dismiss() }
            } foot: {
                SheetFoot {
                    Button {
                        let martial =
                            type.isMartialArt ? MartialArtsDetails(classType: classType, sparringRounds: rounds, roundsBeforeGassed: gassed) : nil
                        let source: ActivitySource = declared.map { .declared($0.id) } ?? .manual
                        model.save(
                            activity: ActivityLog(
                                type: type, start: start, minutes: minutes, intensity: intensity, source: source,
                                martialArts: martial, note: note))
                        dismiss()
                    } label: {
                        Text("Save").frame(maxWidth: .infinity)
                    }
                    .primaryAction()
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("logActivity.save")
                }
            }
        }
        .sheetFrame()
    }

    /// The effort in a word, beside its number.
    private var effortWord: String {
        switch intensity {
        case ...3: "Easy"
        case 4...6: "Moderate"
        case 7...8: "Hard"
        default: "All out"
        }
    }
}
