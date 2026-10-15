import SwiftUI
import ExerciseLibrary
import LiftEngine
import SystemCore

/// The block: its weeks and deload, its days, why it looks the way it does, and life around it.
struct PlanView: View {
    @Environment(AppModel.self) private var model
    @State private var planning = false
    @State private var lifeMode: LifeModeKindChoice?
    @State private var editing: LifeModePeriod?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let analysis = model.analysis, let mesocycle = analysis.mesocycle, let block = analysis.block {
                        header(mesocycle, block: block, analysis: analysis)
                        WeekStrip(block: block, today: model.today, vacations: vacations)
                        nextBlockPrompt(analysis, block: block)
                        if !mesocycle.priorities.isEmpty || mesocycle.block.kind == .standard { priorities(mesocycle) }
                        SectionHeader(title: "Days", detail: "\(mesocycle.days.count) a week")
                        ForEach(Array(mesocycle.days.enumerated()), id: \.element.id) { index, day in
                            NavigationLink(value: DayRoute(mesocycleID: mesocycle.id, dayID: day.id)) {
                                DayCard(day: day, isNext: analysis.next?.dayIndex == index)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        EmptyCard(symbol: "calendar", title: "No block yet", detail: "Finish setup to start your assessment.")
                    }
                    lifeModes
                }
                .padding()
                .readableWidth()
            }
            .background(.pageBackground)
            .navigationTitle("Plan")
            .navigationDestination(for: DayRoute.self) { route in DayDetail(route: route) }
            .sheet(isPresented: $planning) { NextBlockView() }
            .sheet(item: $lifeMode) { choice in LifeModeEditor(period: choice.newPeriod) }
            .sheet(item: $editing) { period in LifeModeEditor(period: period) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { model.showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
                }
            }
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
        let assessmentDone = analysis.assessment.map { $0.complete || $0.canFinishEarly } ?? false
        let ended = model.today > block.end || block.week(of: model.today) == .deload && model.today.days(until: block.end) <= 2
        if assessmentDone || ended {
            VStack(alignment: .leading, spacing: 10) {
                Text(analysis.assessment.map { $0.complete ? "Assessment done" : "Ready to finish the assessment early" } ?? "This block is wrapping up")
                    .font(.headline)
                Text("Your next block is built from everything learned: scores, imbalances, recovery and your schedule.").font(.subheadline).foregroundStyle(.secondary)
                Button { planning = true } label: { Label("Plan the next block", systemImage: "sparkles").frame(maxWidth: .infinity) }
                    .primaryAction()
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
            Toggle("Prioritise automatically", isOn: Binding(get: { model.settings.autoPrioritise }, set: { on in
                var s = model.settings
                s.autoPrioritise = on
                model.save(settings: s)
            }))
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
                Button { editing = period } label: {
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
            }
            HStack {
                Button("Vacation", systemImage: "airplane") { lifeMode = .vacation }
                Button("Crunch", systemImage: "briefcase") { lifeMode = .crunch }
                Button("Injury", systemImage: "bandage") { lifeMode = .injury }
                Button("Ill", systemImage: "thermometer.medium") { lifeMode = .illness }
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
    let route: DayRoute
    @State private var swapping: SlotPlan?

    var body: some View {
        if let mesocycle = model.mesocycles.first(where: { $0.id == route.mesocycleID }),
           let day = mesocycle.days.first(where: { $0.id == route.dayID }) {
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
                    Text("Sets listed per week of the block. Swipe an exercise to swap it for the rest of the block.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(day.name)
            .sheet(item: $swapping) { slot in
                ProgramSwapSheet(mesocycle: mesocycle, dayID: day.id, slot: slot)
            }
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
                let current = model.catalog.resolve(slot.exerciseID)
                ForEach(Substitutions.candidates(for: current, in: model.catalog.all, availability: model.gym.availability,
                                                 injuries: model.analysis?.life.injuries ?? [], avoid: model.settings.avoid, limit: 20)) { exercise in
                    Button {
                        var m = mesocycle
                        if let d = m.days.firstIndex(where: { $0.id == dayID }) {
                            for b in m.days[d].blocks.indices {
                                if let s = m.days[d].blocks[b].slots.firstIndex(where: { $0.id == slot.id }) {
                                    m.days[d].blocks[b].slots[s].exerciseID = exercise.id
                                    m.days[d].blocks[b].slots[s].reason = "You swapped this in for \(current.name)."
                                }
                            }
                        }
                        model.save(m)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(exercise.name).foregroundStyle(.primary)
                            Text(exercise.equipment.label).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Swap \(model.catalog.resolve(slot.exerciseID).name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
