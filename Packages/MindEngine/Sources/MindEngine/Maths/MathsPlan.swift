import Foundation
import SystemCore

/// Where each strand stands and what comes next in it.
public enum MathsPlan {
    /// Topics learned or shown known (they have a memory), in one strand or all.
    public static func known(_ cards: [CardKey: MemoryCard], strand: MathsStrand? = nil) -> Set<String> {
        Set(cards.values.filter { $0.domain == .maths && $0.memory != nil && matches($0.key, strand) }.map(\.key.item))
    }

    /// Started and not yet mastered, oldest first (by key when started together, so the order
    /// never depends on the dictionary's).
    public static func inProgress(_ cards: [CardKey: MemoryCard], strand: MathsStrand? = nil) -> [MathTopic] {
        cards.values.filter { $0.domain == .maths && $0.learning && matches($0.key, strand) }.sorted {
            ($0.introduced, $0.key) < ($1.introduced, $1.key)
        }
        .compactMap { MathCurriculum.topic($0.key.item) }
    }

    /// What can be learned next: not known, not started, everything beneath it known. Lowest level
    /// first, then curriculum order.
    public static func frontier(_ cards: [CardKey: MemoryCard], strand: MathsStrand? = nil) -> [MathTopic] {
        let known = known(cards)
        let started = Set(cards.values.filter { $0.domain == .maths }.map(\.key.item))
        return MathCurriculum.topics.enumerated().filter { _, topic in
            (strand == nil || topic.strand == strand) && !started.contains(topic.id) && topic.prerequisites.allSatisfy(known.contains)
        }.sorted { ($0.element.level, $0.offset) < ($1.element.level, $1.offset) }.map(\.element)
    }

    public static func next(_ cards: [CardKey: MemoryCard], strand: MathsStrand? = nil) -> MathTopic? {
        inProgress(cards, strand: strand).first ?? frontier(cards, strand: strand).first
    }

    /// The level a strand's placement reached: topics at or below it start with a quick check, not
    /// a lesson.
    public static func placedLevel(_ cards: [CardKey: MemoryCard], strand: MathsStrand) -> Int {
        cards.values.filter { $0.domain == .maths && $0.knownBefore && matches($0.key, strand) }
            .compactMap { MathCurriculum.topic($0.key.item)?.level }.max() ?? 0
    }

    /// The highest level learned in a strand.
    public static func highestLevel(_ cards: [CardKey: MemoryCard], strand: MathsStrand) -> Int {
        known(cards, strand: strand).compactMap { MathCurriculum.topic($0)?.level }.max() ?? 0
    }

    /// Whether a strand's level has been found: numeracy and statistics by their own tests, the
    /// classic ladder by any placement or check (the first version's placement counts).
    public static func placed(_ strand: MathsStrand, _ state: StudyState) -> Bool {
        switch strand {
        case .numeracy: state.tests.contains { $0.test == .numeracy }
        case .classic: state.tests.contains { $0.test == .mathsPlacement || $0.test == .maths }
        case .discrete: state.tests.contains { $0.test == .discrete }
        }
    }

    /// The strand a session works on after the numeracy block: the person's first choice two
    /// sessions in three and the second the third, passing over one with nothing left to learn.
    public static func mainStrand(_ state: StudyState) -> MathsStrand? {
        let options = state.settings.strands.filter { $0 != .numeracy && placed($0, state) && next(state.cards, strand: $0) != nil }
        guard options.count > 1 else { return options.first }
        let done = state.sessions.filter { $0.purpose == .regular && $0.domains.contains(.maths) && $0.finished }.count
        return done % 3 == 2 ? options[1] : options[0]
    }

    /// About how many problems the first placement asks, for the strands chosen.
    public static func placementProblems(_ settings: MindSettings) -> Int { MathsPlacementRunner.sizes(settings.strands).reduce(0, +) }

    static func matches(_ key: CardKey, _ strand: MathsStrand?) -> Bool {
        guard let strand else { return true }
        return MathCurriculum.topic(key.item)?.strand == strand
    }
}

/// Finds a strand's level on its skill graph in a handful of problems. It steps up two levels after
/// a right answer and down after a wrong one, then one level at a time once it has turned; a right
/// answer marks everything beneath that topic known, a wrong one everything built on it unknown.
public struct MathsPlacement: Hashable, Sendable {
    public let strand: MathsStrand
    public let maximum: Int
    public private(set) var level: Int
    public private(set) var step = 2
    public private(set) var results: [String: Bool] = [:]
    private var lastCorrect: Bool?

    public init(strand: MathsStrand, start: Int, maximum: Int) {
        self.strand = strand
        self.maximum = maximum
        level = clamp(start, 1, MathCurriculum.maxLevel)
    }

    public var asked: Int { results.count }

    public var known: Set<String> {
        var out: Set<String> = []
        for (id, correct) in results where correct {
            out.insert(id)
            out.formUnion(MathCurriculum.ancestors(of: id))
        }
        return out
    }

