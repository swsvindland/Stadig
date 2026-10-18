import Charts
import SwiftUI
import MindEngine
import SystemCore

/// Reading's honest measures: the level from reading tests and finished books, and focus from
/// reading blocks, kept apart. Pages and minutes read never show up here as progress.
struct ReadingProgress: View {
    @Environment(AppModel.self) private var model
    let analysis: MindAnalysis
    let state: StudyState

    var body: some View {
        let reading = analysis.reading
        let series = model.series(.reading)
        let tests = state.tests.filter { $0.test == .readingTest && $0.domain == .reading }
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                DomainBadge(domain: .reading)
                Text("Reading").font(.headline)
            }
            Text(reading.level.map { "Reads at tier \(ReadingPlan.format($0)) of 10" } ?? "Placed by the reading test").font(.title3.bold())
            if let level = reading.level, let info = ReadingLadder.standard.tier(clamp(Int(level.rounded()), 1, 10)) {
                Text("\(info.label): \(info.description)").font(.subheadline).foregroundStyle(.secondary)
            }
            if series.count >= 2 {
                Chart {
                    ForEach(Array(series.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("Date", point.day.date()), y: .value("Tier", point.score / 10)).foregroundStyle(.teal)
                        PointMark(x: .value("Date", point.day.date()), y: .value("Tier", point.score / 10)).foregroundStyle(.teal)
                    }
                }
                .chartYScale(domain: 1...10)
                .chartYAxis { AxisMarks(position: .leading, values: [1, 4, 7, 10]) }
                .frame(height: 140)
                .accessibilityLabel("Reading level over time: \(series.map { ReadingPlan.format($0.score / 10) }.joined(separator: ", "))")
            }
            ForEach(tests.suffix(3).reversed()) { test in
                LabeledContent(test.placement ? "Reading test, placement" : "Reading test") {
                    Text("Tier \(ReadingPlan.format(test.detail["tier"] ?? 0)) · \(Int(test.detail["wpm"] ?? 0)) words a minute")
                }
            }
            Divider()
            LabeledContent("Focus in one sitting", value: reading.stamina.map { "About \(Int($0)) min" } ?? "Measured as you read")
            LabeledContent("Next reading block", value: "\(reading.nextBlock) min")
            Text("Focus counts print and ebooks; audiobooks count for level and taste only.").font(.caption).foregroundStyle(.secondary)
            Divider()
            LabeledContent("Finished here", value: "\(reading.finished.count)")
            if let pace = reading.pagesPerMinute {
                LabeledContent("Pace", value: "\(Int((pace * 60).rounded())) pages an hour")
            }
            ForEach(reading.finished.prefix(4)) { book in
                LabeledContent(book.title, value: "Tier \(book.tier)\(book.feel.map { " · \($0.label.lowercased())" } ?? "")")
            }
            if !state.reflections.isEmpty {
                NavigationLink {
                    ReflectionsList(reflections: state.reflections, books: state.books)
                } label: {
                    Label("Reflections (\(state.reflections.count))", systemImage: "text.quote")
                }
            }
        }
        .font(.subheadline)
        .card()
    }
}
