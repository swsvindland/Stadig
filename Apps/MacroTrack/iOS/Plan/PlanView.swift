import NutritionEngine
import SwiftUI
import SystemCore

/// The assessment while it runs, then one recommendation with its reasons, then the plan in force
/// with its weekly check-ins.
struct PlanView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let analysis = model.analysis {
                        if let plan = model.plan {
                            if let review = model.planReview { ReviewCard(plan: review) }
                            CurrentPhaseCard(plan: plan, analysis: analysis)
                            TimelineCard(plan: plan, today: model.today)
                            MealPrepCard()
                            SupplementsCard()
                            MaintenanceCard(estimate: analysis.maintenance)
                            CheckInHistory(checkIns: model.checkIns)
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
                }
                .padding()
                .readableWidth()
            }
            .background(.pageBackground)
            .navigationTitle("Plan")
            .toolbar {
                ToolbarItem(placement: .barTrailing) {
                    Button {
                        model.showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("plan.settings")
                }
            }
        }
    }
}

struct AssessmentCard: View {
    let assessment: AssessmentProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Assessment").font(.headline)
                Spacer()
                Text("Day \(assessment.day) of \(assessment.totalDays)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityIdentifier("plan.assessmentDay")
            }
            ProgressView(value: assessment.progress).tint(.accentColor)
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
                Text("Maintenance").font(.headline)
                Spacer()
                Pill(text: estimate.label, color: estimate.spread >= 350 ? .orange : estimate.spread >= 200 ? .blue : .green)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.whole(estimate.kcal)).font(.largeTitle.weight(.bold).monospacedDigit())
                Text("kcal a day").foregroundStyle(.secondary)
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
    @Environment(Purchases.self) private var purchases
    let plan: PhasePlan
    let ready: Bool
    @State private var choosing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ready ? "Recommended" : "Early look").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            Text(plan.headline).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            PhaseChips(phases: plan.phases)
            Text(plan.arc).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            WhyDisclosure(reasons: plan.reasons, confidence: plan.confidence)
            if ready {
                Button {
                    if purchases.unlocked { model.start(plan) } else { model.showPaywall = true }
                } label: {
                    Text("Start \(plan.phases.first?.kind.label.lowercased() ?? "plan")").font(.headline).frame(maxWidth: .infinity).padding(
                        .vertical, 4)
                }
                .primaryAction()
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
            PhaseChooser(recommended: plan)
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
        case .deficit: .orange
        case .maintenance: .teal
        case .surplus: .blue
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
    @Environment(Purchases.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    let recommended: PhasePlan

    var body: some View {
        NavigationStack {
            List(PhaseKind.allCases.filter { $0 != .dietBreak }) { kind in
                Button {
                    guard purchases.unlocked else {
                        dismiss()
                        model.showPaywall = true
                        return
                    }
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

/// The phase in force: which week, at what rate, and today's numbers.
struct CurrentPhaseCard: View {
    @Environment(AppModel.self) private var model
    let plan: PhasePlan
    let analysis: MacroAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let phase = analysis.phase {
                let week = min(phase.weeks, phase.start.days(until: model.today) / 7 + 1)
                HStack(alignment: .firstTextBaseline) {
                    Text(phase.kind.label).font(.title2.weight(.bold))
                        .accessibilityIdentifier("plan.currentPhase")
                    Spacer()
                    Text("Week \(max(1, week)) of \(phase.weeks)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        .accessibilityIdentifier("plan.week")
                }
                ProgressView(value: Double(max(0, phase.start.days(until: model.today))), total: Double(phase.weeks * 7)).tint(phase.kind.color)
                Text(phase.summary).font(.subheadline).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                stat("Calories", analysis.targets.kcal.map(Format.whole) ?? "—", "kcal")
                stat("Protein", analysis.targets.protein.map(Format.grams) ?? "—", nil)
                if model.settings.showAllMacros {
                    stat("Carbs", analysis.targets.carbs.map(Format.grams) ?? "—", nil)
                    stat("Fat", analysis.targets.fat.map(Format.grams) ?? "—", nil)
                }
            }
            if let change = analysis.weeklyChange {
                Label("Trend \(Format.weeklyChange(change, unit: model.units.weight))", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.subheadline)
            }
            WhyDisclosure(reasons: plan.reasons, confidence: plan.confidence)
        }
        .card()
    }

    func stat(_ title: String, _ value: String, _ unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.headline.monospacedDigit())
                if let unit { Text(unit).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A rule fired at a block boundary: the suggested change and why.
struct ReviewCard: View {
    @Environment(AppModel.self) private var model
    let plan: PhasePlan

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Plan check", systemImage: "checklist").font(.headline)
            Text(plan.headline).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            PhaseChips(phases: plan.phases.filter { $0.end >= model.today })
            WhyDisclosure(reasons: plan.reasons, confidence: plan.confidence)
            Button("Use the updated plan") { model.start(plan) }.primaryAction().accessibilityIdentifier("plan.useUpdated")
        }
        .card()
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.accentColor.opacity(0.4), lineWidth: 1))
    }
}

/// Now, next and the year: the three horizons.
struct TimelineCard: View {
    let plan: PhasePlan
    let today: Day

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The plan").font(.headline)
            ForEach(plan.phases) { phase in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(phase.range.contains(today) ? phase.kind.color : phase.kind.color.opacity(0.3)).frame(width: 10, height: 10)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(phase.summary).font(.subheadline.weight(phase.range.contains(today) ? .semibold : .regular))
                        Text(
                            "\(Format.day(phase.start, style: .dateTime.month(.abbreviated).day())) – \(Format.day(phase.end, style: .dateTime.month(.abbreviated).day()))"
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .opacity(phase.end < today ? 0.5 : 1)
            }
            Text(plan.arc).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }
}

/// Each week's small adjustment, with its reason.
struct CheckInHistory: View {
    let checkIns: [CheckIn]

    var body: some View {
        if !checkIns.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Weekly check-ins").font(.headline)
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
