import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

/// The live session. Every block in order, the current set in thumb reach at the bottom, and the
/// next set adapting the moment a set is rated. On a wide screen it's two panes: the session's
/// exercises (drag to reorder) beside the current one with a large logger and rest timer.
struct SessionScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showFeedback = false
    @State private var swapping: SwapTarget?
    @State private var editing: SetTarget?
    @State private var confirmDiscard = false

    var body: some View {
        NavigationStack {
            if let live = model.live {
                Group {
                    if sizeClass.isWide {
                        SessionWorkspace(
                            live: live, swap: { swapping = SwapTarget(index: $0) }, edit: { editing = SetTarget(item: $0, set: $1) },
                            finish: { showFeedback = true })
                    } else {
                        column(live)
                    }
                }
                .environment(\.sessionScale, sizeClass.isWide ? .large : .compact)
                .navigationTitle(live.plan.title)
                .inlineTitle()
                #if os(iOS)
                // The phone draws its own bar over the exercise strip.
                .toolbarVisibility(sizeClass.isWide ? .automatic : .hidden, for: .navigationBar)
                #endif
                .toolbar { if sizeClass.isWide { toolbar(live) } }
                .sheet(isPresented: $showFeedback) { FeedbackSheet() }
                .sheet(item: $swapping) { target in SwapSheet(index: target.index) }
                .sheet(item: $editing) { target in EditSetSheet(itemIndex: target.item, setIndex: target.set) }
                .confirmationDialog("Discard this session?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                    Button("Discard", role: .destructive) { model.discardLive() }
                        .accessibilityIdentifier("session.confirmDiscard")
                } message: {
                    Text("Nothing from it will be saved.")
                }
                // The menu bar's Finish… and Discard… land here.
                .onChange(of: model.sessionRequest, initial: true) { _, request in
                    switch request {
                    case .finish?: showFeedback = true
                    case .discard?: confirmDiscard = true
                    case nil: return
                    }
                    model.sessionRequest = nil
                }
            } else {
                ContentUnavailableView("No session", systemImage: "figure.strengthtraining.traditional")
                    .toolbar { Button("Close") { model.showSession = false }.accessibilityIdentifier("session.close") }
            }
        }
    }

    /// The phone's layout: the exercise in front of you under the session's bar, and the dock at the
    /// bottom that logs its set or runs the rest.
    private func column(_ live: LiveSession) -> some View {
        let index = live.current?.item ?? live.items.indices.last
        return VStack(spacing: 0) {
            SessionTopBar(live: live, menu: AnyView(options(live)))
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 8)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if live.progress == 0 {
                            ForEach(Array(live.plan.notes.enumerated()), id: \.offset) { _, note in
                                Text(note).font(.subheadline).foregroundStyle(Ink.text2).padding(.horizontal, 4)
                            }
                        }
                        if let index, live.items.indices.contains(index) {
                            FocusedExercise(
                                live: live, index: index, swap: { swapping = SwapTarget(index: $0) },
                                edit: { set in editing = SetTarget(item: index, set: set) }
                            )
                            .id("focus")
                        }
                        Color.clear.frame(height: 12)
                    }
                    .padding(.horizontal, 16)
                    .readableWidth()
                }
                .scrollIndicators(.hidden)
                .onChange(of: live.current?.item) { _, _ in
                    withAnimation { proxy.scrollTo("focus", anchor: .top) }
                }
            }
        }
        // A container of its own, so the identifier isn't given to every element in it.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session.screen")
        .background(.pageBackground)
        .safeAreaInset(edge: .bottom) {
            BottomPanel(finish: { showFeedback = true })
                // What scrolls under the dock fades into the ground rather than showing round its corners.
                .background(alignment: .bottom) {
                    LinearGradient(colors: [Ink.ground.opacity(0), Ink.ground], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25))
                        .padding(.top, -24)
                        .ignoresSafeArea(edges: .bottom)
                }
        }
    }

    /// The session's menu: the current exercise's own choices, then Finish and Discard.
    @ViewBuilder
    private func options(_ live: LiveSession) -> some View {
        if let index = live.current?.item {
            let item = live.items[index]
            if item.plan.isStrength {
                Button("Swap exercise", systemImage: "arrow.triangle.2.circlepath") { swapping = SwapTarget(index: index) }
            }
            if item.takesMoreSets {
                Button("Add a set", systemImage: "plus") { model.update { $0.addSet(item: index) } }
            }
            Button("Skip exercise", systemImage: "forward") { model.update { $0.skip(item: index) } }
            Divider()
        }
        Button("Finish now", systemImage: "flag.checkered") { showFeedback = true }
            .accessibilityIdentifier("session.finishNow")
        Button("Discard session", systemImage: "trash", role: .destructive) { confirmDiscard = true }
            .accessibilityIdentifier("session.discard")
    }

    @ToolbarContentBuilder
    private func toolbar(_ live: LiveSession) -> some ToolbarContent {
        ToolbarItem(placement: .barLeading) {
            Button {
                model.showSession = false
            } label: {
                Label("Minimize", systemImage: Platform.isMac ? "rectangle.portrait.and.arrow.right" : "chevron.down")
            }
            .keyboardShortcut(".", modifiers: .command)
            .help("Keep the session running and go back to the app (⌘.)")
            .accessibilityLabel("Minimize")
            .accessibilityIdentifier("session.minimize")
        }
        ToolbarItem(placement: .principal) {
            VStack(spacing: 0) {
                // The Mac's window title already names the session.
                if !Platform.isMac { Text(live.plan.title).font(.headline) }
                HStack(spacing: 8) {
                    Text(live.startedAt, style: .timer).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    if let bpm = model.currentHeartRate {
                        Label("\(Int(bpm))", systemImage: "heart.fill")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Ink.bad)
                            .accessibilityLabel("Heart rate \(Int(bpm))")
                    }
                }
            }
        }
        ToolbarItem(placement: .barTrailing) {
            Menu {
                Button("Finish now", systemImage: "flag.checkered") { showFeedback = true }
                    .accessibilityIdentifier("session.finishNow")
                Button("Discard session", systemImage: "trash", role: .destructive) { confirmDiscard = true }
                    .accessibilityIdentifier("session.discard")
            } label: {
                Label("Session options", systemImage: "ellipsis")
            }
            .accessibilityLabel("Session options")
            .accessibilityIdentifier("session.options")
        }
    }
}

