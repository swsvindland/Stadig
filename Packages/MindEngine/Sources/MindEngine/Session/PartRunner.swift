import Foundation
import SystemCore

/// What the person did on a step other than answering a question.
public enum StepResponse: Hashable, Sendable {
    /// Finished a reading-test passage after this many seconds.
    case passageRead(seconds: Double)
    /// What on-device speech recognition heard (empty when it heard nothing).
    case spoken(transcript: String, seconds: Double)
    /// Text written: typed, or recognised from handwriting.
    case written(text: String, source: WritingSource)
    /// Which of a blind pair was picked: 0 for the first, 1 for the second.
    case picked(Int)
    /// A book chosen to read now.
    case bookPicked(Book)
    /// The reading block ended: where the bookmark is, how the book felt if it's finished, and how
    /// focus held.
    case readingDone(page: Int, finished: Bool, feel: BookFeel?, minutes: Double, focus: ReadingFocus? = nil)
    /// A few sentences after reading, or nil to skip.
    case reflection(String?)
    /// Leave this step.
    case skip
}

/// One part of a session: it hands out steps until it's done. Each subject's parts live in that
/// subject's folder; the run calls them in order and carries time over between them.
public protocol PartRunner: Sendable {
    /// The next step, or nil when the part is done.
    mutating func next(_ run: inout StudyRun) -> StudyRun.Step?
    /// An answer to a question this part asked (the run has already logged it and scheduled
    /// any review).
    mutating func record(_ question: Question, correct: Bool, _ run: inout StudyRun)
    /// Anything else the person did on one of this part's steps. True when it was handled.
    mutating func respond(_ response: StepResponse, _ run: inout StudyRun) -> Bool
    /// The part is over: keep what it measured.
    mutating func finish(_ run: inout StudyRun)
}

extension PartRunner {
    public mutating func record(_ question: Question, correct: Bool, _ run: inout StudyRun) {}
    public mutating func respond(_ response: StepResponse, _ run: inout StudyRun) -> Bool { false }
    public mutating func finish(_ run: inout StudyRun) {}
}

/// A part with nothing to do (its catalog isn't installed, say).
struct EmptyRunner: PartRunner {
    mutating func next(_ run: inout StudyRun) -> StudyRun.Step? { nil }
}

/// Spaced reviews: the warm-up across every course, a review week's practice ahead of schedule,
/// and extra practice when the plan runs out before the clock. A miss comes round again a few
/// questions later, at most twice: it's relearned today, and the schedule brings it back tomorrow.
struct ReviewsRunner: PartRunner {
    struct Again: Sendable {
        var key: CardKey
        var after: Int
    }

    var queue: [CardKey]
    var again: [Again] = []
    var misses: [CardKey: Int] = [:]

    mutating func next(_ run: inout StudyRun) -> StudyRun.Step? {
        // A missed card comes back once a few others have gone by, or straight away at the end.
        let waiting = run.partSeconds >= run.budget || queue.isEmpty ? again.indices.first : nil
        if let ready = again.firstIndex(where: { $0.after <= 0 }) ?? waiting {
            let item = again.remove(at: ready)
            if let question = run.question(for: item.key, kind: .learn) { return .question(question) }
        }
        guard run.partSeconds < run.budget else { return nil }
        while !queue.isEmpty {
            let key = queue.removeFirst()
            if let question = run.question(for: key, kind: .review) { return .question(question) }
        }
        return nil
    }

    mutating func record(_ question: Question, correct: Bool, _ run: inout StudyRun) {
        for i in again.indices { again[i].after -= 1 }
        guard !correct else { return }
        misses[question.key, default: 0] += 1
        again.removeAll { $0.key == question.key }
        if misses[question.key, default: 0] <= 2 { again.append(Again(key: question.key, after: 3)) }
    }
}

/// A fixed list of test questions, scored at the end by `score`.
struct QuestionListRunner: PartRunner {
    var queue: [Question]
    /// Keeps what the list measured, from its attempts.
    let score: @Sendable (_ attempts: [Attempt], _ run: inout StudyRun) -> Void

    mutating func next(_ run: inout StudyRun) -> StudyRun.Step? {
        guard !queue.isEmpty, run.partSeconds < run.budget * 2.5 else { return nil }
        return .question(queue.removeFirst())
    }

    mutating func finish(_ run: inout StudyRun) {
        score(run.partAttempts, &run)
    }
}

extension Question {
    /// The same question as part of a test: measured, with "Don't know".
    func asTest(_ kind: TestKind) -> Question {
        var question = self
        question.test = kind
        question.allowsDontKnow = true
        return question
    }
}

/// Accuracy and time over a test's attempts, as a result.
func accuracyResult(
    _ kind: TestKind, _ attempts: [Attempt], placement: Bool, language: Language? = nil, at date: Date,
    extra: [String: Double] = [:]
) -> TestResult {
    let right = attempts.filter(\.correct).count
    var detail = extra
    detail["seconds"] = attempts.map(\.seconds).reduce(0, +) / Double(max(1, attempts.count))
    detail["asked"] = Double(attempts.count)
    return TestResult(
        test: kind, date: date, score: Double(right) / Double(max(1, attempts.count)), detail: detail,
        placement: placement, language: language)
}
