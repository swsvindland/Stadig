import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

enum LifeModeKindChoice: String, Identifiable {
    case vacation, crunch, injury, illness

    var id: String { rawValue }

    var newPeriod: LifeModePeriod {
        let today = Day.today
        // The length an editor gives a period that has no end yet.
        let lastDay = LifeModePeriod.defaultDays - 1
        return switch self {
        case .vacation: LifeModePeriod(kind: .vacation, start: today.adding(days: 7), end: today.adding(days: 7 + lastDay), createdBy: .liftTrack)
        case .crunch: LifeModePeriod(kind: .crunch(CrunchDials()), start: today, end: today.adding(days: lastDay), createdBy: .liftTrack)
        case .injury: LifeModePeriod(kind: .injury(Injury(parts: [], severity: .mild)), start: today, createdBy: .liftTrack)
        case .illness: LifeModePeriod(kind: .illness(.aboveNeck), start: today, createdBy: .liftTrack)
        }
    }
}

/// An active life mode, in neutral words, with what it changes.
struct LifeModeBanner: View {
    let period: LifeModePeriod
    @State private var editing = false

    var body: some View {
        Button {
            editing = true
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: period.kind.symbol).font(.title2).foregroundStyle(.tint).frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .card()
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityIdentifier("today.lifeMode")
        .sheet(isPresented: $editing) { LifeModeEditor(period: period) }
    }

    private var title: String {
        let until = period.end.map { " until \(Format.day($0, style: .dateTime.weekday(.abbreviated).day()))" } ?? ""
        switch period.kind {
        case .vacation: return "Vacation\(until)"
        case .crunch: return "Crunch mode\(until)"
        case .injury(let injury): return "Injury: \(injury.parts.map(\.label).joined(separator: ", "))"
        case .illness(let kind): return kind.label
        }
    }

    private var detail: String {
        switch period.kind {
        case .vacation: "No logging expected anywhere. These days never count as misses."
        case .crunch(let dials):
            dials.minutesAvailable == 0
                ? "No training expected; nothing counts as a miss."
                : "\(dials.minutesAvailable)-minute minimum-dose sessions with \(dials.equipment.label.lowercased()) equipment. \(dials.exemptFromDiscipline ? "Exempt from Discipline." : "Discipline counts the reduced plan.")"
        case .injury(let injury):
            "\(injury.severity.label): exercises that load it are swapped; everything else keeps progressing. Persistent or worsening pain means a physio or doctor."
        case .illness(let kind):
            kind == .aboveNeck ? "Light work only. Exempt from Discipline." : "Rest. Nothing is expected. A lighter week follows."
        }
    }
}

