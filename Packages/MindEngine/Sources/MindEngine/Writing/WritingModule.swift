import Foundation
import SystemCore

/// Writing. Real pieces for the kinds of writing chosen (the Franklin method, short prompts, scene
/// rewrites, practical rewrites and arguments), typed or handwritten, with a few notes on each from
/// the AI and never a grade. The grammar bank stays as support: placement, one session in three
/// while skills are left, and reviews. What's measured is deterministic and shown as trends; the
/// score moves only on the grammar check and blind comparisons, and a benchmark comes back each term.
enum WritingModule: SubjectModule {
    /// The plan part for a piece of writing; the runner works out which from the record.
    static let compose = "writing"

    static func needsPlacement(_ domain: Domain, state: StudyState, catalogs: Catalogs) -> Bool {
        !state.tests.contains { $0.test == .writing }
    }

    static func placementParts(_ domain: Domain, state: StudyState, catalogs: Catalogs) -> [PlanPart] {
        [PlanPart(kind: .placement, domain: .writing, minutes: 5, title: "Writing level", detail: "One item for each skill")]
    }

    static func mainParts(
        _ domain: Domain, minutes: Int, kind: StudyKind, state: StudyState, catalogs: Catalogs,
        notes: inout [String]
    ) -> [PlanPart] {
        if kind == .review {
            return [
                PlanPart(
                    kind: .practice, domain: .writing, minutes: minutes, title: "Writing practice", detail: "Mixed items from what you've learned")
            ]
        }
        let bank = catalogs.writing
        let franklinDue = WritingSchedule.franklinDue(state.pieces, today: state.today, library: bank.library)
        if WritingSchedule.lastBenchmark(state.pieces) == nil, franklinDue == nil,
            let task = WritingSchedule.benchmarkTask(state, library: bank.library)
        {
            notes.append("Writing starts with a benchmark piece: the same prompt comes back each term, so you can see how your writing changes.")
            return [benchmarkPart(task)]
        }
        let grammar = franklinDue == nil ? WritingPlan.next(state.cards, bank: bank) : nil
        if let skill = grammar, minutes >= 16 {
            return [
                PlanPart(kind: .learn, domain: .writing, minutes: 5, title: "Grammar", detail: "Next: \(skill.title)"),
                composePart(state, minutes: minutes - 5, bank: bank),
            ]
        }
        if let skill = grammar, WritingSchedule.grammarTurn(state) {
            return [PlanPart(kind: .learn, domain: .writing, minutes: minutes, title: "Grammar", detail: "Next: \(skill.title)")]
        }
        return [composePart(state, minutes: minutes, bank: bank)]
    }

    static func composePart(_ state: StudyState, minutes: Int, bank: WritingBank) -> PlanPart {
        let minutes = max(5, minutes)
        let task = WritingSchedule.task(state, minutes: minutes, library: bank.library)
        return PlanPart(
            kind: .custom(compose), domain: .writing, minutes: minutes, title: "Writing",
            detail: task.map(WritingSchedule.detail) ?? "Grammar practice")
    }

    static func benchmarkPart(_ task: WritingTask) -> PlanPart {
        PlanPart(
            kind: .test(.writingBenchmark), domain: .writing, minutes: task.minutes, title: "Benchmark piece",
            detail: "\(task.minutes) minutes on the term's prompt")
    }

    static func checkInParts(_ domain: Domain, state: StudyState, catalogs: Catalogs) -> [PlanPart] {
        var parts = [PlanPart(kind: .test(.writing), domain: .writing, minutes: 4, title: "Grammar check", detail: "Ten items across every skill")]
        guard state.settings.mode(.writing) == .focus else { return parts }
        let library = catalogs.writing.library
        var benchmark: WritingPrompt?
        if WritingSchedule.benchmarkDue(state), let task = WritingSchedule.benchmarkTask(state, library: library) {
            parts.append(benchmarkPart(task))
            benchmark = task.taskID.flatMap(library.prompt)
        }
        let pairs = WritingSchedule.plannedPairs(state, benchmark: benchmark)
        if pairs > 0 {
            parts.append(
                PlanPart(
                    kind: .test(.blindComparison), domain: .writing, minutes: 3 * pairs, title: "Blind comparison",
                    detail: pairs == 1
                        ? "An older and a newer piece, unlabelled: which is stronger?"
                        : "\(pairs) pairs of older and newer pieces, unlabelled"))
        }
        return parts
    }

