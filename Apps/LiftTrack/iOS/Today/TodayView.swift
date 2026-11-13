import Charts
import ExerciseLibrary
import HealthBridge
import LiftEngine
import SwiftUI
import SystemCore

/// Opens ready to train: today's session with every target, then Start. Around it, only what
/// ends in an action.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var minutes: Int?
    @State private var logActivity: ActivityLogSheetItem?
    @State private var showCheckIn = false
    @State private var lifeMode: LifeModeKindChoice?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let analysis = model.analysis {
                    if sizeClass.isWide {
                        HStack(alignment: .top, spacing: 20) {
                            VStack(alignment: .leading, spacing: 16) {
                                banners(analysis)
                                sessionCard(analysis)
                            }
                            .frame(minWidth: 360, maxWidth: 640)
                            VStack(alignment: .leading, spacing: 16) {
                                if let status = analysis.assessment { AssessmentCard(status: status) }
                                around(analysis)
                            }
                            .frame(minWidth: 300, maxWidth: 520)
                        }
                        .padding()
                        .frame(maxWidth: 1200)
                        .frame(maxWidth: .infinity)
                    } else {
                        column(analysis)
                    }
                }
            }
            .accessibilityIdentifier("today.screen")
            .background(.pageBackground)
            .navigationTitle("Today")
            .navigationSubtitleIfAvailable(Format.day(model.today, style: .dateTime.weekday(.wide).month(.wide).day()))
            #if os(iOS)
            // The phone draws its own header: the date over a large title, and its two buttons.
            .toolbarVisibility(sizeClass.isWide ? .automatic : .hidden, for: .navigationBar)
            #endif
            .toolbar {
                if sizeClass.isWide {
                    ToolbarItem(placement: .barTrailing) {
                        Menu {
                            addMenu
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add")
                        .accessibilityIdentifier("today.add")
                    }
                    SettingsToolbarItem(identifier: "today.settings")
                }
            }
            .refreshable { await model.refreshHealth() }
            .sessionResumeToolbar()
            .sheet(item: $logActivity) { item in ActivityLogSheet(declared: item.declared) }
            .sheet(isPresented: $showCheckIn) { CheckInView() }
            .sheet(item: $lifeMode) { choice in LifeModeEditor(period: choice.newPeriod) }
        }
    }

    @ViewBuilder
    private var addMenu: some View {
        Button("Log a class or activity", systemImage: "plus") { logActivity = ActivityLogSheetItem(declared: nil) }
            .accessibilityIdentifier("today.logActivity")
        Button("Check-in tests", systemImage: "checklist") { showCheckIn = true }
            .accessibilityIdentifier("today.checkIn")
        Divider()
        Button("Vacation", systemImage: "airplane") { lifeMode = .vacation }
            .accessibilityIdentifier("today.addVacation")
        Button("Crunch mode", systemImage: "briefcase") { lifeMode = .crunch }
            .accessibilityIdentifier("today.addCrunch")
        Button("Injury", systemImage: "bandage") { lifeMode = .injury }
            .accessibilityIdentifier("today.addInjury")
        Button("Illness", systemImage: "thermometer.medium") { lifeMode = .illness }
            .accessibilityIdentifier("today.addIllness")
    }

    // MARK: The phone

    /// The phone's Today: the date and the week, the session to start, the scores, and the few
    /// things worth doing next as rows in one card.
    private func column(_ analysis: LiftAnalysis) -> some View {
        let plan = model.live == nil && analysis.next != nil ? model.plan(minutes: minutes) : nil
        // The planner puts the assessment's own note first: it goes on the assessment's page.
        let assessmentNote = plan?.assessment == true ? plan?.notes.first : nil
        return VStack(alignment: .leading, spacing: 12) {
            header
            ThisWeekStrip(days: model.weekStrip)
            banners(analysis)
            hero(analysis, plan: plan)
            if let plan, let next = analysis.next,
                let note = dayNote(plan: plan, next: next, life: analysis.life, skipping: assessmentNote == nil ? 0 : 1)
            {
                Text(note).font(.footnote).foregroundStyle(Ink.text2).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .accessibilityIdentifier("today.heroNotes")
            }
            ScoresCard(lines: model.stats) { model.tab = .progress }
            next(analysis, plan: plan, assessmentNote: assessmentNote)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .readableWidth()
    }

    private var header: some View {
        PageHeader(eyebrow: Format.day(model.today, style: .dateTime.weekday(.wide).day().month(.wide)), title: "Today") {
            HStack(spacing: 8) {
                Menu {
                    addMenu
                } label: {
                    CircleIcon(symbol: "plus")
                }
                .accessibilityLabel("Add")
                .accessibilityIdentifier("today.add")
                #if !os(macOS)
                Button {
                    model.showSettings = true
                } label: {
                    CircleIcon(symbol: "gearshape")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("today.settings")
                #endif
            }
        }
    }

    /// The session as the one accent card: its eyebrow, its name, one line of what's in it, Start or
    /// Resume, and Short on time.
    @ViewBuilder
    private func hero(_ analysis: LiftAnalysis, plan: SessionPlan?) -> some View {
        if let live = model.live {
            SessionHero(
                eyebrow: "In progress", trailing: nil, title: live.plan.title,
                subtitle: "\(Int((live.progress * 100).rounded()))% done", progress: live.progress
            ) {
                Button {
                    model.showSession = true
                } label: {
                    Text("Resume session").frame(maxWidth: .infinity)
                }
                .buttonStyle(HeroButtonStyle())
                .accessibilityIdentifier("today.resumeSession")
            }
        } else if let next = analysis.next, let plan {
            SessionHero(
                eyebrow: HeroLine.eyebrow(plan: plan, next: next), trailing: "~\(plan.estimatedMinutes) min", title: plan.title,
                subtitle: HeroLine.contents(plan: plan, catalog: model.catalog),
                shorter: [2, 1].map { HeroLine.contents(plan: plan, catalog: model.catalog, names: $0) }, progress: nil
            ) {
                Button {
                    model.start(plan)
                } label: {
                    Text("Start session").frame(maxWidth: .infinity)
                }
                .buttonStyle(HeroButtonStyle())
                .help("Start today's session (⌘N)")
                .accessibilityIdentifier("today.startSession")
                shortOnTime(budget: next.mesocycle.minutesPerSession)
            }
        } else {
            EmptyCard(symbol: "calendar.badge.plus", title: "No block yet", detail: "Plan your next block from the Plan tab.")
        }
    }

    /// "Short on time?" and the shorter sessions on offer: only those under the block's own length,
    /// and the one picked, so a 45-minute block isn't offered 60.
    @ViewBuilder
    private func shortOnTime(budget: Int) -> some View {
        let options = [30, 45, 60, 75].filter { $0 < budget || $0 == minutes }
        if !options.isEmpty {
            // The chips under the question at the largest text sizes, where they won't fit beside it.
            let layout =
                dynamicType.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 6))
            layout {
                Text("Short on time?").font(.footnote).opacity(0.85)
                if !dynamicType.isAccessibilitySize { Spacer(minLength: 4) }
                HStack(spacing: 6) {
                    ForEach(options, id: \.self) { m in
                        Button {
                            minutes = minutes == m ? nil : m
                        } label: {
                            Text("\(m) min")
                                .font(.footnote.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .padding(.horizontal, 11)
                                .frame(minHeight: 32)
                                .foregroundStyle(minutes == m ? Color.accentColor : Ink.onAccent)
                                .background(minutes == m ? Ink.onAccent : Color.black.opacity(0.16), in: .capsule)
                                // A fingertip's height to hit, round a slimmer chip.
                                .frame(minHeight: 44)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(m) minutes")
                        .accessibilityAddTraits(minutes == m ? .isSelected : [])
                        .accessibilityIdentifier("today.minutes\(m)")
                    }
                }
            }
            .padding(.vertical, -6)
        }
    }

    /// The one line said under the hero, when the day needs it: a rest day, a day off, or the plan's
    /// first note (less the one `skipping` leaves to the assessment's page). The rest of the plan's
    /// notes open the session's whole list; what moved to later is a row of its own.
    private func dayNote(plan: SessionPlan, next: NextSession, life: LifeModeEffects, skipping: Int) -> String? {
        if !next.scheduledToday, let day = next.nextDay, life.trainingExpected {
            return "Rest day. Next planned: \(Format.day(day, style: .dateTime.weekday(.wide))). Train today if you like; the plan just moves along."
        }
        if !life.trainingExpected { return "Nothing is expected today. If you train anyway, keep it easy." }
        return plan.notes.dropFirst(skipping).first
    }

    /// The assessment, Do this next, later today, steps and what's outside the gym: each a row that
    /// ends in an action, in one card, its caption saying which.
    private func next(_ analysis: LiftAnalysis, plan: SessionPlan?, assessmentNote: String?) -> some View {
        // Quests the plan moved out of today's session, when they aren't the day's own already.
        let moved = plan?.quests.filter { quest in !analysis.quests.contains { $0.id == quest.id } } ?? []
        return RowCard {
            if let status = analysis.assessment {
                NavigationLink {
                    AssessmentPage(status: status, note: assessmentNote)
                } label: {
                    AssessmentRow(status: status)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.assessment")
            }
            ForEach(analysis.actions.prefix(3)) { action in
                ActionRow(action: action, actionable: actionable(action)) { perform(action) }
            }
            ForEach(analysis.quests) { quest in QuestLine(quest: quest, kind: "Later today") }
            ForEach(moved) { quest in QuestLine(quest: quest, kind: "Moved out of today's session") }
            if let steps = analysis.steps {
                NavigationLink {
                    StepsPage(steps: steps)
                } label: {
                    StepsLine(steps: steps)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.steps")
            } else if HealthBridge.shared.isAvailable {
                StepsWaitingCard(connected: !model.steps.isEmpty, plain: true) { Task { await model.connectHealth() } }
            }
            outsideRows()
        }
    }

    private func actionable(_ action: NextAction) -> Bool { [.deloadEarly, .checkIn, .measure].contains(action.kind) }

    @ViewBuilder
    private func outsideRows() -> some View {
        let declared = model.profile?.declared(on: model.today) ?? []
        let todays = model.activities.filter { $0.day == model.today }
        ForEach(declared) { item in
            let logged = todays.contains { $0.type == item.activity }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(item.activity.label) \(item.timeOfDay.label.lowercased())")
                        .font(.callout.weight(.semibold))
                    Text(logged ? "Logged" : "Log it after class: rounds, effort, how long you lasted.").font(.caption).foregroundStyle(Ink.text2)
                }
                Spacer()
                if logged {
                    Circle().fill(Ink.good).frame(width: 8, height: 8).accessibilityLabel("Logged")
                } else {
                    Button("Log") { logActivity = ActivityLogSheetItem(declared: item) }.secondaryAction().controlSize(.small)
                        .accessibilityIdentifier("today.logDeclared")
                }
            }
        }
        ForEach(todays.filter { log in !declared.contains { $0.activity == log.type } }) { log in
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(log.type.label).font(.callout.weight(.semibold))
                    Text("\(log.minutes) min · effort \(log.intensity)").font(.caption).foregroundStyle(Ink.text2)
                }
                Spacer()
                Circle().fill(Ink.good).frame(width: 8, height: 8).accessibilityLabel("Done")
            }
        }
    }

    // MARK: Wide

    @ViewBuilder
    private func banners(_ analysis: LiftAnalysis) -> some View {
        ForEach(analysis.life.active) { period in LifeModeBanner(period: period) }
        if analysis.life.reentry { reentryBanner }
    }

    /// What ends in an action around the session: next steps, quests, steps and outside training.
    @ViewBuilder
    private func around(_ analysis: LiftAnalysis) -> some View {
        if !analysis.actions.isEmpty {
            SectionHeader(title: "Do this next")
            ForEach(analysis.actions.prefix(3)) { action in ActionCard(action: action) { perform(action) } }
        }
        if !analysis.quests.isEmpty {
            SectionHeader(title: "Later today")
            ForEach(analysis.quests) { quest in QuestRow(quest: quest) }
        }
        if let steps = analysis.steps {
            StepsCard(steps: steps)
        } else if HealthBridge.shared.isAvailable {
            StepsWaitingCard(connected: !model.steps.isEmpty) { Task { await model.connectHealth() } }
        }
        outside(analysis)
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
                Ruler(value: live.progress, height: 10)
                Button {
                    model.showSession = true
                } label: {
                    Label("Resume session", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .primaryAction()
                .controlSize(.large)
                .accessibilityIdentifier("today.resumeSession")
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
            VStack(alignment: .leading, spacing: 14) {
                outsideRows()
            }
            .card()
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

/// A round button's face in the phone's header.
struct CircleIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Ink.text)
            .frame(width: 44, height: 44)
            .background(Ink.surface, in: .circle)
            .contentShape(.circle)
    }
}

