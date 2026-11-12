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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The set's load, reps and clock, shared by the dock and Floor mode.
    @State private var draft = SetDraft()
    @State private var floor = FloorMode()
    @AppStorage(FloorMode.automaticKey) private var floorAutomatic = true
    /// The iPad's scoreboard in landscape, or the two panes: chosen on this device, not synced, since
    /// it's about where this iPad stands.
    @AppStorage(Self.scoreboardKey) private var scoreboardOn = true
    /// Whether the session's window is wider than it's tall, where the iPad shows the scoreboard.
    @State private var landscape = false
    @State private var showFeedback = false
    @State private var swapping: SwapTarget?
    @State private var editing: SetTarget?
    @State private var confirmDiscard = false
    @State private var about: ExerciseAbout?
    /// Missed on the floor with the reps at the target: how many there were.
    @State private var floorMiss: SetTarget?
    @State private var askFloorMiss = false

    var body: some View {
        NavigationStack {
            if let live = model.live {
                Group {
                    if showsScoreboard {
                        Scoreboard(live: live, finish: { showFeedback = true })
                    } else if sizeClass.isWide {
                        SessionWorkspace(
                            live: live, swap: { swapping = SwapTarget(index: $0) }, edit: { editing = SetTarget(item: $0, set: $1) },
                            finish: { showFeedback = true })
                    } else {
                        phone(live)
                    }
                }
                .environment(draft)
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
                .sheet(item: $about) { target in ExerciseAboutSheet(exerciseID: target.id) }
                .environment(\.showExercise, ShowExerciseAction { about = ExerciseAbout(id: $0) })
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
        // Measured round the whole screen, which stays put while the session inside it changes
        // between the board and the panes (measured inside, each change measured again from nothing
        // and flipped it back), and read on appearing as well as on turning: the iPad may already
        // lie on its side when the session opens.
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { measure(proxy.size) }
                    .onChange(of: proxy.size) { _, size in measure(size) }
            }
        }
    }

    private func measure(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        landscape = size.width > size.height
    }

    static let scoreboardKey = "session.scoreboard"

    /// Whether the scoreboard can show here: an iPad, a wide window, landscape (or `-scoreboard`,
    /// which shows it whichever way the iPad is turned).
    private var scoreboardFits: Bool {
        guard Platform.hasScoreboard, sizeClass.isWide else { return false }
        #if DEBUG
        if LaunchOptions.current.has("-scoreboard") { return true }
        #endif
        return landscape
    }

    private var showsScoreboard: Bool { scoreboardFits && scoreboardOn }

    /// The phone's session, and Floor mode over it while the phone lies on the floor or a bench: the
    /// set or the rest filling the screen, which is the button.
    private func phone(_ live: LiveSession) -> some View {
        let shown = floorShown
        return ZStack {
            column(live)
                .accessibilityHidden(shown != nil)
            if let shown {
                FloorScreen(content: shown, floor: floor) { target in
                    floorMiss = target
                    askFloorMiss = true
                }
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .confirmationDialog("How many did you get?", isPresented: $askFloorMiss, titleVisibility: .visible, presenting: floorMiss) { target in
            // The dock's question, the same answers.
            let reps = targetReps(target)
            ForEach((max(0, reps - 6)..<reps).reversed(), id: \.self) { n in
                Button("\(n) reps") {
                    draft.reps = n
                    draft.log(item: target.item, set: target.set, rating: .red, model: model)
                    floor.logged()
                }
            }
        } message: { _ in
            Text("Missed reps are just data. The next set adjusts.")
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.35), value: shown != nil)
        .hidesSystemChrome(shown != nil)
        // A set logged, or a rest skipped or changed, felt through the glass with the eyes elsewhere.
        .sensoryFeedback(.success, trigger: floor.logs)
        .sensoryFeedback(.impact(weight: .medium), trigger: floor.nudges)
        .onAppear { floor.start(automatic: floorAutomatic) }
        .onDisappear { floor.stop() }
        .onChange(of: floorAutomatic) { _, automatic in floor.setAutomatic(automatic) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { floor.start(automatic: floorAutomatic) } else { floor.stop() }
        }
        // Using the normal screen (changing the weight, logging, a sheet up) isn't setting it down.
        .onChange(of: live.updatedAt) { floor.touched() }
        .onChange(of: draft.load) { floor.touched() }
        .onChange(of: draft.reps) { floor.touched() }
        .onChange(of: presenting) { floor.touched() }
    }

    /// The reps a set asked for, or none when it's no longer there.
    private func targetReps(_ target: SetTarget) -> Int {
        guard let live = model.live, live.items.indices.contains(target.item), live.items[target.item].sets.indices.contains(target.set)
        else { return 0 }
        return live.items[target.item].sets[target.set].prescription.targetReps
    }

    /// What Floor mode shows, while the phone is set down and nothing is open over the session.
    private var floorShown: FloorContent? {
        guard floor.isOn, !presenting else { return nil }
        return model.floorContent
    }

    /// A sheet or a question over the session.
    private var presenting: Bool {
        showFeedback || swapping != nil || editing != nil || about != nil || confirmDiscard
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
                .onScrollPhaseChange { _, phase in
                    if phase != .idle { floor.touched() }
                }
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
            Button("About this exercise", systemImage: "info.circle") { about = ExerciseAbout(id: item.exerciseID) }
                .accessibilityIdentifier("session.aboutExercise")
            if item.plan.isStrength {
                Button("Swap exercise", systemImage: "arrow.triangle.2.circlepath") { swapping = SwapTarget(index: index) }
            }
            if item.takesMoreSets {
                Button("Add a set", systemImage: "plus") { model.update { $0.addSet(item: index) } }
            }
            Button("Skip exercise", systemImage: "forward") { model.update { $0.skip(item: index) } }
            Divider()
        }
        // On now, whatever the angle (propped on a bag, leaning on a bottle); picked up, it's off.
        if Platform.hasFloorMode, model.floorContent != nil {
            Button("Floor mode", systemImage: "tray.and.arrow.down") { floor.turnOn() }
                .accessibilityIdentifier("session.floorMode")
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
        if scoreboardFits {
            ToolbarItem(placement: .barTrailing) {
                // Back to the two panes (to reorder, swap or correct a set), and to the board again.
                Toggle(isOn: $scoreboardOn) {
                    Label("Scoreboard", systemImage: "sportscourt")
                }
                .toggleStyle(.button)
                .help("Show the session as a scoreboard, to read from across the room")
                .accessibilityIdentifier("session.scoreboardToggle")
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
    @Environment(\.showExercise) private var showExercise
    let live: LiveSession
    @Binding var picked: LiveItem.ID?
    let swap: (Int) -> Void

    var body: some View {
        List(selection: $picked) {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(Int((live.progress * 100).rounded()))% done").font(.caption).foregroundStyle(Ink.text2)
                    Ruler(value: live.progress, height: 10)
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
        Button("About This Exercise", systemImage: "info.circle") { showExercise?(item.exerciseID) }
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
    @Environment(\.showExercise) private var showExercise
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
                    Button("About this exercise", systemImage: "info.circle") { showExercise?(item.exerciseID) }
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
            if current { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 2) }
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
                .background(isCurrent ? Color.accentColor : Ink.raised, in: .capsule)
                .foregroundStyle(isCurrent ? Ink.onAccent : Ink.text)
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
                HStack {
                    Text("Every set is done").eyebrow()
                    Spacer()
                    // The last set can be taken back too: there's no rest after it to hold Undo.
                    if let undoable = model.undoable { UndoButton(logged: undoable, identifier: "session.undo") }
                }
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
    @Environment(\.dynamicTypeSize) private var dynamicType
    let rest: RestState
    let message: String?

    var body: some View {
        let total = max(1, rest.endsAt.timeIntervalSince(rest.started))
        let logged = model.justLogged(after: rest)
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(logged.map { "Rest · \($0.name) logged" } ?? "Rest").eyebrow()
                    Spacer(minLength: 8)
                    if let logged, logged.undoable { UndoButton(logged: logged, identifier: "rest.undo") }
                }
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
        guard let next = model.nextSet(after: rest) else { return nil }
        var label = next.label
        if next.repOut { label += " · as many as you can" }
        if let exercise = next.exercise { label += " · \(exercise)" }
        let plates = Format.plates(next.plates, unit: next.plateUnit)
        // The plates under the set at the largest text sizes, where side by side cuts both short.
        let large = dynamicType.isAccessibilitySize
        let layout = large ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        return AnyView(
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.caption).foregroundStyle(Ink.text2).lineLimit(large ? 2 : 1)
                    Text(next.target).font(.body.weight(.semibold).monospacedDigit()).foregroundStyle(Ink.text)
                }
                if !large { Spacer() }
                if let plates { Text(plates).font(.caption.monospacedDigit()).foregroundStyle(Ink.text2).lineLimit(1) }
            }
            .accessibilityElement(children: .combine))
    }
}

