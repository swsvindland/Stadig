import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

/// A lift selected on the desk, in full: where it is tonight, its estimated one-rep max and its line,
/// its score on the levels' ruler, what could replace it for the rest of the block, its sets each
/// week, its day at other lengths, and the exercise's facts.
struct SlotInspector: View {
    @Environment(AppModel.self) private var model
    let mesocycle: Mesocycle
    let day: PlannedDay
    let slot: SlotPlan
    let editable: Bool
    /// The block running now, where tonight's targets mean something.
    let current: Bool
    @State private var shown: ExerciseDetailContent?

    var body: some View {
        let exercise = model.catalog.resolve(slot.exerciseID)
        let strength = slot.role == .main || slot.role == .accessory
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow(exercise)).eyebrow(.accentColor).lineLimit(2)
                    PageTitle(exercise.name, size: 24)
                    Text(slot.reason ?? ProgramRows.defaultReason(slot.role)).font(.subheadline).foregroundStyle(Ink.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                    if model.settings.avoid.contains(exercise.id) {
                        Label("Set aside in Library: today's session swaps it for something else.", systemImage: "nosign")
                            .font(.footnote).foregroundStyle(Ink.text2).padding(.top, 2)
                    }
                }
                if strength, let shown { estimate(shown, exercise: exercise) }
                if strength && editable { SwapList(mesocycle: mesocycle, dayID: day.id, slot: slot) }
                if strength {
                    WeekSetsRow(weeks: ProgramLayout.setsByWeek(slot, block: mesocycle.block), reps: slot.repRange.label)
                    restLines
                }
                RefitCard(mesocycle: mesocycle, day: day)
                VStack(alignment: .leading, spacing: 10) {
                    SectionEyebrow("The exercise")
                    ExerciseFacts(exercise: exercise)
                    Button("Show in Library", systemImage: "books.vertical") { model.show(inLibrary: exercise.id) }
                        .secondaryAction()
                        .controlSize(.small)
                }
                .card(padding: 14, radius: 18)
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .task(id: slot.exerciseID) { shown = ExerciseDetailContent(exercise: model.catalog.resolve(slot.exerciseID), model: model) }
        .accessibilityIdentifier("program.inspector")
    }

    /// "Upper A · Tonight · 3 × 6 at 42.5 kg", or the day and what the exercise is.
    private func eyebrow(_ exercise: Exercise) -> String {
        if current, let plan = model.plan(), plan.dayID == day.id, let item = plan.items.first(where: { $0.slotID == slot.id }),
            let first = item.workSets.first
        {
            let when = model.analysis?.next?.scheduledToday == true ? "Today" : "Next"
            let load = first.loadKg.map { " at \(Format.load($0, unit: model.gym.unit, basis: exercise.loadBasis))" } ?? ""
            return "\(day.name) · \(when) · \(item.workSets.count) × \(first.targetReps)\(load)"
        }
        return "\(day.name) · \(exercise.kindLine)"
    }

    /// The estimated one-rep max as the hero, its line and what it says, and the score on the levels.
    @ViewBuilder
    private func estimate(_ shown: ExerciseDetailContent, exercise: Exercise) -> some View {
        if let current = shown.record.current {
            let unit = model.gym.unit
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Format.number(unit.fromKilograms(current), digits: 1)).numeral(64, weight: .heavy).foregroundStyle(Ink.text)
                    Text("\(unit.symbol) est. 1RM").font(.title3.weight(.semibold)).foregroundStyle(Ink.text2)
                }
                .accessibilityElement(children: .combine)
                if let sentence = shown.sentence {
                    Text(sentence).font(.subheadline.weight(.semibold)).foregroundStyle(shown.movementColor)
                }
                if shown.record.trend.count >= 2 {
                    EstimateLine(points: shown.points, domain: shown.domain)
                        .accessibilityLabel("\(exercise.name) estimated one-rep max over time")
                    HStack {
                        ForEach(Array(shown.scale.enumerated()), id: \.offset) { index, label in
                            if index > 0 { Spacer() }
                            ScaleLabel(label)
                        }
                    }
                    .accessibilityHidden(true)
                }
                if let score = shown.score {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("Score \(Int(score.rounded()))").font(.headline).foregroundStyle(Ink.text)
                            Text("· \(StrengthStandards.level(for: score))").font(.headline.weight(.medium)).foregroundStyle(Ink.text3)
                            Spacer(minLength: 8)
                            if let next = LevelRuler.next(score) { Text(next).font(.caption).foregroundStyle(Ink.text2) }
                        }
                        .accessibilityElement(children: .combine)
                        LevelRuler(score: score, height: 14, short: true)
                    }
                    .padding(.top, 6)
                }
            }
        } else {
            Text("Not done yet. Once it's in a session, its estimated one-rep max and its line show here.")
                .font(.subheadline).foregroundStyle(Ink.text2)
                .card(padding: 14, radius: 18)
        }
    }

    @ViewBuilder
    private var restLines: some View {
        let partners = slot.supersetGroup == nil ? [] : day.slots.filter { $0.id != slot.id && $0.supersetGroup == slot.supersetGroup }
        RowCard(minHeight: 40) {
            InspectorLine(title: "Rest", value: Format.duration(slot.restSeconds))
            if let filler = slot.restFiller { InspectorLine(title: "In the rests", value: model.catalog.resolve(filler).name) }
            if !partners.isEmpty {
                InspectorLine(title: "Superset with", value: partners.map { model.catalog.resolve($0.exerciseID).name }.joined(separator: ", "))
            }
        }
    }
}