    public var unknown: Set<String> {
        var out: Set<String> = []
        for (id, correct) in results where !correct {
            out.insert(id)
            out.formUnion(MathCurriculum.descendants(of: id))
        }
        return out.subtracting(known)
    }

    public var done: Bool { asked >= maximum || nextTopic() == nil }

    /// An undecided topic at the current level (or the nearest one), the one most others build on.
    public func nextTopic() -> MathTopic? {
        guard asked < maximum else { return nil }
        let decided = known.union(unknown)
        let topics = MathCurriculum.topics(strand)
        for distance in 0...2 {
            for candidate in [level + distance, level - distance] where (1...MathCurriculum.maxLevel).contains(candidate) {
                let options = topics.filter { $0.level == candidate && !decided.contains($0.id) }
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
            return MemoryCard(
                key: .topic(id), memory: Scheduler.known(stability: tested ? 10 : 30, at: date), introduced: date,
                knownBefore: true)
        }
    }

    /// The test kind a strand's placement is saved as.
    public var test: TestKind { strand == .classic ? .mathsPlacement : strand.test }

    public func result(at date: Date) -> TestResult {
        let levels = known.compactMap { MathCurriculum.topic($0)?.level }
        let right = results.values.filter { $0 }.count
        return TestResult(
            test: test, date: date, score: Double(known.count),
            detail: ["level": Double(levels.max() ?? 0), "asked": Double(asked), "right": Double(right)], placement: true)
    }
}

/// Where each numeracy skill is working now. A skill steps up a level at four fluent answers of
/// the last five there (right inside the target time, ending on one), and down a level at three
/// misses of five; a right but slow answer counts towards neither.
public struct NumeracyLevels: Hashable, Sendable {
    enum Outcome: Hashable, Sendable { case fluent, slow, miss }

    public private(set) var levels: [NumeracySkill: Int]
    private var recent: [NumeracySkill: [Outcome]] = [:]

    public init(start: [NumeracySkill: Int]) {
        levels = Dictionary(uniqueKeysWithValues: NumeracySkill.allCases.map { ($0, clamp(start[$0] ?? 1, 1, Numeracy.maxLevel)) })
    }

    public init(level: Int) { self.init(start: Dictionary(uniqueKeysWithValues: NumeracySkill.allCases.map { ($0, level) })) }

    public subscript(_ skill: NumeracySkill) -> Int { levels[skill] ?? 1 }

    /// The skills' levels averaged, to the nearest whole level.
    public var overall: Int {
        Int((Double(NumeracySkill.allCases.map { self[$0] }.reduce(0, +)) / Double(NumeracySkill.allCases.count)).rounded())
    }

    /// The limiter: the lowest skill, the first of them in the usual order on a tie.
    public var weakest: NumeracySkill { NumeracySkill.allCases.min { self[$0] < self[$1] }! }

    public mutating func record(_ skill: NumeracySkill, level: Int, correct: Bool, seconds: Double) {
        guard level == self[skill] else { return }
        let outcome: Outcome = !correct ? .miss : seconds <= skill.target(level) ? .fluent : .slow
        var window = Array(((recent[skill] ?? []) + [outcome]).suffix(5))
        if window.count >= 4 && outcome == .fluent && window.filter({ $0 == .fluent }).count >= 4 && level < Numeracy.maxLevel {
            levels[skill] = level + 1
            window = []
        } else if window.filter({ $0 == .miss }).count >= 3 && level > 1 {
            levels[skill] = level - 1
            window = []
        }
        recent[skill] = window
    }
}

/// An adaptive numeracy test: a staircase over the ten levels with the skills taking turns. A pass
/// is right inside one and a half times the target time; the level reported is the one that best
/// explains the passes and misses, so one slip doesn't sink it.
public struct NumeracyTest: Hashable, Sendable {
    public struct Item: Hashable, Sendable {
        public var skill: NumeracySkill
        public var level: Int
        public var right: Bool
        public var seconds: Double
        public var pass: Bool
    }

    static let order: [NumeracySkill] = [.arithmetic, .percentages, .fractions, .estimation, .units]

    public let maximum: Int
    public private(set) var items: [Item] = []
    public private(set) var level: Int
    private var step: Int
    private var lastPass: Bool?

    public init(start: Int, maximum: Int, step: Int = 2) {
        self.maximum = maximum
        self.step = step
        level = clamp(start, 1, Numeracy.maxLevel)
    }

    public var done: Bool { items.count >= maximum }

    /// The next problem's skill and level.
    public var next: (skill: NumeracySkill, level: Int)? { done ? nil : (Self.order[items.count % Self.order.count], level) }

    public mutating func record(right: Bool, seconds: Double) {
        guard let next else { return }
        let pass = right && seconds <= next.skill.target(next.level) * 1.5
        items.append(Item(skill: next.skill, level: next.level, right: right, seconds: seconds, pass: pass))
        if let lastPass, lastPass != pass { step = 1 }
        lastPass = pass
        level = clamp(level + (pass ? step : -step), 1, Numeracy.maxLevel)
    }

