import MindEngine
import SwiftUI
import SystemCore

/// A focused session: one step at a time, the clock in the corner. Full screen on iPhone, iPad and
/// Vision Pro; a window of its own on the Mac.
struct SessionView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingEnd = false

    var body: some View {
        NavigationStack {
            Group {
                if let run = model.run {
                    if let step = run.step {
                        // A screen per step: answering keeps it (with what was typed, and its
                        // haptic), the next step replaces it.
                        StepView(step: step, run: run)
                            .id(model.stepScreen)
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                    } else {
                        SessionSummary(run: run)
                    }
                }
            }
            .animation(.snappy, value: model.stepScreen)
            .animation(.snappy, value: model.run?.feedback == nil)
            .background(.pageBackground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("End", systemImage: "xmark", action: end)
                        .keyboardShortcut(.cancelAction)
                        .help("End the session (Esc)")
                        .accessibilityIdentifier("session.end")
                }
                ToolbarItem(placement: .principal) { SessionHeader() }
                ToolbarItem(placement: .primaryAction) { Clock() }
            }
            .confirmationDialog("End the session?", isPresented: $confirmingEnd, titleVisibility: .visible) {
                Button("End session", role: .destructive) { model.endSession() }
                    .accessibilityIdentifier("session.endConfirm")
                if let part = model.run?.currentPart, model.run.map({ $0.partIndex < $0.planParts.count - 1 }) ?? false {
                    Button("Skip \(part.title.lowercased())") { model.act { $0.skipPart(now: model.now()) } }
                        .accessibilityIdentifier("session.skipPart")
                }
                Button("Keep going", role: .cancel) {}
                    .accessibilityIdentifier("session.keepGoing")
            } message: {
                Text(endMessage)
            }
        }
        // Study ▸ End Session… in the menu bar asks the same way the End button does.
        .onChange(of: model.endRequested) { _, requested in
            guard requested else { return }
            model.endRequested = false
            end()
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

    /// Done: straight out. Otherwise, ask first.
    func end() {
        if model.run?.isComplete == true { model.endSession() } else { confirmingEnd = true }
    }

    var endMessage: String {
        var kept = "Everything answered so far is kept, and anything half-learned comes back tomorrow."
        if case .compose(let task)? = model.run?.step, task.reviewing == nil {
            kept += " The piece you're writing stays on this \(Platform.deviceName) and comes back with its task."
        }
        if Platform.isMac { kept += " Closing the window ends it the same way." }
        return kept
    }
}

extension AppModel {
    /// Advances the session clock without saving: the clock is saved with the next answer.
    func tick() {
        guard var current = run else { return }
        current.tick(now: now())
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
                    .accessibilityIdentifier("session.part")
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
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
    /// Set on appearing, so the success haptic plays once the summary is up.
    @State private var shown = false

    var keys: [SessionKeyBinding] { SessionKeys.bindings(step: nil, feedback: nil) }

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
                    .accessibilityIdentifier("summary.title")
                VStack(alignment: .leading, spacing: 10) {
                    Label(Format.minutes(run.session.minutes), systemImage: "clock")
                    if !attempts.isEmpty {
                        Label(
                            "\(attempts.count) answered, \(Format.percent(Double(right) / Double(attempts.count))) right",
                            systemImage: "checkmark.circle")
                    }
                    ForEach(Domain.languages) { language in
                        let words = learned.filter { $0.domain == language }.count
                        if words > 0 { Label("\(words) new in \(language.label)", systemImage: language.symbol) }
                    }
                    // Topics a placement or quick check found known weren't mastered here.
                    let topics = learned.filter { $0.domain == .maths && !$0.knownBefore }.count
                    if topics > 0 { Label("\(topics) maths topic\(topics == 1 ? "" : "s") mastered", systemImage: Domain.maths.symbol) }
                    let skills = learned.filter { $0.domain == .writing }.count
                    if skills > 0 { Label("\(skills) writing skill\(skills == 1 ? "" : "s") mastered", systemImage: Domain.writing.symbol) }
                    if let reading = run.session.reading, reading.pages > 0 {
                        Label("\(reading.pages) pages read", systemImage: Domain.reading.symbol)
                    }
                    if run.newPieces.contains(where: { !$0.text.isEmpty }) {
                        let words = run.newPieces.map(\.words).reduce(0, +)
                        Label("\(words) words written", systemImage: Domain.writing.symbol)
                    }
                    if run.newPieces.contains(where: { $0.exercise == .franklinNotes }) {
                        Label("Notes kept for a Franklin rewrite next time", systemImage: "text.book.closed")
                    }
                    ForEach(
                        run.newTests.filter { !$0.placement || $0.test == .vocabulary || $0.domain == .maths || $0.test == .readingTest }, id: \.id
                    ) { test in
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
                .accessibilityIdentifier("summary.done")
                .padding(.top, 8)
                KeyLegend(bindings: keys, titles: [.submit: "Done"])
            }
            .padding(24)
            .readableWidth(560)
        }
        .onAppear { shown = true }
        .sensoryFeedback(.success, trigger: shown)
        .sessionKeys(keys) { key in if key == .submit { model.endSession() } }
    }
}

