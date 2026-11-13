import NutritionEngine
import SwiftUI
import SystemCore

/// The assessment while it runs, then one recommendation with its reasons, then the plan in force:
/// the phase and its weeks, today's targets and the trend against them, the year ahead, and the next
/// weekly check-in (its history behind it). Meal prep, supplements and maintenance follow.
struct PlanView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    var compact: Bool { sizeClass == .compact }

    var body: some View {
        NavigationStack {
            ScrollView {
                if compact {
                    VStack(alignment: .leading, spacing: 12) {
                        PageHeader(eyebrow: eyebrow, title: "Plan") {
                            if !Platform.isMac {
                                CircleIconButton(symbol: "gearshape", label: "Settings", identifier: "plan.settings") { model.showSettings = true }
                            }
                        }
                        if let analysis = model.analysis { cards(analysis) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .readableWidth()
                } else if let analysis = model.analysis {
                    // With room: the phase and its reasons, and beside them what feeds and follows it.
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) { phase(analysis) }
                            .frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 12) { side(analysis) }
                            .frame(minWidth: 300, idealWidth: 380, maxWidth: 420)
                    }
                    .padding(20)
                    .frame(maxWidth: 1180)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(.pageBackground)
            .navigationTitle("Plan")
            .hidesNavigationBar(compact)
            .toolbar {
                if !Platform.isMac, !compact {
                    ToolbarItem(placement: .barTrailing) { SettingsButton(identifier: "plan.settings") }
                }
            }
        }
    }

    /// The phase's dates, or how far the assessment is.
    var eyebrow: String {
        if let phase = model.analysis?.phase {
            return
                "\(Format.day(phase.start, style: .dateTime.month(.abbreviated).day())) – \(Format.day(phase.end, style: .dateTime.month(.abbreviated).day()))"
        }
        if let assessment = model.analysis?.assessment, !assessment.complete {
            return "Assessment · day \(assessment.day) of \(assessment.totalDays)"
        }
        return "Your plan"
    }
}

extension PlanView {
    /// The phone's one column: the phase, then what feeds and follows it.
    @ViewBuilder
    func cards(_ analysis: MacroAnalysis) -> some View {
        if let plan = model.plan {
            if let review = model.planReview { ReviewCard(plan: review) }
            if let phase = analysis.phase { PhaseCard(phase: phase, today: model.today) }
            TargetsCard(plan: plan, analysis: analysis)
            YearCard(plan: plan, today: model.today)
            NextCheckInRow(analysis: analysis)
            MealPrepCard()
            SupplementsCard()
            MaintenanceCard(estimate: analysis.maintenance)
        } else {
            if let assessment = analysis.assessment { AssessmentCard(assessment: assessment) }
            MaintenanceCard(estimate: analysis.maintenance)
            if let recommendation = model.recommendation {
                RecommendationCard(plan: recommendation, ready: analysis.assessment?.complete ?? true)
            }
            MealPrepCard()
            SupplementsCard()
        }
    }

    /// With room, the phase and its history on the left.
    @ViewBuilder
    func phase(_ analysis: MacroAnalysis) -> some View {
        if let plan = model.plan {
            if let review = model.planReview { ReviewCard(plan: review) }
            if let phase = analysis.phase { PhaseCard(phase: phase, today: model.today) }
            TargetsCard(plan: plan, analysis: analysis)
            YearCard(plan: plan, today: model.today)
            CheckInHistory(checkIns: model.checkIns)
        } else {
            if let assessment = analysis.assessment { AssessmentCard(assessment: assessment) }
            if let recommendation = model.recommendation {
                RecommendationCard(plan: recommendation, ready: analysis.assessment?.complete ?? true)
            }
        }
    }

    /// And maintenance, meal prep and supplements beside it.
    @ViewBuilder
    func side(_ analysis: MacroAnalysis) -> some View {
        if model.plan != nil { NextCheckInRow(analysis: analysis) }
        MaintenanceCard(estimate: analysis.maintenance)
        MealPrepCard()
        SupplementsCard()
    }
}