/// This week, Monday to Sunday: a green dot for a day trained, the accent for today's session, a
/// grey one for a training day still to come.
struct ThisWeekStrip: View {
    let days: [WeekStripDay]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(days) { day in
                VStack(spacing: 5) {
                    Text(day.day.weekday.short.prefix(1)).font(.caption2.weight(.semibold)).foregroundStyle(day.isToday ? Ink.text : Ink.text3)
                    Text(day.number).font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(day.isToday ? Ink.text : Ink.text2)
                    Circle().fill(color(day)).frame(width: 6, height: 6)
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(day.isToday ? Ink.surface : .clear, in: .rect(cornerRadius: 12, style: .continuous))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week")
        .accessibilityValue(summary)
    }

    private func color(_ day: WeekStripDay) -> Color {
        if day.trained { return Ink.good }
        if day.planned { return day.isToday ? Color.accentColor : Ink.track }
        return .clear
    }

    private var summary: String {
        let trained = days.filter(\.trained).map { $0.day.weekday.name }
        let planned = days.filter(\.planned).map { $0.day.weekday.name }
        var parts: [String] = []
        if !trained.isEmpty { parts.append("trained \(trained.joined(separator: ", "))") }
        if !planned.isEmpty { parts.append("planned \(planned.joined(separator: ", "))") }
        return parts.isEmpty ? "Nothing planned" : parts.joined(separator: "; ")
    }
}

/// Today's session as the one thing on the page in the accent: what it is, how long, and Start.
struct SessionHero<Actions: View>: View {
    let eyebrow: String
    let trailing: String?
    let title: String
    let subtitle: String
    /// The subtitle when it doesn't fit on one line: fewer names, longest first.
    var shorter: [String] = []
    let progress: Double?
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(eyebrow).eyebrow(Ink.onAccent.opacity(0.8))
                Spacer()
                if let trailing { Text(trailing).eyebrow(Ink.onAccent.opacity(0.8)) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).numeral(46, weight: .heavy).accessibilityAddTraits(.isHeader)
                // One line of what's in it, as the design has it; two only when even the short one won't fit.
                ViewThatFits(in: .horizontal) {
                    Text(subtitle).lineLimit(1)
                    ForEach(Array(shorter.enumerated()), id: \.offset) { _, line in Text(line).lineLimit(1) }
                    Text(shorter.last ?? subtitle).lineLimit(2)
                }
                .font(.subheadline).opacity(0.85)
            }
            if let progress {
                Ruler(value: progress, color: Ink.onAccent, height: 10).opacity(0.9)
            }
            actions
        }
        .foregroundStyle(Ink.onAccent)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor, in: .rect(cornerRadius: 22, style: .continuous))
    }
}