/// The wide session: the exercises and their progress on one side, reordered by dragging, and the
/// chosen one (the current one, unless another is picked) above a large logger and rest timer.
struct SessionWorkspace: View {
    @Environment(AppModel.self) private var model
    let live: LiveSession
    let swap: (Int) -> Void
    let edit: (Int, Int) -> Void
    let finish: () -> Void
    /// An exercise picked in the list to look at; nil follows the current one.
    @State private var picked: LiveItem.ID?

    var body: some View {
        HStack(spacing: 0) {
            SessionOutline(live: live, picked: $picked, swap: swap)
                .frame(minWidth: 280, idealWidth: 340, maxWidth: 380)
            Divider()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(live.plan.notes.enumerated()), id: \.offset) { _, note in
                            Text(note).font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let index = shownIndex {
                            let item = live.items[index]
                            Label(item.plan.block.label, systemImage: item.plan.block.symbol)
                                .font(.headline).foregroundStyle(item.plan.block.color)
                            ItemCard(
                                index: index, item: item, current: live.current?.item == index, swap: { swap(index) },
                                edit: { set in edit(index, set) })
                            if picked != nil, live.current?.item != index {
                                Button("Back to the current exercise", systemImage: "arrow.uturn.backward") { picked = nil }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: 820)
                    .frame(maxWidth: .infinity)
                }
                .background(.pageBackground)
                BottomPanel(finish: finish)
                    .frame(maxWidth: 820)
                    .padding(.top, 8)
                KeyboardHints()
                    .padding(.bottom, 8)
            }
            .background(.pageBackground)
        }
        // A container of its own: an identifier on a bare stack is given to every element in it,
        // over the logger's and the rest timer's own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session.screen")
        // Logging moves on to the next exercise: show it.
        .onChange(of: live.current?.item) { picked = nil }
    }

    private var shownIndex: Int? {
        if let picked, let index = live.items.firstIndex(where: { $0.id == picked }) { return index }
        return live.current?.item ?? live.items.indices.last
    }
}

