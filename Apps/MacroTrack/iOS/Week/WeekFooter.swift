import NutritionEngine
import SwiftUI
import SystemCore

/// Along the foot of the desk: the week's average day (its calories and protein against the same
/// days' targets) and the weight trend over the four weeks to the week's end. In a narrow window the
/// trend's line goes first, then protein.
struct WeekFooter: View {
    let average: WeekAverage?
    let weight: WeekWeight?
    let units: WeightUnit

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(protein: true, line: true)
            row(protein: true, line: false)
            row(protein: false, line: false)
        }
        .frame(height: 74)
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .overlay(alignment: .top) { Rectangle().fill(Ink.hairline).frame(height: 1) }
        .padding(.top, 12)
    }

    func row(protein: Bool, line: Bool) -> some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Week average").eyebrow()
                Text(counted).font(.caption).foregroundStyle(Ink.text3)
            }
            .fixedSize()
            .accessibilityElement(children: .combine)
            if let average {
                AverageMeasure(
                    value: average.kcal, target: average.kcalTarget, unit: "kcal a day", color: .accentColor, identifier: "week.averageKcal")
                if protein {
                    AverageMeasure(
                        value: average.protein, target: average.proteinTarget, unit: "g protein a day", color: Ink.protein,
                        identifier: "week.averageProtein")
                }
            }
            Spacer(minLength: 0)
            if let weight {
                HStack(spacing: 14) {
                    if line { WeightLine(weight: weight).frame(width: 196, height: 40) }
                    Measure(value: Format.number(units.fromKilograms(weight.trend)), unit: units.symbol, size: 30, weight: .bold)
                        .foregroundStyle(Ink.text)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Weight trend").eyebrow()
                        if let weekly = weight.weekly {
                            Text(Format.weeklyChange(weekly, unit: units)).font(.caption).foregroundStyle(Ink.text3)
                        }
                    }
                }
                .fixedSize()
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("week.weight")
            }
        }
    }

    /// "2 logged, 5 planned".
    var counted: String {
        guard let average else { return "Nothing yet" }
        let parts = [average.logged > 0 ? "\(average.logged) logged" : nil, average.planned > 0 ? "\(average.planned) planned" : nil]
        return parts.compactMap(\.self).joined(separator: ", ")
    }
}

/// An average beside its unit, how far from the target, and a thin ruler to it.
private struct AverageMeasure: View {
    let value: Double
    let target: Double?
    let unit: String
    let color: Color
    let identifier: String

    var body: some View {
        HStack(spacing: 12) {
            Text(Format.whole(value)).numeral(30).foregroundStyle(Ink.text)
            VStack(alignment: .leading, spacing: 5) {
                Text(caption).font(.caption).foregroundStyle(Ink.text3).lineLimit(1)
                Ruler.thin(target.map { $0 > 0 ? value / $0 : 0 } ?? 0, color: color)
            }
            .frame(width: 134)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    /// "kcal a day · 28 under".
    var caption: String {
        guard let target, target > 0 else { return unit }
        let off = value - target
        guard abs(off) >= 0.5 else { return "\(unit) · on target" }
        return "\(unit) · \(Format.whole(abs(off))) \(off > 0 ? "over" : "under")"
    }
}

/// Four weeks of weigh-ins as dots, the trend through them as a line in the accent, ending on a dot.
private struct WeightLine: View {
    let weight: WeekWeight

    var body: some View {
        Canvas { context, size in
            let points = weight.points
            guard let first = points.first, let last = points.last else { return }
            let values = points.map(\.trend) + points.compactMap { $0.counted ? $0.scale : nil }
            guard let low = values.min(), let high = values.max() else { return }
            let span = max(high - low, 0.4)
            let days = max(1, Double(first.day.days(until: last.day)))
            func spot(_ day: Day, _ kg: Double) -> CGPoint {
                CGPoint(
                    x: 4 + (size.width - 8) * Double(first.day.days(until: day)) / days,
                    y: 4 + (size.height - 8) * (1 - (kg - low) / span))
            }
            for point in points where point.counted {
                guard let scale = point.scale else { continue }
                let at = spot(point.day, scale)
                context.fill(Path(ellipseIn: CGRect(x: at.x - 1.7, y: at.y - 1.7, width: 3.4, height: 3.4)), with: .color(Ink.text3))
            }
            var line = Path()
            for (index, point) in points.enumerated() {
                let at = spot(point.day, point.trend)
                if index == 0 { line.move(to: at) } else { line.addLine(to: at) }
            }
            context.stroke(line, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            let end = spot(last.day, last.trend)
            let dot = Path(ellipseIn: CGRect(x: end.x - 3.4, y: end.y - 3.4, width: 6.8, height: 6.8))
            context.fill(dot, with: .color(.accentColor))
            context.stroke(dot, with: .color(Ink.ground), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
    }
}
