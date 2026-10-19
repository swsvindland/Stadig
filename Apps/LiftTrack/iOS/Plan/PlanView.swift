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
            .navigationDestination(for: DayRoute.self) { route in DayDetail(route: route) }
            .sheet(isPresented: $planning) { NextBlockView() }
            .sheet(item: $lifeMode) { choice in LifeModeEditor(period: choice.newPeriod) }
            .sheet(item: $editing) { period in LifeModeEditor(period: period) }
            .toolbar {
                SettingsToolbarItem(identifier: "plan.settings")
            }
            .sessionResumeToolbar()
        }
    }

    /// The phone's single column, unchanged.
    private var column: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let analysis = model.analysis, let mesocycle = analysis.mesocycle, let block = analysis.block {
                header(mesocycle, block: block, analysis: analysis)
                WeekStrip(block: block, today: model.today, vacations: vacations)
                nextBlockPrompt(analysis, block: block)
                if !mesocycle.priorities.isEmpty || mesocycle.block.kind == .standard { priorities(mesocycle) }
                SectionHeader(title: "Days", detail: "\(mesocycle.days.count) a week")
                days(mesocycle, analysis: analysis)
            } else {
                EmptyCard(symbol: "calendar", title: "No block yet", detail: "Finish setup to start your assessment.")
            }
            lifeModes
        }
        .readableWidth()
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
                Text(Format.range(block.range)).font(.subheadline).foregroundStyle(.secondary)
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
                    Image(systemName: priority.emphasis > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .foregroundStyle(priority.emphasis > 0 ? Color.green : Color.secondary)
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

/// The block's weeks: loading, deload, vacations, today.
struct WeekStrip: View {
    let block: TrainingBlock
    let today: Day
    let vacations: [DayRange]

    var body: some View {
        let weeks = max(1, block.weeksTotal)
        HStack(spacing: 6) {
            ForEach(0..<weeks, id: \.self) { index in
                let start = block.start.adding(weeks: index)
                let week = block.week(of: start)
                let current = DayRange(start, start.adding(days: 6)).contains(today)
                let away = vacations.contains { $0.overlaps(DayRange(start, start.adding(days: 6))) }
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(color(week, away: away))
                        .frame(height: 28)
                        .overlay {
                            if away { Image(systemName: "airplane").font(.caption2).foregroundStyle(.white) }
                        }
                        .overlay { if current { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary, lineWidth: 2) } }
                    Text(label(week, index: index)).font(.caption2).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(label(week, index: index))\(current ? ", this week" : "")\(away ? ", vacation" : "")")
            }
        }
        .card(padding: 12)
    }

    private func color(_ week: BlockWeek, away: Bool) -> Color {
        if away { return .teal }
        switch week {
        case .deload: return .mint.opacity(0.6)
        case .loading(let i): return .orange.opacity(0.35 + 0.6 * Double(i + 1) / Double(max(1, block.loadingWeeks)))
        default: return .secondary.opacity(0.2)
        }
    }

    private func label(_ week: BlockWeek, index: Int) -> String {
        switch week {
        case .deload: "Deload"
        case .loading(let i): "W\(i + 1)"
        default: "W\(index + 1)"
        }
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
                                    Button("Swap") { swapping = slot }.tint(.blue)
                                }
                            }
                            .contextMenu { menu(slot) }
                        }
                    } header: {
                        Label("\(block.kind.label) · \(block.minutes) min", systemImage: block.kind.symbol)
                    }
                }
                if !day.overflow.isEmpty {
                    Section("Didn't fit, offered as quests") {
                        ForEach(day.overflow, id: \.title) { Text($0.title) }
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
            List {
                ForEach(model.swapCandidates(for: slot.exerciseID)) { exercise in
                    Button {
                        model.swap(slot: slot.id, day: dayID, of: mesocycle.id, to: exercise.id)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(exercise.name).foregroundStyle(.primary)
                            Text(exercise.equipment.label).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("programSwap.option")
                }
            }
            .navigationTitle("Swap \(model.catalog.resolve(slot.exerciseID).name)")
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .sheetFrame(minHeight: 480)
    }
}
