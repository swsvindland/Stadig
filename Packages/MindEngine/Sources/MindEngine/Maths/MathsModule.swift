import Foundation
import SystemCore

/// Maths in three strands, each with its own level. Every maths session opens with a few minutes
/// of timed numeracy, like Lift Track's limiter slot, whatever the main topic; the rest works on
/// one strand, the person's first choice two sessions in three. One short adaptive test places
/// every strand at the start, and a strand switched on later places itself in its first session.
enum MathsModule: SubjectModule {
    static func needsPlacement(_ domain: Domain, state: StudyState, catalogs: Catalogs) -> Bool {
        !MathsPlan.placed(.numeracy, state)
    }

    static func placementParts(_ domain: Domain, state: StudyState, catalogs: Catalogs) -> [PlanPart] {
        [placementPart(state.settings.strands.filter { !MathsPlan.placed($0, state) })]
    }

    static func placementPart(_ strands: [MathsStrand]) -> PlanPart {
        let problems = MathsPlacementRunner.sizes(strands).reduce(0, +)
        let names = strands.map { $0 == .numeracy ? $0.label : $0.short }
        return PlanPart(kind: .placement, domain: .maths, minutes: strands.map { $0 == .numeracy ? 2 : 4 }.reduce(0, +), title: "Maths level",
                        detail: "\(ListFormatter.localizedString(byJoining: names)): about \(problems) problems, stepping up and down")
    }

    static func mainParts(_ domain: Domain, minutes: Int, kind: StudyKind, state: StudyState, catalogs: Catalogs,
                          notes: inout [String]) -> [PlanPart] {
        let levels = NumeracyPlan.levels(state)
        let weak = levels.overall < NumeracyPlan.weakBelow
        let others = state.settings.strands.filter { $0 != .numeracy }
        let block = others.isEmpty ? minutes : min(minutes, weak ? 5 : 3)
        var parts = [PlanPart(kind: .custom(numeracyKind), domain: .maths, minutes: block, title: "Numeracy",
                              detail: kind == .review ? "Timed, at today's levels: practice only this week"
                                                      : "Timed: \(levels.weakest.label.lowercased()) first, level \(levels[levels.weakest])")]
        if weak && kind != .review {
            notes.append("Numeracy is at level \(levels.overall) of 10, so its block runs five minutes until the everyday basics are quick.")
        }
        var left = minutes - block
        guard left > 0 else { return parts }
        if kind == .review {
            parts.append(PlanPart(kind: .practice, domain: .maths, minutes: left, title: "Maths practice", detail: "Mixed problems from what you've learned"))
            return parts
        }
        let unplaced = others.filter { !MathsPlan.placed($0, state) }
        if !unplaced.isEmpty {
            let placement = placementPart(unplaced)
            parts.append(placement)
            left = max(0, left - placement.minutes)
        }
        guard left > 0 else { return parts }
        if let strand = MathsPlan.mainStrand(state), let next = MathsPlan.next(state.cards, strand: strand) {
            let carrying = state.cards[next.key]?.learning == true
            parts.append(PlanPart(kind: .learn, domain: .maths, minutes: left, title: strand.label,
                                  detail: carrying ? "Carrying on: \(next.title)" : "Next: \(next.title)"))
        } else if unplaced.isEmpty {
            parts.append(PlanPart(kind: .practice, domain: .maths, minutes: left, title: "Maths practice",
                                  detail: others.isEmpty ? "Mixed problems from what you've learned" : "Everything in the graph is learned: mixed practice"))
        }
        return parts
    }

    static let numeracyKind = "numeracy"

    static func checkInParts(_ domain: Domain, state: StudyState, catalogs: Catalogs) -> [PlanPart] {
        var parts: [PlanPart] = []
        if MathsPlan.placed(.numeracy, state) {
            parts.append(PlanPart(kind: .test(.numeracy), domain: .maths, minutes: 3, title: "Numeracy", detail: "Eight timed problems, stepping up and down"))
        }
        for strand in state.settings.strands where strand != .numeracy && MathsPlan.known(state.cards, strand: strand).count >= 3 {
            let count = checkSize(strand)
            parts.append(PlanPart(kind: .test(strand.test), domain: .maths, minutes: strand == .classic ? 7 : 6, title: strand.label,
                                  detail: "\(count) problems across what you've learned"))
        }
        return parts
    }

    static func checkSize(_ strand: MathsStrand) -> Int { strand == .classic ? 8 : 6 }

