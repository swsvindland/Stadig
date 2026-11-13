import NutritionEngine
import SwiftUI
import SystemCore

/// A fast: start one toward a goal (from the last meal, or a time picked), or follow the running
/// one through its phases, change its goal or start, and end it. Goals over a day ask the person to
/// read who shouldn't, once; they aren't offered under 18 or underweight.
struct FastSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    if let status = model.analysis?.fast {
                        RunningFast(status: status)
                    } else {
                        NewFast(close: { dismiss() })
                    }
                    PhasesSection(hours: model.analysis?.fast?.hours)
                    PastFastsSection()
                }
                .inkRows()
            }
            .inkForm()
            .navigationTitle(model.analysis?.fast == nil ? "Start a Fast" : "Fasting")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("fast.done")
                }
            }
        }
    }
}

/// The goal and start of a new fast, the safety screen when the goal needs it, and Start.
private struct NewFast: View {
    @Environment(AppModel.self) private var model
    let close: () -> Void
    @State private var goal = 16.0
    @State private var fromLastMeal = true
    @State private var start = Date()
    @State private var read = false

    var body: some View {
        let block = model.fastingBlock
        let longest = FastSafety.longest(block)
        let suggested = model.suggestedFastStart()
        let hasMeal = suggested < Date().addingTimeInterval(-60)
        Section {
            GoalPicker(goal: $goal, longest: longest)
            if hasMeal {
                Toggle("From the end of your last meal", isOn: $fromLastMeal)
                    .accessibilityIdentifier("fast.fromLastMeal")
                if fromLastMeal {
                    LabeledContent("Started", value: Format.moment(suggested))
                }
            }
            if !hasMeal || !fromLastMeal {
                DatePicker("Started", selection: $start, in: model.earliestFastStart()...Date())
                    .accessibilityIdentifier("fast.startTime")
            }
        } header: {
            Text("Goal").eyebrow()
        } footer: {
            if let block { Text(block.reason) }
        }
        let notes = FastSafety.notes(goalHours: goal, phase: model.analysis?.phase?.kind)
        if !notes.isEmpty || FastSafety.electrolytes(hours: goal) != nil {
            Section {
                ForEach(notes, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").font(.subheadline) }
                if let salt = FastSafety.electrolytes(hours: goal) { Label(salt, systemImage: "drop.triangle").font(.subheadline) }
            }
        }
        if model.needsFastingScreen(goalHours: goal) {
            SafetySection(read: $read)
        }
        Section {
            Button {
                if model.needsFastingScreen(goalHours: goal) { model.acknowledgeFastingScreen() }
                model.startFast(goalHours: goal, start: hasMeal && fromLastMeal ? suggested : start)
                close()
            } label: {
                Text("Start \(Format.goal(goal)) Fast").frame(maxWidth: .infinity)
            }
            .primaryAction().controlSize(.large)
            .disabled(model.needsFastingScreen(goalHours: goal) && !read)
            .accessibilityIdentifier("fast.start")
        }
    }
}

/// The presets as a row of choices, and a stepper for any goal up to the longest offered.
private struct GoalPicker: View {
    @Binding var goal: Double
    let longest: Double

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Fasting.presets.filter { $0 <= longest }, id: \.self) { hours in
                    Button(Format.goal(hours)) { goal = hours }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule).choiceTint(goal == hours)
                        .accessibilityIdentifier("fast.goal.\(Int(hours))")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        Stepper(value: $goal, in: 12...longest, step: goal >= 48 ? 12 : 1) {
            LabeledContent("Goal", value: Format.goal(goal))
        }
        .accessibilityIdentifier("fast.goalStepper")
    }
}

/// Who shouldn't fast for more than a day, and when to stop: read once before the first long fast.
private struct SafetySection: View {
    @Binding var read: Bool

    var body: some View {
        Section {
            ForEach(FastSafety.whoShouldnt, id: \.self) { Label($0, systemImage: "person.crop.circle.badge.exclamationmark").font(.subheadline) }
            Text("Stop and eat if you're \(FastSafety.stopIf.map { $0.lowercased() }.joined(separator: ", ")).")
                .font(.subheadline)
            Toggle("I've read this", isOn: $read)
                .accessibilityIdentifier("fast.acknowledge")
        } header: {
            Text("Before a fast over a day").eyebrow()
        } footer: {
            Text("Stadig Macro can't know your medicines or history. If any of these apply, talk to your doctor first.")
        }
    }
}

