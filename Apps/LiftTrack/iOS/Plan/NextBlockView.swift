import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

/// One recommendation by default, with "Why?". The person can override the phase answer, but the
/// default needs no expertise.
struct NextBlockView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var answer: SelfReportedPhase?
    @State private var preview: Mesocycle?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let decision = Assessment.nextBlock(nutrition: model.nutrition, selfReported: answer ?? model.settings.selfReportedPhase)
                    if decision.askPhase && answer == nil {
                        phaseQuestion
                    } else {
                        Text(decision.reason).font(.subheadline).foregroundStyle(.secondary)
                        if let preview {
                            summary(preview)
                        } else {
                            ProgressView().frame(maxWidth: .infinity).onAppear { build(decision) }
                        }
                    }
                }
                .padding()
                .readableWidth()
            }
            .background(.pageBackground)
            .navigationTitle("Next block")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("nextBlock.cancel")
                }
                if let preview {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Start") { accept(preview) }.accessibilityIdentifier("nextBlock.start")
                    }
                }
            }
        }
        .sheetFrame()
    }

    private var phaseQuestion: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Right now, are you…").font(.title2.bold())
            Text("One tap. With Stadig Macro this is decided from your data instead.").foregroundStyle(.secondary)
            ForEach(SelfReportedPhase.allCases) { option in
                Button {
                    answer = option
                    var s = model.settings
                    s.selfReportedPhase = option
                    model.save(settings: s)
                } label: {
                    Text(option.label).font(.headline).frame(maxWidth: .infinity, alignment: .leading).card()
                }
                .buttonStyle(.plain)
                .hoverHighlight()
            }
        }
    }

    private func summary(_ m: Mesocycle) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(m.rationale.headline).font(.title3.weight(.semibold))
                HStack(spacing: 6) {
                    Pill(text: "\(m.block.loadingWeeks) weeks + deload", color: .secondary)
                    Pill(text: m.split.label, color: .secondary)
                }
                WhyDisclosure(rationale: m.rationale)
            }
            .card()
            ForEach(m.days) { day in DayCard(day: day, isNext: false) }
        }
    }

    private func build(_ decision: NextBlockDecision) {
        preview = model.generate(kind: decision.kind, start: model.nextBlockStart, phase: decision.phase)
    }

    private func accept(_ m: Mesocycle) {
        model.accept(nextBlock: m)
        dismiss()
    }
}
