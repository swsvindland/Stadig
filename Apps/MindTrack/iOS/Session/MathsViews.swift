import Charts
import MindEngine
import SwiftUI

/// The chart a statistics problem is about, each bar labelled with its value so it can be read
/// exactly. The person's own numbers say where they came from.
struct DataFigureView: View {
    let figure: DataFigure

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(figure.title).font(.subheadline.weight(.semibold))
                Spacer()
                if let source = figure.source {
                    Label(source, systemImage: "link").font(.caption).foregroundStyle(.secondary)
                }
            }
            Chart {
                ForEach(Array(figure.points.enumerated()), id: \.offset) { _, point in
                    switch figure.style {
                    case .bars:
                        BarMark(x: .value("Label", point.label), y: .value(figure.unit, point.value))
                            .foregroundStyle(Domain.maths.color.gradient)
                            .annotation(position: .top) {
                                Text(Self.value(point.value)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            }
                    case .line:
                        LineMark(x: .value("Label", point.label), y: .value(figure.unit, point.value)).foregroundStyle(Domain.maths.color)
                        PointMark(x: .value("Label", point.label), y: .value(figure.unit, point.value)).foregroundStyle(Domain.maths.color)
                            .annotation(position: .top) {
                                Text(Self.value(point.value)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            }
                    }
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .chartYAxisLabel(figure.unit)
            .frame(height: 180)
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(figure.title), in \(figure.unit): " + figure.points.map { "\($0.label) \(Self.value($0.value))" }.joined(separator: ", "))
    }

    static func value(_ value: Double) -> String {
        value.rounded() == value ? Int(value).formatted() : value.formatted(.number.precision(.fractionLength(1)))
    }
}

extension Question {
    /// The answer as it's shown after a miss: a decimal for numeracy outside fractions (0.34 kg,
    /// not 17/50), exact everywhere else.
    var shownAnswer: String {
        guard case .number(let value, let tolerance) = answer else { return "" }
        if tolerance > 0 { return String(format: "%.2f", value.double) }
        if let numeracy = key.numeracy, numeracy.skill != .fractions, let decimal = value.decimal { return decimal }
        return value.tex
    }

    /// Answered right inside the target time.
    func fluent(_ seconds: Double?) -> Bool { seconds.map { $0 <= expectedSeconds } ?? false }
}