    /// The level most likely to give these answers, if passes come at or below it nine times in
    /// ten and above it one time in seven. Ties go to the lower level.
    public var estimate: Int {
        guard !items.isEmpty else { return 1 }
        func likelihood(_ level: Int) -> Double {
            items.map { item in
                let p = item.level <= level ? 0.9 : 0.15
                return log(item.pass ? p : 1 - p)
            }.reduce(0, +)
        }
        return (1...Numeracy.maxLevel).max { likelihood($0) < likelihood($1) || (likelihood($0) == likelihood($1) && $0 > $1) }!
    }

    /// Where each skill starts its drills: the estimate, or a level below for a skill missed at or
    /// under it.
    public var starts: [NumeracySkill: Int] {
        let level = estimate
        return Dictionary(
            uniqueKeysWithValues: NumeracySkill.allCases.map { skill in
                let slipped = items.contains { $0.skill == skill && !$0.pass && $0.level <= level }
                return (skill, max(1, slipped ? level - 1 : level))
            })
    }

    public func result(at date: Date, placement: Bool) -> TestResult {
        var detail: [String: Double] = [
            "level": Double(estimate), "asked": Double(items.count),
            "seconds": items.map(\.seconds).reduce(0, +) / Double(max(1, items.count)),
            "fluent": Double(items.filter(\.pass).count) / Double(max(1, items.count)),
        ]
        if placement { for (skill, start) in starts { detail["start.\(skill.rawValue)"] = Double(start) } }
        return TestResult(
            test: .numeracy, date: date, score: Double(items.filter(\.right).count) / Double(max(1, items.count)),
            detail: detail, placement: placement)
    }
}

public enum NumeracyPlan {
    /// Numeracy under this level gets the longer block: everyday percentages, fractions of amounts
    /// and unit sums aren't fluent yet.
    public static let weakBelow = 5

    /// Each skill's level now: where the placement put it, moved by every drill since. Review weeks
    /// hold the levels where they are, so their drills are replayed as practice only.
    public static func levels(_ state: StudyState) -> NumeracyLevels {
        guard let placement = state.tests.last(where: { $0.test == .numeracy && $0.placement }) else { return NumeracyLevels(level: 1) }
        let level = Int(placement.detail["level"] ?? 1)
        var levels = NumeracyLevels(
            start: Dictionary(
                uniqueKeysWithValues: NumeracySkill.allCases.map {
                    ($0, Int(placement.detail["start.\($0.rawValue)"] ?? Double(level)))
                }))
        for session in state.sessions where session.purpose != .review {
            for attempt in session.attempts where attempt.kind == .learn && attempt.at > placement.date {
                if let numeracy = attempt.key.numeracy {
                    levels.record(numeracy.skill, level: numeracy.level, correct: attempt.correct, seconds: attempt.seconds)
                }
            }
        }
        return levels
    }

    /// Whether numeracy is weak enough to get the longer block.
    public static func weak(_ state: StudyState) -> Bool { levels(state).overall < weakBelow }
}

/// A strand's level, for Plan and Progress.
public struct StrandLevel: Hashable, Sendable, Identifiable {
    public var strand: MathsStrand
    /// At the last test (placement or check-in): the number Intelligence uses.
    public var measured: Int?
    public var measuredOn: Day?
    /// Where practice is now: numeracy's working level, or the highest level learned.
    public var working: Int
    /// What's next: the topic, or numeracy's weakest skill.
    public var next: String?
    public var known: Int
    public var total: Int

    public var id: MathsStrand { strand }
}

extension MathsPlan {
    /// Every chosen strand's level, most important first.
    public static func levels(_ state: StudyState) -> [StrandLevel] {
        state.settings.strands.map { strand in
            let test = MathsModule.latestTest(strand, state)
            let measured = test.flatMap(MathsModule.level).map { Int($0.rounded()) }
            switch strand {
            case .numeracy:
                let levels = NumeracyPlan.levels(state)
                return StrandLevel(
                    strand: strand, measured: measured, measuredOn: test?.day(startingAt: state.dayStart),
                    working: placed(.numeracy, state) ? levels.overall : 0,
                    next: placed(.numeracy, state) ? levels.weakest.label : nil, known: 0, total: 0)
            case .classic, .discrete:
                return StrandLevel(
                    strand: strand, measured: measured, measuredOn: test?.day(startingAt: state.dayStart),
                    working: highestLevel(state.cards, strand: strand),
                    next: next(state.cards, strand: strand)?.title, known: known(state.cards, strand: strand).count,
                    total: MathCurriculum.topics(strand).count)
            }
        }
    }

    /// A strand's 0–100 readings from its tests, one a day, oldest first.
    public static func series(_ strand: MathsStrand, state: StudyState) -> [(day: Day, score: Double)] {
        var out: [(day: Day, score: Double)] = []
        for test in state.tests where MathsStrand(test: test.test) == strand {
            guard let score = MathsModule.score(test) else { continue }
            let day = test.day(startingAt: state.dayStart)
            if out.last?.day == day { out[out.count - 1].score = score } else { out.append((day, score)) }
        }
        return out
    }
}
