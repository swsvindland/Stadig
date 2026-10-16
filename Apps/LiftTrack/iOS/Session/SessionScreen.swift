import SwiftUI
import ExerciseLibrary
import LiftEngine
import SystemCore

/// The live session. Every block in order, the current set in thumb reach at the bottom, and the
/// next set adapting the moment a set is rated.
struct SessionScreen: View {
    @Environment(AppModel.self) private var model
    @State private var showFeedback = false
    @State private var swapping: SwapTarget?
    @State private var editing: SetTarget?
    @State private var confirmDiscard = false

    var body: some View {
        NavigationStack {
            if let live = model.live {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(live.plan.notes.enumerated()), id: \.offset) { _, note in
                                Text(note).font(.subheadline).foregroundStyle(.secondary)
                            }
                            // In the session's order, which the person can change; a heading where the block changes.
                            ForEach(Array(live.items.enumerated()), id: \.element.id) { index, item in
                                if index == 0 || live.items[index - 1].plan.block != item.plan.block {
                                    Label(item.plan.block.label, systemImage: item.plan.block.symbol)
                                        .font(.headline)
                                        .foregroundStyle(item.plan.block.color)
                                        .padding(.top, 6)
                                }
                                ItemCard(index: index, item: item, current: live.current?.item == index,
                                         swap: { swapping = SwapTarget(index: index) },
                                         edit: { set in editing = SetTarget(item: index, set: set) })
                                    .id(item.id)
                            }
                            Color.clear.frame(height: 24)
                        }
                        .padding()
                        .readableWidth()
                    }
                    .background(.pageBackground)
                    .onChange(of: live.current?.item) { _, item in
                        guard let item else { return }
                        withAnimation { proxy.scrollTo(live.items[item].id, anchor: .top) }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    BottomPanel(finish: { showFeedback = true })
                }
                .navigationTitle(live.plan.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { model.showSession = false } label: { Image(systemName: "chevron.down") }
                            .accessibilityLabel("Minimize")
                    }
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 0) {
                            Text(live.plan.title).font(.headline)
                            HStack(spacing: 8) {
                                Text(live.startedAt, style: .timer).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                if let bpm = model.currentHeartRate {
                                    Label("\(Int(bpm))", systemImage: "heart.fill")
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(.red)
                                        .accessibilityLabel("Heart rate \(Int(bpm))")
                                }
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Finish now", systemImage: "flag.checkered") { showFeedback = true }
                            Button("Discard session", systemImage: "trash", role: .destructive) { confirmDiscard = true }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("Session options")
                    }
                }
                .sheet(isPresented: $showFeedback) { FeedbackSheet() }
                .sheet(item: $swapping) { target in SwapSheet(index: target.index) }
                .sheet(item: $editing) { target in EditSetSheet(itemIndex: target.item, setIndex: target.set) }
                .confirmationDialog("Discard this session?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                    Button("Discard", role: .destructive) { model.discardLive() }
                } message: {
                    Text("Nothing from it will be saved.")
                }
            } else {
                ContentUnavailableView("No session", systemImage: "figure.strengthtraining.traditional")
                    .toolbar { Button("Close") { model.showSession = false } }
            }
        }
    }
}

struct SwapTarget: Identifiable {
    let index: Int
    var id: Int { index }
}

struct SetTarget: Identifiable {
    let item: Int
    let set: Int
    var id: String { "\(item).\(set)" }
}

/// One exercise: its sets, prescribed and logged, and why it's here.
struct ItemCard: View {
    @Environment(AppModel.self) private var model
    let index: Int
    let item: LiveItem
    let current: Bool
    let swap: () -> Void
    /// Corrects a logged set.
    let edit: (Int) -> Void

    var body: some View {
        let exercise = model.catalog.resolve(item.exerciseID)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(exercise.name).font(.headline)
                        if item.plan.supersetGroup != nil { Pill(text: "Superset", color: .purple) }
                    }
                    if exercise.kind == .strength { MuscleLine(exercise: exercise) }
                }
                Spacer()
                if item.isDone {
                    Image(systemName: item.skipped ? "forward.fill" : "checkmark.circle.fill")
                        .foregroundStyle(item.skipped ? Color.secondary : Color.green)
                        .accessibilityLabel(item.skipped ? "Skipped" : "Done")
                }
                Menu {
                    // The rack's taken, or this one's free: do it now and come back to the rest.
                    if !item.isDone && !current {
                        Button("Do this now", systemImage: "arrow.up.to.line") { model.update { $0.doNext(item: index) } }
                    }
                    if item.plan.isStrength { Button("Swap exercise", systemImage: "arrow.triangle.2.circlepath", action: swap) }
                    Button("Add a set", systemImage: "plus") { model.update { $0.addSet(item: index) } }
                    if !item.isDone { Button("Skip", systemImage: "forward") { model.update { $0.skip(item: index) } } }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3)
                }
                .accessibilityLabel("\(exercise.name) options")
            }
            if let replaced = item.plan.substitutedFor {
                Text("Instead of \(model.catalog.resolve(replaced).name)").font(.caption).foregroundStyle(.secondary)
            }
            if current || !item.isDone {
                if let reason = item.plan.reason { Text(reason).font(.caption).foregroundStyle(.secondary) }
                if let note = item.plan.note, item.plan.isStrength { Text(note).font(.caption).foregroundStyle(.secondary) }
                if !exercise.cue.isEmpty, current { Label(exercise.cue, systemImage: "lightbulb").font(.caption) }
            }
            if let conditioning = item.plan.conditioning {
                Text(conditioning.summary).font(.subheadline.monospacedDigit())
                if let log = item.conditioning {
                    Text("Done: \(log.minutes) min\(log.averageHeartRate.map { " · avg \(Int($0)) bpm" } ?? "")").font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(item.sets.enumerated()), id: \.element.id) { setIndex, set in
                        if set.logged != nil, item.plan.isStrength {
                            // A logged set opens for a correction: the wrong weight, a rating tapped too fast.
                            Button { edit(setIndex) } label: {
                                SetRow(set: set, number: number(of: setIndex), exercise: exercise, isCurrent: false, editable: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Edit this set")
                        } else {
                            SetRow(set: set, number: number(of: setIndex), exercise: exercise,
                                   isCurrent: current && model.live?.current?.set == setIndex)
                        }
                    }
                }
            }
        }
        .card()
        .overlay {
            if current { RoundedRectangle(cornerRadius: 22).strokeBorder(Color.accentColor, lineWidth: 2) }
        }
        .opacity(item.isDone && !current ? 0.7 : 1)
    }

    /// "W1", "W2" for warm-ups, then 1, 2, 3 for work.
    private func number(of index: Int) -> String {
        let set = item.sets[index]
        if set.prescription.kind == .warmup {
            let warmups = item.sets[...index].filter { $0.prescription.kind == .warmup }.count
            return "W\(warmups)"
        }
        return "\(item.sets[...index].filter { $0.prescription.kind != .warmup }.count)"
    }
}

