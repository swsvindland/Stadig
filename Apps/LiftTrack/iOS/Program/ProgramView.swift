import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

/// The block laid out for planning, on the iPad and the Mac: every day and every slot with its sets
/// week by week, the weeks and the calendar, and an inspector that explains a slot and swaps it for
/// the rest of the block. A next block, planned or offered, shows beside the current one.
struct ProgramView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selection: UUID?
    @State private var inspecting = false
    @State private var width: CGFloat = 0
    @State private var pane = Pane.current
    /// The next block as it would be built now, when one is offered but not planned yet.
    @State private var offered: Mesocycle?

    enum Pane: Hashable { case current, next }

    var body: some View {
        NavigationStack {
            Group {
                if let analysis = model.analysis, let current = analysis.mesocycle, let block = analysis.block {
                    content(current: current, block: block, analysis: analysis)
                } else {
                    EmptyCard(symbol: "list.bullet.rectangle", title: "No block yet", detail: "Finish setup to start your assessment.")
                        .padding(16)
                        .frame(maxWidth: 520)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(.pageBackground)
            // A container of its own, so the next block's column keeps its identifiers rather than
            // taking the screen's.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("program.screen")
            .navigationTitle("Program")
            .ownHeader()
            .sideInspector(isPresented: $inspecting) {
                inspector
            }
            .toolbar { toolbar }
            .sessionResumeToolbar()
            .task(id: model.nextBlockOffered) { buildOffered() }
            .onChange(of: selection) { _, id in if id != nil { inspecting = true } }
            .onAppear { if sizeClass.isWide { inspecting = true } }
            #if DEBUG
            // `-programLift <exercise id>` selects that lift's first slot in the block, as a click does.
            .task {
                guard let id = LaunchOptions.current.value(after: "-programLift") else { return }
                selection = model.analysis?.mesocycle?.days.flatMap(\.slots).first { $0.exerciseID == id }?.id
            }
            #endif
        }
    }

    /// The block after this one: planned and waiting, or offered and previewed.
    private var next: (mesocycle: Mesocycle, planned: Bool)? {
        if let upcoming = model.analysis?.upcoming { return (upcoming, true) }
        if let offered { return (offered, false) }
        return nil
    }

    /// Room for the next block as a column beside this block's table.
    private var sideBySide: Bool { next != nil && sizeClass.isWide && width >= 1100 }

    @ViewBuilder
    private func content(current: Mesocycle, block: TrainingBlock, analysis: LiftAnalysis) -> some View {
        Group {
            if pane == .next, let next {
                BlockPane(
                    mesocycle: next.mesocycle, block: next.mesocycle.block, selection: $selection, title: nextTitle(next), editable: next.planned)
            } else if sideBySide, let next {
                HStack(spacing: 0) {
                    BlockPane(mesocycle: current, block: block, selection: $selection, title: nil, editable: true)
                    Divider()
                    NextBlockColumn(mesocycle: next.mesocycle, title: nextTitle(next), planned: next.planned) { pane = .next }
                        .frame(width: 380)
                }
            } else {
                BlockPane(mesocycle: current, block: block, selection: $selection, title: nil, editable: true)
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
    }

    private func nextTitle(_ next: (mesocycle: Mesocycle, planned: Bool)) -> String {
        next.planned ? "Next block · starts \(Format.day(next.mesocycle.block.start))" : "Next block · offered, not planned yet"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if next != nil && (!sideBySide || pane == .next) {
            ToolbarItem(placement: .principal) {
                Picker("Block", selection: $pane) {
                    Text("This block").tag(Pane.current)
                    Text("Next block").tag(Pane.next)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityIdentifier("program.pane")
            }
        }
        if model.nextBlockOffered {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.sheet = .nextBlock
                } label: {
                    Label("Plan the Next Block", systemImage: "sparkles")
                }
                .help("Build your next block from everything learned")
                .accessibilityIdentifier("program.nextBlock")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                inspecting.toggle()
            } label: {
                Label(inspecting ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.trailing")
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .help(inspecting ? "Hide the inspector" : "Show the inspector")
            .accessibilityIdentifier("program.inspectorToggle")
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if let found = findSlot() {
            SlotInspector(
                mesocycle: found.mesocycle, day: found.day, slot: found.slot, editable: found.editable,
                current: found.mesocycle.id == model.analysis?.mesocycle?.id
            )
            .id(found.slot.id)
        } else if let current = model.analysis?.mesocycle {
            BlockOverview(mesocycle: current)
        } else {
            Text("Nothing selected").font(.subheadline).foregroundStyle(Ink.text3).padding(16)
        }
    }

    /// The selected slot, in whichever block it's in.
    private func findSlot() -> (mesocycle: Mesocycle, day: PlannedDay, slot: SlotPlan, editable: Bool)? {
        guard let selection else { return nil }
        var blocks: [(Mesocycle, Bool)] = []
        if let current = model.analysis?.mesocycle { blocks.append((current, true)) }
        if let next { blocks.append((next.mesocycle, next.planned)) }
        for (mesocycle, editable) in blocks {
            for day in mesocycle.days {
                if let slot = day.slots.first(where: { $0.id == selection }) { return (mesocycle, day, slot, editable) }
            }
        }
        return nil
    }

    /// The next block as the Plan sheet would build it now, to look at beside this one. Built only
    /// while one is offered, and only when the phase needn't be asked first.
    private func buildOffered() {
        guard model.nextBlockOffered, model.analysis?.upcoming == nil else {
            offered = nil
            return
        }
        let decision = Assessment.nextBlock(nutrition: model.nutrition, selfReported: model.settings.selfReportedPhase)
        offered = decision.askPhase ? nil : model.generate(kind: decision.kind, start: model.nextBlockStart, phase: decision.phase)
    }
}

/// The next block beside this one: what it is and its days, to compare. Opening it shows it in full,
/// with its slots to select.
private struct NextBlockColumn: View {
    @Environment(AppModel.self) private var model
    let mesocycle: Mesocycle
    let title: String
    let planned: Bool
    let open: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).eyebrow(.accentColor)
                PageTitle(mesocycle.block.kind.label, size: 24)
                Text(mesocycle.rationale.headline).font(.subheadline).foregroundStyle(Ink.text2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Pill(text: mesocycle.split.label, color: .secondary)
                    Pill(
                        text: mesocycle.block.deloadRange == nil
                            ? "\(mesocycle.block.loadingWeeks) weeks" : "\(mesocycle.block.loadingWeeks) weeks + deload",
                        color: .secondary)
                }
                WhyDisclosure(rationale: mesocycle.rationale)
                ForEach(mesocycle.days) { day in DayCard(day: day, isNext: false) }
                HStack {
                    Button("Show in Full", systemImage: "list.bullet.rectangle", action: open).secondaryAction()
                    if !planned && model.nextBlockOffered {
                        Button("Plan It…", systemImage: "sparkles") { model.sheet = .nextBlock }.primaryAction()
                    }
                }
                .controlSize(.small)
            }
            .padding()
        }
        .background(.pageBackground)
        .accessibilityIdentifier("program.nextBlockColumn")
    }
}

/// One block: its header over the desk of its days and weeks.
private struct BlockPane: View {
    @Environment(AppModel.self) private var model
    let mesocycle: Mesocycle
    let block: TrainingBlock
    @Binding var selection: UUID?
    /// Set for a next block: what it is and when it starts.
    let title: String?
    let editable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                PageHeader(eyebrow: title ?? eyebrow, title: mesocycle.split.label)
                Text(mesocycle.rationale.headline).font(.subheadline).foregroundStyle(Ink.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                if let reason = block.deloadReason {
                    Label(reason, systemImage: "arrow.down.circle").font(.footnote).foregroundStyle(Ink.text2).padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            ProgramDesk(mesocycle: mesocycle, current: title == nil, editable: editable, selection: $selection)
        }
    }

    /// "Assessment · 24 Oct – 20 Nov · 60 min".
    private var eyebrow: String {
        "\(block.kind.label) · \(Format.range(block.range)) · \(mesocycle.minutesPerSession) min"
    }
}
