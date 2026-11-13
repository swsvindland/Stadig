import NutritionEngine
import SwiftUI
import SystemCore

/// A fast: start one toward a goal (from the last meal, or a time picked), or follow the running
/// one through its phases, change its goal or start, and end it. Goals over a day ask the person to
/// read who shouldn't, once; they aren't offered under 18 or underweight.
struct FastSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = FastDraft()

    var body: some View {
        let running = model.analysis?.fast
        NavigationStack {
            Form {
                FormHeading(eyebrow: "Today · meal timing", title: running == nil ? "Start a fast" : "Fasting")
                Group {
                    if let running {
                        RunningFast(status: running)
                    } else {
                        NewFast(draft: $draft)
                    }
                    PhasesSection(hours: running?.hours)
                    PastFastsSection()
                }
                .inkRows()
                .actionRows()
                if running != nil {
                    Section {
                        FormActionRow("End fast", destructive: true, identifier: "fast.end") { model.endFast() }
                    } footer: {
                        Text("Logging a meal ends it too, and Undo on that meal puts the fast back.")
                    }
                }
            }
            .inkForm()
            .inkSheet {
                SheetBar(label: "Done", identifier: "fast.done") { dismiss() }
            } foot: {
                if running == nil { startButton }
            }
        }
    }

    /// Start, at the foot while a new fast is being set up.
    private var startButton: some View {
        let screen = model.needsFastingScreen(goalHours: draft.goal)
        return SheetFoot {
            Button {
                if screen { model.acknowledgeFastingScreen() }
                model.startFast(goalHours: draft.goal, start: draft.start(model))
                dismiss()
            } label: {
                Text("Start \(Format.goal(draft.goal)) fast").frame(maxWidth: .infinity)
            }
            .primaryAction()
            .keyboardShortcut(.defaultAction)
            .disabled(screen && !draft.read)
            .accessibilityIdentifier("fast.start")
        }
    }
}

/// A new fast as it's set up: its goal, and when it started.
private struct FastDraft {
    var goal = 16.0
    var fromLastMeal = true
    var start = Date()
    var read = false

    /// From the end of the last meal, while there's one to start from and that's chosen.
    @MainActor
    func start(_ model: AppModel) -> Date {
        let suggested = model.suggestedFastStart()
        return Self.hasMeal(suggested) && fromLastMeal ? suggested : start
    }

    static func hasMeal(_ suggested: Date) -> Bool { suggested < Date().addingTimeInterval(-60) }
}

/// The goal and start of a new fast, and the safety screen when the goal needs it.
private struct NewFast: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: FastDraft

    var body: some View {
        let block = model.fastingBlock
        let longest = FastSafety.longest(block)
        let suggested = model.suggestedFastStart()
        let hasMeal = FastDraft.hasMeal(suggested)
        Section {
            GoalPicker(goal: $draft.goal, longest: longest)
            if hasMeal {
                Toggle("From the end of your last meal", isOn: $draft.fromLastMeal)
                    .accessibilityIdentifier("fast.fromLastMeal")
                if draft.fromLastMeal {
                    LabeledContent("Started", value: Format.moment(suggested))
                }
            }
            if !hasMeal || !draft.fromLastMeal {
                DatePicker("Started", selection: $draft.start, in: model.earliestFastStart()...Date())
                    .accessibilityIdentifier("fast.startTime")
            }
        } header: {
            Text("Goal").eyebrow()
        } footer: {
            if let block { Text(block.reason) }
        }
        let notes = FastSafety.notes(goalHours: draft.goal, phase: model.analysis?.phase?.kind)
        if !notes.isEmpty || FastSafety.electrolytes(hours: draft.goal) != nil {
            Section {
                ForEach(notes, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").font(.subheadline) }
                if let salt = FastSafety.electrolytes(hours: draft.goal) { Label(salt, systemImage: "drop.triangle").font(.subheadline) }
            }
        }
        if model.needsFastingScreen(goalHours: draft.goal) {
            SafetySection(read: $draft.read)
        }
    }
}

/// The presets as chips (`ChoiceChip`), and a stepper for any goal up to the longest offered.
private struct GoalPicker: View {
    @Binding var goal: Double
    let longest: Double

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
            ForEach(Fasting.presets.filter { $0 <= longest }, id: \.self) { hours in
                ChoiceChip(title: Format.goal(hours), isOn: goal == hours, identifier: "fast.goal.\(Int(hours))") { goal = hours }
            }
        }
        .padding(.vertical, 6)
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
                .padding(.vertical, 8)
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
                            Text(phase.hoursLabel).font(.caption.monospacedDigit()).foregroundStyle(Ink.text3)
                        }
                        Text(phase.detail).font(.caption).foregroundStyle(Ink.text2).fixedSize(horizontal: false, vertical: true)
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
                            Text(Format.moment(run.fast.start)).font(.caption).foregroundStyle(Ink.text3)
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
