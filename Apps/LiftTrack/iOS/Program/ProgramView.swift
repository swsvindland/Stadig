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
    @State private var selection: ProgramRow.ID?
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
                    ContentUnavailableView(
                        "No block yet", systemImage: "list.bullet.rectangle", description: Text("Finish setup to start your assessment."))
                }
            }
            // A container of its own, so the next block's column keeps its identifiers rather than
            // taking the screen's.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("program.screen")
            .navigationTitle("Program")
            .sideInspector(isPresented: $inspecting) {
                inspector
            }
            .toolbar { toolbar }
            .sessionResumeToolbar()
            .task(id: model.nextBlockOffered) { buildOffered() }
            .onChange(of: selection) { _, id in if id != nil { inspecting = true } }
            .onAppear { if sizeClass.isWide { inspecting = true } }
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
            SlotInspector(mesocycle: found.mesocycle, day: found.day, slot: found.slot, editable: found.editable)
                .id(found.slot.id)
        } else if let current = model.analysis?.mesocycle {
            BlockOverview(mesocycle: current)
        } else {
            ContentUnavailableView("Nothing selected", systemImage: "sidebar.trailing")
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
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                Text(mesocycle.block.kind.label).font(.title3.bold())
                Text(mesocycle.rationale.headline).font(.subheadline).fixedSize(horizontal: false, vertical: true)
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
                    Button("Show in Full", systemImage: "list.bullet.rectangle", action: open)
                    if !planned && model.nextBlockOffered {
                        Button("Plan It…", systemImage: "sparkles") { model.sheet = .nextBlock }
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .background(.pageBackground)
        .accessibilityIdentifier("program.nextBlockColumn")
    }
}

