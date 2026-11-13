import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

/// The block: its weeks and deload, its days, why it looks the way it does, and life around it.
struct PlanView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var planning = false
    @State private var lifeMode: LifeModeKindChoice?
    @State private var editing: LifeModePeriod?
    /// An exercise sent to Library from a narrow window, which has no Library: it opens here.
    @State private var focused: String?
    /// The phone's Focus, opened from the header's menu.
    @State private var showFocus = false

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if sizeClass.isWide {
                        wide
                    } else {
                        column
                    }
                }
                .padding()
            }
            .accessibilityIdentifier("plan.screen")
            .background(.pageBackground)
            .navigationTitle("Plan")
            #if os(iOS)
            // The phone draws its own header: when the block ends over a large title.
            .toolbarVisibility(sizeClass.isWide ? .automatic : .hidden, for: .navigationBar)
            #endif
            .navigationDestination(for: DayRoute.self) { route in DayDetail(route: route) }
            .navigationDestination(for: SessionRecord.self) { record in SessionDetail(record: record) }
            .navigationDestination(item: $focused) { id in PushedExerciseDetail(exerciseID: id) }
            .navigationDestination(isPresented: $showFocus) { FocusScreen(from: "Plan") }
            .onChange(of: model.libraryFocus, initial: true) { _, focus in
                // Plan is the tab a narrow window shows for Library (`AppTab.tabBarFallback`).
                guard !sizeClass.isWide, let focus else { return }
                focused = focus
                model.libraryFocus = nil
            }
            .sheet(isPresented: $planning) { NextBlockView() }
            .sheet(item: $lifeMode) { choice in LifeModeEditor(period: choice.newPeriod) }
            #if DEBUG
            // `-lifeMode vacation|crunch|injury|illness` opens that life mode's editor, as the menu's Add does.
            .onAppear {
                if let kind = LaunchOptions.current.value(after: "-lifeMode") { lifeMode = LifeModeKindChoice(rawValue: kind) }
            }
            #endif
            .sheet(item: $editing) { period in LifeModeEditor(period: period) }
            .toolbar {
                if sizeClass.isWide { SettingsToolbarItem(identifier: "plan.settings") }
            }
            .sessionResumeToolbar()
        }
    }

    /// The phone's single column, as the design has it: the block and its weeks, the priorities, and
    /// this week's sessions. Life modes and the rest are in the header's menu; a life mode under way
    /// is a row of its own.
    private var column: some View {
        VStack(alignment: .leading, spacing: 12) {
            phoneHeader
            if let analysis = model.analysis, let mesocycle = analysis.mesocycle, let block = analysis.block {
                blockCard(mesocycle, block: block, analysis: analysis)
                nextBlockPrompt(analysis, block: block)
                if !mesocycle.priorities.isEmpty || mesocycle.block.kind == .standard { priorityRows(mesocycle, analysis: analysis) }
                thisWeek(analysis, mesocycle: mesocycle)
            } else {
                EmptyCard(symbol: "calendar", title: "No block yet", detail: "Finish setup to start your assessment.")
            }
            lifeRows
        }
        .readableWidth()
    }

    private var phoneHeader: some View {
        PageHeader(
            eyebrow: model.analysis?.block.map { "Current block · ends \(Format.day($0.range.end, style: .dateTime.day().month(.abbreviated)))" },
            title: "Plan"
        ) {
            Menu {
                planMenu
            } label: {
                CircleIcon(symbol: "ellipsis")
            }
            .accessibilityLabel("Plan options")
            .accessibilityIdentifier("plan.options")
        }
        .padding(.top, -16)
    }

    /// The header's menu: what changes the plan from outside it (life, focus, the next block) and Settings.
    @ViewBuilder
    private var planMenu: some View {
        if model.nextBlockOffered {
            Button("Plan the next block", systemImage: "sparkles") { planning = true }
        }
        Section {
            Button("Vacation", systemImage: "airplane") { lifeMode = .vacation }.accessibilityIdentifier("plan.addVacation")
            Button("Crunch mode", systemImage: "briefcase") { lifeMode = .crunch }.accessibilityIdentifier("plan.addCrunch")
            Button("Injury", systemImage: "bandage") { lifeMode = .injury }.accessibilityIdentifier("plan.addInjury")
            Button("Illness", systemImage: "thermometer.medium") { lifeMode = .illness }.accessibilityIdentifier("plan.addIllness")
        } header: {
            Text("Life").eyebrow()
        }
        Section {
            Button("Focus: \(model.settings.focusSummary)", systemImage: "scope") { showFocus = true }
                .accessibilityIdentifier("plan.focus")
            Toggle("Prioritise automatically", systemImage: "wand.and.stars", isOn: model.setting(\.autoPrioritise))
        } header: {
            Text("Next block").eyebrow()
        }
        #if !os(macOS)
        Button("Settings", systemImage: "gearshape") { model.showSettings = true }
            .accessibilityIdentifier("plan.settings")
        #endif
    }

    /// The block as the design draws it: its split, what it's for and the week, why, and the weeks
    /// as bars of their load.
    private func blockCard(_ mesocycle: Mesocycle, block: TrainingBlock, analysis: LiftAnalysis) -> some View {
        let week = min(block.weeksTotal, max(1, block.start.days(until: model.today) / 7 + 1))
        let focus = block.kind == .standard ? "\(analysis.phase.kind.label) focus" : block.kind.label
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(mesocycle.split.label).font(.title3.weight(.bold)).tracking(-0.4).foregroundStyle(Ink.text)
                    Text("\(focus) · week \(week) of \(block.weeksTotal)").font(.subheadline).foregroundStyle(Ink.text2)
                }
                Spacer(minLength: 8)
                NavigationLink {
                    BlockWhyPage(mesocycle: mesocycle, block: block)
                } label: {
                    Text("Why this plan?").font(.caption).foregroundStyle(Ink.text2)
                        .padding(.top, 4)
                        .frame(minHeight: 44, alignment: .top)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("plan.why")
            }
            if let reason = block.deloadReason {
                Label(reason, systemImage: "arrow.down.circle").font(.footnote).foregroundStyle(Ink.text2)
            }
            WeekStrip(block: block, today: model.today, vacations: vacations, carded: false)
        }
        .card(padding: 16)
    }

    /// What the block favours, each with its score, as rows; Focus last.
    private func priorityRows(_ mesocycle: Mesocycle, analysis: LiftAnalysis) -> some View {
        RowCard(title: "Priorities", minHeight: 42) {
            if mesocycle.priorities.filter({ $0.emphasis != 0 }).isEmpty {
                Text("Balanced: nothing lagging enough to favour.").font(.subheadline).foregroundStyle(Ink.text2)
            }
            ForEach(mesocycle.priorities.filter { $0.emphasis != 0 }) { priority in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(priority.label).font(.callout.weight(.semibold)).foregroundStyle(Ink.text)
                        Text(
                            priority.emphasis > 0
                                ? priority.reason : "Less of it: \(priority.reason.prefix(1).lowercased() + priority.reason.dropFirst())"
                        )
                        .font(.caption).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if let score = score(of: priority, analysis: analysis) {
                        Text("\(score)").numeral(20).foregroundStyle(Ink.text2)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// The score a priority moves, when there is one.
    private func score(of priority: TrainingPriority, analysis: LiftAnalysis) -> Int? {
        let value: Double? =
            switch priority.target {
            case .category(let category): analysis.strength[category]?.score
            case .conditioning: analysis.endurance.score
            case .physique: analysis.physique.score
            default: nil
            }
        return value.map { Int($0.rounded()) }
    }

    /// This week's sessions: the ones done (opening what was done), today's and the ones to come
    /// (opening the day of the program), and every day of the block below.
    private func thisWeek(_ analysis: LiftAnalysis, mesocycle: Mesocycle) -> some View {
        let rows = ThisWeek.sessions(
            next: analysis.next, records: model.sessions, trainingDays: model.profile?.schedule.trainingDays ?? [], today: model.today)
        let done = rows.filter { $0.state == .done }.count
        return RowCard(title: "This week", detail: analysis.next.map { "\(done) of \($0.plannedThisWeek) done" }, minHeight: 48) {
            ForEach(rows) { row in
                if row.state == .done, let id = row.sessionID, let record = model.sessions.first(where: { $0.id == id }) {
                    NavigationLink(value: record) { WeekSessionRow(row: row) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("plan.session")
                } else if let dayID = row.dayID {
                    NavigationLink(value: DayRoute(mesocycleID: mesocycle.id, dayID: dayID)) { WeekSessionRow(row: row) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("plan.day")
                } else {
                    WeekSessionRow(row: row)
                }
            }
            NavigationLink {
                BlockDaysPage(mesocycle: mesocycle, nextIndex: analysis.next?.dayIndex)
            } label: {
                LinkRowLabel(title: "Every day of the block", caption: nil, trailing: "\(mesocycle.days.count)")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("plan.allDays")
        }
    }

    /// Life modes under way or to come, as rows that open them.
    private var lifeRows: some View {
        let upcoming = model.lifeModes.filter { $0.end.map { $0 >= model.today } ?? true }
        return RowCard(title: "Life") {
            ForEach(upcoming) { period in
                Button {
                    editing = period
                } label: {
                    LinkRowLabel(
                        title: period.kind.label,
                        caption: period.end.map { Format.range(DayRange(period.start, $0)) } ?? "Since \(Format.day(period.start))")
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Edit…", systemImage: "pencil") { editing = period }
                    if model.canEnd(period) {
                        Button("End It Now", systemImage: "stop.circle") { model.end(lifeMode: period) }
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) { model.delete(lifeMode: period.id) }
                }
                .accessibilityIdentifier("plan.lifeMode")
            }
        }
    }

    /// The block and life beside its days, which sit in a grid.
    private var wide: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                if let analysis = model.analysis, let mesocycle = analysis.mesocycle, let block = analysis.block {
                    header(mesocycle, block: block, analysis: analysis)
                    WeekStrip(block: block, today: model.today, vacations: vacations)
                    nextBlockPrompt(analysis, block: block)
                    if !mesocycle.priorities.isEmpty || mesocycle.block.kind == .standard { priorities(mesocycle) }
                } else {
                    EmptyCard(symbol: "calendar", title: "No block yet", detail: "Finish setup to start your assessment.")
                }
                lifeModes
            }
            .frame(minWidth: 320, maxWidth: 420)
            if let analysis = model.analysis, let mesocycle = analysis.mesocycle {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        SectionHeader(title: "Days", detail: "\(mesocycle.days.count) a week")
                        Button("Open Program", systemImage: "list.bullet.rectangle") { model.tab = .program }
                            .buttonStyle(.borderless)
                            .help("Every slot, week by week, with swaps")
                            .accessibilityIdentifier("plan.openProgram")
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)], spacing: 16) {
                        days(mesocycle, analysis: analysis)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: 1400)
        .frame(maxWidth: .infinity)
    }

    private func days(_ mesocycle: Mesocycle, analysis: LiftAnalysis) -> some View {
        ForEach(Array(mesocycle.days.enumerated()), id: \.element.id) { index, day in
            NavigationLink(value: DayRoute(mesocycleID: mesocycle.id, dayID: day.id)) {
                DayCard(day: day, isNext: analysis.next?.dayIndex == index)
            }
            .buttonStyle(.plain)
            .hoverHighlight()
            .accessibilityIdentifier("plan.day")
        }
    }

    private var vacations: [DayRange] {
        model.lifeModes.compactMap { period in
            if case .vacation = period.kind { return period.range(openUntil: model.today) }
            return nil
        }
    }

    private func header(_ mesocycle: Mesocycle, block: TrainingBlock, analysis: LiftAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(block.kind.label).font(.title2.bold())
                Spacer()
                Text(Format.range(block.range)).font(.subheadline).foregroundStyle(Ink.text2)
            }
            Text(mesocycle.rationale.headline).font(.body)
            HStack(spacing: 6) {
                Pill(text: mesocycle.split.label, color: .secondary)
                Pill(text: "\(mesocycle.minutesPerSession) min", color: .secondary)
                if block.kind == .standard { Pill(text: analysis.phase.kind.label, color: .secondary) }
            }
            if let reason = block.deloadReason { Label(reason, systemImage: "arrow.down.circle").font(.subheadline) }
            WhyDisclosure(rationale: mesocycle.rationale)
        }
        .card()
    }

    @ViewBuilder
    private func nextBlockPrompt(_ analysis: LiftAnalysis, block: TrainingBlock) -> some View {
        if let upcoming = analysis.upcoming {
            // Already planned: it waits for its start, so this block keeps its deload and check-in.
            VStack(alignment: .leading, spacing: 6) {
                Label("Next block starts \(Format.day(upcoming.block.start))", systemImage: "calendar.badge.clock").font(.headline)
                    .accessibilityIdentifier("plan.upcoming")
                Text(upcoming.rationale.headline).font(.subheadline).foregroundStyle(.secondary)
            }
            .card()
        } else if model.nextBlockOffered {
            VStack(alignment: .leading, spacing: 10) {
                Text(
                    analysis.assessment.map { $0.complete ? "Assessment done" : "Ready to finish the assessment early" }
                        ?? "This block is wrapping up"
                )
                .font(.headline)
                Text("Your next block is built from everything learned: scores, imbalances, recovery and your schedule.").font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    planning = true
                } label: {
                    Label("Plan the next block", systemImage: "sparkles").frame(maxWidth: .infinity)
                }
                .primaryAction()
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .accessibilityIdentifier("plan.nextBlock")
            }
            .card()
        }
    }

    private func priorities(_ mesocycle: Mesocycle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Priorities").font(.headline)
            if mesocycle.priorities.isEmpty {
                Text("Balanced: nothing lagging enough to favour.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(mesocycle.priorities.filter { $0.emphasis != 0 }) { priority in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: priority.emphasis > 0 ? "arrow.up" : "arrow.down")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(priority.emphasis > 0 ? Color.accentColor : Ink.text3)
                        .accessibilityLabel(priority.emphasis > 0 ? "More" : "Less")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(priority.label).font(.subheadline.weight(.semibold))
                        Text(priority.reason).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            NavigationLink {
                FocusScreen()
            } label: {
                HStack {
                    Text("Focus")
                    Spacer()
                    Text(model.settings.focusSummary).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .font(.subheadline)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .hoverHighlight()
            Toggle("Prioritise automatically", isOn: model.setting(\.autoPrioritise))
                .font(.subheadline)
                .tint(.accentColor)
            Text("Takes effect at the next block.").font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }

    private var lifeModes: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Life", detail: nil)
            let upcoming = model.lifeModes.filter { $0.end.map { $0 >= model.today } ?? true }
            ForEach(upcoming) { period in
                Button {
                    editing = period
                } label: {
                    HStack {
                        Image(systemName: period.kind.symbol).frame(width: 28)
                        VStack(alignment: .leading) {
                            Text(period.kind.label).font(.subheadline.weight(.semibold))
                            Text(period.end.map { Format.range(DayRange(period.start, $0)) } ?? "Since \(Format.day(period.start))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .card(padding: 12)
                }
                .buttonStyle(.plain)
                .hoverHighlight()
                .contextMenu {
                    Button("Edit…", systemImage: "pencil") { editing = period }
                    if model.canEnd(period) {
                        Button("End It Now", systemImage: "stop.circle") { model.end(lifeMode: period) }
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) { model.delete(lifeMode: period.id) }
                }
                .accessibilityIdentifier("plan.lifeMode")
            }
            HStack {
                Button("Vacation", systemImage: "airplane") { lifeMode = .vacation }.accessibilityIdentifier("plan.addVacation")
                Button("Crunch", systemImage: "briefcase") { lifeMode = .crunch }.accessibilityIdentifier("plan.addCrunch")
                Button("Injury", systemImage: "bandage") { lifeMode = .injury }.accessibilityIdentifier("plan.addInjury")
                Button("Ill", systemImage: "thermometer.medium") { lifeMode = .illness }.accessibilityIdentifier("plan.addIllness")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            Text("Life modes apply across every app. None of them ever count as failure.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct DayRoute: Hashable {
    let mesocycleID: UUID
    let dayID: UUID
}

/// The block's weeks as bars of their load: rising through the loading weeks, short for the
/// deload. The weeks done are grey, this week is the accent, a vacation carries a plane.
struct WeekStrip: View {
    let block: TrainingBlock
    let today: Day
    let vacations: [DayRange]
    /// In a card of its own, or inside the block's.
    var carded = true

    var body: some View {
        let weeks = max(1, block.weeksTotal)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<weeks, id: \.self) { index in
                let start = block.start.adding(weeks: index)
                let range = DayRange(start, start.adding(days: 6))
                let week = block.week(of: start)
                let current = range.contains(today)
                let done = range.end < today
                let away = vacations.contains { $0.overlaps(range) }
                VStack(alignment: .leading, spacing: 6) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(current ? Color.accentColor : (done ? Ink.text3 : Ink.track))
                            .frame(height: 44 * height(week))
                            .overlay {
                                if away { Image(systemName: "airplane").font(.caption2).foregroundStyle(current ? Ink.onAccent : Ink.text) }
                            }
                    }
                    .frame(height: 44)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(label(week, index: index)).font(.caption.weight(.semibold)).foregroundStyle(current ? Ink.text : Ink.text2)
                        Text(state(week, current: current, done: done, away: away)).font(.caption2).foregroundStyle(Ink.text3)
                    }
                    .lineLimit(1)
                    // Seven weeks across a small phone leave each about 38 points.
                    .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                // Its name and state, as drawn ("Week 3, Now"); a week away this week says both.
                .accessibilityLabel(
                    [label(week, index: index), state(week, current: current, done: done, away: away), away && current ? "this week" : ""]
                        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        .joined(separator: ", "))
            }
        }
        .padding(carded ? 14 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(carded ? Color.cardBackground : .clear, in: .rect(cornerRadius: 22, style: .continuous))
    }

    /// How tall a week's bar is: its share of the block's heaviest load.
    private func height(_ week: BlockWeek) -> Double {
        switch week {
        case .deload: 0.46
        case .loading(let i): 0.55 + 0.45 * Double(i + 1) / Double(max(1, block.loadingWeeks))
        default: 0.5
        }
    }

    private func label(_ week: BlockWeek, index: Int) -> String {
        switch week {
        case .deload: "Deload"
        case .loading(let i): "Week \(i + 1)"
        default: "Week \(index + 1)"
        }
    }

    private func state(_ week: BlockWeek, current: Bool, done: Bool, away: Bool) -> String {
        if away { return "Away" }
        if current { return "Now" }
        if done { return "Done" }
        if case .loading(let i) = week, i + 1 == block.loadingWeeks, block.loadingWeeks > 1 { return "Heaviest" }
        return " "
    }
}

struct DayCard: View {
    @Environment(AppModel.self) private var model
    let day: PlannedDay
    let isNext: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(day.name).font(.headline)
                if isNext { Pill(text: "Next", color: .accentColor) }
                Spacer()
                Text("\(day.minutes) min").font(.subheadline).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            ForEach(day.strengthSlots) { slot in
                let exercise = model.catalog.resolve(slot.exerciseID)
                HStack {
                    Text(exercise.name).font(.subheadline)
                    Spacer()
                    Text("\(slot.sets(week: 0)) × \(slot.repRange.label)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            let extras = day.blocks.filter { $0.kind != .main && $0.kind != .accessory }
            if !extras.isEmpty {
                Text(extras.map { "\($0.kind.label) \($0.minutes) min" }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }
}

/// A day in full: every block, every slot and why it's there, with swaps for the rest of the block.
struct DayDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let route: DayRoute
    @State private var swapping: SlotPlan?
    /// An exercise shown in place, in a narrow window, which has no Library to send it to.
    @State private var shownExercise: String?

    var body: some View {
        if let mesocycle = model.mesocycles.first(where: { $0.id == route.mesocycleID }),
            let day = mesocycle.days.first(where: { $0.id == route.dayID })
        {
            List {
                ForEach(day.blocks) { block in
                    Section {
                        ForEach(block.slots) { slot in
                            let exercise = model.catalog.resolve(slot.exerciseID)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(exercise.name).font(.body.weight(.medium))
                                    Spacer()
                                    if let c = slot.conditioning {
                                        Text(c.summary).font(.subheadline).foregroundStyle(.secondary)
                                    } else if slot.role == .main || slot.role == .accessory {
                                        Text("\(slot.sets.map(String.init).joined(separator: "/")) × \(slot.repRange.label)")
                                            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                                    } else if let s = slot.seconds {
                                        Text(Format.duration(s)).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                if slot.role == .main || slot.role == .accessory {
                                    Text("Rest \(Format.duration(slot.restSeconds)) · \(exercise.safetyTier.label.lowercased())")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                if let reason = slot.reason { Text(reason).font(.caption).foregroundStyle(.tint) }
                                if let filler = slot.restFiller { Text("In the rests: \(model.catalog.resolve(filler).name)").font(.caption) }
                            }
                            .swipeActions {
                                if slot.role == .main || slot.role == .accessory {
                                    Button("Swap") { swapping = slot }.tint(.accentColor)
                                }
                            }
                            .contextMenu { menu(slot) }
                        }
                    } header: {
                        Label("\(block.kind.label) · \(block.minutes) min", systemImage: block.kind.symbol)
                    }
                }
                if !day.overflow.isEmpty {
                    Section {
                        ForEach(day.overflow, id: \.title) { Text($0.title) }
                    } header: {
                        Text("Didn't fit, offered as quests").eyebrow()
                    }
                }
                Section {
                    Text(
                        Platform.isPhoneOrPad
                            ? "Sets listed per week of the block. Swipe an exercise, or touch and hold it, to swap it for the rest of the block."
                            : "Sets listed per week of the block. Control-click an exercise to swap it for the rest of the block."
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .inkList()
            .navigationTitle(day.name)
            .navigationDestination(item: $shownExercise) { id in PushedExerciseDetail(exerciseID: id) }
            .sheet(item: $swapping) { slot in
                ProgramSwapSheet(mesocycle: mesocycle, dayID: day.id, slot: slot)
            }
        }
    }

    @ViewBuilder
    private func menu(_ slot: SlotPlan) -> some View {
        if slot.role == .main || slot.role == .accessory {
            Button("Swap for the Rest of the Block…", systemImage: "arrow.triangle.2.circlepath") { swapping = slot }
        }
        // There's no Library in a narrow window: the exercise opens here instead.
        if sizeClass.isWide {
            Button("Show in Library", systemImage: "books.vertical") { model.show(inLibrary: slot.exerciseID) }
        } else {
            Button("Show Exercise", systemImage: "info.circle") { shownExercise = slot.exerciseID }
        }
    }
}

/// Swaps a slot's exercise for the rest of the block.
struct ProgramSwapSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let mesocycle: Mesocycle
    let dayID: UUID
    let slot: SlotPlan

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    let current = model.catalog.resolve(slot.exerciseID)
                    SheetHeading(eyebrow: "Swap · for the rest of the block", title: current.name)
                    RowCard(title: "Best fits in this gym") {
                        ForEach(model.swapCandidates(for: slot.exerciseID)) { exercise in
                            Button {
                                model.swap(slot: slot.id, day: dayID, of: mesocycle.id, to: exercise.id)
                                dismiss()
                            } label: {
                                LinkRowLabel(
                                    title: exercise.name,
                                    caption: SwapReason.line(for: exercise, replacing: current, injuries: model.analysis?.life.injuries ?? []))
                            }
                            .buttonStyle(.plain)
                            .hoverHighlight()
                            .accessibilityIdentifier("programSwap.option")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .readableWidth(620)
            }
            .inkSheet {
                SheetBar(label: "Cancel", identifier: "programSwap.cancel") { dismiss() }
            }
        }
        .sheetFrame(minHeight: 480)
    }
}

/// One of this week's sessions on Plan: the weekday, its name, its minutes and whether it's done.
struct WeekSessionRow: View {
    let row: WeekSession

    var body: some View {
        let today = row.state == .today
        HStack(spacing: 12) {
            Text(row.day.weekday.short).font(.caption.weight(.semibold)).foregroundStyle(today ? Color.accentColor : Ink.text3)
                .frame(width: 34, alignment: .leading)
            Text(row.title).font(.callout.weight(.semibold)).foregroundStyle(row.state == .done ? Ink.text2 : Ink.text).lineLimit(1)
            Spacer(minLength: 4)
            Text(row.state == .done ? "\(row.minutes) min" : "~\(row.minutes) min").font(.caption.monospacedDigit()).foregroundStyle(Ink.text3)
            HStack(spacing: 6) {
                switch row.state {
                case .done: Text("Done").font(.caption).foregroundStyle(Ink.text3)
                case .today: Text("Today").font(.caption).foregroundStyle(Color.accentColor)
                case .planned: EmptyView()
                }
                Circle().fill(row.state == .done ? Ink.good : (today ? Color.accentColor : Ink.track)).frame(width: 8, height: 8)
            }
            .frame(width: 62, alignment: .trailing)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityValue(row.state == .done ? "Done" : (today ? "Today" : "Planned"))
    }
}

/// Why the block looks the way it does, opened from its card: the headline and every reason.
struct BlockWhyPage: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let mesocycle: Mesocycle
    let block: TrainingBlock

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !sizeClass.isWide { DetailHeader(eyebrow: "Plan", title: "Why this plan?") }
                VStack(alignment: .leading, spacing: 10) {
                    Text(mesocycle.rationale.headline).font(.body.weight(.semibold)).foregroundStyle(Ink.text)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(mesocycle.rationale.reasons.enumerated()), id: \.offset) { _, reason in
                        Label(reason, systemImage: "circle.fill").labelStyle(BulletLabelStyle()).font(.subheadline).foregroundStyle(Ink.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let confidence = mesocycle.rationale.confidence {
                        Text(confidence).font(.footnote).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .card()
                RowCard {
                    detail("Dates", Format.range(block.range))
                    detail("Split", mesocycle.split.label)
                    detail("Sessions", "\(mesocycle.days.count) a week · \(mesocycle.minutesPerSession) min")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .readableWidth()
        }
        .background(.pageBackground)
        .detailPage(title: "Why this plan?", wide: sizeClass.isWide)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(Ink.text2)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Every day of the block, each with its lifts, opening the day in full.
struct BlockDaysPage: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let mesocycle: Mesocycle
    let nextIndex: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !sizeClass.isWide { DetailHeader(eyebrow: "Plan", title: "The block's days") }
                ForEach(Array(mesocycle.days.enumerated()), id: \.element.id) { index, day in
                    NavigationLink(value: DayRoute(mesocycleID: mesocycle.id, dayID: day.id)) {
                        DayCard(day: day, isNext: nextIndex == index)
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight()
                    .accessibilityIdentifier("plan.blockDay")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .readableWidth()
        }
        .background(.pageBackground)
        .detailPage(title: "Days", wide: sizeClass.isWide)
    }
}