    static func runner(for part: PlanPart, state: StudyState, catalogs: Catalogs) -> (any PartRunner)? {
        switch part.kind {
        case .placement: return MathsPlacementRunner(state: state)
        case .custom(numeracyKind): return NumeracyRunner(levels: NumeracyPlan.levels(state), holding: state.phase.isReview)
        case .learn: return TopicsRunner(domain: .maths, strand: MathsPlan.mainStrand(state))
        case .test(.numeracy):
            return NumeracyTestRunner(test: NumeracyTest(start: NumeracyPlan.levels(state).overall, maximum: 8, step: 1))
        case .test(let kind):
            guard let strand = MathsStrand(test: kind), strand != .numeracy else { return nil }
            return QuestionListRunner(queue: check(state, strand: strand)) { attempts, run in
                let tested = attempts.filter { $0.test == kind }
                guard tested.count >= 4 else { return }
                let levels = tested.filter(\.correct).compactMap { MathCurriculum.topic($0.key.item)?.level }
                let mean = Double(tested.compactMap { MathCurriculum.topic($0.key.item)?.level }.reduce(0, +)) / Double(tested.count)
                run.newTests.append(accuracyResult(kind, tested, placement: false, at: run.now,
                                                   extra: ["reach": Double(levels.max() ?? 0), "level": mean]))
            }
        default: return nil
        }
    }

    /// A strand's check: the highest topics learned and a few others, made-up numbers only so
    /// one check compares with the next.
    static func check(_ state: StudyState, strand: MathsStrand) -> [Question] {
        let count = checkSize(strand)
        let known = MathsPlan.known(state.cards, strand: strand).compactMap(MathCurriculum.topic).sorted { ($0.level, $0.id) > ($1.level, $1.id) }
        var rng = SeededRandom("maths-check", strand.rawValue, state.today.iso)
        let top = count * 5 / 8
        let picked = Array(known.prefix(top)) + Array(known.dropFirst(top).shuffled(using: &rng).prefix(count - top))
        return picked.enumerated().map { index, topic in
            topic.problem(seed: "check.\(state.today.iso).\(index)").question(kind: .test, id: "check.\(topic.id).\(state.today.iso)").asTest(strand.test)
        }
    }

    static func question(for key: CardKey, kind: AttemptKind, run: StudyRun) -> Question? {
        MathCurriculum.topic(key.item)?.problem(seed: run.seed, data: run.catalogs.systemData).question(kind: kind, id: "\(key.raw).\(run.seed)")
    }

    static func usable(_ key: CardKey, catalogs: Catalogs) -> Bool { MathCurriculum.topic(key.item) != nil }

    static func reviewSeconds(_ card: MemoryCard) -> Double { 55 }

    /// Maths' reading on each test day: the mean of every strand measured so far, each at its
    /// latest test. A strand is never dropped from the mean once measured, so switching off the
    /// weakest can't raise the number.
    static func series(_ domain: Domain, state: StudyState) -> [(day: Day, score: Double)] {
        var latest: [MathsStrand: Double] = [:]
        var out: [(day: Day, score: Double)] = []
        for test in state.tests {
            guard let strand = MathsStrand(test: test.test), let score = score(test) else { continue }
            latest[strand] = score
            let mean = latest.values.reduce(0, +) / Double(latest.count)
            if out.last?.day == test.day { out[out.count - 1].score = mean } else { out.append((test.day, mean)) }
        }
        return out
    }

    /// A maths test's 0–100: ten points a level, with a check's reach scaled by its accuracy.
    static func score(_ test: TestResult) -> Double? {
        guard let level = level(test) else { return nil }
        let checked = (test.test == .maths || test.test == .discrete) && !test.placement
        return min(100, 10 * level * (checked ? 0.5 + 0.5 * test.score : 1))
    }

    /// The level a maths test found: numeracy's staircase, a placement's highest topic, a check's
    /// highest topic answered right.
    static func level(_ test: TestResult) -> Double? {
        switch test.test {
        case .numeracy, .mathsPlacement: test.detail["level"]
        case .maths, .discrete: test.placement ? test.detail["level"] : test.detail["reach"]
        default: nil
        }
    }

    static func latestTest(_ strand: MathsStrand, _ state: StudyState) -> TestResult? {
        state.tests.last { MathsStrand(test: $0.test) == strand }
    }

    static func label(_ domain: Domain, state: StudyState) -> String {
        let levels = MathsStrand.allCases.compactMap { strand in
            latestTest(strand, state).flatMap(level).map { "\(strand.short) \(Int($0.rounded()))" }
        }
        return levels.isEmpty ? "Maths" : "Maths: " + levels.joined(separator: ", ")
    }

    /// The maths line of "What we've learned".
    static func learnedNote(_ state: StudyState) -> String? {
        guard MathsPlan.placed(.numeracy, state) else { return nil }
        let levels = state.settings.strands.compactMap { strand in
            latestTest(strand, state).flatMap(level).map { "\(strand.short) level \(Int($0.rounded()))" }
        }
        let next = MathsPlan.mainStrand(state).flatMap { MathsPlan.next(state.cards, strand: $0) }.map { " Next up: \($0.title)." } ?? ""
        let weak = NumeracyPlan.weak(state) ? " Numeracy gets five minutes a session until it's quick." : ""
        return "Maths: \(ListFormatter.localizedString(byJoining: levels)), of 10.\(next)\(weak)"
    }
}

/// The placement: one short adaptive test sampling each strand not yet placed. Numeracy comes
/// first, then the others in the person's order, the first of them asked a question more. Weak
/// numeracy starts the others lower.
struct MathsPlacementRunner: PartRunner {
    struct Current: Sendable {
        var index: Int
        var topic: String
    }