    static func runner(for part: PlanPart, state: StudyState, catalogs: Catalogs) -> (any PartRunner)? {
        let bank = catalogs.writing
        switch part.kind {
        case .placement:
            let questions = bank.skills.compactMap { skill in
                bank.item(for: skill.id, seen: 0, seed: "placement").map { bank.question($0, kind: .test, seed: "placement").asTest(.writing) }
            }
            return QuestionListRunner(queue: questions) { attempts, run in
                let tested = attempts.filter { $0.test == .writing }
                guard tested.count >= 8 else { return }
                run.newTests.append(accuracyResult(.writing, tested, placement: true, at: run.now))
                for attempt in tested where attempt.correct && run.cards[attempt.key]?.memory == nil {
                    run.graduate(attempt.key, memory: Scheduler.known(stability: 7, at: run.now), knownBefore: true)
                }
            }
        case .learn:
            return TopicsRunner(domain: .writing)
        case .custom(compose):
            // Nothing to write (no content installed): grammar practice instead.
            guard let task = WritingSchedule.task(state, minutes: part.minutes, library: bank.library) else { return TopicsRunner(domain: .writing) }
            return ComposeRunner(task: task)
        case .test(.writingBenchmark):
            return WritingSchedule.benchmarkTask(state, library: bank.library).map(ComposeRunner.init)
        case .test(.blindComparison):
            return BlindComparisonRunner(limit: WritingSchedule.pairsPerCheckIn, earlier: state.comparisons)
        case .test(.writing):
            var rng = SeededRandom("writing-check", state.today.iso)
            let questions = bank.skills.shuffled(using: &rng).prefix(10).compactMap { skill in
                bank.item(for: skill.id, seen: state.today.ordinal, seed: "check")
                    .map { bank.question($0, kind: .test, seed: state.today.iso).asTest(.writing) }
            }
            return QuestionListRunner(queue: questions) { attempts, run in
                let tested = attempts.filter { $0.test == .writing }
                guard tested.count >= 4 else { return }
                run.newTests.append(accuracyResult(.writing, tested, placement: false, at: run.now))
            }
        default:
            return nil
        }
    }

    static func question(for key: CardKey, kind: AttemptKind, run: StudyRun) -> Question? {
        let bank = run.catalogs.writing
        let reps = run.cards[key]?.memory?.reps ?? 0
        return bank.item(for: key.item, seen: reps + run.asked, seed: run.today.iso).map { bank.question($0, kind: kind, seed: run.seed) }
    }

    static func usable(_ key: CardKey, catalogs: Catalogs) -> Bool { catalogs.writing.skill(key.item) != nil }

    static func reviewSeconds(_ card: MemoryCard) -> Double { 25 }

    static func series(_ domain: Domain, state: StudyState) -> [(day: Day, score: Double)] {
        WritingProgress.series(tests: state.tests, comparisons: state.comparisons)
    }

    static func label(_ domain: Domain, state: StudyState) -> String {
        "Writing \(Int((series(domain, state: state).last?.score ?? 0).rounded()))"
    }
}

extension WritingSchedule {
    /// One writing session in three goes to a grammar skill while any are left to learn.
    static func grammarTurn(_ state: StudyState) -> Bool {
        let sessions = state.sessions.filter { $0.finished && $0.purpose == .regular && $0.domains.contains(.writing) }.count
        return sessions % grammarEvery == grammarEvery - 1
    }

    /// A line for Today and the plan: what this piece of writing will be.
    public static func detail(_ task: WritingTask) -> String {
        switch task.exercise {
        case .franklinNotes: "Franklin method: read a passage and take notes\(task.sourceCredit.map { " (\($0))" } ?? "")"
        case .franklinRewrite: "Franklin method: rewrite the passage from your notes\(task.sourceCredit.map { " (\($0))" } ?? "")"
        case .sceneRewrite: "Scene rewrite\(task.sourceCredit.map { ": \($0)" } ?? "")"
        case .practical: "Practical rewrite: make a message clear"
        case .argument: "Argument: make a case"
        case .prompt: "A short piece from a prompt"
        case .benchmark: "Benchmark piece: the term's prompt"
        }
    }
}