/// The running fast: how long, its goal and start to change, how to break it, and End.
private struct RunningFast: View {
    @Environment(AppModel.self) private var model
    let status: FastStatus
    @State private var read = false
    /// The start being picked, saved once the picker has settled rather than on every turn of it.
    @State private var start: Date?

    var body: some View {
        Section {
            TimelineView(.periodic(from: status.fast.start, by: 60)) { context in
                let now = Fasting.status(status.fast, now: context.date)
                VStack(alignment: .leading, spacing: 8) {
                    Text(Format.duration(now.elapsed)).numeral(44).foregroundStyle(Ink.text)
                    Ruler(value: now.hours / max(1, status.fast.goalHours), height: 14)
                    Text(
                        now.goalReached
                            ? "Goal of \(Format.goal(status.fast.goalHours)) reached"
                            : "\(Format.duration(now.remaining)) to \(Format.goal(status.fast.goalHours))"
                    )
                    .font(.subheadline).foregroundStyle(Ink.text2)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("fast.elapsed")
            }
            Stepper(
                value: Binding(get: { status.fast.goalHours }, set: { model.updateFast(goalHours: $0) }),
                in: 12...model.longestFast, step: status.fast.goalHours >= 48 ? 12 : 1
            ) {
                LabeledContent("Goal", value: Format.goal(status.fast.goalHours))
            }
            .accessibilityIdentifier("fast.goal")
            DatePicker(
                "Started", selection: Binding(get: { start ?? status.fast.start }, set: { start = $0 }),
                in: model.earliestFastStart()...Date()
            )
            .accessibilityIdentifier("fast.started")
            .task(id: start) {
                guard let picked = start else { return }
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                model.updateFast(start: picked)
                start = nil
            }
        } footer: {
            if let block = model.fastingBlock { Text(block.reason) }
        }
        // Past a day only once the notes are read, as when starting one.
        if model.fastingBlock == nil, model.needsFastingScreen(goalHours: FastSafety.screenHours + 1) {
            SafetySection(read: $read)
                .onChange(of: read) { _, read in if read { model.acknowledgeFastingScreen() } }
        }
        if let refeed = FastSafety.refeed(hours: max(status.hours, status.fast.goalHours)) {
            Section {
                Text(refeed).font(.subheadline)
                if let salt = FastSafety.electrolytes(hours: status.hours) { Text(salt).font(.subheadline) }
            } header: {
                Text("Breaking it").eyebrow()
            }
        }
        Section {
            Button("End Fast", role: .destructive) { model.endFast() }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("fast.end")
        } footer: {
            Text("Logging a meal ends it too, and Undo on that meal puts the fast back.")
        }
    }
}

/// What's likely happening, phase by phase, the current one marked.
private struct PhasesSection: View {
    let hours: Double?

    var body: some View {
        Section {
            ForEach(FastPhase.allCases, id: \.self) { phase in
                let current = hours.map { FastPhase.at(hours: $0) == phase } ?? false
                let passed = hours.map { FastPhase.at(hours: $0) > phase } ?? false
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: passed ? "checkmark.circle.fill" : phase.symbol)
                        .foregroundStyle(current || passed ? Color.accentColor : Ink.text3)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(phase.title).font(.subheadline.weight(current ? .bold : .semibold))
                            Spacer()
                            Text(phase.hoursLabel).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Text(phase.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
                .listRowBackground(current ? Color.accentColor.opacity(0.12) : Color.cardBackground)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("fast.phase.\(phase.rawValue)")
            }
        } header: {
            Text("What's likely happening").eyebrow()
        } footer: {
            Text(FastPhase.caveat)
        }
    }
}

/// The last few fasts, how long each ran against its goal.
private struct PastFastsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let past = Array(model.pastFasts.prefix(10))
        if !past.isEmpty {
            Section {
                ForEach(past) { run in
                    let hours = run.duration(at: run.end ?? Date()) / 3600
                    HStack {
                        Image(systemName: hours >= run.fast.goalHours ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(hours >= run.fast.goalHours ? Ink.good : Ink.text3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Format.duration(hours * 3600)) of \(Format.goal(run.fast.goalHours))").font(.subheadline.weight(.semibold))
                            Text(Format.moment(run.fast.start)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { model.delete(fast: run.id) }
                    }
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) { model.delete(fast: run.id) }
                    }
                }
            } header: {
                Text("Recent fasts").eyebrow()
            }
        }
    }
}