/// The hero's lines about a planned session.
enum HeroLine {
    /// "Session 3 of 4 · Block week 2", "Assessment", "Deload · Check-in".
    static func eyebrow(plan: SessionPlan, next: NextSession) -> String {
        var parts: [String] = []
        if next.scheduledToday {
            parts.append("Session \(min(next.doneThisWeek + 1, max(1, next.plannedThisWeek))) of \(next.plannedThisWeek)")
        } else {
            parts.append("Next session")
        }
        if plan.assessment {
            parts.append("Assessment")
        } else if plan.deload {
            parts.append("Deload")
        } else if let week = plan.week {
            parts.append("Block week \(week + 1)")
        }
        if plan.checkIn { parts.append("Check-in") }
        return parts.joined(separator: " · ")
    }

    /// "Bench press, row, overhead press and 3 more · 19 sets": the first `names` lifts by the short
    /// name of what they score (the exercise's own name where that's taken or there's none), and how
    /// many lifts more.
    static func contents(plan: SessionPlan, catalog: ExerciseCatalog, names count: Int = 3) -> String {
        let lifts = plan.items.filter(\.isStrength).filter { $0.block == .main || $0.block == .accessory }
        var names: [String] = []
        for lift in lifts.prefix(count) {
            let exercise = catalog.resolve(lift.exerciseID)
            let short = exercise.strength?.category.label ?? exercise.name
            names.append(names.contains(short.lowercased()) ? exercise.name.lowercased() : short.lowercased())
        }
        var line = names.joined(separator: ", ")
        if let first = line.first { line = first.uppercased() + line.dropFirst() }
        let sets = plan.items.reduce(0) { $0 + $1.workSets.count }
        if lifts.isEmpty {
            line = "\(plan.items.count) \(plan.items.count == 1 ? "exercise" : "exercises")"
        } else if lifts.count > names.count {
            line += " and \(lifts.count - names.count) more"
        }
        return sets > 0 ? "\(line) · \(sets) sets" : line
    }
}