struct SetRow: View {
    @Environment(AppModel.self) private var model
    let set: LiveSet
    let number: String
    let exercise: Exercise
    let isCurrent: Bool
    var editable = false

    var body: some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.caption.weight(.bold).monospacedDigit())
                .frame(width: 30, height: 24)
                .background(isCurrent ? Color.accentColor : Color.secondary.opacity(0.15), in: .capsule)
                .foregroundStyle(isCurrent ? .white : .primary)
            if let logged = set.logged {
                Text(Format.logged(logged, exercise: exercise, unit: model.gym.unit)).font(.body.monospacedDigit())
                if set.prescription.kind == .repOut { Pill(text: "Rep-out", color: .purple) }
                Spacer()
                RatingMark(rating: logged.rating)
                if editable { Image(systemName: "pencil").font(.caption).foregroundStyle(.tertiary) }
            } else if set.skipped {
                Text("Skipped").foregroundStyle(.secondary)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(Format.set(set.prescription, exercise: exercise, unit: model.gym.unit))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(set.prescription.kind == .warmup ? .secondary : .primary)
                    if let note = set.note, isCurrent { Text(note).font(.caption).foregroundStyle(.tint) }
                }
                Spacer()
                switch set.prescription.kind {
                case .repOut: Pill(text: set.prescription.stopAtFormBreakdown ? "To form breakdown" : "As many as you can", color: .purple)
                case .findingWeight: Pill(text: "Find weight", color: .blue)
                case .deload: Pill(text: "Easy", color: .teal)
                default: EmptyView()
                }
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// The bottom of the screen: the rest timer, or the current set's controls, or Finish.
struct BottomPanel: View {
    @Environment(AppModel.self) private var model
    let finish: () -> Void

    var body: some View {
        Group {
            if let live = model.live {
                if let rest = live.rest {
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        if context.date < rest.endsAt {
                            RestPanel(rest: rest, message: live.message)
                        } else {
                            current(live)
                        }
                    }
                } else {
                    current(live)
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func current(_ live: LiveSession) -> some View {
        if let position = live.current {
            SetLogger(itemIndex: position.item, setIndex: position.set)
                .id(live.items[position.item].sets[position.set].id)
        } else {
            Button(action: finish) {
                Label("Finish session", systemImage: "flag.checkered").font(.headline).frame(maxWidth: .infinity)
            }
            .primaryAction()
            .controlSize(.large)
            .padding(.vertical, 8)
        }
    }
}

/// Rest: the countdown, the adjustment just made, ±15 s and skip.
struct RestPanel: View {
    @Environment(AppModel.self) private var model
    let rest: RestState
    let message: String?

    var body: some View {
        VStack(spacing: 10) {
            if let message { Text(message).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center) }
            HStack(alignment: .center, spacing: 16) {
                Button { model.update { $0.extendRest(by: -15) } } label: { Text("−15") .frame(width: 44) }
                    .secondaryAction()
                    .accessibilityLabel("Fifteen seconds less")
                VStack(spacing: 0) {
                    Text("Rest").font(.caption).foregroundStyle(.secondary)
                    Text(timerInterval: Date()...max(Date(), rest.endsAt), countsDown: true)
                        .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                }
                .frame(maxWidth: .infinity)
                Button { model.update { $0.extendRest(by: 15) } } label: { Text("+15").frame(width: 44) }
                    .secondaryAction()
                    .accessibilityLabel("Fifteen seconds more")
            }
            if let filler = rest.filler {
                Label("Use the rest: \(model.catalog.resolve(filler).name)", systemImage: "figure.flexibility").font(.footnote)
            }
            Button("Skip rest") { model.update { $0.endRest() } }.font(.subheadline)
        }
        .padding()
        .floatingGlass(in: RoundedRectangle(cornerRadius: 28), interactive: false)
    }
}
