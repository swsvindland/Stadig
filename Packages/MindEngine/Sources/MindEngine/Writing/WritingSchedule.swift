import Foundation
import SystemCore

/// What a writing session holds, worked out from the record so the plan and the session always
/// agree. In order: a Franklin rewrite when notes are waiting, the first benchmark (during the
/// assessment), a grammar skill one session in three while any are left, and otherwise the next
/// exercise in the rotation for the kinds of writing chosen.
public enum WritingSchedule {
    /// Notes are rewritten in a later session, at least this many days on, as Franklin did.
    public static let franklinGap = 2
    /// A benchmark comes back about once a term: every other check-in.
    public static let benchmarkGap = 77
    /// An older and a newer piece in a blind pair are at least five weeks apart, which the first
    /// check-in (about seven weeks in) can just reach.
    public static let pairGap = 35
    public static let pairsPerCheckIn = 2
    /// Shorter pieces say too little to compare or measure.
    public static let minimumWords = 40
    static let grammarEvery = 3

    /// The exercises each kind rotates through. The Franklin method comes round once in each
    /// kind's four, with passages that model that kind; with its rewrite it takes two sessions.
    static func cycle(_ kind: WritingKind) -> [WritingExercise] {
        switch kind {
        case .creative: [.prompt, .franklinNotes, .prompt, .sceneRewrite]
        case .practical: [.practical, .franklinNotes, .practical, .practical]
        case .argument: [.argument, .franklinNotes, .argument, .argument]
        }
    }

    static func kinds(_ settings: MindSettings) -> [WritingKind] {
        settings.writingKinds.isEmpty ? [.creative] : settings.writingKinds
    }

    // MARK: The Franklin method

    /// Notes taken and not yet rewritten, the oldest first.
    public static func waitingNotes(_ pieces: [WritingPiece]) -> WritingPiece? {
        pieces.filter { $0.exercise == .franklinNotes }.sorted { $0.date < $1.date }.first { notes in
            !pieces.contains { $0.exercise == .franklinRewrite && $0.taskID == notes.taskID && $0.date > notes.date }
        }
    }

    /// Notes ready to be rewritten today.
    public static func franklinDue(_ pieces: [WritingPiece], today: Day) -> WritingPiece? {
        waitingNotes(pieces).flatMap { $0.day.days(until: today) >= franklinGap ? $0 : nil }
    }

    /// The passage notes were taken on: the person's own page, or the library's.
    public static func original(of notes: WritingPiece, library: WritingLibrary) -> (text: String, credit: String?)? {
        if let own = notes.original { return (own, nil) }
        return notes.taskID.flatMap(library.passage).map { ($0.text, $0.credit) }
    }

    static func rewriteTask(_ notes: WritingPiece, minutes: Int, library: WritingLibrary) -> WritingTask? {
        guard let original = original(of: notes, library: library) else { return nil }
        return WritingTask(id: "franklin-rewrite.\(notes.id)", exercise: .franklinRewrite, writingKind: notes.writingKind,
                           instruction: "Rewrite the passage from your notes, in full sentences, as well as you can. Don't look it up: finding the words is the exercise. Then you'll see the original beside it.",
                           source: original.text, sourceCredit: original.credit, notes: notes.notes, minutes: minutes, taskID: notes.taskID)
    }

    // MARK: What comes next

    /// The writing task for a session's composition part: a waiting Franklin rewrite, or the next
    /// exercise in the rotation.
    public static func task(_ state: StudyState, minutes: Int, library: WritingLibrary) -> WritingTask? {
        if let notes = franklinDue(state.pieces, today: state.today), let task = rewriteTask(notes, minutes: minutes, library: library) {
            return task
        }
        return nextExercise(state, minutes: minutes, library: library)
    }

    /// The next exercise for the kinds chosen. Kinds take turns; each kind runs through its cycle.
    /// A step with nothing to offer (no passages for it, notes already waiting) passes to the next.
    public static func nextExercise(_ state: StudyState, minutes: Int, library: WritingLibrary) -> WritingTask? {
        let kinds = kinds(state.settings)
        let rotating: Set<WritingExercise> = [.prompt, .sceneRewrite, .practical, .argument, .franklinNotes]
        let done = state.pieces.filter { rotating.contains($0.exercise) }.count
        let waiting = waitingNotes(state.pieces) != nil
        for step in 0..<(kinds.count * 4) {
            let n = done + step
            let kind = kinds[n % kinds.count]
            let cycle = cycle(kind)
            let exercise = cycle[(n / kinds.count) % cycle.count]
            if exercise == .franklinNotes && waiting { continue }
            if let task = task(exercise, kind: kind, state: state, minutes: minutes, library: library) { return task }
        }
        return nil
    }

