import Foundation
import SystemCore

/// Maths. For now one ladder placed adaptively and learned topic by topic; the v2 rework splits it
/// into three strands (numeracy, the classic ladder, discrete and statistics), each with its own
/// level, and opens every session with a numeracy block.
enum MathsModule: SubjectModule {
    static func needsPlacement(_ domain: Domain, state: StudyState, catalogs: Catalogs) -> Bool {
        !state.tests.contains { $0.test == .mathsPlacement }
    }

    static func placementParts(_ domain: Domain, state: StudyState, catalogs: Catalogs) -> [PlanPart] {
        [PlanPart(kind: .placement, domain: .maths, minutes: 10, title: "Maths level", detail: "About a dozen problems, stepping up and down")]
    }

    static func mainParts(_ domain: Domain, minutes: Int, kind: StudyKind, state: StudyState, catalogs: Catalogs,
                          notes: inout [String]) -> [PlanPart] {
        if kind == .review {
            return [PlanPart(kind: .practice, domain: .maths, minutes: minutes, title: "Maths practice", detail: "Mixed problems from what you've learned")]
        }
        let detail: String
        if let next = MathsPlan.next(state.cards) {
            detail = state.cards[next.key]?.learning == true ? "Carrying on: \(next.title)" : "Next: \(next.title)"
        } else {
            detail = "Everything in the graph is learned: mixed practice"
        }
        return [PlanPart(kind: .learn, domain: .maths, minutes: minutes, title: "Maths", detail: detail)]
    }

    static func checkInParts(_ domain: Domain, state: StudyState, catalogs: Catalogs) -> [PlanPart] {
        guard MathsPlan.known(state.cards).count >= 3 else { return [] }
        return [PlanPart(kind: .test(.maths), domain: .maths, minutes: 7, title: "Maths", detail: "Eight problems across what you've learned")]
    }

    static func runner(for part: PlanPart, state: StudyState, catalogs: Catalogs) -> (any PartRunner)? {
        switch part.kind {
        case .placement: return MathsPlacementRunner(placement: MathsPlacement(background: state.settings.mathsBackground))
        case .learn: return TopicsRunner(domain: .maths)
        case .test(.maths):
            return QuestionListRunner(queue: check(state)) { attempts, run in
                let tested = attempts.filter { $0.test == .maths }
                guard tested.count >= 4 else { return }
                let levels = tested.filter(\.correct).compactMap { MathCurriculum.topic($0.key.item)?.level }
                let mean = Double(tested.compactMap { MathCurriculum.topic($0.key.item)?.level }.reduce(0, +)) / Double(tested.count)
                run.newTests.append(accuracyResult(.maths, tested, placement: false, at: run.now,
                                                   extra: ["reach": Double(levels.max() ?? 0), "level": mean]))
            }
        default: return nil
        }
    }

    /// Eight problems: the five highest topics learned and three others.
    static func check(_ state: StudyState) -> [Question] {
        let known = MathsPlan.known(state.cards).compactMap(MathCurriculum.topic).sorted { $0.level > $1.level }
        var rng = SeededRandom("maths-check", state.today.iso)
        let picked = Array(known.prefix(5)) + Array(known.dropFirst(5).shuffled(using: &rng).prefix(3))
        return picked.enumerated().map { index, topic in
            topic.problem(seed: "check.\(state.today.iso).\(index)").question(kind: .test, id: "check.\(topic.id).\(state.today.iso)").asTest(.maths)
        }
    }

    static func question(for key: CardKey, kind: AttemptKind, run: StudyRun) -> Question? {
        MathCurriculum.topic(key.item)?.problem(seed: run.seed).question(kind: kind, id: "\(key.raw).\(run.seed)")
    }

    static func usable(_ key: CardKey, catalogs: Catalogs) -> Bool { MathCurriculum.topic(key.item) != nil }

    static func reviewSeconds(_ card: MemoryCard) -> Double { 55 }

    static func series(_ domain: Domain, state: StudyState) -> [(day: Day, score: Double)] {
        state.tests.compactMap { test in
            switch test.test {
            case .mathsPlacement: return (test.day, min(100, 10 * (test.detail["level"] ?? 0)))
            case .maths: return (test.day, min(100, 10 * (test.detail["reach"] ?? 0) * (0.5 + 0.5 * test.score)))
            default: return nil
            }
        }
    }

    static func label(_ domain: Domain, state: StudyState) -> String {
        let level = Int(state.tests.last { $0.test == .maths }?.detail["reach"] ?? state.latest(.mathsPlacement)?.detail["level"] ?? 0)
        return "Maths level \(level)"
    }
}

/// The adaptive placement: about a dozen problems stepping up and down the ladder.
struct MathsPlacementRunner: PartRunner {
    var placement: MathsPlacement
    var current: String?

    mutating func next(_ run: inout StudyRun) -> StudyRun.Step? {
        guard !placement.done, let topic = placement.nextTopic() else { return nil }
        var question = topic.problem(seed: "placement.\(placement.asked)").question(kind: .test, id: "placement.\(topic.id)")
        question.test = .mathsPlacement
        question.allowsDontKnow = true
        current = topic.id
        return .question(question)
    }

    mutating func record(_ question: Question, correct: Bool, _ run: inout StudyRun) {
        if let current { placement.record(topic: current, correct: correct) }
        current = nil
    }

    mutating func finish(_ run: inout StudyRun) {
        guard placement.asked >= 6 || placement.done else { return }
        for card in placement.cards(at: run.now) where run.cards[card.key]?.memory == nil { run.save(card) }
        run.newTests.append(placement.result(at: run.now))
    }
}