/// The phase in force as its name, big, and which week; a ruler a week, the one it is filling.
struct PhaseCard: View {
    @Environment(AppModel.self) private var model
    let phase: PlannedPhase
    let today: Day

    var body: some View {
        let week = phase.week(on: today)
        // Today counts: the first day of a phase is a seventh of its first week.
        let into = Double(max(0, phase.start.days(until: today) + 1)) / 7
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(phase.kind.label).numeral(48, weight: .heavy).foregroundStyle(Ink.text)
                    .accessibilityIdentifier("plan.currentPhase")
                Text("week \(week) of \(phase.weeks)").font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(Ink.text2)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .accessibilityIdentifier("plan.week")
                Spacer(minLength: 4)
                if phase.ratePerWeek != 0 {
                    Text(rate).font(.caption.monospacedDigit()).foregroundStyle(Ink.text3).lineLimit(1)
                }
            }
            VStack(spacing: 5) {
                HStack(spacing: 4) {
                    ForEach(0..<phase.weeks, id: \.self) { index in
                        Ruler(value: min(1, max(0, into - Double(index))), height: 14, divisions: 0)
                    }
                }
                HStack(spacing: 4) {
                    ForEach(0..<phase.weeks, id: \.self) { index in
                        ScaleLabel(index == 0 ? "Week 1" : "\(index + 1)", highlighted: index + 1 == week)
                            .opacity(phase.weeks > 12 && index + 1 != week && index != 0 ? 0 : 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Week \(week) of \(phase.weeks)")
        }
        .inkCard()
    }

    /// "−0.5% a week".
    var rate: String {
        "\(phase.ratePerWeek > 0 ? "+" : "−")\(abs(phase.ratePerWeek * 100).formatted(.number.precision(.fractionLength(0...2))))% a week"
    }
}

/// Today's targets: calories as the hero, the macros in their colours, then the trend against the
/// phase in a line, with the plan's reasons behind Why?.
struct TargetsCard: View {
    @Environment(AppModel.self) private var model
    let plan: PhasePlan
    let analysis: MacroAnalysis
    @State private var showsWhy = false

    var body: some View {
        let targets = analysis.targets
        VStack(alignment: .leading, spacing: 14) {
            if let kcal = targets.kcal {
                Measure(value: Format.whole(kcal), unit: "kcal a day", size: 48, weight: .heavy)
                    .foregroundStyle(Ink.text)
                    .accessibilityIdentifier("plan.kcal")
            }
            HStack(alignment: .top, spacing: 14) {
                macro(.protein, targets.protein)
                if model.settings.showAllMacros {
                    macro(.carbs, targets.carbs)
                    macro(.fat, targets.fat)
                } else {
                    Spacer().frame(maxWidth: .infinity)
                    Spacer().frame(maxWidth: .infinity)
                }
            }
            if targets.mode != .phase {
                Text(targets.note).font(.caption).foregroundStyle(Ink.text2).fixedSize(horizontal: false, vertical: true)
            }
            Rectangle().fill(Ink.hairline).frame(height: 1)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                trend.font(.subheadline).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button("Why?") { withAnimation(.snappy) { showsWhy.toggle() } }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .padding(.vertical, -12)
                    .accessibilityIdentifier("plan.why")
            }
            if showsWhy {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(plan.reasons.enumerated()), id: \.offset) { _, reason in
                        Label(reason, systemImage: "circle.fill").labelStyle(BulletLabelStyle()).font(.subheadline).foregroundStyle(Ink.text)
                    }
                    if let confidence = plan.confidence {
                        Label(confidence, systemImage: "info.circle").font(.footnote).foregroundStyle(Ink.text2)
                    }
                }
                .transition(.opacity)
            }
        }
        .inkCard()
    }

    func macro(_ macro: Macro, _ grams: Double?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Measure(value: grams.map(Format.whole) ?? "–", unit: "g", size: 30).foregroundStyle(Ink.text)
            Text(macro.label).font(.caption).foregroundStyle(macro.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// "Trend −1.09 kg a week. On pace."
    var trend: Text {
        guard let change = analysis.weeklyChange else {
            return Text("Trend: weigh in each morning and it shows here.").foregroundStyle(Ink.text2)
        }
        let verdict = PhasePace.verdict(
            weeklyChange: change, phase: analysis.phase, weightKg: analysis.trend.latest?.trend ?? analysis.referenceKg)
        let words = Format.weeklyChange(change, unit: model.units.weight)
        let said = Text("\(Text("Trend").foregroundStyle(Ink.text2)) \(words).").foregroundStyle(Ink.text)
        guard let verdict else { return said }
        return Text("\(said) \(Text(verdict.label).foregroundStyle(verdict.color))")
    }
}

extension PhasePace.Verdict {
    var color: Color {
        switch self {
        case .onPace: Ink.good
        case .faster, .slower: Ink.ok
        case .offCourse: Ink.bad
        }
    }
}

/// The year as its phases on one line, each as long as it runs: the one now in the accent, the
/// rest on the track, with when each starts. The plan's long view under it.
struct YearCard: View {
    let plan: PhasePlan
    let today: Day

    var body: some View {
        let phases = plan.phases.filter { $0.end >= today }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your year").eyebrow()
                Spacer(minLength: 8)
                if let last = phases.last, phases.count > 1 {
                    Text("To \(Format.day(last.end, style: .dateTime.month(.wide)))").font(.caption).foregroundStyle(Ink.text3)
                }
            }
            WeightedRow(spacing: 4) {
                ForEach(phases) { phase in
                    let now = phase.range.contains(today)
                    VStack(alignment: .leading, spacing: 8) {
                        Capsule().fill(now ? Color.accentColor : Ink.track).frame(height: 6)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(phase.kind.label).font(.subheadline.weight(.semibold)).foregroundStyle(now ? Color.accentColor : Ink.text)
                                .lineLimit(1).minimumScaleFactor(0.8)
                            Text(when(phase, now: now)).font(.caption).foregroundStyle(Ink.text3).lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // As long as it runs, but a short phase keeps room for its name.
                    .layoutWeight(Double(max(3, phase.weeks)))
                }
            }
            .accessibilityElement(children: .combine)
            Text(plan.arc).font(.caption).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
        }
        .inkCard()
        .accessibilityIdentifier("plan.year")
    }

    /// "Now · 4 weeks", "Dec 7", or the month for one further off.
    func when(_ phase: PlannedPhase, now: Bool) -> String {
        if now { return "Now · \(phase.weeks) weeks" }
        if today.days(until: phase.start) <= 45 { return Format.day(phase.start, style: .dateTime.month(.abbreviated).day()) }
        return Format.day(phase.start, style: .dateTime.month(.wide))
    }
}