    /// When each prompt, task or passage was last used.
    static func lastUsed(_ pieces: [WritingPiece]) -> [String: Date] {
        var out: [String: Date] = [:]
        for piece in pieces {
            guard let id = piece.taskID else { continue }
            out[id] = max(out[id] ?? .distantPast, piece.date)
        }
        return out
    }

    /// Never used first, in a fixed shuffled order; once everything's been used, the least recent.
    static func fresh<T>(_ pool: [T], id: (T) -> String, used: [String: Date], seed: String) -> T? {
        var rng = SeededRandom("writing-order", seed)
        let order = pool.shuffled(using: &rng)
        return order.first { used[id($0)] == nil } ?? order.min { used[id($0)]! < used[id($1)]! }
    }

    static func length(_ minutes: Int, _ exercise: WritingExercise) -> String {
        if exercise == .argument { return minutes >= 12 ? "Make your case in about three paragraphs." : "Make your case in one solid paragraph." }
        return minutes >= 12 ? "Write about three paragraphs." : minutes >= 8 ? "Write one or two paragraphs." : "Write one paragraph."
    }

    /// Passages near the tier being read, the current book's first.
    static func passages(_ kind: WritingKind, state: StudyState, library: WritingLibrary) -> [WritingPassage] {
        let target = state.currentBook?.tier ?? ReadingPlan.targetTier(state.books)
        let matching = library.passages.filter { $0.kinds.contains(kind) }
        let pool = matching.isEmpty ? library.passages : matching
        let near = pool.filter { abs($0.tier - target) <= 2 }
        return near.isEmpty ? pool : near
    }

    static func task(_ exercise: WritingExercise, kind: WritingKind, state: StudyState, minutes: Int, library: WritingLibrary) -> WritingTask? {
        let used = lastUsed(state.pieces)
        let id = "\(exercise.rawValue).\(state.today.iso)"
        switch exercise {
        case .prompt, .argument:
            guard let prompt = fresh(library.prompts(exercise, kind), id: \.id, used: used, seed: exercise.rawValue) else { return nil }
            return WritingTask(id: id, exercise: exercise, writingKind: kind, instruction: "\(prompt.text) \(length(minutes, exercise))",
                               minutes: minutes, taskID: prompt.id)
        case .practical:
            guard let prompt = fresh(library.prompts(.practical, kind), id: \.id, used: used, seed: "practical"), let source = prompt.source
            else { return nil }
            return WritingTask(id: id, exercise: .practical, writingKind: kind, instruction: prompt.text, source: source, minutes: minutes,
                               taskID: prompt.id)
        case .sceneRewrite:
            let scenes = passages(.creative, state: state, library: library).flatMap { passage in
                passage.twists.indices.map { (passage: passage, twist: $0) }
            }
            guard let scene = fresh(scenes, id: { "\($0.passage.id)#\($0.twist)" }, used: used, seed: "scene") else { return nil }
            return WritingTask(id: id, exercise: .sceneRewrite, writingKind: kind,
                               instruction: "\(scene.passage.twists[scene.twist]) \(length(minutes, .sceneRewrite))",
                               source: scene.passage.text, sourceCredit: scene.passage.credit, minutes: minutes,
                               taskID: "\(scene.passage.id)#\(scene.twist)")
        case .franklinNotes:
            let pool = passages(kind, state: state, library: library)
            let reading = state.currentBook?.ladderID
            let ownBook = pool.filter { $0.book != nil && $0.book == reading && used[$0.id] == nil }
            guard let passage = ownBook.first ?? fresh(pool, id: \.id, used: used, seed: "franklin.\(kind.rawValue)") else { return nil }
            return WritingTask(id: id, exercise: .franklinNotes, writingKind: kind,
                               instruction: "Read the passage twice. Then jot brief notes: a few words for the point of each sentence, not the sentence itself. Next time you'll rewrite it from these notes alone and compare.",
                               source: passage.text, sourceCredit: passage.credit, minutes: minutes, taskID: passage.id)
        case .benchmark:
            return benchmarkTask(state, library: library)
        case .franklinRewrite:
            return nil
        }
    }

    // MARK: Benchmarks

    /// The term's benchmark: the same prompt every time, for the first kind chosen.
    public static func benchmarkPrompt(_ settings: MindSettings, library: WritingLibrary) -> WritingPrompt? {
        kinds(settings).lazy.compactMap(library.benchmark).first
    }

