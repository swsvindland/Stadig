import Charts
import SwiftUI
import MindEngine
import SystemCore

/// The honest measures: tests at check-ins and finished books. Time spent and cards reviewed never
/// show up here as progress.
struct ProgressTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let analysis = model.analysis, let state = model.state {
                        StatCards(stats: analysis.stats)
                        ForEach(analysis.languages, id: \.domain) { LanguageProgress(summary: $0, state: state) }
                        if state.settings.has(.maths) { MathsProgress(analysis: analysis, state: state) }
                        if state.settings.has(.writing) { WritingProgressCard(analysis: analysis, state: state) }
                        if state.settings.has(.reading) { ReadingProgress(analysis: analysis, state: state) }
                        SectionHeader(title: "Discipline")
                            .accessibilityIdentifier("progress.discipline")
                        DisciplineGauge(score: analysis.discipline).card()
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .readableWidth()
            }
            .background(.pageBackground)
            .navigationTitle("Progress")
        }
    }
}

private struct StatCards: View {
    let stats: [StatReading]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(stats, id: \.stat) { reading in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: reading.stat.symbol).font(.title2).foregroundStyle(.tint).frame(width: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(reading.stat.label).font(.headline)
                                .accessibilityIdentifier("progress.stat.\(reading.stat.rawValue)")
                            Spacer()
                            Label(reading.trend.label, systemImage: reading.trend.symbol).font(.caption.weight(.semibold))
                                .foregroundStyle(reading.trend.color)
                        }
                        Text(reading.score.map { "\(Int($0.rounded()))" } ?? "—").font(.largeTitle.bold().monospacedDigit())
                        Text(reading.label).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .card()
            }
            Text("Intelligence moves only on the check-in tests; Wisdom only on the reading test and finished books. Reviewing or reading for longer doesn't raise either.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// A test's history as a line, newest on the right.
private struct TestChart: View {
    let points: [(date: Date, value: Double)]
    let label: String
    var color: Color = .accentColor
    var format: (Double) -> String = { "\(Int($0.rounded()))" }

    var body: some View {
        if points.count >= 2 {
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Date", point.date), y: .value(label, point.value))
                        .foregroundStyle(color)
                    PointMark(x: .value("Date", point.date), y: .value(label, point.value))
                        .foregroundStyle(color)
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 140)
            .accessibilityLabel("\(label) over time: \(points.map { format($0.value) }.joined(separator: ", "))")
        }
    }
}

struct ReflectionsList: View {
    let reflections: [Reflection]
    let books: [Book]

    var body: some View {
        List(reflections.reversed()) { reflection in
            VStack(alignment: .leading, spacing: 4) {
                Text(books.first { $0.id == reflection.bookID }?.title ?? "Reading").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(reflection.text)
                Text(reflection.date.formatted(date: .abbreviated, time: .omitted) + (reflection.page.map { " · page \($0)" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        .navigationTitle("Reflections")
    }
}
