import NutritionEngine
import SwiftUI
import SystemCore

/// This morning's weight as the design's face: "The scale says" over the weight big, the trend under
/// it, and the scale at the edge beside the crown, the trend's mark and the reading's. The crown
/// corrects it, 0.1 kg or 0.2 lb a detent, from the last weigh-in; the band keeps it (Double Tap).
/// Today's reading kept as it is saves nothing new; changed, or before today's, it's saved.
struct WeighInView: View {
    @Environment(WristModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let dial: WeighInDial
    let weighedToday: Bool
    let trendKg: Double?
    /// Set once, so a sync arriving mid-turn doesn't move the number under the person's thumb.
    @State private var value: Double
    @FocusState private var crownFocused: Bool

    init(dial: WeighInDial, weighedToday: Bool, trendKg: Double?) {
        self.dial = dial
        self.weighedToday = weighedToday
        self.trendKg = trendKg
        _value = State(initialValue: dial.start)
    }

    var body: some View {
        let shown = WristFormat.dial(dial.snapped(value))
        let trend = trendKg.map { dial.unit.fromKilograms($0) }
        let keeps = weighedToday && dial.snapped(value) == dial.start
        GeometryReader { screen in
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(weighedToday ? "The scale says" : "This morning")
                        .faceEyebrow(Color.accentColor)
                        .faceTopLine()
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        BigNumber(value: shown, points: WristFace.numeralSize(64, fitting: [shown], besides: WristFace.margin * 2 + 50))
                            .contentTransition(.numericText())
                        Text(dial.unit.symbol)
                            .faceFont(16, weight: .semibold)
                            .foregroundStyle(WristInk.text2)
                    }
                    .padding(.top, WristFace.small ? 10 : 26)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Weight")
                    .accessibilityValue("\(shown) \(dial.unit == .lb ? "pounds" : "kilograms")")
                    .accessibilityAdjustableAction { direction in
                        value = dial.snapped(value + (direction == .increment ? dial.step : -dial.step))
                    }
                    .accessibilityIdentifier("weighIn.value")
                    if let trend {
                        HStack(spacing: 7) {
                            Capsule().fill(WristInk.text).frame(width: 12, height: 3)
                            Text("trend \(WristFormat.dial(trend))")
                                .faceFont(13)
                                .foregroundStyle(WristInk.text2)
                        }
                        .padding(.top, 12)
                        .accessibilityElement(children: .combine)
                    }
                    Spacer(minLength: 2)
                }
                .padding(.horizontal, WristFace.margin)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                ActionBand(title: weighedToday ? "Keep" : "Save") {
                    if !keeps { model.weighIn(kg: dial.kilograms(value)) }
                    dismiss()
                }
                .accessibilityIdentifier("weighIn.save")
            }
            .frame(width: screen.size.width, height: screen.size.height)
            .background(alignment: .topLeading) {
                DialScale(value: dial.snapped(value), trend: trend, step: dial.step, center: screen.size.height * 0.37)
                    .frame(width: screen.size.width, height: screen.size.height - WristFace.band)
            }
        }
        .ignoresSafeArea()
        .contentShape(.rect)
        .focusable()
        .focused($crownFocused)
        .digitalCrownRotation(
            $value, from: dial.range.lowerBound, through: dial.range.upperBound, by: dial.step, sensitivity: .low,
            isContinuous: false, isHapticFeedbackEnabled: true
        )
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle("Weigh In")
        .onAppear { crownFocused = true }
    }
}

/// The scale at the edge of the weigh-in, beside the crown: a tick a step, a longer one every five,
/// rolling as the crown turns; the reading's mark in the accent, level with the number, and the
/// trend's in white, as far above or below as it is.
private struct DialScale: View {
    let value: Double
    let trend: Double?
    let step: Double
    let center: CGFloat

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 8
            let steps = (value / step).rounded()
            let reach = Int(size.height / spacing) + 1
            for offset in -reach...reach {
                let y = center + CGFloat(offset) * spacing
                guard y > 4, y < size.height - 2 else { continue }
                let major = Int(steps) - offset
                let long = major % 5 == 0
                let width: CGFloat = long ? 13 : 7
                context.fill(
                    Path(CGRect(x: size.width - width, y: y - 0.75, width: width, height: 1.5)),
                    with: .color(.white.opacity(long ? 0.5 : 0.26)))
            }
            if let trend {
                let y = center - CGFloat((trend - value) / step) * spacing
                if y > 4, y < size.height - 4 {
                    context.fill(
                        RoundedRectangle(cornerRadius: 1.5).path(in: CGRect(x: size.width - 18, y: y - 1.5, width: 18, height: 3)),
                        with: .color(WristInk.text))
                }
            }
            context.fill(
                RoundedRectangle(cornerRadius: 1.5).path(in: CGRect(x: size.width - 22, y: center - 1.5, width: 22, height: 3)),
                with: .color(.accentColor))
        }
        .accessibilityHidden(true)
    }
}
