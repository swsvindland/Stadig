import Charts
import SwiftUI
import MindEngine
import SystemCore

/// Maths on Progress: each strand's level at its last test, and the strands over time. Only the
/// placement and the check-ins move these; drills and lessons never do.
struct MathsProgress: View {
    let analysis: MindAnalysis
    let state: StudyState

    var body: some View {
        let levels = MathsPlan.levels(state)
        let series = levels.map { (strand: $0.strand, points: MathsPlan.series($0.strand, state: state)) }
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                DomainBadge(domain: .maths)
                Text("Maths").font(.headline)
            }
            HStack(alignment: .top, spacing: 12) {
                ForEach(levels) { level in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(level.measured.map(String.init) ?? "—").font(.title.bold().monospacedDigit())
                        Text(level.strand.label).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(level.measured.map { "\(level.strand.label): level \($0) of 10" } ?? "\(level.strand.label): not measured yet")
                }
            }
            Text("Levels of 10 at the last test, the placement or a check-in. Numeracy counts speed as well as accuracy.")
                .font(.footnote).foregroundStyle(.secondary)
            if series.contains(where: { $0.points.count >= 2 }) {
                Chart {
                    ForEach(series, id: \.strand) { line in
                        ForEach(Array(line.points.enumerated()), id: \.offset) { _, point in
                            LineMark(x: .value("Date", point.day.date()), y: .value("Score", point.score))
                                .foregroundStyle(by: .value("Strand", line.strand.label))
                            PointMark(x: .value("Date", point.day.date()), y: .value("Score", point.score))
                                .foregroundStyle(by: .value("Strand", line.strand.label))
                        }
                    }
                }
                .chartForegroundStyleScale(domain: levels.map(\.strand.label), range: levels.map { Self.color($0.strand) })
                .chartYScale(domain: 0...100)
                .chartYAxis { AxisMarks(position: .leading) }
                .chartLegend(position: .bottom)
                .frame(height: 160)
                .accessibilityLabel("Maths strands over time, out of 100")
            }
            let checks = levels.compactMap { level in
                state.tests.last { MathsStrand(test: $0.test) == level.strand && !$0.placement }.map { (level.strand, $0) }
            }
            if checks.isEmpty {
                LabeledContent("Next measured", value: "At the first check-in")
            } else {
                ForEach(checks, id: \.0) { strand, test in
                    LabeledContent(strand.label, value: "\(Format.percent(test.score)) right · \(Format.seconds(test.detail["seconds"] ?? 0)) a problem")
                }
            }
        }
        .font(.subheadline)
        .card()
    }

    static func color(_ strand: MathsStrand) -> Color {
        switch strand {
        case .numeracy: .blue
        case .classic: .indigo
        case .discrete: .cyan
        }
    }
}
