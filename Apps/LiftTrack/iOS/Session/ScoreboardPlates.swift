import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

// What goes on the bar, drawn for the scoreboard to be read from across the room.

/// What goes on the bar for a set: a side's plates, in the gym's unit, and the empty bar.
struct BoardPlateLoad: Equatable {
    var plates: [Double]
    var unit: WeightUnit
    var bar: Double

    /// "25 kg a side".
    var side: String { "\(Format.number(plates.reduce(0, +), digits: 2)) \(unit.symbol) a side" }
    /// "20 + 5 · bar 20".
    var list: String {
        plates.map { Format.number($0, digits: 2) }.joined(separator: " + ") + " · bar \(Format.number(bar, digits: 2))"
    }
}

/// The drawn bar beside what it says: "25 kg a side" over "20 + 5 · bar 20".
struct BoardPlates: View {
    let plates: BoardPlateLoad
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 28 * scale) {
            BarbellDiagram(plates: plates.plates, unit: plates.unit)
                .frame(width: 380 * scale, height: 130 * scale)
            VStack(alignment: .leading, spacing: 4) {
                Text(plates.side).font(.system(size: 44 * max(scale, 0.75), weight: .heavy)).tracking(-1).foregroundStyle(Ink.text)
                Text(plates.list).font(scale < 1 ? .title3 : .title2).foregroundStyle(Ink.text2)
            }
            .lineLimit(1).minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A barbell as flat rectangles: the bar with its collars and, on each sleeve, a side's plates from
/// the collar out, each sized by its weight, so the heavy ones read as heavy from across the room.
struct BarbellDiagram: View {
    /// One side's plates, heaviest first, in the gym's unit.
    let plates: [Double]
    let unit: WeightUnit

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let barHeight = max(4, size.height * 0.08)
            context.fill(
                Path(roundedRect: CGRect(x: 0, y: midY - barHeight / 2, width: size.width, height: barHeight), cornerRadius: barHeight / 2),
                with: .color(Ink.text3))
            let collar = CGSize(width: max(4, size.width * 0.02), height: size.height * 0.24)
            let sleeve = size.width * 0.3
            let gap = max(2, size.width * 0.008)
            let shapes = plates.map { Self.plate(kg: unit.toKilograms($0), height: size.height) }
            let needed = shapes.reduce(0) { $0 + $1.width } + gap * Double(max(0, shapes.count - 1))
            // More plates than the sleeve holds at full width: all of them thinner, none dropped.
            let squeeze = needed > sleeve - collar.width ? (sleeve - collar.width) / needed : 1
            for side in [-1.0, 1.0] {
                let collarX = side < 0 ? sleeve - collar.width : size.width - sleeve
                context.fill(
                    Path(roundedRect: CGRect(x: collarX, y: midY - collar.height / 2, width: collar.width, height: collar.height), cornerRadius: 2),
                    with: .color(Ink.text3))
                var x = side < 0 ? collarX - gap : collarX + collar.width + gap
                for shape in shapes {
                    let width = shape.width * squeeze
                    let rect = CGRect(x: side < 0 ? x - width : x, y: midY - shape.height / 2, width: width, height: shape.height)
                    context.fill(Path(roundedRect: rect, cornerRadius: min(4, width / 3)), with: .color(Ink.text))
                    x += side * (width + gap * squeeze)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// A plate's face: 25 kg is the full height, 2.5 kg under half of it, by the square root of the
    /// weight as bumper plates go.
    static func plate(kg: Double, height: CGFloat) -> CGSize {
        let t = (min(max(kg, 0.5), 25) / 25).squareRoot()
        return CGSize(width: height * (0.07 + 0.14 * t), height: height * (0.24 + 0.76 * t))
    }
}

extension AppModel {
    /// The current set's bar, when it's loaded with plates.
    func boardPlates(item: LiveItem, exercise: Exercise, load: Double) -> BoardPlateLoad? {
        guard item.plan.isStrength, exercise.equipment.platePaired else { return nil }
        let increments = gymForToday.increments(for: exercise)
        guard let plates = increments.platesPerSide(load), !plates.isEmpty else { return nil }
        return BoardPlateLoad(plates: plates, unit: increments.gym.unit, bar: increments.gym.unit.fromKilograms(increments.barKg))
    }

    /// The next set's bar, from what the rest says comes next.
    func boardPlates(next: NextSet) -> BoardPlateLoad? {
        guard let plates = next.plates, !plates.isEmpty else { return nil }
        return BoardPlateLoad(plates: plates, unit: next.plateUnit, bar: next.plateBar ?? 0)
    }
}
