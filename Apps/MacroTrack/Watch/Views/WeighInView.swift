import NutritionEngine
import SwiftUI
import SystemCore

/// This morning's weight on the Digital Crown: it starts at the last weigh-in, moves 0.1 kg or
/// 0.2 lb a detent, and Save keeps it.
struct WeighInView: View {
    @Environment(WristModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let dial: WeighInDial
    let weighedToday: Bool
    /// Set once, so a sync arriving mid-turn doesn't move the number under the person's thumb.
    @State private var value: Double
    @FocusState private var crownFocused: Bool

    init(dial: WeighInDial, weighedToday: Bool) {
        self.dial = dial
        self.weighedToday = weighedToday
        _value = State(initialValue: dial.start)
    }

    var body: some View {
        let shown = WristFormat.dial(dial.snapped(value))
        VStack(alignment: .leading, spacing: 4) {
            Text(weighedToday ? "Weighed in today" : "This morning")
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.tint)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(shown)
                    .font(.system(size: 52, weight: .bold).monospacedDigit())
                    .tracking(-1.5)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(dial.unit.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(crownFocused ? Color.accentColor : .clear, lineWidth: 2)
            }
            .contentShape(.rect(cornerRadius: 12))
            .onTapGesture { crownFocused = true }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weight")
            .accessibilityValue("\(shown) \(dial.unit == .lb ? "pounds" : "kilograms")")
            .accessibilityAdjustableAction { direction in
                value = dial.snapped(value + (direction == .increment ? dial.step : -dial.step))
            }
            .accessibilityIdentifier("weighIn.value")
            .focusable()
            .focused($crownFocused)
            .digitalCrownRotation(
                $value, from: dial.range.lowerBound, through: dial.range.upperBound, by: dial.step, sensitivity: .low,
                isContinuous: false, isHapticFeedbackEnabled: true)
            Text(weighedToday ? "Already weighed in today" : "Turn the Digital Crown")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button {
                model.weighIn(kg: dial.kilograms(value))
                dismiss()
            } label: {
                Label("Save", systemImage: "checkmark")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Color.accentColor, in: .rect(cornerRadius: 23, style: .continuous))
                    .contentShape(.rect(cornerRadius: 23))
            }
            .buttonStyle(.plain)
            .handGestureShortcut(.primaryAction)
            .accessibilityIdentifier("weighIn.save")
        }
        .padding(.horizontal, 4)
        .navigationTitle("Weigh In")
        .onAppear { crownFocused = true }
    }
}