    var numeracy: NumeracyTest?
    var graphs: [MathsPlacement]
    var current: Current?

    init(state: StudyState) {
        let strands = state.settings.strands.filter { !MathsPlan.placed($0, state) }
        let sizes = Self.sizes(strands)
        numeracy = strands.first == .numeracy ? NumeracyTest(start: 4, maximum: sizes[0]) : nil
        let graphStrands = Array(strands.drop { $0 == .numeracy })
        graphs = zip(graphStrands, sizes.suffix(graphStrands.count)).map { strand, size in
            MathsPlacement(strand: strand, start: Self.start(strand), maximum: size)
        }
    }

    /// Problems per strand: six for numeracy, six and five for the others (seven for one alone).
    static func sizes(_ strands: [MathsStrand]) -> [Int] {
        let graphs = strands.filter { $0 != .numeracy }.count
        return strands.map { strand in
            if strand == .numeracy { return 6 }
            if graphs == 1 { return 7 }
            return strand == strands.first(where: { $0 != .numeracy }) ? 6 : 5
        }
    }

    static func start(_ strand: MathsStrand, weakNumeracy: Bool = false) -> Int {
        weakNumeracy ? 2 : strand == .classic ? 4 : 3
    }

    mutating func next(_ run: inout StudyRun) -> StudyRun.Step? {
        guard run.partSeconds < run.budget * 2 else { return nil }
        if let item = numeracy?.next {
            return .question(item.skill.question(level: item.level, seed: "placement.\(run.seed)", kind: .test).asTest(.numeracy))
        }
        guard let index = graphs.firstIndex(where: { !$0.done }) else { return nil }
        if graphs[index].asked == 0, let estimate = numeracy?.estimate, estimate < NumeracyPlan.weakBelow - 1 {
            graphs[index] = MathsPlacement(strand: graphs[index].strand, start: Self.start(graphs[index].strand, weakNumeracy: true),
                                           maximum: graphs[index].maximum)
        }
        guard let topic = graphs[index].nextTopic() else { return nil }
        current = Current(index: index, topic: topic.id)
        let question = topic.problem(seed: "placement.\(graphs[index].asked)").question(kind: .test, id: "placement.\(topic.id)")
        return .question(question.asTest(graphs[index].test))
    }

    mutating func record(_ question: Question, correct: Bool, _ run: inout StudyRun) {
        if question.test == .numeracy {
            numeracy?.record(right: correct, seconds: run.answered.last?.seconds ?? 0)
        } else if let current {
            graphs[current.index].record(topic: current.topic, correct: correct)
            self.current = nil
        }
    }

    mutating func finish(_ run: inout StudyRun) {
        if let numeracy, numeracy.items.count >= 4 { run.newTests.append(numeracy.result(at: run.now, placement: true)) }
        for graph in graphs where graph.asked >= 3 || (graph.done && graph.asked > 0) {
            for card in graph.cards(at: run.now) where run.cards[card.key]?.memory == nil { run.save(card) }
            run.newTests.append(graph.result(at: run.now))
        }
    }
}

/// The numeracy block: timed problems for its few minutes, every other one from the weakest skill
/// and the rest taking turns. Levels move as it goes, by the same rule the history is replayed
/// with, except in a review week, which practises at the levels as they are.
struct NumeracyRunner: PartRunner {
    struct Current: Sendable {
        var skill: NumeracySkill
        var level: Int
    }

    var levels: NumeracyLevels
    let holding: Bool
    var asked = 0
    var current: Current?

    mutating func next(_ run: inout StudyRun) -> StudyRun.Step? {
        guard run.partSeconds < run.budget else { return nil }
        let skill = asked % 2 == 0 ? levels.weakest : NumeracySkill.allCases[(asked / 2) % NumeracySkill.allCases.count]
        asked += 1
        current = Current(skill: skill, level: levels[skill])
        return .question(skill.question(level: levels[skill], seed: run.seed, kind: .learn))
    }

    mutating func record(_ question: Question, correct: Bool, _ run: inout StudyRun) {
        guard let current, let seconds = run.answered.last?.seconds else { return }
        if !holding { levels.record(current.skill, level: current.level, correct: correct, seconds: seconds) }
        self.current = nil
    }
}

/// The check-in's numeracy test: eight timed problems stepping a level at a time from where the
/// drills are.
struct NumeracyTestRunner: PartRunner {
    var test: NumeracyTest

    mutating func next(_ run: inout StudyRun) -> StudyRun.Step? {
        guard let item = test.next, run.partSeconds < run.budget * 2.5 else { return nil }
        return .question(item.skill.question(level: item.level, seed: "check.\(run.seed)", kind: .test).asTest(.numeracy))
    }

    mutating func record(_ question: Question, correct: Bool, _ run: inout StudyRun) {
        test.record(right: correct, seconds: run.answered.last?.seconds ?? 0)
    }

    mutating func finish(_ run: inout StudyRun) {
        guard test.items.count >= 5 else { return }
        run.newTests.append(test.result(at: run.now, placement: false))
    }
}