/// One block: its summary, calendar and weeks over the table of its days and slots.
private struct BlockPane: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let mesocycle: Mesocycle
    let block: TrainingBlock
    @Binding var selection: ProgramRow.ID?
    /// Set for a next block: what it is and when it starts.
    let title: String?
    let editable: Bool
    @State private var swapping: ProgramRow?
    /// The table's width, for which columns fit (`allColumns`); 0 until it's laid out.
    @State private var tableWidth: CGFloat = 0

    var body: some View {
        let days = ProgramRows.days(
            of: mesocycle, nextDayID: title == nil ? model.analysis?.next?.day.id : nil, catalog: model.catalog, avoid: model.settings.avoid)
        VStack(spacing: 0) {
            header
                .padding()
            Table(of: ProgramRow.self, selection: $selection) {
                TableColumn("Exercise") { row in ExerciseCell(row: row, wide: sizeClass.isWide) }
                    .width(min: width(170, 200), ideal: 230)
                TableColumn("Block", value: \.role).width(min: width(84, 112), ideal: 92)
                TableColumn("Sets by week") { row in Text(row.sets).monospacedDigit() }.width(min: width(84, 124), ideal: 100)
                TableColumn("Reps", value: \.reps).width(min: 48, ideal: 64, max: cap(72))
                TableColumn("Rest", value: \.rest).width(min: 40, ideal: 52, max: cap(64))
                if allColumns {
                    TableColumn("Why") { row in
                        Text(row.why).foregroundStyle(.secondary).lineLimit(2).help(row.why)
                    }
                    .width(min: 120, ideal: 200)
                }
            } rows: {
                ForEach(days) { day in
                    Section {
                        ForEach(day.rows) { row in TableRow(row) }
                    } header: {
                        HStack {
                            Text(day.name).font(.headline)
                            if day.isNext { Pill(text: "Next", color: .accentColor) }
                            Spacer()
                            Text("\(day.minutes) min").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .inkList()
            .contextMenu(forSelectionType: ProgramRow.ID.self) { ids in
                if let id = ids.first, let row = days.flatMap(\.rows).first(where: { $0.id == id }) {
                    if editable && row.isStrength {
                        Button("Swap for the Rest of the Block…", systemImage: "arrow.triangle.2.circlepath") { swapping = row }
                    }
                    Button("Show in Library", systemImage: "books.vertical") { model.show(inLibrary: row.exerciseID) }
                }
            }
            .accessibilityIdentifier("program.table")
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                tableWidth = $0
            }
        }
        .sheet(item: $swapping) { row in
            if let day = mesocycle.days.first(where: { $0.id == row.dayID }), let slot = day.slots.first(where: { $0.id == row.id }) {
                ProgramSwapSheet(mesocycle: mesocycle, dayID: day.id, slot: slot)
            }
        }
    }

    /// A column's least width: the Mac's, for its 13-point table text, or iPad's and Vision Pro's,
    /// for text at 17.
    private func width(_ mac: CGFloat, _ touch: CGFloat) -> CGFloat { Platform.isMac ? mac : touch }

    /// The most a short column takes on iPad and Vision Pro, whose tables share the room out evenly
    /// rather than by ideal width.
    private func cap(_ touch: CGFloat) -> CGFloat? { Platform.isMac ? nil : touch }

    /// Room for every column. An iPad in portrait with the inspector beside the table has room for
    /// five readable ones: why each slot is there gives way to the inspector, which explains the
    /// one selected.
    private var allColumns: Bool { Platform.isMac || tableWidth == 0 || tableWidth >= 900 }

    private var header: some View {
        let weeks = ProgramLayout.calendar(
            block: block, trainingDays: Set(model.profile?.schedule.trainingDays ?? []), trained: Set(model.sessions.map(\.day)),
            vacations: vacations, today: model.today)
        return VStack(alignment: .leading, spacing: 12) {
            if sizeClass.isWide {
                HStack(alignment: .top, spacing: 24) {
                    summary.frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
                    calendar(weeks)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    summary
                    calendar(weeks)
                }
            }
            WeekStrip(block: block, today: model.today, vacations: vacations)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.tint) }
            HStack(alignment: .firstTextBaseline) {
                Text(block.kind.label).font(.title2.bold())
                Text(Format.range(block.range)).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(mesocycle.rationale.headline).font(.body).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Pill(text: mesocycle.split.label, color: .secondary)
                Pill(text: "\(mesocycle.minutesPerSession) min", color: .secondary)
                Pill(
                    text: block.deloadRange == nil ? "\(block.loadingWeeks) weeks" : "\(block.loadingWeeks) weeks + deload", color: .secondary)
            }
            if let reason = block.deloadReason { Label(reason, systemImage: "arrow.down.circle").font(.subheadline) }
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    private func calendar(_ weeks: [ProgramLayout.CalendarWeek]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            BlockCalendar(weeks: weeks).frame(maxWidth: 280)
            BlockCalendarKey()
        }
    }

    private var vacations: [DayRange] {
        model.lifeModes.compactMap { period in
            if case .vacation = period.kind { return period.range(openUntil: model.today) }
            return nil
        }
    }
}

/// The exercise column: its name, and on a narrow screen (where the table shows one column) the
/// sets and reps under it.
private struct ExerciseCell: View {
    let row: ProgramRow
    let wide: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: row.blockKind.symbol).foregroundStyle(row.blockKind.color).frame(width: 18)
                Text(row.exercise).fontWeight(row.blockKind == .main ? .semibold : .regular)
                if !row.superset.isEmpty {
                    Pill(text: "Superset \(row.superset)", color: .accentColor)
                        .help("Done in turn with the other \(row.superset) slot of the day")
                }
                if row.setAside {
                    Image(systemName: "nosign").foregroundStyle(.secondary).help("Set aside: today's session swaps it out")
                        .accessibilityLabel("Set aside")
                }
            }
            if !wide {
                Text([row.sets.isEmpty ? nil : "\(row.sets) sets", row.reps.isEmpty ? nil : row.reps].compactMap { $0 }.joined(separator: " × "))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// With nothing selected: why the block looks the way it does.
private struct BlockOverview: View {
    let mesocycle: Mesocycle

    var body: some View {
        Form {
            Section("This block") {
                Text(mesocycle.rationale.headline)
                ForEach(Array(mesocycle.rationale.reasons.enumerated()), id: \.offset) { _, reason in
                    Label(reason, systemImage: "circle.fill").labelStyle(BulletLabelStyle()).font(.subheadline)
                }
                if let confidence = mesocycle.rationale.confidence {
                    Label(confidence, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if !mesocycle.priorities.filter({ $0.emphasis != 0 }).isEmpty {
                Section("Priorities") {
                    ForEach(mesocycle.priorities.filter { $0.emphasis != 0 }) { priority in
                        VStack(alignment: .leading, spacing: 2) {
                            Label(priority.label, systemImage: priority.emphasis > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                .font(.subheadline.weight(.semibold))
                            Text(priority.reason).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                Text("Select an exercise to see why it's there, what it trains, and what could replace it for the rest of the block.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .inkList()
        .formStyle(.grouped)
    }
}

/// A slot in full: why it's there, its sets week by week, the exercise, what could replace it for
/// the rest of the block, and its day at other lengths.
private struct SlotInspector: View {
    @Environment(AppModel.self) private var model
    let mesocycle: Mesocycle
    let day: PlannedDay
    let slot: SlotPlan
    let editable: Bool

    var body: some View {
        let exercise = model.catalog.resolve(slot.exerciseID)
        let strength = slot.role == .main || slot.role == .accessory
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name).font(.title3.bold())
                    Text("\(day.name) · \(exercise.kindLine)").font(.subheadline).foregroundStyle(.secondary)
                }
                Text(slot.reason ?? ProgramRows.defaultReason(slot.role)).font(.subheadline)
                if model.settings.avoid.contains(exercise.id) {
                    Label("Set aside in Library: today's session swaps it for something else.", systemImage: "nosign").font(.footnote)
                }
            }
            if strength {
                Section("Each week") {
                    WeekSetsRow(weeks: ProgramLayout.setsByWeek(slot, block: mesocycle.block), reps: slot.repRange.label)
                    LabeledContent("Rest", value: Format.duration(slot.restSeconds))
                    if let filler = slot.restFiller { LabeledContent("In the rests", value: model.catalog.resolve(filler).name) }
                    if slot.supersetGroup != nil {
                        let partners = day.slots.filter { $0.id != slot.id && $0.supersetGroup == slot.supersetGroup }
                        LabeledContent("Superset with", value: partners.map { model.catalog.resolve($0.exerciseID).name }.joined(separator: ", "))
                    }
                }
            }
            Section("The exercise") {
                ExerciseFacts(exercise: exercise)
                Button("Show in Library", systemImage: "books.vertical") { model.show(inLibrary: exercise.id) }
            }
            if strength && editable {
                SwapSection(mesocycle: mesocycle, dayID: day.id, slot: slot)
            }
            RefitSection(mesocycle: mesocycle, day: day)
        }
        .inkList()
        .formStyle(.grouped)
        .accessibilityIdentifier("program.inspector")
    }
}

/// A slot's working sets in each week, the deload apart.
private struct WeekSetsRow: View {
    let weeks: [ProgramLayout.WeekSets]
    let reps: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                    VStack(spacing: 2) {
                        Text("\(week.sets)").font(.headline.monospacedDigit())
                        Text(week.isDeload ? "Deload" : "W\(index + 1)").font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 34)
                    .padding(.vertical, 4)
                    .background((week.isDeload ? Ink.raised : Color.accentColor.opacity(0.15)), in: .rect(cornerRadius: 8))
                }
            }
            Text("Working sets of \(reps) reps").font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            weeks.enumerated().map { index, week in "\(week.isDeload ? "deload" : "week \(index + 1)") \(week.sets) sets" }.joined(separator: ", "))
    }
}

/// What could replace the slot's exercise, and the swap itself.
private struct SwapSection: View {
    @Environment(AppModel.self) private var model
    let mesocycle: Mesocycle
    let dayID: UUID
    let slot: SlotPlan
    @State private var showAll = false

    var body: some View {
        let candidates = model.swapCandidates(for: slot.exerciseID)
        Section {
            if candidates.isEmpty {
                Text("Nothing in your gym trains the same thing without what your injuries rule out.").foregroundStyle(.secondary)
            }
            ForEach(candidates.prefix(showAll ? 20 : 6)) { exercise in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name)
                        Text(exercise.kindLine).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Swap") {
                        model.swap(slot: slot.id, day: dayID, of: mesocycle.id, to: exercise.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Swap \(exercise.name) in for the rest of the block")
                    .accessibilityLabel("Swap in \(exercise.name)")
                    .accessibilityIdentifier("program.swapOption")
                }
            }
            if candidates.count > 6 {
                Button(showAll ? "Fewer" : "More options") { showAll.toggle() }
            }
        } header: {
            Text("Swap for the rest of the block")
        } footer: {
            Text("The same movement first, from what your gym has; nothing an injury rules out or you've set aside.")
        }
    }
}

/// The slot's day fitted to 30, 45, 60 or 90 minutes: what stays, what's supersetted, what moves.
private struct RefitSection: View {
    @Environment(AppModel.self) private var model
    let mesocycle: Mesocycle
    let day: PlannedDay
    @State private var minutes: Int?
    @State private var refit: PlannedDay?

    var body: some View {
        Section {
            Picker("Minutes", selection: $minutes) {
                Text("As planned").tag(Int?.none)
                ForEach([30, 45, 60, 90], id: \.self) { Text("\($0) min").tag(Int?.some($0)) }
            }
            .accessibilityIdentifier("program.refitMinutes")
            let shown = minutes == nil ? day : refit
            if let shown {
                ForEach(shown.blocks) { block in
                    VStack(alignment: .leading, spacing: 4) {
                        Label("\(block.kind.label) · \(block.minutes) min", systemImage: block.kind.symbol)
                            .font(.subheadline.weight(.semibold)).foregroundStyle(block.kind.color)
                        ForEach(block.slots) { slot in
                            HStack {
                                Text(model.catalog.resolve(slot.exerciseID).name)
                                if slot.supersetGroup != nil { Pill(text: "Superset", color: .accentColor) }
                                Spacer()
                                if slot.role == .main || slot.role == .accessory {
                                    Text("\(slot.sets(week: 0)) × \(slot.repRange.label)").monospacedDigit().foregroundStyle(.secondary)
                                }
                            }
                            .font(.caption)
                        }
                    }
                }
                if !shown.overflow.isEmpty {
                    Text("Moved to quests: \(shown.overflow.map(\.title).joined(separator: ", ")).").font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("\(day.name) at other lengths")
        } footer: {
            Text("A look only: on the day, Today's \"Short on time?\" fits the session to the minutes you have.")
        }
        .task(id: minutes) {
            refit = minutes.flatMap { model.refitted(day, of: mesocycle, minutes: $0) }
        }
    }
}
