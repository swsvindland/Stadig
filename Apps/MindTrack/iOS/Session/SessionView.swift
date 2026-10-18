import SwiftUI
import MindEngine
import SystemCore

/// A focused session, full screen: one step at a time, the clock in the corner.
struct SessionView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingEnd = false

    var body: some View {
        NavigationStack {
            Group {
                if let run = model.run {
                    if let step = run.step {
                        StepView(step: step, run: run)
                            .id(stepID(step, run))
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                    } else {
                        SessionSummary(run: run)
                    }
                }
            }
            .animation(.snappy, value: model.run.map { stepID($0.step, $0) })
            .background(.pageBackground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("End", systemImage: "xmark") {
                        if model.run?.isComplete == true { model.endSession() } else { confirmingEnd = true }
                    }
                }
                ToolbarItem(placement: .principal) { SessionHeader() }
                ToolbarItem(placement: .primaryAction) { Clock() }
            }
            .confirmationDialog("End the session?", isPresented: $confirmingEnd, titleVisibility: .visible) {
                Button("End session", role: .destructive) { model.endSession() }
                if let part = model.run?.currentPart, model.run.map({ $0.partIndex < $0.planParts.count - 1 }) ?? false {
                    Button("Skip \(part.title.lowercased())") { model.act { $0.skipPart(now: Date()) } }
                }
                Button("Keep going", role: .cancel) {}
            } message: {
                Text("Everything answered so far is kept, and anything half-learned comes back tomorrow.")
            }
        }
        .task {
            // The session clock: counted while the screen is up, long gaps left out.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard model.run != nil else { continue }
                model.tick()
            }
        }
    }

    func stepID(_ step: StudyRun.Step?, _ run: StudyRun) -> String {
        "\(run.session.attempts.count).\(run.partIndex).\(run.feedback == nil).\(step.map { "\($0)".prefix(60) } ?? "end")"
    }
}

extension AppModel {
    /// Advances the session clock without saving: the clock is saved with the next answer.
    func tick() {
        guard var current = run else { return }
        current.tick(now: Date())
        run = current
    }
}

private struct SessionHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let run = model.run, let part = run.currentPart {
            VStack(spacing: 1) {
                Text(part.title).font(.subheadline.weight(.semibold))
                Text("Part \(run.partIndex + 1) of \(run.planParts.count)").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

private struct Clock: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let run = model.run {
            let total = Double(run.plan.minutes)
            let used = min(total, run.session.minutes)
            HStack(spacing: 6) {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 3)
                    Circle().trim(from: 0, to: used / max(1, total)).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 18, height: 18)
                Text(run.minutesLeft > 0.5 ? "\(Int(run.minutesLeft.rounded())) min" : "Time")
                    .font(.subheadline.monospacedDigit())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(run.minutesLeft > 0.5 ? "\(Int(run.minutesLeft.rounded())) minutes left" : "Time is up")
        }
    }
}

private struct StepView: View {
    @Environment(AppModel.self) private var model
    let step: StudyRun.Step
    let run: StudyRun

    var body: some View {
        switch step {
        case .lesson(let lesson):
            LessonView(lesson: lesson)
        case .question(let question):
            QuestionView(question: question, feedback: run.feedback)
        case .pickBook(let options):
            PickBookView(options: options)
        case .read(let book, let minutes):
            ReadingTimerView(book: book, minutes: minutes)
        case .reflect(let book, let finished):
            ReflectView(book: book, finished: finished)
        case .passage(let passage):
            PassageView(passage: passage)
        case .speak(let task):
            SpeakView(task: task, feedback: run.feedback)
        case .compose(let task):
            ComposeView(task: task)
        case .compare(let pair):
            CompareView(pair: pair)
        }
    }
}

/// The end: what the session did, plainly.
private struct SessionSummary: View {
    @Environment(AppModel.self) private var model
    let run: StudyRun