/// The next weekly check-in, and every one so far behind it.
struct NextCheckInRow: View {
    @Environment(AppModel.self) private var model
    let analysis: MacroAnalysis

    var body: some View {
        let next = PhasePace.nextCheckIn(last: analysis.checkIn, today: model.today)
        NavigationLink {
            CheckInsScreen()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar").font(.title3.weight(.light)).foregroundStyle(Ink.text2).frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Check-in \(Format.prepDay(next, today: model.today))").font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
                    Text("Targets adjust to your trend").font(.caption).foregroundStyle(Ink.text3)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Ink.text3)
            }
            .frame(minHeight: 36)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.cardBackground, in: .rect(cornerRadius: 18, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plan.checkIn")
    }
}

/// Each week's check-in with its reason, and the maintenance they're built on.
struct CheckInsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        // The Mac reports no size class: it always has room.
        let wide = sizeClass != .compact
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !wide { DetailHeader(eyebrow: "Plan", title: "Check-ins") }
                if let analysis = model.analysis { MaintenanceCard(estimate: analysis.maintenance) }
                CheckInHistory(checkIns: model.checkIns)
            }
            .padding(.horizontal, 16)
            .padding(.top, wide ? 16 : 0)
            .padding(.bottom, 24)
            .readableWidth()
        }
        .background(.pageBackground)
        .detailPage(title: "Check-ins", wide: wide)
    }
}

