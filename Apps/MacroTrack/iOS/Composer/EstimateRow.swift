import NutritionEngine
import SwiftUI
import SystemCore

/// Words being worked out on the thread, in the place their foods will land, or why they couldn't
/// be, with the logger a tap away. Today's thread, the Mac's menu bar and, over their composer, a
/// phone's other tabs show it. Words too vague to log a guess at show what the model made of them
/// and ask (`EstimateProposalRow`).
struct EstimateRow: View {
    @Environment(AppModel.self) private var model
    let estimate: ThreadEstimate
    var tile = TileSize.row

    var body: some View {
        if let proposal = estimate.proposal {
            EstimateProposalRow(estimate: estimate, entries: proposal, tile: tile)
        } else {
            working
        }
    }

    @ViewBuilder
    private var working: some View {
        let failed = failure != nil
        HStack(spacing: 12) {
            Image(systemName: failed ? "exclamationmark" : "ellipsis")
                .font(.system(size: tile * 0.42, weight: .bold))
                .foregroundStyle(failed ? Ink.ok : Ink.text2)
                .symbolEffect(.pulse, isActive: !failed)
                .frame(width: tile, height: tile)
                .background(Ink.raised, in: .rect(cornerRadius: tile * 0.3))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(failed ? "Couldn't log “\(estimate.words)”" : "Working out “\(estimate.words)”")
                    .font(.body.weight(.medium)).foregroundStyle(Ink.text).lineLimit(2)
                Text(detail).font(.caption).foregroundStyle(Ink.text2).lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            // On the words, not the row: a row's identifier would cover its buttons'.
            .accessibilityIdentifier("today.estimate")
            if failed {
                Button("Logger", action: openLogger)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
                    .accessibilityLabel("Find it in the logger")
                    .accessibilityIdentifier("today.estimate.open")
                Button("Dismiss", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Ink.text3)
                    .frame(width: 32, height: 44)
                    .contentShape(.rect)
                    .accessibilityIdentifier("today.estimate.dismiss")
            }
        }
        .buttonStyle(.borderless)
    }

    private var failure: String? {
        if case .failed(let why) = estimate.state { return why }
        return nil
    }

    private var detail: String {
        if let failure { return failure }
        return model.ai.describesOnDevice ? "Working it out on device. Keep going." : "Working it out with Private Cloud Compute. Keep going."
    }

    private func openLogger() { model.openEstimateInLogger(estimate.id) }

    private func dismiss() { model.dismissEstimate(estimate.id) }
}

/// Under the foods an estimate logged: the words they came from, and "Looks right", which keeps
/// them as they are.
struct EstimateConfirmRow: View {
    @Environment(AppModel.self) private var model
    let estimate: ThreadEstimate

    var body: some View {
        HStack(spacing: 8) {
            Text("Estimated from “\(estimate.words)”").font(.caption).foregroundStyle(Ink.text2).lineLimit(2)
            Spacer(minLength: 8)
            Button("Looks right", action: confirm)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(minHeight: 44)
                .contentShape(.rect)
                .accessibilityHint("Keeps the estimate as logged")
                .accessibilityIdentifier("today.looksRight")
        }
        .buttonStyle(.borderless)
    }

    private func confirm() {
        guard case .logged(let ids) = estimate.state else { return }
        model.confirmEstimates(Set(ids))
    }
}

/// What the model made of words that name no food ("whatever was in the fridge"), not logged until
/// the person says so: the foods and their total, "Log", the logger to change them, or ×.
struct EstimateProposalRow: View {
    @Environment(AppModel.self) private var model
    let estimate: ThreadEstimate
    let entries: [FoodEntry]
    var tile = TileSize.row

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "questionmark")
                .font(.system(size: tile * 0.42, weight: .bold))
                .foregroundStyle(Ink.ok)
                .frame(width: tile, height: tile)
                .background(Ink.raised, in: .rect(cornerRadius: tile * 0.3))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Log this for “\(estimate.words)”?")
                    .font(.body.weight(.medium)).foregroundStyle(Ink.text).lineLimit(2)
                Text(summary).font(.caption).foregroundStyle(Ink.text2).lineLimit(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("today.estimate.proposal")
            Button("Log", action: accept)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Ink.ground)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(Color.accentColor, in: .capsule)
                .frame(minHeight: 44)
                .contentShape(.rect)
                .accessibilityLabel("Log these foods")
                .accessibilityIdentifier("today.estimate.accept")
            Menu("More", systemImage: "ellipsis") {
                Button("Change in the Logger", systemImage: "square.and.pencil", action: openLogger)
                    .accessibilityIdentifier("today.estimate.open")
                Button("Don't Log", systemImage: "xmark", role: .destructive, action: dismiss)
                    .accessibilityIdentifier("today.estimate.dismiss")
            }
            .labelStyle(.iconOnly)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Ink.text3)
            .frame(width: 32, height: 44)
            .contentShape(.rect)
            .accessibilityIdentifier("today.estimate.more")
        }
        .buttonStyle(.borderless)
    }

    /// "A guess, not logged yet: Beans ≈218, Chicken breast ≈231, Rice ≈502 · 951 kcal".
    private var summary: String {
        let foods = entries.map { "\(FoodLabel.short($0.name)) ≈\(Format.whole($0.nutrients.kcal))" }.joined(separator: ", ")
        let total = Format.kcal(entries.map(\.nutrients.kcal).reduce(0, +))
        return "A guess, not logged yet: \(foods) · \(total)"
    }

    private func accept() { model.acceptEstimate(estimate.id) }

    private func openLogger() { model.openEstimateInLogger(estimate.id) }

    private func dismiss() { model.dismissEstimate(estimate.id) }
}