/// The hero's own button: ink on the accent, the reverse of every other primary button.
struct HeroButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.accentColor)
            .frame(minHeight: 52)
            .background(Ink.onAccent, in: .rect(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(.rect)
            .hoverHighlight()
    }
}

/// Four of the six scores, two by two, each a numeral over a thin ruler; the rest is on Progress.
struct ScoresCard: View {
    let lines: [StatLine]
    let open: () -> Void

    private static let shown: [StatKind] = [.strength, .endurance, .agility, .discipline]

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Your scores").font(.callout.weight(.semibold)).foregroundStyle(Ink.text)
                    Spacer()
                    Text("All progress").font(.caption).foregroundStyle(Ink.text3)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)], alignment: .leading, spacing: 14) {
                    ForEach(Self.shown, id: \.self) { stat in
                        cell(stat, line: lines.first { $0.stat == stat })
                    }
                }
            }
            .card()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityIdentifier("today.scores")
    }

    private func cell(_ stat: StatKind, line: StatLine?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(stat.label).font(.caption).foregroundStyle(Ink.text3)
                Spacer()
                if let line, let trend = TrendWord(line.trend) {
                    Text(trend.text).font(.caption.weight(.semibold)).foregroundStyle(trend.color)
                }
            }
            Text(line?.score.map(String.init) ?? "–").numeral(30).foregroundStyle(line?.score == nil ? Ink.text3 : Ink.text)
            Ruler.thin(Double(line?.score ?? 0) / 100)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stat.label)
        .accessibilityValue(line?.score.map { "\($0)" } ?? "Not measured yet")
    }
}

