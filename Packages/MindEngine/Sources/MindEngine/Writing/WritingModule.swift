import Foundation
import SystemCore

/// Writing. For now the objective grammar bank, mastered skill by skill; the v2 rework adds the
/// real thing: writing kinds, the Franklin method, prompts and practical rewrites, AI notes (never
/// a grade), deterministic metrics as trends, and a blind comparison each term.
enum WritingModule: SubjectModule {
    static func needsPlacement(_ domain: Domain, state: StudyState, catalogs: Catalogs) -> Bool {
        !state.tests.contains { $0.test == .writing }
    }

    static func placementParts(_ domain: Domain, state: StudyState, catalogs: Catalogs) -> [PlanPart] {
        [PlanPart(kind: .placement, domain: .writing, minutes: 5, title: "Writing level", detail: "One item for each skill")]
    }

    static func mainParts(_ domain: Domain, minutes: Int, kind: StudyKind, state: StudyState, catalogs: Catalogs,
                          notes: inout [String]) -> [PlanPart] {
        if kind == .review {
            return [PlanPart(kind: .practice, domain: .writing, minutes: minutes, title: "Writing practice", detail: "Mixed items from what you've learned")]
        }
        let next = WritingPlan.next(state.cards, bank: catalogs.writing)
        return [PlanPart(kind: .learn, domain: .writing, minutes: minutes, title: "Writing", detail: next.map { "Next: \($0.title)" } ?? "Mixed practice")]
    }

    static func checkInParts(_ domain: Domain, state: StudyState, catalogs: Catalogs) -> [PlanPart] {
        [PlanPart(kind: .test(.writing), domain: .writing, minutes: 4, title: "Writing", detail: "Ten items across every skill")]
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
        state.tests.filter { $0.test == .writing }.map { ($0.day, $0.score * 100) }
    }

    static func label(_ domain: Domain, state: StudyState) -> String {
        "Writing \(Int(((state.latest(.writing)?.score ?? 0) * 100).rounded()))%"
    }
}