/// A title and its value, as an inspector's quiet rows have them.
private struct InspectorLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline).foregroundStyle(Ink.text2)
            Spacer(minLength: 8)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A slot's working sets in each week, the deload apart, as small numbered columns.
private struct WeekSetsRow: View {
    let weeks: [ProgramLayout.WeekSets]
    let reps: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow("Each week", detail: "Working sets of \(reps)")
            HStack(spacing: 6) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                    VStack(spacing: 2) {
                        Text("\(week.sets)").numeral(20)
                        Text(week.isDeload ? "Deload" : "Week \(index + 1)").font(.caption2).foregroundStyle(Ink.text3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(week.isDeload ? Ink.raised : Color.cardBackground, in: .rect(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            weeks.enumerated().map { index, week in "\(week.isDeload ? "deload" : "week \(index + 1)") \(week.sets) sets" }.joined(separator: ", "))
    }
}

/// What could replace the slot's exercise for the rest of the block, numbered, each with Swap.
private struct SwapList: View {
    @Environment(AppModel.self) private var model
    let mesocycle: Mesocycle
    let dayID: UUID
    let slot: SlotPlan
    @State private var showAll = false

    var body: some View {
        let candidates = model.swapCandidates(for: slot.exerciseID)
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow("Swap for", detail: "the rest of the block")
            if candidates.isEmpty {
                Text("Nothing in your gym trains the same thing without what your injuries rule out.")
                    .font(.subheadline).foregroundStyle(Ink.text2)
            }
            VStack(spacing: 6) {
                ForEach(Array(candidates.prefix(showAll ? 20 : 3).enumerated()), id: \.element.id) { index, exercise in
                    HStack(spacing: 12) {
                        Text("\(index + 1)").font(.caption.weight(.semibold)).foregroundStyle(Ink.text2)
                            .frame(width: 22, height: 22)
                            .background(Ink.raised, in: .rect(cornerRadius: 6))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(exercise.name).font(.callout.weight(.semibold)).foregroundStyle(Ink.text)
                            Text(exercise.kindLine).font(.caption).foregroundStyle(Ink.text3)
                        }
                        Spacer(minLength: 6)
                        Button("Swap") {
                            model.swap(slot: slot.id, day: dayID, of: mesocycle.id, to: exercise.id)
                        }
                        .secondaryAction()
                        .controlSize(.small)
                        .help("Swap \(exercise.name) in for the rest of the block")
                        .accessibilityLabel("Swap in \(exercise.name)")
                        .accessibilityIdentifier("program.swapOption")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(index == 0 ? Ink.raised : Color.cardBackground, in: .rect(cornerRadius: 12, style: .continuous))
                }
            }
            if candidates.count > 3 {
                Button(showAll ? "Fewer" : "More options") { showAll.toggle() }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
            }
            Text("The same movement first, from what your gym has; nothing an injury rules out or you've set aside.")
                .font(.caption).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The slot's day fitted to 30, 45, 60 or 90 minutes: what stays, what's supersetted, what moves.
private struct RefitCard: View {
    @Environment(AppModel.self) private var model
    let mesocycle: Mesocycle
    let day: PlannedDay
    @State private var minutes = 0
    @State private var refit: PlannedDay?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow("\(day.name) at other lengths")
            InkSegmented(options: [(0, "Planned")] + [30, 45, 60, 90].map { ($0, "\($0) min") }, selection: $minutes)
                .accessibilityIdentifier("program.refitMinutes")
            let shown = minutes == 0 ? day : refit
            if let shown {
                ForEach(shown.blocks) { block in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(block.kind.label) · \(block.minutes) min").font(.caption.weight(.semibold)).foregroundStyle(Ink.text2)
                        ForEach(block.slots) { slot in
                            HStack {
                                Text(model.catalog.resolve(slot.exerciseID).name).foregroundStyle(Ink.text)
                                if slot.supersetGroup != nil { Pill(text: "Superset", color: .accentColor) }
                                Spacer()
                                if slot.role == .main || slot.role == .accessory {
                                    Text("\(slot.sets(week: 0)) × \(slot.repRange.label)").monospacedDigit().foregroundStyle(Ink.text3)
                                }
                            }
                            .font(.caption)
                        }
                    }
                }
                if !shown.overflow.isEmpty {
                    Text("Moved to quests: \(shown.overflow.map(\.title).joined(separator: ", ")).").font(.caption).foregroundStyle(Ink.text3)
                }
            }
            Text("A look only: on the day, Today's \"Short on time?\" fits the session to the minutes you have.")
                .font(.caption).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: 14, radius: 18)
        .task(id: minutes) {
            refit = minutes == 0 ? nil : model.refitted(day, of: mesocycle, minutes: minutes)
        }
    }
}

/// With nothing selected: why the block looks the way it does, its priorities and its calendar.
struct BlockOverview: View {
    @Environment(AppModel.self) private var model
    let mesocycle: Mesocycle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("This block").eyebrow(.accentColor)
                    PageTitle(mesocycle.block.kind.label, size: 24)
                    Text(Format.range(mesocycle.block.range)).font(.subheadline).foregroundStyle(Ink.text2)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(mesocycle.rationale.headline).font(.callout.weight(.semibold)).foregroundStyle(Ink.text)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(mesocycle.rationale.reasons.enumerated()), id: \.offset) { _, reason in
                        Label(reason, systemImage: "circle.fill").labelStyle(BulletLabelStyle()).font(.subheadline).foregroundStyle(Ink.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let confidence = mesocycle.rationale.confidence {
                        Text(confidence).font(.footnote).foregroundStyle(Ink.text3)
                    }
                }
                .card(padding: 14, radius: 18)
                let priorities = mesocycle.priorities.filter { $0.emphasis != 0 }
                if !priorities.isEmpty {
                    RowCard(title: "Priorities") {
                        ForEach(priorities) { priority in
                            VStack(alignment: .leading, spacing: 2) {
                                Label(priority.label, systemImage: priority.emphasis > 0 ? "arrow.up" : "arrow.down")
                                    .font(.callout.weight(.semibold)).foregroundStyle(Ink.text)
                                Text(priority.reason).font(.caption).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    SectionEyebrow("Calendar")
                    BlockCalendar(weeks: calendar).frame(maxWidth: 300, alignment: .leading)
                    BlockCalendarKey()
                    if let reason = mesocycle.block.deloadReason {
                        Label(reason, systemImage: "arrow.down.circle").font(.footnote).foregroundStyle(Ink.text2)
                    }
                }
                .card(padding: 14, radius: 18)
                Text("Select a lift to see where it stands, why it's there, and what could replace it for the rest of the block.")
                    .font(.footnote).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
    }

    private var calendar: [ProgramLayout.CalendarWeek] {
        let vacations = model.lifeModes.compactMap { period -> DayRange? in
            if case .vacation = period.kind { return period.range(openUntil: model.today) }
            return nil
        }
        return ProgramLayout.calendar(
            block: mesocycle.block, trainingDays: Set(model.profile?.schedule.trainingDays ?? []), trained: Set(model.sessions.map(\.day)),
            vacations: vacations, today: model.today)
    }
}
