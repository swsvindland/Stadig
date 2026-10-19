import Charts
import MindEngine
import SwiftUI
import SystemCore

private struct WritingHeader: View {
    var detail: String?

    var body: some View {
        HStack(spacing: 10) {
            DomainBadge(domain: .writing)
            Text("Writing").font(.headline)
            Spacer()
            if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
        }
    }
}

/// Writing on the Plan tab: what comes next, a Franklin rewrite waiting, the term's benchmark and
/// the grammar skills behind it all.
struct WritingPlanCard: View {
    @Environment(AppModel.self) private var model
    let analysis: MindAnalysis
    let state: StudyState

    var body: some View {
        let library = model.catalogs.writing.library
        let summary = analysis.writing
        VStack(alignment: .leading, spacing: 10) {
            WritingHeader(detail: state.settings.writingKinds.map(\.label).joined(separator: " · "))
            if let task = WritingSchedule.task(state, minutes: 8, library: library) {
                LabeledContent("Next piece", value: WritingSchedule.detail(task))
            }
            if let notes = WritingSchedule.waitingNotes(state.pieces, library: library) {
                let ready = notes.day.adding(days: WritingSchedule.franklinGap)
                let credit = WritingSchedule.original(of: notes, library: library)?.credit
                Label(
                    "Your notes on \(credit.map { "the passage (\($0))" } ?? "a page of your book") are waiting. The rewrite comes \(ready <= state.today ? "in the next writing session" : "from \(Format.day(ready))"), from the notes alone.",
                    systemImage: "text.book.closed"
                )
                .foregroundStyle(.secondary)
            }
            if let next = WritingSchedule.nextBenchmark(state) {
                LabeledContent("Benchmark", value: "At the first check-in from \(Format.day(next, style: .dateTime.month(.abbreviated).day()))")
            } else {
                LabeledContent("Benchmark", value: "In your next writing session")
            }
            LabeledContent("Grammar skills", value: "\(summary.known) of \(summary.total) in")
        }
        .font(.subheadline)
        .card()
    }
}

/// Writing on the Progress tab: the score behind Intelligence's writing share (the grammar check
/// and blind comparisons only), how the comparisons went, and the measured metrics as trends.
struct WritingProgressCard: View {
    @Environment(AppModel.self) private var model
    let analysis: MindAnalysis
    let state: StudyState