/// A trend as a word: up, holding, slipping. Nothing until there's enough to say.
struct TrendWord {
    let text: String
    let color: Color
    /// The arrow beside it in a chip, for a score that's moving.
    let symbol: String?

    init?(_ trend: Trajectory) {
        switch trend {
        case .ahead: (text, color, symbol) = ("rising", Ink.good, "chevron.up")
        case .onPace: (text, color, symbol) = ("on pace", Ink.good, "chevron.up")
        case .stalled: (text, color, symbol) = ("steady", Ink.text3, nil)
        case .regressing: (text, color, symbol) = ("slipping", Ink.ok, "chevron.down")
        case .notEnoughData: return nil
        }
    }
}

/// A next step as a row: what to do, "Do this next" and the step, and a tap when the app can do it.
struct ActionRow: View {
    let action: NextAction
    let actionable: Bool
    let perform: () -> Void

    var body: some View {
        if actionable {
            Button(action: perform) { content(chevron: true) }
                .buttonStyle(.plain)
                .hoverHighlight()
                .accessibilityIdentifier("today.action\(action.kind.rawValue.identifierSuffix)")
        } else {
            content(chevron: false)
        }
    }

    private func content(chevron: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(action.title).font(.callout.weight(.semibold)).foregroundStyle(Ink.text)
                Text("Do this next · \(action.action)").font(.caption).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if chevron { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Ink.text3) }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint(action.detail)
    }
}