/// Undo for the set just logged, top right of the rest's dock (and of the dock once every set is
/// done): the set is open again with the numbers it was logged with.
struct UndoButton: View {
    @Environment(AppModel.self) private var model
    @Environment(SetDraft.self) private var draft
    @Environment(\.sessionScale) private var scale
    let logged: JustLogged
    let identifier: String

    var body: some View {
        Button("Undo") { draft.undo(model: model) }
            .font((scale.isLarge ? Font.body : .subheadline).weight(.semibold))
            .foregroundStyle(Ink.text2)
            .buttonStyle(.plain)
            // A fingertip's room round a short word, without pushing the eyebrow down.
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .contentShape(.rect)
            .padding(.vertical, -14)
            .padding(.trailing, -10)
            .hoverHighlight()
            .accessibilityLabel("Undo \(logged.name.lowercased())")
            .accessibilityHint("\(logged.text). Takes it back to log again.")
            .accessibilityIdentifier(identifier)
    }
}

/// The set after a rest, as the rest's dock and Floor mode name it.
struct NextSet {
    /// "Next · set 3 of 3", "Next · warm-up".
    var label: String
    /// The exercise's name, when the set is another exercise's: a superset's partner, the next exercise.
    var exercise: String?
    var repOut: Bool
    var stopAtFormBreakdown: Bool
    /// "70 kg × 7", with a "+" for a rep-out.
    var target: String
    /// A side's plates, for a barbell.
    var plates: [Double]?
    var plateUnit: WeightUnit
    /// The empty bar the plates go on, in the gym's unit.
    var plateBar: Double?
}