    var body: some View {
        let series = model.series(.writing)
        let record = WritingProgress.record(state.comparisons)
        let trends = WritingProgress.trends(state.pieces)
        VStack(alignment: .leading, spacing: 14) {
            WritingHeader()
            if let latest = series.last {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(latest.score.rounded()))").font(.title2.bold().monospacedDigit())
                    Text("Half the grammar check, half the blind comparisons. Writing more doesn't move it; writing better does.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if series.count >= 2 {
                    Chart(Array(series.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("Date", point.day.date()), y: .value("Writing", point.score)).foregroundStyle(Domain.writing.color)
                        PointMark(x: .value("Date", point.day.date()), y: .value("Writing", point.score)).foregroundStyle(Domain.writing.color)
                    }
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: 120)
                    .accessibilityLabel("Writing over time: \(series.map { "\(Int($0.score.rounded()))" }.joined(separator: ", "))")
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Blind comparisons").font(.subheadline.weight(.semibold))
                if record.judged == 0 {
                    Text("None yet. At a check-in, once there are pieces five weeks apart, you'll judge an older and a newer one unlabelled.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("You picked the newer piece \(record.newerPicked) of \(record.judged) times.")
                    if record.aiJudged > 0 {
                        Text(
                            "Apple Intelligence, judging blind, picked it \(record.aiNewerPicked) of \(record.aiJudged)\(record.bothJudged > 0 ? ", and agreed with you \(record.agreed) of \(record.bothJudged)" : "")."
                        )
                        .foregroundStyle(.secondary)
                    }
                    if record.aiJudged < record.judged {
                        Text(
                            "Its pick counts only when it holds whichever way round the pieces are shown; \(record.judged - record.aiJudged == 1 ? "one comparison has" : "\(record.judged - record.aiJudged) have") no clear second opinion."
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let check = state.latest(.writing) {
                LabeledContent("Grammar check", value: "\(Format.percent(check.score)) right\(check.placement ? " (placement)" : "")")
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Measured on every piece").font(.subheadline.weight(.semibold))
                ForEach(trends) { trend in TrendRow(trend: trend) }
            }
            if !state.pieces.isEmpty {
                NavigationLink {
                    PiecesList()
                } label: {
                    Label("Your writing (\(state.pieces.count))", systemImage: "doc.richtext")
                }
            }
        }
        .font(.subheadline)
        .card()
        #if DEBUG
        .modifier(WritingDebugScreen())
        #endif
    }
}

/// A metric's direction in words and its shape as a line, with no numbers on it.
private struct TrendRow: View {
    let trend: WritingTrend

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(trend.metric.title).font(.subheadline.weight(.medium))
                    if let symbol { Image(systemName: symbol).font(.caption.weight(.bold)).foregroundStyle(color) }
                }
                Text(trend.summary).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if trend.points.count >= 2 {
                Chart(Array(trend.points.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Date", point.date), y: .value(trend.metric.title, point.value))
                        .foregroundStyle(color)
                        .interpolationMethod(.monotone)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(width: 96, height: 36)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    var color: Color {
        switch trend.direction {
        case .better: .green
        case .worse: .orange
        case .steady, .notEnoughData: .secondary
        }
    }

    var symbol: String? {
        switch trend.direction {
        case .better, .worse:
            // An arrow for which way the number went: fewer slips points down and is good.
            let up = (trend.direction == .better) != (trend.metric == .slips)
            return up ? "arrow.up.right" : "arrow.down.right"
        case .steady: return "arrow.right"
        case .notEnoughData: return nil
        }
    }
}

/// Every piece, newest first.
struct PiecesList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(model.pieces.reversed()) { piece in
            NavigationLink {
                PieceDetail(id: piece.id)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label(piece.exercise.label, systemImage: piece.exercise.symbol).font(.caption.weight(.semibold))
                            .foregroundStyle(Domain.writing.color)
                        Spacer()
                        Text(piece.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(piece.text.isEmpty ? piece.notes ?? "" : piece.text).font(.subheadline).lineLimit(2)
                    if piece.source == .handwritten {
                        Label("Handwritten", systemImage: "pencil.and.scribble").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Your writing")
    }
}

/// One piece, on a screen of its own (from Progress, on an iPhone).
struct PieceDetail: View {
    @Environment(AppModel.self) private var model
    let id: UUID

    var body: some View {
        PieceView(id: id)
            .navigationTitle(model.pieces.last { $0.id == id }?.date.formatted(date: .abbreviated, time: .omitted) ?? "Piece")
            .inlineTitle()
    }
}

/// One piece: the task, what it worked from, the text with its slips marked, and the notes on it,
/// or a way to ask for them if they never came. In a wide window what it worked from sits beside it.
struct PieceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let id: UUID
    @State private var slips: [WritingSlip] = []

    var body: some View {
        ScrollView {
            if let piece = model.pieces.last(where: { $0.id == id }) {
                let source = model.source(of: piece)
                let wide = sizeClass == .regular && (source != nil || piece.notes != nil) && !piece.text.isEmpty
                VStack(alignment: .leading, spacing: 14) {
                    Label(piece.exercise.label, systemImage: piece.exercise.symbol).font(.subheadline.weight(.semibold))
                        .foregroundStyle(Domain.writing.color)
                    Text(piece.prompt).font(.callout)
                    let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 16)) : AnyLayout(VStackLayout(spacing: 14))
                    layout {
                        if source != nil || piece.notes != nil {
                            VStack(spacing: 14) {
                                if let source {
                                    TextCard(title: piece.exercise == .practical ? "The original" : "The passage", detail: nil, text: Text(source))
                                }
                                if let notes = piece.notes {
                                    TextCard(title: "Notes", detail: nil, text: Text(notes))
                                }
                            }
                        }
                        if !piece.text.isEmpty {
                            TextCard(
                                title: piece.source == .handwritten ? "Written by hand" : "Typed", detail: "\(piece.words) words",
                                text: MarkedText.text(piece.text, slips: slips))
                        }
                    }
                    if !piece.text.isEmpty {
                        NotesCard(state: WritingAssistant.shared.state(for: piece), asked: false) {
                            WritingAssistant.shared.requestNotes(for: piece, source: model.source(of: piece), model: model, again: true)
                        }
                    }
                }
                .padding(20)
                .readableWidth(wide ? 1080 : 680)
                .task(id: piece.text) { slips = WritingAssistant.slips(piece.text) }
            }
        }
        .background(.pageBackground)
    }
}
