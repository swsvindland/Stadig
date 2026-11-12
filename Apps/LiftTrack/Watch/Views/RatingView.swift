import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

/// The rating as three big stacked zones: Easy above, Just right in the middle in the accent (Double
/// Tap presses it), Missed below. Each carries its words and a mark as well as its colour. A miss asks
/// how many reps were done.
struct RatingView: View {
    @Environment(WatchModel.self) private var model
    let draft: SetDraft

    var body: some View {
        VStack(spacing: 3) {
            ForEach(SetRating.allCases) { rating in
                if rating == .red, let target, draft.reps >= target {
                    // A miss asks how many reps were done: the next set is set from them.
                    NavigationLink(value: SessionRoute.reps(missed(target: target), .red)) { zone(rating) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(rating.label): \(rating.detail)")
                } else {
                    Button {
                        model.log(item: draft.item, set: draft.set, reps: draft.reps, loadKg: draft.loadKg, rating: rating)
                    } label: {
                        zone(rating)
                    }
                    .buttonStyle(.plain)
                    .handGestureShortcut(.primaryAction, isEnabled: rating == .orange)
                    .accessibilityLabel("\(rating.label): \(rating.detail)")
                }
            }
        }
        .frame(maxHeight: .infinity)
        .navigationTitle(summary)
    }

    /// Easy and Missed share what's left of the face; Just right is the band between them.
    private func zone(_ rating: SetRating) -> some View {
        let middle = rating == .orange
        return HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(rating.label)
                    .font(.system(size: middle ? 19 : 22, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(middle ? WatchInk.onAccent : rating.tint)
                Text(rating.detail)
                    .font(.system(size: 12, weight: middle ? .semibold : .regular))
                    .foregroundStyle(middle ? WatchInk.onAccent : .secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Group {
                switch rating {
                case .green: Image(systemName: "chevron.up").font(.system(size: 17, weight: .bold))
                case .orange: DoubleTapGlyph(size: 20)
                case .red: Image(systemName: "chevron.down").font(.system(size: 17, weight: .bold))
                }
            }
            .foregroundStyle(middle ? WatchInk.onAccent : rating.tint)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: middle ? 50 : 44, maxHeight: middle ? 54 : .infinity)
        .background(middle ? Color.accentColor : rating.tint.opacity(0.17), in: .rect(cornerRadius: 16, style: .continuous))
        .contentShape(.rect)
    }

    private var target: Int? {
        guard let live = model.live, live.items.indices.contains(draft.item),
            live.items[draft.item].sets.indices.contains(draft.set)
        else { return nil }
        return live.items[draft.item].sets[draft.set].prescription.targetReps
    }

    private func missed(target: Int) -> SetDraft {
        var missed = draft
        missed.reps = max(0, target - 1)
        return missed
    }

    private var summary: String {
        let exercise = model.exercise(draft.item)
        guard exercise.loadBasis != .none else { return "\(draft.reps) reps" }
        return "\(WatchFormat.load(draft.loadKg, unit: model.unit, basis: exercise.loadBasis)) × \(draft.reps)"
    }
}

/// Reps done, on the crown: after a rep-out, which isn't rated, or after a miss.
struct RepsView: View {
    @Environment(WatchModel.self) private var model
    let draft: SetDraft
    let rating: SetRating?

    @State private var reps = 0.0
    @State private var prepared = false
    @FocusState private var crownFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text(rating == nil ? "As many as you could" : "Missed is just data")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Fewer", systemImage: "minus") { reps = max(0, reps - 1) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                    Text("\(Int(reps))")
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold).monospacedDigit())
                        .frame(minWidth: 50)
                        .focusable()
                        .focused($crownFocused)
                        .digitalCrownRotation(
                            $reps, from: 0, through: 99, by: 1, sensitivity: .low,
                            isContinuous: false, isHapticFeedbackEnabled: true
                        )
                        .accessibilityLabel("Reps done")
                        .accessibilityValue("\(Int(reps))")
                        .accessibilityAdjustableAction { direction in
                            reps = max(0, min(99, reps + (direction == .increment ? 1 : -1)))
                        }
                    Button("More", systemImage: "plus") { reps = min(99, reps + 1) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                }
                if let rating {
                    Label(rating.label, systemImage: rating.symbol)
                        .font(.footnote)
                        .foregroundStyle(rating.tint)
                }
                Button {
                    model.log(item: draft.item, set: draft.set, reps: Int(reps), loadKg: draft.loadKg, rating: rating)
                } label: {
                    Label("Log Set", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .handGestureShortcut(.primaryAction)
            }
        }
        .navigationTitle("Reps done")
        .onAppear {
            guard !prepared else { return }
            prepared = true
            reps = Double(draft.reps)
            crownFocused = true
        }
    }
}