    public static func benchmarkTask(_ state: StudyState, library: WritingLibrary) -> WritingTask? {
        guard let prompt = benchmarkPrompt(state.settings, library: library) else { return nil }
        let minutes = prompt.minutes ?? 12
        return WritingTask(id: "benchmark.\(state.today.iso)", exercise: .benchmark, writingKind: prompt.writingKind,
                           instruction: "\(prompt.text) You have \(minutes) minutes. The same prompt comes back each term, so later pieces can be set beside this one.",
                           minutes: minutes, taskID: prompt.id)
    }

    public static func lastBenchmark(_ pieces: [WritingPiece]) -> WritingPiece? { pieces.last { $0.exercise == .benchmark } }

    /// At a check-in: once a term, or now if there's never been one.
    public static func benchmarkDue(_ state: StudyState) -> Bool {
        guard let last = lastBenchmark(state.pieces) else { return true }
        return last.day.days(until: state.today) >= benchmarkGap
    }

    /// When the next benchmark comes: the first check-in a term after the last.
    public static func nextBenchmark(_ state: StudyState) -> Day? {
        lastBenchmark(state.pieces).map { $0.day.adding(days: benchmarkGap) }
    }

    // MARK: Blind comparisons

    /// Pieces that can go in a blind pair: the person's own prose, long enough to judge. Franklin
    /// rewrites are left out, since most of their quality is the original's.
    static func comparable(_ pieces: [WritingPiece]) -> [WritingPiece] {
        pieces.filter { $0.exercise.composes && $0.exercise != .franklinRewrite && $0.words >= minimumWords }.sorted { $0.date < $1.date }
    }

    /// Older and newer pieces to set side by side at a check-in: the newest benchmark against the
    /// one a term before it, then recent pieces against one of the same exercise and kind from at
    /// least five weeks earlier. No pair twice, and no piece judged as the newer one twice.
    public static func pairs(_ pieces: [WritingPiece], comparisons: [BlindComparison], today: Day,
                             limit: Int = pairsPerCheckIn) -> [BlindPair] {
        let eligible = comparable(pieces)
        let done = Set(comparisons.map { "\($0.older).\($0.newer)" })
        let judged = Set(comparisons.map(\.newer))
        var used: Set<UUID> = []
        var out: [BlindPair] = []

        func add(_ older: WritingPiece, _ newer: WritingPiece) {
            guard out.count < limit, !done.contains("\(older.id).\(newer.id)") else { return }
            used.formUnion([older.id, newer.id])
            out.append(pair(older, newer))
        }

        let benchmarks = eligible.filter { $0.exercise == .benchmark }
        if let newest = benchmarks.last, !judged.contains(newest.id),
           let previous = benchmarks.last(where: { $0.taskID == newest.taskID && $0.day.days(until: newest.day) >= pairGap }) {
            add(previous, newest)
        }
        let recent = eligible.filter { $0.exercise != .benchmark && $0.day.days(until: today) <= pairGap && !judged.contains($0.id) }
        for newer in recent.reversed() where out.count < limit && !used.contains(newer.id) {
            let older = eligible.last {
                $0.exercise == newer.exercise && $0.writingKind == newer.writingKind && $0.day.days(until: newer.day) >= pairGap
                    && !used.contains($0.id) && !done.contains("\($0.id).\(newer.id)")
            }
            if let older { add(older, newer) }
        }
        return out
    }

    /// The pair in a fixed random order, so neither position gives the newer piece away.
    public static func pair(_ older: WritingPiece, _ newer: WritingPiece) -> BlindPair {
        var rng = SeededRandom("blind", older.id.uuidString, newer.id.uuidString)
        let newerFirst = rng.chance(0.5)
        let prompt = older.taskID != nil && older.taskID == newer.taskID
            ? "Both were written for the same prompt. Which is the stronger piece of writing?"
            : "Two \(newer.exercise.plural), each with its task. Which is the stronger piece of writing?"
        return BlindPair(id: "\(older.id).\(newer.id)", first: newerFirst ? newer : older, second: newerFirst ? older : newer, prompt: prompt)
    }

    /// How many pairs a check-in will have: those there now, plus one for a benchmark about to be
    /// written when there's an earlier one to set it beside.
    static func plannedPairs(_ state: StudyState, benchmark: WritingPrompt?) -> Int {
        var count = pairs(state.pieces, comparisons: state.comparisons, today: state.today).count
        if let benchmark, comparable(state.pieces).contains(where: { $0.exercise == .benchmark && $0.taskID == benchmark.id }) {
            count += 1
        }
        return min(pairsPerCheckIn, count)
    }
}

extension BlindPair {
    public var newer: WritingPiece { first.date >= second.date ? first : second }
    public var older: WritingPiece { first.date >= second.date ? second : first }
}
