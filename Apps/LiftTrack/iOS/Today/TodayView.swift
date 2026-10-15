import SwiftUI
import ExerciseLibrary
import LiftEngine
import SystemCore

/// Opens ready to train: today's session with every target, then Start. Around it, only what
/// ends in an action.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var minutes: Int?
    @State private var logActivity: ActivityLogSheetItem?
    @State private var showCheckIn = false
    @State private var lifeMode: LifeModeKindChoice?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let analysis = model.analysis {
                        ForEach(analysis.life.active) { period in LifeModeBanner(period: period) }
                        if analysis.life.reentry { reentryBanner }
                        if let status = analysis.assessment { AssessmentCard(status: status) }
                        sessionCard(analysis)
                        if !analysis.actions.isEmpty {
                            SectionHeader(title: "Do this next")
                            ForEach(analysis.actions.prefix(3)) { action in ActionCard(action: action) { perform(action) } }
                        }
                        if !analysis.quests.isEmpty {
                            SectionHeader(title: "Later today")
                            ForEach(analysis.quests) { quest in QuestRow(quest: quest) }
                        }
                        outside(analysis)
                    }
                }
                .padding()
                .readableWidth()
            }
            .background(.pageBackground)
            .navigationTitle("Today")
            .navigationSubtitle(Format.day(model.today, style: .dateTime.weekday(.wide).month(.wide).day()))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Log a class or activity", systemImage: "plus") { logActivity = ActivityLogSheetItem(declared: nil) }
                        Button("Check-in tests", systemImage: "checklist") { showCheckIn = true }
                        Divider()
                        Button("Vacation", systemImage: "airplane") { lifeMode = .vacation }
                        Button("Crunch mode", systemImage: "briefcase") { lifeMode = .crunch }
                        Button("Injury", systemImage: "bandage") { lifeMode = .injury }
                        Button("Illness", systemImage: "thermometer.medium") { lifeMode = .illness }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { model.showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .refreshable { await model.refreshHealth() }
            .sheet(item: $logActivity) { item in ActivityLogSheet(declared: item.declared) }
            .sheet(isPresented: $showCheckIn) { CheckInView() }
            .sheet(item: $lifeMode) { choice in LifeModeEditor(period: choice.newPeriod) }
        }
    }

    private var reentryBanner: some View {
        Label("First week back: easing in, a little lighter.", systemImage: "arrow.uturn.forward")
            .font(.subheadline)
            .card()
    }

    // MARK: Session

    @ViewBuilder
    private func sessionCard(_ analysis: LiftAnalysis) -> some View {
        if let live = model.live {
            VStack(alignment: .leading, spacing: 12) {
                Text(live.plan.title).font(.title2.bold())
                ProgressView(value: live.progress)
                Button { model.showSession = true } label: {
                    Label("Resume session", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .primaryAction()
                .controlSize(.large)
            }
            .card()
        } else if let next = analysis.next, let plan = model.plan(minutes: minutes) {
            SessionCard(plan: plan, next: next, minutes: $minutes, life: analysis.life) { model.start(plan) }
        } else {
            EmptyCard(symbol: "calendar.badge.plus", title: "No block yet", detail: "Plan your next block from the Plan tab.")
        }
    }

    // MARK: Outside training

    @ViewBuilder
    private func outside(_ analysis: LiftAnalysis) -> some View {
        let declared = model.profile?.declared(on: model.today) ?? []
        let todays = model.activities.filter { $0.day == model.today }
        if !declared.isEmpty || !todays.isEmpty {
            SectionHeader(title: "Outside the gym")
            ForEach(declared) { item in
                let logged = todays.contains { $0.type == item.activity }
                HStack {
                    Image(systemName: item.activity.symbol).font(.title3).frame(width: 32)
                    VStack(alignment: .leading) {
                        Text("\(item.activity.label) \(item.timeOfDay.label.lowercased())").font(.headline)
                        Text(logged ? "Logged" : "Log it after class: rounds, effort, how long you lasted.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !logged {
                        Button("Log") { logActivity = ActivityLogSheetItem(declared: item) }.secondaryAction()
                    } else {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
                .card()
            }
            ForEach(todays.filter { log in !declared.contains { $0.activity == log.type } }) { log in
                HStack {
                    Image(systemName: log.type.symbol).font(.title3).frame(width: 32)
                    VStack(alignment: .leading) {
                        Text(log.type.label).font(.headline)
                        Text("\(log.minutes) min · effort \(log.intensity)").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .card()
            }
        }
    }

    private func perform(_ action: NextAction) {
        switch action.kind {
        case .deloadEarly: model.deloadNow(reason: action.detail)
        case .checkIn: showCheckIn = true
        case .measure: model.tab = .body
        default: break
        }
    }
}

struct ActivityLogSheetItem: Identifiable {
    let id = UUID()
    let declared: RecurringActivity?
}

/// Today's session: what it is, how long, every block, and Start.
struct SessionCard: View {
    @Environment(AppModel.self) private var model
    let plan: SessionPlan
    let next: NextSession
    @Binding var minutes: Int?
    let life: LifeModeEffects
    let start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(next.scheduledToday ? "Today's session" : "Next session").font(.subheadline).foregroundStyle(.secondary)
                    Text(plan.title).font(.title.bold())
                }
                Spacer()
                Text("~\(plan.estimatedMinutes) min").font(.headline).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                if plan.assessment { Pill(text: "Assessment", symbol: "scope", color: .blue) }
                if plan.deload { Pill(text: "Deload", symbol: "arrow.down.circle", color: .teal) }
                if plan.checkIn { Pill(text: "Check-in", symbol: "checklist", color: .purple) }
                if let week = plan.week, !plan.assessment { Pill(text: "Week \(week + 1)", color: .secondary) }
                Pill(text: "\(next.doneThisWeek) of \(next.plannedThisWeek) this week", color: .secondary)
            }
            if !next.scheduledToday, let day = next.nextDay, life.trainingExpected {
                Text("Rest day. Next planned: \(Format.day(day, style: .dateTime.weekday(.wide))). Train today if you like; the plan just moves along.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if !life.trainingExpected {
                Text("Nothing is expected today. If you train anyway, keep it easy.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(Array(plan.notes.prefix(2).enumerated()), id: \.offset) { _, note in
                Text(note).font(.subheadline)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(blocks, id: \.0) { kind, items in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: kind.symbol).foregroundStyle(kind.color).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.label).font(.subheadline.weight(.semibold))
                            ForEach(items) { item in itemLine(item) }
                        }
                    }
                }
            }
            ForEach(plan.quests.filter { quest in !(model.analysis?.quests.contains { $0.id == quest.id } ?? false) }) { quest in
                Label("Moved to later: \(quest.title.lowercased())", systemImage: "clock.arrow.circlepath")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            HStack {
                Text("Short on time?").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                ForEach([30, 45, 60, 90], id: \.self) { m in
                    Button("\(m)") { minutes = minutes == m ? nil : m }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(minutes == m ? .accentColor : .secondary)
                        .controlSize(.small)
                        .accessibilityLabel("\(m) minutes")
                }
            }
            Button(action: start) {
                Label("Start", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity)
            }
            .primaryAction()
            .controlSize(.large)
        }
        .card()
    }

    private var blocks: [(SessionBlockKind, [PlannedItem])] {
        SessionBlockKind.allCases.compactMap { kind in
            let items = plan.items.filter { $0.block == kind }
            return items.isEmpty ? nil : (kind, items)
        }
    }

    @ViewBuilder
    private func itemLine(_ item: PlannedItem) -> some View {
        let exercise = model.catalog.resolve(item.exerciseID)
        let work = item.workSets
        HStack(alignment: .firstTextBaseline) {
            Text(exercise.name).font(.subheadline)
            Spacer(minLength: 8)
            Group {
                if let c = item.conditioning {
                    Text(c.summary)
                } else if item.isStrength, let first = work.first {
                    Text(first.loadKg == nil ? "\(work.count) × \(first.targetReps) · find weight" : "\(work.count) × \(Format.set(first, exercise: exercise, unit: model.gym.unit))")
                } else if let seconds = item.seconds {
                    Text(Format.duration(seconds))
                }
            }
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        if let replaced = item.substitutedFor {
            Text("Instead of \(model.catalog.resolve(replaced).name)").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// The assessment: how far along, and what's been learned so far.
struct AssessmentCard: View {
    let status: AssessmentStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Assessment", systemImage: "scope").font(.headline)
                Spacer()
                Text(status.complete ? "Done" : "Week \(status.week) of \(status.totalWeeks)").font(.subheadline).foregroundStyle(.secondary)
            }
            ProgressView(value: status.complete ? 1 : status.progress)
            Text("What we've learned").font(.subheadline.weight(.semibold))
            ForEach(Array(status.learned.enumerated()), id: \.offset) { _, line in
                Label(line, systemImage: "circle.fill").labelStyle(BulletLabelStyle()).font(.subheadline)
            }
            if status.complete {
                Text("Your first real block is ready to plan on the Plan tab.").font(.subheadline.weight(.semibold))
            } else if status.canFinishEarly {
                Text("You can finish early from the Plan tab.").font(.subheadline.weight(.semibold))
            }
        }
        .card()
    }
}

/// A prescriptive insight: what was seen, then the action.
struct ActionCard: View {
    let action: NextAction
    let perform: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(action.title, systemImage: action.stat.symbol)
                .font(.headline)
                .foregroundStyle(action.stat.color)
            Text(action.detail).font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "arrow.right.circle.fill").foregroundStyle(.tint)
                Text(action.action).font(.subheadline.weight(.semibold))
            }
            if [.deloadEarly, .checkIn, .measure].contains(action.kind) {
                Button(buttonTitle, action: perform).secondaryAction().controlSize(.small)
            }
        }
        .card()
    }

    private var buttonTitle: String {
        switch action.kind {
        case .deloadEarly: "Deload this week"
        case .checkIn: "Open check-in"
        case .measure: "Measure"
        default: "Do it"
        }
    }
}

struct QuestRow: View {
    let quest: Quest

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: quest.stat.symbol).foregroundStyle(quest.stat.color).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(quest.title).font(.subheadline.weight(.semibold))
                if !quest.detail.isEmpty { Text(quest.detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if let minutes = quest.minutes { Text("\(minutes) min").font(.caption).foregroundStyle(.secondary) }
        }
        .card(padding: 12)
    }
}