/// The session's exercises, in order: each one's block, sets done and state. Drag to reorder what
/// isn't done; supersets move whole.
private struct SessionOutline: View {
    @Environment(AppModel.self) private var model
    let live: LiveSession
    @Binding var picked: LiveItem.ID?
    let swap: (Int) -> Void

    var body: some View {
        List(selection: $picked) {
            Section {
                ProgressView(value: live.progress) {
                    Text("\(Int((live.progress * 100).rounded()))% done").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(Array(live.items.enumerated()), id: \.element.id) { index, item in
                    OutlineRow(item: item, current: live.current?.item == index)
                        .tag(item.id)
                        .moveDisabled(item.isDone)
                        .contextMenu { menu(index, item) }
                        .accessibilityIdentifier("session.outlineItem")
                }
                .onMove { source, destination in model.moveLive(items: source, to: destination) }
            } header: {
                Text("Exercises")
            } footer: {
                Text(Platform.isMac ? "Drag an exercise to change the order." : "Touch and hold an exercise, then drag, to change the order.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(.pageBackground)
        .accessibilityIdentifier("session.outline")
    }

    @ViewBuilder
    private func menu(_ index: Int, _ item: LiveItem) -> some View {
        if !item.isDone && live.current?.item != index {
            Button("Do This Now", systemImage: "arrow.up.to.line") { model.update { $0.doNext(item: index) } }
        }
        if item.plan.isStrength {
            Button("Swap Exercise…", systemImage: "arrow.triangle.2.circlepath") { swap(index) }
        }
        if item.takesMoreSets {
            Button("Add a Set", systemImage: "plus") { model.update { $0.addSet(item: index) } }
        }
        if !item.isDone {
            Button("Skip", systemImage: "forward") { model.update { $0.skip(item: index) } }
        }
    }
}

private struct OutlineRow: View {
    @Environment(AppModel.self) private var model
    let item: LiveItem
    let current: Bool

    var body: some View {
        let exercise = model.catalog.resolve(item.exerciseID)
        let work = item.sets.filter { $0.prescription.kind != .warmup }
        let done = work.filter { !$0.isOpen }.count
        HStack(spacing: 10) {
            Image(systemName: item.plan.block.symbol).foregroundStyle(item.plan.block.color).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(exercise.name).fontWeight(current ? .semibold : .regular).lineLimit(1)
                    if item.plan.supersetGroup != nil { Pill(text: "Superset", color: .accentColor) }
                }
                Text(
                    item.plan.conditioning?.summary
                        ?? (work.isEmpty ? item.plan.block.label : "\(done) of \(work.count) \(work.count == 1 ? "set" : "sets")")
                )
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
            if item.isDone {
                Image(systemName: item.skipped ? "forward.fill" : "checkmark.circle.fill")
                    .foregroundStyle(item.skipped ? Color.secondary : Ink.good)
                    .accessibilityLabel(item.skipped ? "Skipped" : "Done")
            } else if current {
                Image(systemName: "arrowtriangle.right.fill").foregroundStyle(.tint).accessibilityLabel("Now")
            }
        }
        .opacity(item.isDone ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// The hardware keyboard's shortcuts, under the logger on the Mac (the iPad lists them while ⌘ is held).
private struct KeyboardHints: View {
    var body: some View {
        if Platform.isMac {
            Text("1 Easy · 2 Just right · 3 Missed · Return Done · ↑↓ weight · − + reps · Space ends a rest · ⌘. minimizes")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityHidden(true)
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
                        if item.plan.supersetGroup != nil { Pill(text: "Superset", color: .accentColor) }
                    }
                    if exercise.kind == .strength { MuscleLine(exercise: exercise) }
                }
                Spacer()
                if item.isDone {
                    Image(systemName: item.skipped ? "forward.fill" : "checkmark.circle.fill")
                        .foregroundStyle(item.skipped ? Color.secondary : Ink.good)
                        .accessibilityLabel(item.skipped ? "Skipped" : "Done")
                }
                Menu {
                    // The rack's taken, or this one's free: do it now and come back to the rest.
                    if !item.isDone && !current {
                        Button("Do this now", systemImage: "arrow.up.to.line") { model.update { $0.doNext(item: index) } }
                    }
                    if item.plan.isStrength {
                        Button("Swap exercise", systemImage: "arrow.triangle.2.circlepath", action: swap)
                            .accessibilityIdentifier("session.swap")
                    }
                    if item.takesMoreSets {
                        Button("Add a set", systemImage: "plus") { model.update { $0.addSet(item: index) } }
                    }
                    if !item.isDone { Button("Skip", systemImage: "forward") { model.update { $0.skip(item: index) } } }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3)
                }
                .accessibilityLabel("\(exercise.name) options")
                .accessibilityIdentifier("session.itemOptions")
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
                    Text("Done: \(log.minutes) min\(log.averageHeartRate.map { " · avg \(Int($0)) bpm" } ?? "")").font(.subheadline).foregroundStyle(
                        .secondary)
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(item.sets.enumerated()), id: \.element.id) { setIndex, set in
                        if let logged = set.logged, item.plan.isStrength {
                            // A logged set opens for a correction: the wrong weight, a rating tapped too fast. One
                            // logged before a swap reads as the exercise it was done on.
                            let doneOn = model.catalog.resolve(logged.exerciseID)
                            Button {
                                edit(setIndex)
                            } label: {
                                SetRow(set: set, number: number(of: setIndex), exercise: doneOn, isCurrent: false, editable: true)
                            }
                            .buttonStyle(.plain)
                            .hoverHighlight()
                            .accessibilityHint("Edit this set")
                            .accessibilityIdentifier("session.loggedSet")
                        } else {
                            SetRow(
                                set: set, number: number(of: setIndex), exercise: exercise,
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
                if set.prescription.kind == .repOut { Pill(text: "Rep-out", color: .accentColor) }
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
                case .repOut: Pill(text: set.prescription.stopAtFormBreakdown ? "To form breakdown" : "As many as you can", color: .accentColor)
                case .findingWeight: Pill(text: "Find weight", color: .accentColor)
                case .deload: Pill(text: "Easy", color: .accentColor)
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
    @Environment(\.sessionScale) private var scale
    let finish: () -> Void

    var body: some View {
        Group {
            if let live = model.live {
                // The rest gives way to the set when its time is up, though the session keeps it until
                // the set is logged: the logger then stays put, so a load already changed isn't reset.
                if let rest = model.activeRest {
                    RestPanel(rest: rest, message: live.message)
                } else {
                    current(live)
                }
            }
        }
        .padding(.horizontal, scale.isLarge ? 16 : 8)
        .padding(.bottom, scale.isLarge ? 8 : 0)
    }

    @ViewBuilder
    private func current(_ live: LiveSession) -> some View {
        if let position = live.current {
            SetLogger(itemIndex: position.item, setIndex: position.set)
                .id(live.items[position.item].sets[position.set].id)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Every set is done").eyebrow()
                Button(action: finish) {
                    Label("Finish session", systemImage: "flag.checkered").frame(maxWidth: .infinity)
                }
                .primaryAction()
                .controlSize(.large)
                .accessibilityIdentifier("session.finish")
            }
            .sessionDock()
        }
    }
}

/// Rest, in the dock where the logger was: the countdown large, a ruler draining under it, heart
/// rate when the Watch is on, ±15 s and skip, a drill to use the time, and the set that's next.
struct RestPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionScale) private var scale
    let rest: RestState
    let message: String?

    var body: some View {
        let total = max(1, rest.endsAt.timeIntervalSince(rest.started))
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Rest").eyebrow()
                if let message {
                    Text(message).font(.footnote).foregroundStyle(Ink.text2).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(alignment: .lastTextBaseline) {
                Text(timerInterval: Date()...max(Date(), rest.endsAt), countsDown: true)
                    .numeral(scale.isLarge ? 120 : 84, weight: .heavy)
                    .foregroundStyle(Ink.text)
                    .accessibilityLabel("Rest left")
                Spacer(minLength: 8)
                if let bpm = model.currentHeartRate {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: "heart").font(.subheadline.weight(.bold)).foregroundStyle(Ink.bad)
                            Text("\(Int(bpm))").numeral(28)
                        }
                        Text("bpm").font(.caption).foregroundStyle(Ink.text2)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Heart rate \(Int(bpm))")
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Ruler(value: max(0, rest.endsAt.timeIntervalSince(context.date)) / total, height: 28)
                }
                HStack {
                    Text("of \(Format.duration(Int(total.rounded())))")
                    Spacer()
                    if rest.plan.heartRateGuided, model.currentHeartRate != nil { Text("Ends early when your heart rate recovers") }
                }
                .font(.caption2.weight(.semibold)).textCase(.uppercase).foregroundStyle(Ink.text3)
            }
            HStack(spacing: 8) {
                Button {
                    model.update { $0.extendRest(by: -15) }
                } label: {
                    Text("−15").frame(maxWidth: .infinity)
                }
                .accessibilityLabel("Fifteen seconds less")
                .accessibilityIdentifier("rest.less")
                Button {
                    model.update { $0.extendRest(by: 15) }
                } label: {
                    Text("+15").frame(maxWidth: .infinity)
                }
                .accessibilityLabel("Fifteen seconds more")
                .accessibilityIdentifier("rest.more")
                Button {
                    model.update { $0.endRest() }
                } label: {
                    Text("Skip").frame(maxWidth: .infinity)
                }
                .keyboardShortcut(scale.shortcut(.space))
                .accessibilityLabel("Skip rest")
                .accessibilityIdentifier("rest.skip")
            }
            .secondaryAction()
            .controlSize(.large)
            VStack(spacing: 0) {
                if let filler = rest.filler {
                    Rectangle().fill(Ink.hairline).frame(height: 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use the rest").font(.caption).foregroundStyle(Ink.text2)
                        Text(model.catalog.resolve(filler).name).font(.body.weight(.semibold)).foregroundStyle(Ink.text)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
                if let next = nextSet {
                    Rectangle().fill(Ink.hairline).frame(height: 1)
                    next.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                }
            }
        }
        .sessionDock()
    }

    /// The set after the rest: which, its target, and the plates.
    private var nextSet: AnyView? {
        guard let live = model.live, let position = live.current else { return nil }
        let item = live.items[position.item]
        guard item.sets.indices.contains(position.set), item.plan.conditioning == nil else { return nil }
        let set = item.sets[position.set]
        let exercise = model.catalog.resolve(item.exerciseID)
        let increments = model.gymForToday.increments(for: exercise.equipment)
        let work = item.sets.filter { $0.prescription.kind != .warmup }
        let number = item.sets[...position.set].filter { $0.prescription.kind != .warmup }.count
        var label =
            set.prescription.kind == .warmup
            ? "Next · warm-up"
            : "Next · set \(number) of \(work.count)"
        if set.prescription.kind == .repOut { label += " · as many as you can" }
        if live.items[position.item].id != rest.itemID { label += " · \(exercise.name)" }
        let plates =
            exercise.equipment.platePaired ? Format.plates(increments.platesPerSide(set.prescription.loadKg ?? 0), unit: increments.gym.unit) : nil
        let target = Format.set(set.prescription, exercise: exercise, unit: model.gym.unit) + (set.prescription.kind == .repOut ? "+" : "")
        return AnyView(
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.caption).foregroundStyle(Ink.text2).lineLimit(1)
                    Text(target).font(.body.weight(.semibold).monospacedDigit()).foregroundStyle(Ink.text)
                }
                Spacer()
                if let plates { Text(plates).font(.caption.monospacedDigit()).foregroundStyle(Ink.text2).lineLimit(1) }
            }
            .accessibilityElement(children: .combine))
    }
}
