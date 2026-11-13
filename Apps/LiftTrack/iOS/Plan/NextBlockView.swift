import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

/// One recommendation by default, with "Why?". The person can override the phase answer, but the
/// default needs no expertise. Drawn as Plan's block card is: the split large, what it's for and how
/// long, its reasons a tap away, then each day as a row.
struct NextBlockView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var answer: SelfReportedPhase?
    @State private var preview: Mesocycle?
    @State private var showWhy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    let decision = Assessment.nextBlock(nutrition: model.nutrition, selfReported: answer ?? model.settings.selfReportedPhase)
                    if decision.askPhase && answer == nil {
                        phaseQuestion
                    } else {
                        SheetHeading(eyebrow: "Plan", title: "The next block", detail: decision.reason)
                        if let preview {
                            summary(preview)
                        } else {
                            ProgressView().frame(maxWidth: .infinity).padding(.top, 24).onAppear { build(decision) }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .readableWidth(620)
            }
            .inkSheet {
                SheetBar(label: "Cancel", identifier: "nextBlock.cancel") { dismiss() }
            } foot: {
                if let preview {
                    SheetFoot {
                        Button {
                            accept(preview)
                        } label: {
                            Text("Start this block").frame(maxWidth: .infinity)
                        }
                        .primaryAction()
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("nextBlock.start")
                    }
                }
            }
        }
        .sheetFrame()
    }

    private var phaseQuestion: some View {
        VStack(alignment: .leading, spacing: 12) {
            SheetHeading(
                eyebrow: "Plan the next block", title: "Right now, are you…",
                detail: "One tap. With Stadig Macro this is decided from your data instead.")
            ForEach(SelfReportedPhase.allCases) { option in
                ChoiceCard(title: option.label, selected: answer == option, identifier: "nextBlock.phase\(option.rawValue.identifierSuffix)") {
                    answer = option
                    var s = model.settings
                    s.selfReportedPhase = option
                    model.save(settings: s)
                }
            }
        }
    }

    private func summary(_ m: Mesocycle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(m.split.label).font(.title3.weight(.bold)).foregroundStyle(Ink.text)
                    Spacer(minLength: 8)
                    Button(showWhy ? "Hide why" : "Why?") { withAnimation(.snappy) { showWhy.toggle() } }
                        .font(.subheadline)
                        .foregroundStyle(Ink.text2)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("nextBlock.why")
                }
                Text("\(m.block.loadingWeeks) weeks + deload · \(m.days.count) days a week · \(m.minutesPerSession) min")
                    .font(.subheadline).foregroundStyle(Ink.text2)
                Text(m.rationale.headline).font(.callout.weight(.semibold)).foregroundStyle(Ink.text).fixedSize(horizontal: false, vertical: true)
                if showWhy {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(m.rationale.reasons.enumerated()), id: \.offset) { _, reason in
                            Label(reason, systemImage: "circle.fill").labelStyle(BulletLabelStyle()).font(.subheadline).foregroundStyle(Ink.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let confidence = m.rationale.confidence {
                            Text(confidence).font(.footnote).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .card()
            RowCard(title: "Each week") {
                ForEach(m.days) { day in dayRow(day) }
            }
        }
    }

    private func dayRow(_ day: PlannedDay) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(day.name).font(.callout.weight(.semibold)).foregroundStyle(Ink.text)
                Spacer(minLength: 8)
                Text("\(day.minutes) min").font(.caption.monospacedDigit()).foregroundStyle(Ink.text3)
            }
            Text(day.strengthSlots.map { model.catalog.resolve($0.exerciseID).name }.joined(separator: " · "))
                .font(.caption).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func build(_ decision: NextBlockDecision) {
        preview = model.generate(kind: decision.kind, start: model.nextBlockStart, phase: decision.phase)
    }

    private func accept(_ m: Mesocycle) {
        model.accept(nextBlock: m)
        dismiss()
    }
}