/// Vacation, crunch, injury and illness: system-wide, set here or in any app in the family.
struct LifeModeEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var period: LifeModePeriod
    @State private var openEnded: Bool
    @State private var showExercises = false

    init(period: LifeModePeriod) {
        _period = State(initialValue: period)
        _openEnded = State(initialValue: period.end == nil)
    }

    private var isNew: Bool { !model.lifeModes.contains { $0.id == period.id } }

    var body: some View {
        NavigationStack {
            Form {
                dates
                switch period.kind {
                case .vacation: vacation
                case .crunch(let dials): crunch(dials)
                case .injury(let injury): injuryForm(injury)
                case .illness(let kind): illness(kind)
                }
                if !isNew {
                    Section {
                        // One that hasn't started has nothing to end: Delete calls it off.
                        if model.canEnd(period) {
                            Button(endTitle) {
                                model.end(lifeMode: period)
                                dismiss()
                            }
                            .accessibilityIdentifier("lifeMode.endNow")
                        }
                        Button("Delete", role: .destructive) {
                            model.delete(lifeMode: period.id)
                            dismiss()
                        }
                        .accessibilityIdentifier("lifeMode.delete")
                    }
                }
            }
            .navigationTitle(period.kind.label)
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("lifeMode.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.save(lifeMode: draft)
                        dismiss()
                    }
                    // What the model saves: the dates in order, and only a period that can apply.
                    .disabled(!draft.normalized().isValid)
                    .accessibilityIdentifier("lifeMode.save")
                }
            }
        }
        .sheetFrame()
    }

    private var endTitle: String {
        switch period.kind {
        case .injury: "It's better: ramp back in"
        case .illness: "I'm better"
        default: "End it now"
        }
    }

    /// What Save stores: what every app's editor saves.
    private var draft: LifeModePeriod { period.edited(openEnded: openEnded) }

    /// As Save would store it: open-ended only where the kind allows it, so "Until" shows otherwise.
    private var isOpenEnded: Bool { draft.end == nil }

    private var dates: some View {
        Section {
            DatePicker("From", selection: Binding(get: { period.start.date() }, set: { period.moveStart(to: Day($0)) }), displayedComponents: .date)
            if period.kind.allowsOpenEnd {
                Toggle("Until it's better", isOn: $openEnded)
            }
            if !isOpenEnded {
                DatePicker(
                    "Until", selection: Binding(get: { period.editorEnd.date() }, set: { period.moveEnd(to: Day($0)) }),
                    in: period.start.date()..., displayedComponents: .date)
            }
        } footer: {
            if case .vacation = period.kind {
                Text(
                    "Near a planned deload, the trip becomes the deload. Early in a block, the block ends there and a fresh one starts after. The first week back eases in."
                )
            }
        }
    }

    private var vacation: some View {
        Section {
            Label("No logging expected in any app.", systemImage: "moon.zzz")
            Label("Excluded from Discipline entirely.", systemImage: "checkmark.seal")
        }
    }

    private func crunch(_ dials: CrunchDials) -> some View {
        let binding = Binding<CrunchDials>(get: { dials }, set: { period.kind = .crunch($0) })
        return Group {
            Section("Time") {
                Picker("Free per session", selection: binding.minutesAvailable) {
                    Text("Nothing").tag(0)
                    ForEach([15, 20, 30, 45], id: \.self) { Text("\($0) min").tag($0) }
                }
            }
            Section("Equipment") {
                Picker("Equipment", selection: binding.equipment) {
                    ForEach(EquipmentAccess.allCases) { Text($0.label).tag($0) }
                }
            }
            Section("Food") {
                Picker("Food", selection: binding.food) {
                    ForEach(FoodControl.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                Toggle("Exempt from Discipline", isOn: binding.exemptFromDiscipline)
            } footer: {
                Text(
                    "Sessions become a minimum effective dose: short, far fewer sets, the big lifts kept. Conditioning and accessories go first. Crunch periods never count as failure."
                )
            }
        }
    }

    private func injuryForm(_ injury: Injury) -> some View {
        // Reads the edited period, not this snapshot, so several writes in one action each see the last.
        let binding = Binding<Injury>(
            get: {
                if case .injury(let current) = period.kind { current } else { injury }
            }, set: { period.kind = .injury($0) })
        let excluded = model.catalog.of(kind: .strength).filter { injury.excludes($0) }
        return Group {
            Section("Where") {
                ForEach(Joint.allCases) { joint in
                    let part = injury.parts.first { $0.joint == joint }
                    HStack {
                        Toggle(
                            joint.label,
                            isOn: Binding(
                                get: { part != nil },
                                set: { on in
                                    var i = injury
                                    if on { i.parts.append(InjuredPart(joint)) } else { i.parts.removeAll { $0.joint == joint } }
                                    binding.wrappedValue = i
                                }))
                    }
                    if let part, joint.isPaired {
                        Picker(
                            "Side",
                            selection: Binding(
                                get: { part.side },
                                set: { side in
                                    var i = injury
                                    if let index = i.parts.firstIndex(where: { $0.joint == joint }) { i.parts[index].side = side }
                                    binding.wrappedValue = i
                                })
                        ) {
                            ForEach(BodySide.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            Section("Severity") {
                Picker("Severity", selection: binding.severity) {
                    ForEach(InjurySeverity.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                TextField("What happened (optional)", text: binding.note, axis: .vertical)
            }
            if !injury.parts.isEmpty {
                Section {
                    Button("\(excluded.count) exercises set aside · adjust") { showExercises = true }
                } footer: {
                    Text(
                        "Filtering uses the joints each exercise loads. Add any back or take more out by hand. Persistent or worsening pain means a physio or doctor, not more training around it."
                    )
                }
                .sheet(isPresented: $showExercises) { InjuryOverrides(injury: binding) }
            }
        }
    }

    private func illness(_ kind: IllnessKind) -> some View {
        Section {
            Picker("How bad", selection: Binding(get: { kind }, set: { period.kind = .illness($0) })) {
                ForEach(IllnessKind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(kind.detail).font(.subheadline).foregroundStyle(.secondary)
        } footer: {
            Text("Exempt from Discipline. Coming back counts as stress too, so the first week back is lighter.")
        }
    }
}

/// Add back or take out exercises by hand while injured.
struct InjuryOverrides: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Binding var injury: Injury
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                let all = model.catalog.of(kind: .strength).filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
                ForEach(all.filter { injury.affects($0) || injury.removed.contains($0.id) }) { exercise in
                    let out = injury.excludes(exercise)
                    Button {
                        // One write: separate writes through the binding would each start from the same value.
                        var updated = injury
                        updated.toggleOverride(for: exercise)
                        injury = updated
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(exercise.name)
                                Text(
                                    exercise.joints.filter { injury.joints.contains($0.joint) }.map {
                                        "\($0.joint.label): \($0.stress.label.lowercased())"
                                    }.joined(separator: ", ")
                                )
                                .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(out ? "Set aside" : "Allowed").font(.subheadline).foregroundStyle(out ? Ink.ok : Ink.good)
                        }
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight()
                }
            }
            .searchable(text: $query)
            .navigationTitle("Exercises")
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .sheetFrame()
    }
}