extension AppModel {
    /// The set that comes after a rest, or nil when there's none or it's a conditioning piece.
    func nextSet(after rest: RestState) -> NextSet? {
        guard let live, let position = live.current else { return nil }
        let item = live.items[position.item]
        guard item.sets.indices.contains(position.set), item.plan.conditioning == nil else { return nil }
        let set = item.sets[position.set]
        let exercise = catalog.resolve(item.exerciseID)
        let increments = gymForToday.increments(for: exercise.equipment)
        let work = item.sets.filter { $0.prescription.kind != .warmup }
        let number = item.sets[...position.set].filter { $0.prescription.kind != .warmup }.count
        return NextSet(
            label: set.prescription.kind == .warmup ? "Next · warm-up" : "Next · set \(number) of \(work.count)",
            exercise: item.id != rest.itemID ? exercise.name : nil, repOut: set.prescription.kind == .repOut,
            stopAtFormBreakdown: set.prescription.stopAtFormBreakdown,
            target: Format.set(set.prescription, exercise: exercise, unit: gym.unit) + (set.prescription.kind == .repOut ? "+" : ""),
            plates: exercise.equipment.platePaired ? increments.platesPerSide(set.prescription.loadKg ?? 0) : nil,
            plateUnit: increments.gym.unit,
            plateBar: exercise.equipment.platePaired ? increments.gym.unit.fromKilograms(increments.barKg) : nil)
    }
}

/// An exercise opened from the session's menus, by its id.
struct ExerciseAbout: Identifiable {
    let id: String
}

/// Opens an exercise's own page over the session, from any exercise's menu in it. Always equal to
/// another: it only ever sets the session screen's own state, so a new copy changes nothing below.
nonisolated struct ShowExerciseAction: Equatable {
    let open: @MainActor (String) -> Void

    @MainActor func callAsFunction(_ exerciseID: String) { open(exerciseID) }

    static func == (_: ShowExerciseAction, _: ShowExerciseAction) -> Bool { true }
}

extension EnvironmentValues {
    @Entry var showExercise: ShowExerciseAction? = nil
}

/// An exercise's own page over the session, closed to carry on; a substitute picked in it is pushed after it.
struct ExerciseAboutSheet: View {
    @Environment(\.dismiss) private var dismiss
    let exerciseID: String

    var body: some View {
        NavigationStack {
            PushedExerciseDetail(exerciseID: exerciseID)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close) { dismiss() }
                            .accessibilityIdentifier("library.close")
                    }
                }
        }
        .sheetFrame(minWidth: 560, idealWidth: 720, minHeight: 600, idealHeight: 760)
    }
}
