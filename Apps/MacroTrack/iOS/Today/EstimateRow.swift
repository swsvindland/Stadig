import NutritionEngine
import SwiftUI

/// Words being worked out on the thread, in the place their foods will land, or why they couldn't
/// be, with the logger a tap away. Today's thread and the Mac's menu bar both show it.
struct EstimateRow: View {
    @Environment(AppModel.self) private var model
    let estimate: ThreadEstimate
    var tile = TileSize.row

    var body: some View {
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
        .accessibilityIdentifier("today.estimate")
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
