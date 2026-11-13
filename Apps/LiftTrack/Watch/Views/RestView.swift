import ExerciseLibrary
import HealthBridge
import LiftEngine
import SwiftUI
import SystemCore

/// The rest between sets, as the design's face: the accent filling the screen from the foot toward
/// go, the countdown huge across it, heart rate and the rate that ends the rest early at the top, the
/// next set and Go now (Double Tap) at the foot; whatever the level has risen over is drawn again in
/// ink on it. The crown adds time, or takes it off, a quarter-minute a step. Scrolled on: what the
/// last rating changed, the drill for the rest, a quarter-minute less or more, and the next set in
/// full. Heart rate may end an accessory's rest early (the model watches for that).
struct RestView: View {
    @Environment(WatchModel.self) private var model
    /// The crown's position; each step from where it was adds or takes off 15 seconds.
    @State private var crown = 0.0
    @FocusState private var crownFocused: Bool

    var body: some View {
        if let live = model.live, let rest = live.rest {
            ScrollView {
                VStack(spacing: 8) {
                    face(rest)
                        .containerRelativeFrame(.vertical)
                    VStack(spacing: 8) {
                        if let message = live.message {
                            Text(message)
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let filler = rest.filler {
                            Label("Use the rest: \(model.catalog[filler]?.name ?? filler)", systemImage: "figure.flexibility")
                                .font(.footnote)
                                .foregroundStyle(WatchInk.text2)
                        }
                        HStack {
                            Button("15 s", systemImage: "minus") { model.extendRest(by: -15) }
                                .accessibilityLabel("15 seconds less")
                            Button("15 s", systemImage: "plus") { model.extendRest(by: 15) }
                                .accessibilityLabel("15 seconds more")
                        }
                        .labelStyle(.titleAndIcon)
                        .font(.footnote)
                        .buttonStyle(.glass)
                        if rest.plan.heartRateGuided {
                            Text("Ends early once your heart rate settles, after \(WatchFormat.clock(rest.plan.minimum)).")
                                .font(.caption2)
                                .foregroundStyle(WatchInk.text2)
                                .multilineTextAlignment(.center)
                        }
                        upNext
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 24)
                }
            }
            .ignoresSafeArea()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: The face

    private func face(_ rest: RestState) -> some View {
        TimelineView(.periodic(from: rest.started, by: 1)) { context in
            let total = max(1, rest.endsAt.timeIntervalSince(rest.started))
            let elapsed = min(total, max(0, context.date.timeIntervalSince(rest.started)))
            GeometryReader { geometry in
                let level = geometry.size.height * elapsed / total
                ZStack(alignment: .bottom) {
                    content(rest, onLevel: false)
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: level)
                        .accessibilityHidden(true)
                    content(rest, onLevel: true)
                        .mask(alignment: .bottom) { Rectangle().frame(height: level) }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .focusable()
        .focused($crownFocused)
        .digitalCrownRotation(
            $crown, from: -1_000, through: 1_000, by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true
        )
        .onChange(of: crown) { old, new in
            let steps = Int(new.rounded()) - Int(old.rounded())
            if steps != 0 { model.extendRest(by: 15 * steps) }
        }
        .onAppear { crownFocused = true }
    }

    /// The face's words and numbers: in their colours over the ground, in ink on the level.
    private func content(_ rest: RestState, onLevel: Bool) -> some View {
        let ink = onLevel ? WatchInk.onAccent : WatchInk.text
        let quiet = onLevel ? WatchInk.onAccent : WatchInk.text2
        return VStack(spacing: 0) {
            heartRate(rest, ink: ink, quiet: quiet, onLevel: onLevel)
            countdown(rest)
                .foregroundStyle(ink)
                .padding(.top, WatchFace.small ? 4 : 10)
            Spacer(minLength: 4)
            nextSet
                .foregroundStyle(ink)
            Button {
                model.endRest()
            } label: {
                HStack(spacing: 6) {
                    DoubleTapGlyph(size: 16)
                    Text("Go now").faceFont(13, weight: .semibold)
                }
                .foregroundStyle(quiet)
                .frame(maxWidth: .infinity, minHeight: 30)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .handGestureShortcut(.primaryAction, isEnabled: !onLevel)
            .accessibilityLabel("Go now")
            .accessibilityHint("Ends the rest.")
            .padding(.top, 2)
        }
        .padding(.top, 18)
        .padding(.horizontal, WatchFace.margin)
        .padding(.bottom, WatchFace.small ? 6 : 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .trailing) {
            EdgeTicks(color: onLevel ? WatchInk.onAccent.opacity(0.5) : .white.opacity(0.26))
        }
    }

    private func countdown(_ rest: RestState) -> some View {
        TimelineView(.periodic(from: rest.started, by: 1)) { context in
            let remaining = max(0, rest.endsAt.timeIntervalSince(context.date))
            let clock = WatchFormat.clock(Int(remaining.rounded(.up)))
            BigNumber(value: clock, points: WatchFace.numeralSize(78, fitting: [clock], besides: WatchFace.margin * 2 + 4))
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Rest")
                .accessibilityValue("\(WatchFormat.clock(Int(remaining.rounded(.up)))) left")
        }
    }

    /// "Next 70 × 7+", over Go now.
    @ViewBuilder private var nextSet: some View {
        if let live = model.live, let (item, set) = model.position {
            let exercise = model.exercise(item)
            let prescription = live.items[item].sets[set].prescription
            Text("Next \(WatchFormat.nextSet(prescription, exercise: exercise, unit: model.unit, plannedSeconds: live.items[item].plan.seconds))")
                .faceFont(15, weight: .semibold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
        }
    }

    /// Heart rate in the corner of the face, and the rate under which the rest ends early.
    @ViewBuilder private func heartRate(_ rest: RestState, ink: Color, quiet: Color, onLevel: Bool) -> some View {
        let goAt = rest.recoveredAt(zones: model.zones)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                if let bpm = model.heartRate {
                    HeartGlyph(size: 15, color: onLevel ? WatchInk.onAccent : WatchInk.bad)
                    Text("\(Int(bpm.rounded()))")
                        .font(.system(size: 18, weight: .bold).monospacedDigit())
                        .tracking(-0.36)
                        .foregroundStyle(ink)
                }
            }
            .frame(minHeight: 22)
            // Its line is kept when heart rate doesn't guide the rest, so the countdown sits where the
            // design has it either way.
            Text("go at \(goAt ?? 100)").faceFont(13).foregroundStyle(quiet).opacity(goAt == nil ? 0 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [model.heartRate.map { "Heart rate \(Int($0.rounded()))" }, goAt.map { "ends early at \($0)" }].compactMap(\.self)
                .joined(separator: ", ")
        )
        .accessibilityHidden(onLevel || (model.heartRate == nil && goAt == nil))
    }

    @ViewBuilder private var upNext: some View {
        if let live = model.live, let (item, set) = model.position {
            let exercise = model.exercise(item)
            let liveItem = live.items[item]
            VStack(spacing: 2) {
                Text("Up next").font(.caption2).foregroundStyle(WatchInk.text2)
                Text(exercise.name).font(.footnote.weight(.semibold)).multilineTextAlignment(.center)
                Text(
                    WatchFormat.prescription(
                        liveItem.sets[set].prescription, exercise: exercise, unit: model.unit,
                        plannedSeconds: liveItem.plan.seconds)
                )
                .font(.footnote.monospacedDigit())
                .foregroundStyle(WatchInk.text2)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
