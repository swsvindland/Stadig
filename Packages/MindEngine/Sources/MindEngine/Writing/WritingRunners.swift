import Foundation
import SystemCore

/// One writing task: write it (typed or by hand), then see it back with notes on it. Franklin
/// notes are kept for the rewrite and have nothing to review; a benchmark also leaves its result.
/// The clock never cuts a piece short: it's done when the person says so.
struct ComposeRunner: PartRunner {
    enum Stage: Sendable { case write, review, done }

    var task: WritingTask
    var stage: Stage = .write
    var pieceID: UUID?

    init(task: WritingTask) { self.task = task }

    mutating func next(_ run: inout StudyRun) -> StudyRun.Step? {
        switch stage {
        case .write:
            return .compose(task)
        case .review:
            var shown = task
            shown.reviewing = pieceID
            return .compose(shown)
        case .done:
            return nil
        }
    }

    mutating func respond(_ response: StepResponse, _ run: inout StudyRun) -> Bool {
        switch (stage, response) {
        case (.write, .written(let text, let source)):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            let notesOnly = task.exercise == .franklinNotes
            let piece = WritingPiece(date: run.now, exercise: task.exercise, writingKind: task.writingKind, prompt: task.instruction,
                                     text: notesOnly ? "" : trimmed, source: source, notes: notesOnly ? trimmed : task.notes,
                                     metrics: notesOnly ? [:] : WritingCheck.measure(trimmed).dictionary, taskID: task.taskID,
                                     updatedAt: run.now)
            run.newPieces.append(piece)
            if task.exercise == .benchmark {
                run.newTests.append(TestResult(test: .writingBenchmark, date: run.now, score: Double(piece.words), detail: piece.metrics))
            }
            pieceID = piece.id
            stage = notesOnly ? .done : .review
            return true
        case (.write, .skip), (.review, _):
            stage = .done
            return true
        default:
            return false
        }
    }
}

/// Blind side-by-sides at a check-in: an older and a newer piece, unlabelled and in random order.
/// The pick is kept with the pair, and the AI's own blind pick is added later as a second opinion.
struct BlindComparisonRunner: PartRunner {
    let limit: Int
    /// Pairs judged before this session, so none comes round twice.
    let earlier: [BlindComparison]
    var shown = 0
    var current: BlindPair?

    mutating func next(_ run: inout StudyRun) -> StudyRun.Step? {
        guard shown < limit else { return nil }
        // Pieces from this session count too: the benchmark just written meets last term's.
        var pieces: [UUID: WritingPiece] = Dictionary(run.pieces.map { ($0.id, $0) }, uniquingKeysWith: { $0.updatedAt >= $1.updatedAt ? $0 : $1 })
        for piece in run.newPieces { pieces[piece.id] = piece }
        guard let pair = WritingSchedule.pairs(Array(pieces.values), comparisons: earlier + run.newComparisons, today: run.today,
                                               limit: 1).first else { return nil }
        current = pair
        return .compare(pair)
    }

    mutating func respond(_ response: StepResponse, _ run: inout StudyRun) -> Bool {
        guard let pair = current else { return false }
        switch response {
        case .picked(let index):
            let picked = index == 0 ? pair.first : pair.second
            let newer = picked.id == pair.newer.id
            run.newComparisons.append(BlindComparison(date: run.now, older: pair.older.id, newer: pair.newer.id, pickedNewer: newer,
                                                      updatedAt: run.now))
            run.newTests.append(TestResult(test: .blindComparison, date: run.now, score: newer ? 1 : 0,
                                           detail: ["days": Double(pair.older.day.days(until: pair.newer.day))]))
            shown += 1
            current = nil
            return true
        case .skip:
            // Leaving it unjudged: nothing is recorded, and the pair can come back next time.
            shown = limit
            current = nil
            return true
        default:
            return false
        }
    }
}

// The app's hooks into a running session's writing: what the platform's spell checker found,
// notes from the AI arriving while the session is still on, and a page of the person's own book.
extension StudyRun {
    /// A piece written this session, as it stands.
    public func piece(_ id: UUID) -> WritingPiece? { newPieces.last { $0.id == id } }

    /// Hands in what was written, with the words the platform's spell checker flagged, so the
    /// piece's slip count includes them. `original` is a page of the person's own book that
    /// Franklin notes were taken on, in place of the library's passage.
    public mutating func submitWriting(_ text: String, source: WritingSource, misspelled: [String], original: String? = nil, now: Date) {
        let before = newPieces.count
        respond(.written(text: text, source: source), now: now)
        guard newPieces.count > before else { return }
        var piece = newPieces[newPieces.count - 1]
        if !piece.text.isEmpty {
            piece.metrics = WritingCheck.measure(piece.text, misspelled: misspelled).dictionary
        }
        if let original {
            piece.original = original
            piece.taskID = "own.\(piece.id)"
        }
        newPieces[newPieces.count - 1] = piece
        if piece.exercise == .benchmark, let index = newTests.lastIndex(where: { $0.test == .writingBenchmark && $0.date == piece.date }) {
            newTests[index].detail = piece.metrics
        }
    }

    /// Notes on a piece from this session, arriving while it's still running.
    public mutating func attachFeedback(_ feedback: String, to id: UUID) {
        guard let index = newPieces.lastIndex(where: { $0.id == id }) else { return }
        newPieces[index].feedback = feedback
        newPieces[index].updatedAt = lastNow
    }

    /// The AI's blind pick on a comparison from this session.
    public mutating func attachSecondOpinion(_ pickedNewer: Bool, older: UUID, newer: UUID) {
        guard let index = newComparisons.lastIndex(where: { $0.older == older && $0.newer == newer }) else { return }
        newComparisons[index].aiPickedNewer = pickedNewer
        newComparisons[index].updatedAt = lastNow
    }
}
