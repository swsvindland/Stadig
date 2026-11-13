import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

/// The set's face in the accent for a few seconds after a rest ran out on its own, the moment the
/// wrist was tapped: "GO · BENCH PRESS", the set big, its note or what it asks for, and the heart
/// rate with how early it ended the rest. A tap, or the seconds running out, shows the set face.
struct GoFace: View {
    @Environment(WatchModel.self) private var model
    let item: Int
    let set: Int
    let go: GoMoment
    let loadKg: Double?
    let reps: Int

    var body: some View {
        if let live = model.live, live.items.indices.contains(item), live.items[item].sets.indices.contains(set) {
            let liveItem = live.items[item]
            let liveSet = liveItem.sets[set]
            let exercise = model.exercise(item)
            let repOut = liveSet.prescription.kind == .repOut
            let hasLoad = exercise.loadBasis != .none
            let load = WatchFormat.loadParts(loadKg, unit: model.unit, basis: exercise.loadBasis)
            let points = WatchFace.numeralSize(
                64, fitting: (hasLoad ? [load.value] : []) + ["\(reps)\(repOut ? "+" : "")"],
                besides: WatchFace.margin * 2 + (hasLoad ? 14 + 18 * WatchFace.scale : 0))
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "applewatch.radiowaves.left.and.right")
                            .font(.system(size: 12, weight: .semibold))
                            .accessibilityHidden(true)
                        Text("Go · \(exercise.name)").faceEyebrow(WatchInk.onAccent)
                    }
                    .faceTopLine()
                    SetDots(index: set, sets: liveItem.sets, onAccent: true)
                }
                Spacer(minLength: 2)
                HStack(alignment: .top, spacing: 7) {
                    if hasLoad {
                        number(load.value, unit: load.unit, points: points)
                        Text("×")
                            .font(.system(size: 28 * points / 64, weight: .semibold))
                            .opacity(0.62)
                            .frame(height: points * 0.9)
                    }
                    number("\(reps)", unit: repOut ? "or more" : "reps", points: points, plus: repOut)
                }
                Text(liveSet.note ?? WatchFormat.goLine(liveSet.prescription, last: set == liveItem.sets.count - 1))
                    .faceFont(15, weight: .bold)
                    .tracking(-0.15)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, WatchFace.small ? 8 : 12)
                Spacer(minLength: 2)
                if let heart = heartLine {
                    HStack(spacing: 5) {
                        if go.heartRate != nil { HeartGlyph(size: 14, color: WatchInk.onAccent) }
                        Text(heart).faceFont(13, weight: .semibold).monospacedDigit()
                    }
                }
            }
            .foregroundStyle(WatchInk.onAccent)
            .padding(.horizontal, WatchFace.margin)
            .padding(.bottom, WatchFace.small ? 12 : 17)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.accentColor)
            .ignoresSafeArea()
            .contentShape(.rect)
            .onTapGesture { model.dismissGo() }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Shows the set.")
        }
    }

    /// "104 · 22 s early", or either alone.
    private var heartLine: String? {
        let parts = [go.heartRate.map { "\(Int($0.rounded()))" }, go.early.map { "\($0) s early" }].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func number(_ value: String, unit: String, points: CGFloat, plus: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            BigNumber(value: value, points: points, plus: plus)
            Text(unit).faceFont(13, weight: .semibold).lineLimit(1).fixedSize()
        }
    }
}