/// A quest as a row: its title, when it's for and what it is, and how long.
struct QuestLine: View {
    let quest: Quest
    /// "Later today", "Moved out of today's session".
    let kind: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(quest.title).font(.callout.weight(.semibold)).foregroundStyle(Ink.text)
                Text(([kind] + (quest.detail.isEmpty ? [] : [quest.detail])).joined(separator: " · "))
                    .font(.caption).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let minutes = quest.minutes { Text("\(minutes) min").font(.caption.monospacedDigit()).foregroundStyle(Ink.text2) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Steps so far against the day's aim, in a line over a slim ruler.
struct StepsLine: View {
    let steps: StepAim

    var body: some View {
        let count = steps.today ?? 0
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Steps").font(.callout.weight(.semibold)).foregroundStyle(Ink.text)
                    Spacer()
                    Text("\(count.formatted()) of \(steps.aim.formatted())").font(.caption.monospacedDigit()).foregroundStyle(Ink.text3)
                }
                Ruler.thin(Double(count) / Double(max(1, steps.aim)), color: count >= steps.aim ? Ink.good : Ink.text2)
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Ink.text3)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// The assessment as Today's row: how far along on a slim ruler. It opens what's been learned.
struct AssessmentRow: View {
    let status: AssessmentStatus

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Assessment").font(.callout.weight(.semibold)).foregroundStyle(Ink.text)
                    Spacer()
                    Text(status.complete ? "Done · plan your first block" : "Week \(status.week) of \(status.totalWeeks) · what we've learned")
                        .font(.caption.monospacedDigit()).foregroundStyle(Ink.text3).lineLimit(1)
                }
                Ruler.thin(status.complete ? 1 : status.progress)
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Ink.text3)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// The assessment in full, opened from Today's row: this week's note and what's been learned.
struct AssessmentPage: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let status: AssessmentStatus
    let note: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !sizeClass.isWide { BackHeader(eyebrow: "Today", title: "Assessment") }
                AssessmentCard(status: status, note: note, titled: false)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .readableWidth()
        }
        .background(.pageBackground)
        .pageWithoutBar(title: "Assessment", wide: sizeClass.isWide)
        .accessibilityIdentifier("today.assessmentPage")
    }
}

/// The step aim in full, opened from Today's row.
struct StepsPage: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let steps: StepAim

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !sizeClass.isWide { BackHeader(eyebrow: "Today", title: "Steps") }
                StepsCard(steps: steps)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .readableWidth()
        }
        .background(.pageBackground)
        .pageWithoutBar(title: "Steps", wide: sizeClass.isWide)
    }
}

/// This week, for the strip on Today.
struct WeekStripDay: Identifiable, Hashable {
    let day: Day
    let number: String
    let trained: Bool
    let planned: Bool
    let isToday: Bool
    var id: Day { day }
}