/// One line for a test result.
enum TestLine {
    static func text(_ test: TestResult) -> String {
        let language = test.domain.label
        let rating = ["lost", "caught bits", "followed most", "followed nearly all"][min(3, max(0, Int((test.score * 3).rounded())))]
        switch test.test {
        case .vocabulary:
            let low = Int(test.detail["low"] ?? test.score)
            let high = Int(test.detail["high"] ?? test.score)
            return "About \(Int(test.score).formatted()) \(language) words known (\(low.formatted())–\(high.formatted()))"
        case .listening, .speaking, .languageReading, .languageWriting:
            let level = LanguageSkills.level(test)
            return "\(language) \(test.test.label.lowercased()): level \(level?.level ?? 0), about \((level?.words ?? 0).formatted()) words' reach"
        case .episode: return "\(language) episode without subtitles: \(rating)"
        case .conversation: return "\(language) conversation: \(rating)"
        case .numeracy:
            let level = test.detail["level"].map { "level \(Int($0)) of 10 · " } ?? ""
            return "Numeracy: \(level)\(Format.percent(test.score)) right\(pace(test))"
        case .mathsPlacement: return "\(MathsStrand.classic.label): \(placed(test))"
        case .maths, .discrete:
            let strand = MathsStrand(test: test.test)?.label ?? test.test.label
            if test.placement { return "\(strand): \(placed(test))" }
            let reach = test.detail["reach"].map { "level \(Int($0)) reached · " } ?? ""
            return "\(strand): \(reach)\(Format.percent(test.score)) right\(pace(test))"
        case .writing: return "Grammar\(test.placement ? " placement" : " check"): \(Format.percent(test.score)) right"
        case .writingBenchmark: return "Benchmark piece written"
        case .blindComparison:
            return test.score >= 0.5 ? "Blind comparison: the newer piece was picked" : "Blind comparison: the older piece was picked"
        case .readingTest:
            // A result saved without its details says less rather than "tier 0".
            let parts = [test.detail["tier"].map { "tier \(ReadingPlan.format($0))" }, test.detail["wpm"].map { "\(Int($0)) words a minute" }]
            let said = parts.compactMap { $0 }.joined(separator: ", ")
            return said.isEmpty ? "Reading test done" : "Reading test: \(said)"
        }
    }

    /// ", 6 s a problem", when the time was kept.
    private static func pace(_ test: TestResult) -> String { test.detail["seconds"].map { ", \(Format.seconds($0)) a problem" } ?? "" }

    private static func placed(_ test: TestResult) -> String { test.detail["level"].map { "placed at level \(Int($0)) of 10" } ?? "placed" }
}
