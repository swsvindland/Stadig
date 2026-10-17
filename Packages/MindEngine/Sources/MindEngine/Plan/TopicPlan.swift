import Foundation
import SystemCore

/// Mastery for maths topics and writing skills: a topic is learned at four of the last five right
/// (at least four tried, ending on a right one), and set aside for the day after three of the last
/// five wrong, so a struggle ends with the worked solution, not a spiral. A lucky streak doesn't
/// stick for long: two missed reviews in a row put a topic back into learning.
public enum Mastery {
    public static let window = 5
    public static let needed = 4
    public static let minimumAttempts = 4
    public static let maximumPerVisit = 9

    public static func mastered(_ recent: [Bool]) -> Bool {
        recent.count >= minimumAttempts && recent.last == true && recent.suffix(window).filter { $0 }.count >= needed
    }

    public static func struggling(_ recent: [Bool]) -> Bool {
        recent.count >= 3 && recent.suffix(window).filter { !$0 }.count >= 3
    }

    /// The first grade for a just-mastered topic: Good if it came cleanly, Hard if it took a while.
    public static func grade(_ recent: [Bool]) -> Grade { recent.filter { !$0 }.isEmpty ? .good : .hard }
}

public enum MathsPlan {
    /// Topics learned or shown known (they have a memory).
    public static func known(_ cards: [CardKey: MemoryCard]) -> Set<String> {
        Set(cards.values.filter { $0.domain == .maths && $0.memory != nil }.map(\.key.item))
    }

    /// Started and not yet mastered.
    public static func inProgress(_ cards: [CardKey: MemoryCard]) -> [MathTopic] {
        cards.values.filter { $0.domain == .maths && $0.learning }.sorted { $0.introduced < $1.introduced }
            .compactMap { MathCurriculum.topic($0.key.item) }
    }

    /// What can be learned next: not known, not started, everything beneath it known. Lowest level
    /// first, then curriculum order.
    public static func frontier(_ cards: [CardKey: MemoryCard]) -> [MathTopic] {
        let known = known(cards)
        let started = Set(cards.values.filter { $0.domain == .maths }.map(\.key.item))
        return MathCurriculum.topics.filter { topic in
            !started.contains(topic.id) && topic.prerequisites.allSatisfy(known.contains)
        }.sorted { $0.level < $1.level }
    }

    public static func next(_ cards: [CardKey: MemoryCard]) -> MathTopic? { inProgress(cards).first ?? frontier(cards).first }

    /// The level placement reached: topics at or below it start with a quick check, not a lesson.
    public static func placedLevel(_ cards: [CardKey: MemoryCard]) -> Int {
        cards.values.filter { $0.domain == .maths && $0.knownBefore }.compactMap { MathCurriculum.topic($0.key.item)?.level }.max() ?? 0
    }
}

/// Finds a maths level in about a dozen problems. It steps up two levels after a right answer
/// and down after a wrong one, then one level at a time once it has turned; a right answer marks
/// everything beneath that topic known, a wrong one everything built on it unknown.
public struct MathsPlacement: Hashable, Sendable {
    public static let maximumQuestions = 12

    public private(set) var level: Int
    public private(set) var step = 2
    public private(set) var results: [String: Bool] = [:]
    private var lastCorrect: Bool?

    public init(background: MathsBackground) { level = background.startLevel }

    public var asked: Int { results.count }

    public var known: Set<String> {
        var out: Set<String> = []
        for (id, correct) in results where correct { out.insert(id); out.formUnion(MathCurriculum.ancestors(of: id)) }
        return out
    }

    public var unknown: Set<String> {
        var out: Set<String> = []
        for (id, correct) in results where !correct { out.insert(id); out.formUnion(MathCurriculum.descendants(of: id)) }
        return out.subtracting(known)
    }

    public var done: Bool { asked >= Self.maximumQuestions || nextTopic() == nil }

    /// An undecided topic at the current level (or the nearest one), the one most others build on.
    public func nextTopic() -> MathTopic? {
        guard asked < Self.maximumQuestions else { return nil }
        let decided = known.union(unknown)
        for distance in 0...2 {
            for candidate in [level + distance, level - distance] where (1...MathCurriculum.maxLevel).contains(candidate) {
                let options = MathCurriculum.topics.filter { $0.level == candidate && !decided.contains($0.id) }
                if let best = options.max(by: { MathCurriculum.descendants(of: $0.id).count < MathCurriculum.descendants(of: $1.id).count }) {
                    return best
                }
            }
        }
        return nil
    }

    public mutating func record(topic: String, correct: Bool) {
        results[topic] = correct
        if let lastCorrect, lastCorrect != correct { step = 1 }
        lastCorrect = correct
        level = clamp(level + (correct ? step : -step), 1, MathCurriculum.maxLevel)
    }

    /// Cards for what's known: a topic answered right comes back for a check in about ten days;
    /// one assumed from what's built on it, in about a month.
    public func cards(at date: Date) -> [MemoryCard] {
        known.sorted().map { id in
            let tested = results[id] == true
            return MemoryCard(key: .topic(id), memory: Scheduler.known(stability: tested ? 10 : 30, at: date), introduced: date,
                              knownBefore: true)
        }
    }

    public func result(at date: Date) -> TestResult {
        let levels = known.compactMap { MathCurriculum.topic($0)?.level }
        return TestResult(test: .mathsPlacement, date: date, score: Double(known.count),
                          detail: ["level": Double(levels.max() ?? 0), "asked": Double(asked)], placement: true)
    }
}

public enum WritingPlan {
    public static func known(_ cards: [CardKey: MemoryCard]) -> Set<String> {
        Set(cards.values.filter { $0.domain == .writing && $0.memory != nil }.map(\.key.item))
    }

    /// Skills not yet started, easiest first. Skills have no prerequisites.
    public static func next(_ cards: [CardKey: MemoryCard], bank: WritingBank) -> WritingSkill? {
        let learning = cards.values.filter { $0.domain == .writing && $0.learning }.sorted { $0.introduced < $1.introduced }
        if let current = learning.first, let skill = bank.skill(current.key.item) { return skill }
        let started = Set(cards.values.filter { $0.domain == .writing }.map(\.key.item))
        return bank.skills.filter { !started.contains($0.id) }.min { ($0.level, bank.skills.firstIndex(of: $0)!) < ($1.level, bank.skills.firstIndex(of: $1)!) }
    }
}