extension AppModel {
    /// Monday to Sunday of this week: the days trained, and the training days from today on.
    var weekStrip: [WeekStripDay] {
        let monday = today.adding(days: 1 - today.weekday.rawValue)
        let sunday = monday.adding(days: 6)
        let trained = Set(sessions.lazy.map(\.day).filter { $0 >= monday && $0 <= sunday })
        let training = Set(profile?.schedule.trainingDays ?? [])
        return (0..<7).map { offset in
            let day = monday.adding(days: offset)
            let done = trained.contains(day)
            return WeekStripDay(
                day: day, number: Format.day(day, style: .dateTime.day()), trained: done,
                planned: !done && day >= today && training.contains(day.weekday), isToday: day == today)
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
                if plan.assessment { Pill(text: "Assessment", symbol: "scope", color: .accentColor) }
                if plan.deload { Pill(text: "Deload", symbol: "arrow.down.circle", color: .accentColor) }
                if plan.checkIn { Pill(text: "Check-in", symbol: "checklist", color: .accentColor) }
                if let week = plan.week, !plan.assessment { Pill(text: "Week \(week + 1)", color: .secondary) }
                Pill(text: "\(next.doneThisWeek) of \(next.plannedThisWeek) this week", color: .secondary)
            }
            if !next.scheduledToday, let day = next.nextDay, life.trainingExpected {
                Text(
                    "Rest day. Next planned: \(Format.day(day, style: .dateTime.weekday(.wide))). Train today if you like; the plan just moves along."
                )
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
                        .choiceTint(minutes == m)
                        .controlSize(.small)
                        .accessibilityLabel("\(m) minutes")
                        .accessibilityIdentifier("today.minutes\(m)")
                }
            }
            Button(action: start) {
                Label("Start", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity)
            }
            .primaryAction()
            .controlSize(.large)
            .help("Start today's session (⌘N)")
            .accessibilityIdentifier("today.startSession")
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
                    Text(
                        first.loadKg == nil
                            ? "\(work.count) × \(first.targetReps) · find weight"
                            : "\(work.count) × \(Format.set(first, exercise: exercise, unit: model.gym.unit))")
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
    @Environment(\.dynamicTypeSize) private var dynamicType
    let status: AssessmentStatus
    /// What this week of it is for, from today's plan (the phone's Today moves it here off the hero).
    var note: String?
    /// Its own title, unless the page it's on is titled already.
    var titled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The week under the title at the largest text sizes, rather than "Assessment" broken in two.
            let layout =
                dynamicType.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
            layout {
                if titled { Text("Assessment").font(.headline) }
                if titled && !dynamicType.isAccessibilitySize { Spacer() }
                Text(status.complete ? "Done" : "Week \(status.week) of \(status.totalWeeks)").eyebrow()
            }
            Ruler(value: status.complete ? 1 : status.progress, height: 10, divisions: max(1, status.totalWeeks))
            if let note {
                Text(note).font(.subheadline).foregroundStyle(Ink.text).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("today.assessmentNote")
            }
            Text("What we've learned").eyebrow().padding(.top, 4)
            ForEach(Array(status.learned.enumerated()), id: \.offset) { _, line in
                Label(line, systemImage: "circle.fill").labelStyle(BulletLabelStyle()).font(.subheadline).foregroundStyle(Ink.text2)
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
                    .accessibilityIdentifier("today.action\(action.kind.rawValue.identifierSuffix)")
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

/// The daily step aim: today so far against it, the last seven days, and why. It's judged on the
/// week's average, so one quiet day doesn't matter, and it asks for a walk only when the week is
/// behind.
struct StepsCard: View {
    let steps: StepAim

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Steps", systemImage: "figure.walk").font(.headline)
                Spacer()
                Text("Aim \(steps.aim.formatted()) a day").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            today
            Chart {
                ForEach(steps.week, id: \.day) { day in
                    BarMark(x: .value("Day", day.day.weekday.short), y: .value("Steps", day.steps))
                        .foregroundStyle(day.steps >= steps.aim ? Color.accentColor : Ink.track)
                        .cornerRadius(4)
                }
                RuleMark(y: .value("Aim", steps.aim))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(.secondary)
            }
            .chartYAxis(.hidden)
            .chartXAxis { AxisMarks { AxisValueLabel() } }
            .frame(height: 84)
            .accessibilityHidden(true)
            week
            if steps.target > steps.aim {
                Text("Heading for \(steps.target.formatted()) a day.").font(.subheadline)
            }
            Text(steps.reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private var today: some View {
        let count = steps.today ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(count.formatted()).font(.title2.bold().monospacedDigit())
                Text("today").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if count >= steps.aim {
                    Label("Aim reached", systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(Ink.good)
                } else {
                    Text("\((steps.aim - count).formatted()) to go").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Ruler(value: Double(count) / Double(max(1, steps.aim)), height: 10)
        }
    }

    @ViewBuilder
    private var week: some View {
        if let recent = steps.recent, let onTrack = steps.onTrack {
            let average = Steps.round(recent, to: 100).formatted()
            if onTrack {
                Label("\(average) a day over the last week: on track", systemImage: "checkmark.circle.fill")
                    .font(.subheadline).foregroundStyle(Ink.good)
            } else {
                Label(
                    "\(average) a day over the last week, \(Steps.round(steps.gap, to: 100).formatted()) short", systemImage: "arrow.up.circle.fill"
                )
                .font(.subheadline).foregroundStyle(Ink.ok)
            }
        } else {
            Label("Too few days with your phone or Watch to judge the week yet", systemImage: "questionmark.circle")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

/// No step aim yet: Health isn't sharing steps, or hasn't a week of them to find the usual count.
struct StepsWaitingCard: View {
    let connected: Bool
    /// A row in a list rather than a card of its own.
    var plain = false
    let connect: () -> Void

    var body: some View {
        if plain {
            content
        } else {
            content.card()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Steps", systemImage: "figure.walk").font(.headline)
            if connected {
                Text(
                    "A daily aim comes once Health has a week of steps from your phone or Watch. It starts from your usual count, not a universal 10,000."
                )
                .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text(
                    "Stadig Lift sets a daily step aim from your usual count, read from Apple Health. Already connected? Turn on Steps for Stadig Lift in the Health app, under Profile → Apps."
                )
                .font(.subheadline).foregroundStyle(.secondary)
                Button("Connect Apple Health", action: connect).secondaryAction().controlSize(.small)
            }
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