    var body: some View {
        let attempts = run.session.attempts.filter { $0.kind != .test }
        let right = attempts.filter(\.correct).count
        let learned = run.changedCards.compactMap { run.cards[$0] }.filter { card in
            card.memory?.reps == 1 && card.introduced >= run.session.start.addingTimeInterval(-60)
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 48)).foregroundStyle(.tint)
                Text(run.plan.kind == .checkIn ? "Check-in done" : "Session done").font(.largeTitle.bold())
                VStack(alignment: .leading, spacing: 10) {
                    Label(Format.minutes(run.session.minutes), systemImage: "clock")
                    if !attempts.isEmpty {
                        Label("\(attempts.count) answered, \(Format.percent(Double(right) / Double(attempts.count))) right", systemImage: "checkmark.circle")
                    }
                    ForEach(Domain.languages) { language in
                        let words = learned.filter { $0.domain == language }.count
                        if words > 0 { Label("\(words) new in \(language.label)", systemImage: language.symbol) }
                    }
                    let topics = learned.filter { $0.domain == .maths }.count
                    if topics > 0 { Label("\(topics) maths topic\(topics == 1 ? "" : "s") mastered", systemImage: Domain.maths.symbol) }
                    let skills = learned.filter { $0.domain == .writing }.count
                    if skills > 0 { Label("\(skills) writing skill\(skills == 1 ? "" : "s") mastered", systemImage: Domain.writing.symbol) }
                    if let reading = run.session.reading, reading.pages > 0 {
                        Label("\(reading.pages) pages read", systemImage: Domain.reading.symbol)
                    }
                    if !run.newPieces.isEmpty {
                        let words = run.newPieces.map(\.words).reduce(0, +)
                        Label("\(words) words written", systemImage: Domain.writing.symbol)
                    }
                    ForEach(run.newTests.filter { !$0.placement || $0.test == .vocabulary }, id: \.id) { test in
                        Label(TestLine.text(test), systemImage: "gauge.with.dots.needle.50percent")
                    }
                }
                .font(.body)
                Text("Reviews come back on their own schedule; there's nothing to keep up with between sessions.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button {
                    model.endSession()
                } label: {
                    Text("Done").font(.headline).frame(maxWidth: .infinity)
                }
                .primaryAction()
                .controlSize(.large)
                .padding(.top, 8)
            }
            .padding(24)
            .readableWidth(560)
        }
        .sensoryFeedback(.success, trigger: true)
    }
}

/// One line for a test result.
enum TestLine {
    static func text(_ test: TestResult) -> String {
        let language = test.domain.label
        let rating = ["lost", "caught bits", "followed most", "followed nearly all"][min(3, max(0, Int((test.score * 3).rounded())))]
        switch test.test {
        case .vocabulary:
            let low = Int(test.detail["low"] ?? test.score), high = Int(test.detail["high"] ?? test.score)
            return "About \(Int(test.score).formatted()) \(language) words known (\(low.formatted())–\(high.formatted()))"
        case .listening, .speaking, .languageReading, .languageWriting:
            let level = LanguageSkills.level(test)
            return "\(language) \(test.test.label.lowercased()): level \(level?.level ?? 0), about \((level?.words ?? 0).formatted()) words' reach"
        case .episode: return "\(language) episode without subtitles: \(rating)"
        case .conversation: return "\(language) conversation: \(rating)"
        case .numeracy: return "Numeracy: \(Format.percent(test.score)) right, \(Format.seconds(test.detail["seconds"] ?? 0)) a problem"
        case .mathsPlacement: return "Maths: placed at level \(Int(test.detail["level"] ?? 0)) of 10"
        case .maths: return "Maths check: \(Format.percent(test.score)) right, \(Format.seconds(test.detail["seconds"] ?? 0)) a problem"
        case .discrete: return "Discrete and statistics: \(Format.percent(test.score)) right"
        case .writing: return "Writing\(test.placement ? " placement" : " check"): \(Format.percent(test.score)) right"
        case .writingBenchmark: return "Benchmark piece written"
        case .blindComparison: return test.score >= 0.5 ? "Blind comparison: the newer piece was picked" : "Blind comparison: the older piece was picked"
        case .readingTest: return "Reading test: tier \(Int(test.detail["tier"] ?? test.score))"
        }
    }
}