struct AssessmentCard: View {
    let assessment: AssessmentProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Assessment").font(.callout.weight(.semibold))
                Spacer()
                Text("Day \(assessment.day) of \(assessment.totalDays)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityIdentifier("plan.assessmentDay")
            }
            Ruler(value: assessment.progress, height: 12, divisions: 3)
            Text("Eat as you normally do, log it, and weigh in each morning. Nothing changes until the data says what your maintenance is.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(assessment.learned.enumerated()), id: \.offset) { _, line in
                    Label(line, systemImage: "circle.fill").labelStyle(BulletLabelStyle()).font(.subheadline)
                }
            }
        }
        .card()
    }
}

/// Maintenance with its honest range: wide early, narrowing as days are logged.
struct MaintenanceCard: View {
    let estimate: MaintenanceEstimate

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Maintenance").font(.callout.weight(.semibold))
                Spacer()
                Pill(text: estimate.label, color: estimate.spread >= 350 ? Ink.ok : estimate.spread >= 200 ? Ink.text2 : Ink.good)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Measure(value: Format.whole(estimate.kcal), unit: "kcal a day", size: 30)
            }
            RangeBar(low: estimate.low, high: estimate.high, value: estimate.kcal, formula: estimate.formula)
            Text(basisText).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    var basisText: String {
        switch estimate.basis {
        case .formula: "From height, weight, age and activity so far. Your own logs and weigh-ins take over from week two."
        case .blended:
            "Your logs and weigh-ins, blended with the formula while data builds. Likely between \(Format.whole(estimate.low)) and \(Format.whole(estimate.high)). Week one is left out: it's mostly water."
        case .data:
            "From \(estimate.days) complete days against your weight trend. Likely between \(Format.whole(estimate.low)) and \(Format.whole(estimate.high))."
        }
    }
}

/// The likely range, with the estimate and the formula's guess marked.
struct RangeBar: View {
    let low: Double
    let high: Double
    let value: Double
    let formula: Double

    var body: some View {
        let lo = min(low, formula) - 150
        let hi = max(high, formula) + 150
        GeometryReader { proxy in
            let w = proxy.size.width
            let x = { (v: Double) -> CGFloat in CGFloat((v - lo) / max(1, hi - lo)) * w }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.12)).frame(height: 10)
                Capsule().fill(Color.accentColor.opacity(0.35)).frame(width: max(10, x(high) - x(low)), height: 10).offset(x: x(low))
                Circle().fill(Color.accentColor).frame(width: 16, height: 16).offset(x: x(value) - 8)
                Rectangle().fill(Color.secondary).frame(width: 2, height: 16).offset(x: x(formula) - 1)
            }
            .frame(height: 16)
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }
}

/// One recommendation, its reasons and how sure it is.
struct RecommendationCard: View {
    @Environment(AppModel.self) private var model
    let plan: PhasePlan
    let ready: Bool
    @State private var choosing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ready ? "Recommended" : "Early look").eyebrow(Color.accentColor)
            Text(plan.headline).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            PhaseChips(phases: plan.phases)
            Text(plan.arc).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            WhyDisclosure(reasons: plan.reasons, confidence: plan.confidence)
            if ready {
                Button {
                    model.start(plan)
                } label: {
                    Text("Start \(plan.phases.first?.kind.label.lowercased() ?? "plan")").font(.headline).frame(maxWidth: .infinity)
                }
                .primaryAction().controlSize(.large)
                .accessibilityIdentifier("plan.start")
                Button("Choose a different phase") { choosing = true }
                    .accessibilityIdentifier("plan.choosePhase")
                    .frame(maxWidth: .infinity)
                    .font(.subheadline)
            } else {
                Text("This firms up as the assessment finishes. Keep eating as usual until then.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .card()
        .sheet(isPresented: $choosing) {
            PhaseChooser(recommended: plan).macSheetSize(width: 460, height: 560)
        }
    }
}

