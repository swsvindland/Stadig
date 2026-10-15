import SwiftUI
import StoreKit
import ExerciseLibrary
import LiftEngine
import SystemCore

/// One recommendation by default, with "Why?". The person can override the phase answer, but the
/// default needs no expertise.
struct NextBlockView: View {
    @Environment(AppModel.self) private var model
    @Environment(Purchases.self) private var purchases
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if let preview {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Start") { accept(preview) }
                    }
                }
            }
        }
    }

    private var phaseQuestion: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Right now, are you…").font(.title2.bold())
            Text("One tap. With Macro Track this is decided from your data instead.").foregroundStyle(.secondary)
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
            if !purchases.unlocked {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Training blocks are part of the one-time unlock.").font(.headline)
                    Text("Logging, your history, export and backup stay free either way.").font(.subheadline).foregroundStyle(.secondary)
                    Button { model.showPaywall = true } label: { Text("Unlock Lift Track").frame(maxWidth: .infinity) }.primaryAction()
                }
                .card()
            }
        }
    }

    private func build(_ decision: NextBlockDecision) {
        let start = startDay
        preview = model.generate(kind: decision.kind, start: start, phase: decision.phase)
    }

    /// Today, or the day after the current block if it's still running.
    private var startDay: Day {
        guard let block = model.analysis?.block else { return model.today }
        return block.end >= model.today && block.kind != .assessment ? max(model.today, block.end.adding(days: 1)) : model.today
    }

    private func accept(_ m: Mesocycle) {
        guard purchases.unlocked else {
            model.showPaywall = true
            return
        }
        // An assessment finished early ends today.
        if var current = model.currentMesocycle, current.block.kind == .assessment, current.block.end >= m.block.start {
            current.block.endOverride = m.block.start.adding(days: -1)
            model.save(current)
        }
        model.save(m)
        dismiss()
    }
}

/// The one-time unlock. No subscription.
struct PaywallView: View {
    @Environment(Purchases.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "lock.open.fill").font(.system(size: 44)).foregroundStyle(.tint)
                Text("Lift Track, for good").font(.largeTitle.bold())
                VStack(alignment: .leading, spacing: 12) {
                    Label("Every training block after the assessment, built from your data", systemImage: "calendar")
                    Label("Deloads, vacations, crunch, injury and illness modes", systemImage: "airplane")
                    Label("One purchase. No subscription. Ever.", systemImage: "checkmark.seal")
                    Label("Your data is yours: logging, export and backup are always free", systemImage: "square.and.arrow.up")
                }
                Spacer()
                Button {
                    Task {
                        await purchases.buy()
                        if purchases.unlocked { dismiss() }
                    }
                } label: {
                    Text(purchases.product.map { "Unlock for \($0.displayPrice)" } ?? "Unlock").font(.headline).frame(maxWidth: .infinity)
                }
                .primaryAction()
                .controlSize(.large)
                .disabled(purchases.product == nil || purchases.purchasing)
                Button("Restore purchase") { Task { await purchases.restore() } }.frame(maxWidth: .infinity)
                if let error = purchases.error { Text(error).font(.footnote).foregroundStyle(.secondary) }
                Text("Part of The System bundle on the App Store, with Macro Track and the Knowledge app.").font(.footnote).foregroundStyle(.secondary)
            }
            .padding(24)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } } }
        }
    }
}