/// The phases in order, as compact chips.
struct PhaseChips: View {
    let phases: [PlannedPhase]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(Array(phases.enumerated()), id: \.element.id) { i, phase in
                    if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(phase.kind.label).font(.caption.weight(.semibold))
                        Text("\(phase.weeks) wk\(phase.ratePerWeek != 0 ? " · \(rate(phase))" : "")").font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(phase.kind.color.opacity(0.15), in: .rect(cornerRadius: 10))
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    func rate(_ phase: PlannedPhase) -> String {
        "\(phase.ratePerWeek > 0 ? "+" : "−")\(abs(phase.ratePerWeek * 100).formatted(.number.precision(.fractionLength(0...2))))%/wk"
    }
}

extension PhaseKind {
    var color: Color {
        switch energy {
        case .deficit: Ink.ok
        case .maintenance: Ink.good
        case .surplus: Ink.carbs
        }
    }

    var explanation: String {
        switch self {
        case .cut: "Lose fat steadily over a few months."
        case .miniCut: "A short, quicker cut of 4–6 weeks before building again."
        case .maintenance: "Hold weight; train and recover well."
        case .dietBreak: "Calories back to maintenance for a week or two inside a cut."
        case .reverseDiet: "Raise calories gradually after a long diet while weight stays steady."
        case .recomp: "Around maintenance with high protein: lose fat and build muscle slowly."
        case .leanBulk: "A slow surplus to build muscle with little fat."
        }
    }
}

/// The person's own choice over the recommendation.
struct PhaseChooser: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let recommended: PhasePlan

    var body: some View {
        NavigationStack {
            List(PhaseKind.allCases.filter { $0 != .dietBreak }) { kind in
                Button {
                    let weeks = kind == .miniCut ? 5 : kind == .reverseDiet ? 6 : 8
                    model.start(
                        PhasePlan(
                            phases: [PlannedPhase(kind: kind, weeks: weeks, start: model.today)],
                            headline: "\(kind.label), your choice.",
                            reasons: [
                                "You picked this over the recommendation (\(recommended.headline.lowercased()))",
                                "Targets still adapt each week from your logs and weigh-ins.",
                            ],
                            confidence: nil, arc: "Revisited when the phase ends or the data says to."))
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(kind.label).font(.headline)
                            if recommended.phases.first?.kind == kind { Pill(text: "Recommended", color: .accentColor) }
                        }
                        Text(kind.explanation).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .hoverHighlight()
                .accessibilityIdentifier("phaseChooser.\(kind.rawValue)")
            }
            .navigationTitle("Choose a phase")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("phaseChooser.cancel") }
            }
        }
    }
}

/// A rule fired at a block boundary: the suggested change and why.
struct ReviewCard: View {
    @Environment(AppModel.self) private var model
    let plan: PhasePlan

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plan check").eyebrow(Color.accentColor)
            Text(plan.headline).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            PhaseChips(phases: plan.phases.filter { $0.end >= model.today })
            WhyDisclosure(reasons: plan.reasons, confidence: plan.confidence)
            Button("Use the updated plan") { model.start(plan) }.primaryAction().accessibilityIdentifier("plan.useUpdated")
        }
        .card()
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.accentColor.opacity(0.4), lineWidth: 1))
    }
}

/// Each week's small adjustment, with its reason.
struct CheckInHistory: View {
    let checkIns: [CheckIn]

    var body: some View {
        if !checkIns.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Weekly check-ins").font(.callout.weight(.semibold))
                ForEach(checkIns.suffix(8).reversed()) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(Format.day(c.day)).font(.subheadline.weight(.medium))
                            Spacer()
                            Text(Format.kcal(c.kcal)).font(.subheadline.monospacedDigit())
                        }
                        Text(c.reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if c.id != checkIns.suffix(8).first?.id { Divider() }
                }
            }
            .card()
        }
    }
}
