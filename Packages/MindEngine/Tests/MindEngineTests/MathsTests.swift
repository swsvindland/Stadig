import Foundation
import Testing
import SystemCore
@testable import MindEngine

@Suite("Maths strands")
struct MathsTests {
    let deck = Fixtures.deck()
    let monday = Fixtures.monday

    // MARK: Content

    @Test("numeracy: every skill makes well-formed problems at every level, with sums and estimates that check out")
    func numeracyProblems() throws {
        for skill in NumeracySkill.allCases {
            for level in 1...10 {
                if level > 1 { #expect(skill.target(level) > skill.target(level - 1), "\(skill) slows as it gets harder") }
                for seed in 0..<150 {
                    let problem = skill.problem(level: level, seed: "\(seed)")
                    let label = "\(skill) \(level) #\(seed): \(problem.prompt)"
                    #expect(problem.prompt.filter { $0 == "$" }.count % 2 == 0 && balanced(problem.prompt), "\(label)")
                    #expect(!problem.steps.isEmpty && problem.steps.allSatisfy { balanced($0) && $0.filter { $0 == "$" }.count % 2 == 0 }, "\(label) \(problem.steps)")
                    let question = skill.question(level: level, seed: "\(seed)", kind: .learn)
                    #expect(question.timed && question.key.numeracy?.skill == skill && question.key.numeracy?.level == level)
                    switch problem.answer {
                    case .choice(let index):
                        #expect(problem.choices.indices.contains(index) && problem.choices.count >= 3 && Set(problem.choices).count == problem.choices.count,
                                "\(label): \(problem.choices)")
                        if skill == .estimation, let truth = evaluate(problem.prompt) {
                            let distance = problem.choices.map { abs(log(amount($0) / truth.double)) }
                            #expect(distance.indices.allSatisfy { $0 == index || distance[$0] > distance[index] + 0.3 }, "\(label): \(problem.choices)")
                        }
                    case .number(let value, let tolerance):
                        #expect(question.check(typed: tolerance > 0 ? String(format: "%.2f", value.double) : value.description), "\(label) = \(value)")
                        if skill == .arithmetic, let truth = evaluate(problem.prompt) { #expect(truth == value, "\(label) = \(value), not \(truth)") }
                        if skill != .fractions && !problem.prompt.contains("fraction") {
                            #expect(value.decimal != nil, "\(label) = \(value): outside fractions, answers are plain decimals")
                        }
                    }
                }
            }
        }
        #expect(NumeracySkill.percentages.problem(level: 3, seed: "x") == NumeracySkill.percentages.problem(level: 3, seed: "x"), "deterministic")
        if ProcessInfo.processInfo.environment["PRINT_PROBLEMS"] != nil {
            for skill in NumeracySkill.allCases {
                for level in 1...10 {
                    let problem = skill.problem(level: level, seed: "print")
                    let answer = switch problem.answer {
                    case .choice(let i): problem.choices[i]
                    case .number(let v, _): v.description
                    }
                    print("[\(skill.rawValue) \(level), \(Int(skill.target(level))) s] \(problem.prompt)  →  \(answer)")
                }
            }
        }
    }

    @Test("statistics and logic: its own graph from charts to least squares, every topic placed in the strand")
    func discreteGraph() {
        let topics = MathCurriculum.topics(.discrete)
        #expect(topics.count >= 20)
        #expect(Set(topics.map(\.level)) == Set(1...10), "every level has a topic")
        for topic in topics {
            #expect(topic.prerequisites.allSatisfy { MathCurriculum.topic($0)?.strand == .discrete }, "\(topic.id) stands within its strand")
        }
        for id in ["reading-charts", "sets", "if-then", "probability", "two-way-tables", "sampling", "base-rates", "normal-distribution", "regression"] {
            #expect(MathCurriculum.topic(id)?.strand == .discrete, "\(id)")
        }
        #expect(MathCurriculum.topics(.classic).allSatisfy { $0.prerequisites.allSatisfy { MathCurriculum.topic($0)?.strand == .classic } })
        #expect(MathCurriculum.ancestors(of: "bayes").contains("conditional-probability"))
    }

    @Test("statistics problems use the person's own numbers when there are enough, and made-up ones otherwise")
    func personalData() throws {
        let data = Self.sampleData(ending: monday)
        let personal = MathCurriculum.topics.filter(\.usesData)
        #expect(personal.count >= 8 && personal.allSatisfy { $0.strand == .discrete })
        for topic in personal {
            for seed in 0..<40 {
                let problem = try #require(topic.personalProblem(seed: "\(seed)", data: data), "\(topic.id) has data to use")
                let text = (problem.prompt + (problem.figure?.source ?? "")).lowercased()
                #expect(text.contains("you") || text.contains("lift track") || text.contains("macro track"), "\(topic.id): \(problem.prompt)")
                #expect(balanced(problem.prompt) && !problem.steps.isEmpty, "\(topic.id): \(problem.prompt)")
                if case .number(let value, let tolerance) = problem.answer {
                    #expect(problem.question(kind: .learn, id: "t").check(typed: tolerance > 0 ? String(format: "%.2f", value.double) : value.description))
                }
                if let figure = problem.figure { #expect(figure.points.count >= 5 && figure.source == "From Lift Track") }
            }
            #expect(topic.personalProblem(seed: "x", data: .none) == nil)
            let mixed = (0..<40).map { topic.problem(seed: "\($0)", data: data) }
            #expect(mixed.contains { $0.figure?.source != nil || $0.prompt.lowercased().contains("you") }, "\(topic.id) sometimes uses the data")
            #expect((0..<40).map { topic.problem(seed: "\($0)") }.allSatisfy { $0.figure?.source == nil && !$0.prompt.contains("Lift Track") }, "never without it")
        }
        // The mean of five step days is worked out from the chart's own rounded values.
        let week = try #require(data.stepWeek?.rounded(to: 100))
        #expect(week.allSatisfy { $0.value.truncatingRemainder(dividingBy: 100) == 0 } && week.count == 7)
    }

    @Test("System data comes from what Lift Track and Macro Track publish, phone-on-a-desk days left out")
    func systemDataFromSummaries() {
        let days = (0..<14).map { monday.adding(days: $0) }
        let lift = AppSummary(app: .liftTrack, sessions: days.enumerated().compactMap { index, day in
            index % 3 == 0 ? SessionSummary(id: UUID(), app: .liftTrack, kind: .strength, start: day.date().addingTimeInterval(64_800), minutes: 55, planned: true) : nil
        } + [SessionSummary(id: UUID(), app: .liftTrack, kind: .activity, start: monday.date(), minutes: 30, planned: false)],
                              steps: StepSummary(days: days.map { StepDay(day: $0, steps: $0 == monday ? 400 : 8000 + $0.ordinal % 7 * 300) }, aim: nil, baseline: nil))
        let macro = AppSummary(app: .macroTrack, sessions: days.map {
            SessionSummary(id: UUID(), app: .macroTrack, kind: .nutrition, start: $0.date(), minutes: 0, metrics: ["kcal": 2400, "protein": 150], planned: true)
        })
        let nutrition = NutritionSummary(phase: nil, maintenanceKcal: nil, days: days.map { NutritionDay(day: $0, logged: true, proteinHit: $0.ordinal % 2 == 0, caloriesHit: nil) })
        let data = SystemData(lift: lift, macro: macro, nutrition: nutrition)
        #expect(data.steps.count == 13, "the 400-step day is unknown, not sedentary")
        #expect(data.training.count == 5 && data.training.allSatisfy { $0.value == 55 }, "strength sessions only")
        #expect(data.protein.count == 14 && data.calories.first?.value == 2400 && data.proteinHits.count == 14)
        #expect(data.trainingAndProtein != nil && data.stepWeek?.count == 7)
        #expect(SystemData(lift: nil, macro: nil, nutrition: nil).isEmpty)
    }

    @Test("typed answers take thousands separators, never a decimal comma")
    func separators() {
        #expect(Rational(parsing: "8,400") == 8400 && Rational(parsing: "12,000.5") == Rational(24_001, 2) && Rational(parsing: "-1,250") == -1250)
        #expect(Rational(parsing: "1,5") == nil && Rational(parsing: "12,00") == nil)
    }

    // MARK: Levels

    @Test("numeracy levels rise only on fluent answers: right, and inside the target time")
    func numeracyLevels() {
        var levels = NumeracyLevels(level: 4)
        let quick = NumeracySkill.percentages.target(4) - 1
        for _ in 0..<10 { levels.record(.percentages, level: 4, correct: true, seconds: 60) }
        #expect(levels[.percentages] == 4, "right but slow isn't fluent yet")
        for _ in 0..<4 { levels.record(.percentages, level: 4, correct: true, seconds: quick) }
        #expect(levels[.percentages] == 5)
        levels.record(.percentages, level: 4, correct: true, seconds: quick)
        #expect(levels[.percentages] == 5, "an answer at an old level doesn't count")
        for _ in 0..<3 { levels.record(.percentages, level: 5, correct: false, seconds: 3) }
        #expect(levels[.percentages] == 4, "three misses of five step down")
        levels.record(.fractions, level: 4, correct: false, seconds: 3)
        levels.record(.fractions, level: 4, correct: false, seconds: 3)
        levels.record(.fractions, level: 4, correct: false, seconds: 3)
        #expect(levels.weakest == .fractions && levels.overall == 4)
    }

    @Test("the numeracy test: a staircase whose estimate one slip doesn't sink")
    func numeracyTest() {
        var test = NumeracyTest(start: 4, maximum: 6)
        for pass in [true, true, false, true, false, true] {
            let item = test.next!
            test.record(right: pass, seconds: pass ? 1 : item.skill.target(item.level))
        }
        #expect(test.estimate == 7 && test.done)
        var slip = NumeracyTest(start: 4, maximum: 6)
        for pass in [false, true, true, true, true, true] { slip.record(right: pass, seconds: 1) }
        #expect(slip.estimate >= 5, "an early slip, then everything right up to level \(slip.items.last!.level): \(slip.estimate)")
        var slow = NumeracyTest(start: 4, maximum: 6)
        for _ in 0..<6 { slow.record(right: true, seconds: 120) }
        #expect(slow.estimate == 1 && slow.result(at: Date(), placement: true).score == 1, "all right, all far too slow: accuracy kept, level not given")
    }

    @Test("placement lands each strand near the student's true level, from about seventeen problems")
    func placementAccuracy() throws {
        var rng = SeededRandom(seed: 17)
        var off: [MathsStrand: [Int]] = [:]
        for index in 0..<60 {
            let truth = (numeracy: rng.int(2...9), classic: rng.int(2...8), discrete: rng.int(2...8))
            var store = Store(settings: Fixtures.settings([.maths]))
            var student = Student(vocabulary: 0, mathsLevel: truth.classic, writingLevel: 0, numeracyLevel: truth.numeracy, discreteLevel: truth.discrete,
                                  rng: SeededRandom(seed: UInt64(100 + index)), deck: deck)
            let run = try #require(store.study(on: monday, student: &student, deck: deck))
            #expect(run.plan.parts.first?.kind == .placement && run.plan.parts.first?.detail.contains("about 17 problems") == true, "\(run.plan.parts)")
            let numeracy = try #require(store.tests.first { $0.test == .numeracy })
            let classic = try #require(store.tests.first { $0.test == .mathsPlacement })
            let discrete = try #require(store.tests.first { $0.test == .discrete })
            #expect(numeracy.placement && classic.placement && discrete.placement)
            off[.numeracy, default: []].append(Int(numeracy.detail["level"]!) - truth.numeracy)
            off[.classic, default: []].append(Int(classic.detail["level"]!) - truth.classic)
            off[.discrete, default: []].append(Int(discrete.detail["level"]!) - truth.discrete)
            let asked = run.session.attempts.filter { $0.kind == .test }.count
            #expect(asked <= 17, "\(asked) problems")
        }
        for (strand, errors) in off {
            let close = errors.filter { abs($0) <= 1 }.count
            #expect(close >= 51, "\(strand): \(close) of 60 within a level, errors \(errors)")
            #expect(errors.allSatisfy { abs($0) <= 3 }, "\(strand): \(errors)")
        }
    }

    // MARK: Plans

    @Test("every maths session opens with numeracy whatever the strand; weak numeracy gets five minutes; review weeks hold levels")
    func numeracyBlock() throws {
        var store = placedStore(numeracy: 6)
        let state = store.state(on: monday.adding(days: 15))
        let plan = SessionPlanner.plan(.regular, domains: [.maths], state: state, catalogs: Catalogs())
        let numeracy = try #require(plan.parts.first)
        #expect(numeracy.kind == .custom("numeracy") && numeracy.minutes == 3 && numeracy.domain == .maths, "\(plan.parts.map(\.kind))")
        #expect(plan.parts.contains { $0.kind == .learn && $0.title == MathsStrand.classic.label })

        store.tests = store.tests.map { test in
            guard test.test == .numeracy else { return test }
            var weak = test
            weak.detail = ["level": 3]
            return weak
        }
        let weak = SessionPlanner.plan(.regular, domains: [.maths, .writing], state: store.state(on: monday.adding(days: 15)), catalogs: Catalogs())
        #expect(weak.parts.first?.minutes == 5 && weak.notes.contains { $0.contains("Numeracy is at level 3") }, "\(weak.parts.map(\.minutes)) \(weak.notes)")

        let review = SessionPlanner.plan(.review, domains: [.maths], state: store.state(on: monday.adding(days: 15)), catalogs: Catalogs())
        #expect(review.parts.first?.kind == .custom("numeracy") && !review.parts.contains { $0.kind == .learn })
    }

    @Test("the first strand chosen gets two sessions in three; only numeracy means the whole block is numeracy")
    func priorities() throws {
        var store = placedStore(numeracy: 6)
        store.settings.mathsStrands = [.numeracy, .discrete, .classic]
        var strands: [MathsStrand?] = []
        for offset in 0..<6 {
            let day = monday.adding(days: 15 + offset)
            strands.append(MathsPlan.mainStrand(store.state(on: day)))
            store.sessions.append(StudySession(purpose: .regular, start: day.date(), end: day.date().addingTimeInterval(1500), plannedMinutes: 25,
                                               domains: [.maths], planned: true, ranToEnd: true))
        }
        #expect(strands == [.discrete, .discrete, .classic, .discrete, .discrete, .classic])

        store.settings.mathsStrands = [.numeracy]
        let plan = SessionPlanner.plan(.regular, domains: [.maths], state: store.state(on: monday.adding(days: 30)), catalogs: Catalogs())
        #expect(plan.parts.filter { $0.domain == .maths }.map(\.kind) == [.custom("numeracy")], "\(plan.parts.map(\.kind))")

        // Statistics switched on later places itself after the numeracy block.
        store.settings.mathsStrands = [.numeracy, .classic, .discrete]
        store.tests.removeAll { $0.test == .discrete }
        let later = SessionPlanner.plan(.regular, domains: [.maths], state: store.state(on: monday.adding(days: 30)), catalogs: Catalogs())
        let maths = later.parts.filter { $0.domain == .maths }
        #expect(Array(maths.map(\.kind).prefix(2)) == [.custom("numeracy"), .placement] && maths[1].detail.hasPrefix("statistics"), "\(later.parts)")
    }

    @Test("a first-version placement keeps the ladder: only numeracy and statistics are placed")
    func firstVersion() throws {
        var store = Store(settings: Fixtures.settings([.maths]))
        let now = monday.date()
        store.tests = [TestResult(test: .mathsPlacement, date: now, score: 6, detail: ["level": 5], placement: true)]
        store.sessions = [StudySession(purpose: .placement, start: now, end: now, plannedMinutes: 25, domains: [.maths], planned: true, ranToEnd: true),
                          StudySession(purpose: .regular, start: now + 86_400, end: now + 87_000, plannedMinutes: 25, domains: [.maths], planned: true)]
        store.cards[.topic("linear-equations")] = MemoryCard(key: .topic("linear-equations"), memory: Scheduler.known(stability: 10, at: now), introduced: now, knownBefore: true)
        let state = store.state(on: monday.adding(days: 2))
        #expect(state.needsPlacement(.maths, catalogs: Catalogs()))
        let plan = try #require(SessionPlanner.today(state, catalogs: Catalogs()))
        let part = try #require(plan.parts.first { $0.kind == .placement })
        #expect(part.detail.contains("Numeracy") && part.detail.contains("statistics") && !part.detail.contains("algebra"), "\(part.detail)")
        var student = Student(vocabulary: 0, mathsLevel: 5, writingLevel: 0, deck: deck)
        store.study(on: monday.adding(days: 2), student: &student, deck: deck)
        #expect(store.tests.filter { $0.test == .mathsPlacement }.count == 1 && store.tests.contains { $0.test == .numeracy } && store.tests.contains { $0.test == .discrete })
    }

    // MARK: Over weeks

    @Test("eight weeks: numeracy opens every session and its levels climb, both strands are learned, and the check-in tests each one")
    func weeks() throws {
        var settings = Fixtures.settings([.maths])
        settings.mathsStrands = [.numeracy, .discrete, .classic]
        var store = Store(settings: settings)
        var student = Student(vocabulary: 0, mathsLevel: 4, writingLevel: 0, numeracyLevel: 8, discreteLevel: 2, deck: deck)
        var checkIn: StudyRun?
        var levelsSeen: [Int] = []
        var intelligenceBetweenTests: Set<Int> = []
        for offset in 0..<57 {
            let day = monday.adding(days: offset)
            guard let run = store.study(on: day, student: &student, deck: deck) else { continue }
            if run.plan.kind == .regular || run.plan.kind == .review {
                #expect(run.plan.parts.first { $0.domain == .maths }?.kind == .custom("numeracy"), "\(day): \(run.plan.parts.map(\.kind))")
                #expect(run.session.attempts.contains { $0.key.numeracy != nil && $0.kind == .learn && $0.seconds < 30 })
            }
            if run.plan.kind == .checkIn { checkIn = run }
            levelsSeen.append(NumeracyPlan.levels(store.state(on: day.adding(days: 1))).overall)
            if run.newTests.isEmpty && offset > 1 && checkIn == nil {
                let score = Analyst.stats(store.state(on: day.adding(days: 1))).first { $0.stat == .intelligence }?.score
                intelligenceBetweenTests.insert(Int((score ?? -1).rounded()))
            }
        }
        let placed = try #require(store.tests.first { $0.test == .numeracy && $0.placement })
        #expect((7...9).contains(levelsSeen.last!) && abs(Int(placed.detail["level"]!) - 8) <= 1, "the drills settle at the student's 8: \(levelsSeen)")
        #expect(intelligenceBetweenTests.count == 1, "drills and learning never move Intelligence between tests: \(intelligenceBetweenTests)")
        let discrete = MathsPlan.known(store.cards, strand: .discrete).count, classic = MathsPlan.known(store.cards, strand: .classic).count
        let placedDiscrete = store.cards.values.filter { $0.knownBefore && MathCurriculum.topic($0.key.item)?.strand == .discrete }.count
        #expect(discrete > placedDiscrete + 3, "statistics first: \(discrete) known, \(placedDiscrete) from placement")
        #expect(classic > 0)
        let run = try #require(checkIn)
        #expect(Set(run.newTests.map(\.test)).isSuperset(of: [.numeracy, .maths, .discrete]), "\(run.newTests.map(\.test))")
        let analysis = Analyst.analyse(store.state(on: monday.adding(days: 57)), catalogs: Fixtures.catalogs(deck))
        let intelligence = try #require(analysis.stats.first { $0.stat == .intelligence })
        #expect(intelligence.label.contains("numeracy") && intelligence.label.contains("statistics") && intelligence.label.contains("algebra"), "\(intelligence.label)")
        #expect(Analyst.series(.maths, state: store.state(on: monday.adding(days: 57))).count == 2, "a point at placement and one at the check-in")
    }

    @Test("drills climb from a low placement to where the student really is, and a review week holds the levels")
    func climbing() throws {
        var store = placedStore(numeracy: 3)
        var student = Student(vocabulary: 0, mathsLevel: 3, writingLevel: 0, numeracyLevel: 8, deck: deck)
        var levels = [NumeracyPlan.levels(store.state(on: monday.adding(days: 15))).overall]
        for offset in 0..<10 {
            let state = store.state(on: monday.adding(days: 15 + offset))
            let plan = SessionPlanner.plan(.regular, domains: [.maths], state: state, catalogs: Catalogs())
            var run = StudyRun(plan: plan, state: state, catalogs: Catalogs(), now: state.now)
            _ = student.run(&run, from: state.now)
            store.save(run)
            levels.append(NumeracyPlan.levels(store.state(on: monday.adding(days: 16 + offset))).overall)
        }
        #expect(levels.first == 3 && levels.last! >= 6, "\(levels)")
        #expect(zip(levels, levels.dropFirst()).allSatisfy { $0 <= $1 + 1 }, "\(levels)")
        let before = NumeracyPlan.levels(store.state(on: monday.adding(days: 30)))
        let state = store.state(on: monday.adding(days: 30))
        var run = StudyRun(plan: SessionPlanner.plan(.review, domains: [.maths], state: state, catalogs: Catalogs()), state: state, catalogs: Catalogs(), now: state.now)
        _ = student.run(&run, from: state.now)
        store.save(run)
        #expect(run.session.purpose == .review && run.session.attempts.contains { $0.key.numeracy != nil })
        #expect(NumeracyPlan.levels(store.state(on: monday.adding(days: 31))) == before, "a review week practises without moving levels")
    }

    @Test("maths' share of Intelligence is the mean of the strands measured, and switching off the weakest can't raise it")
    func honestScore() {
        var store = Store(settings: Fixtures.settings([.maths]))
        let day0 = monday.date(), day56 = monday.adding(days: 56).date()
        store.tests = [
            TestResult(test: .numeracy, date: day0, score: 0.6, detail: ["level": 6], placement: true),
            TestResult(test: .mathsPlacement, date: day0, score: 8, detail: ["level": 4], placement: true),
            TestResult(test: .discrete, date: day0, score: 3, detail: ["level": 2], placement: true),
        ]
        var series = Analyst.series(.maths, state: store.state(on: monday.adding(days: 1)))
        #expect(series.count == 1 && abs(series[0].score - 40) < 0.01)
        store.settings.mathsStrands = [.numeracy, .classic]
        series = Analyst.series(.maths, state: store.state(on: monday.adding(days: 1)))
        #expect(abs(series[0].score - 40) < 0.01, "dropping statistics leaves its last reading in")
        store.tests += [
            TestResult(test: .numeracy, date: day56, score: 0.75, detail: ["level": 7]),
            TestResult(test: .maths, date: day56, score: 0.8, detail: ["reach": 5]),
            TestResult(test: .discrete, date: day56, score: 1, detail: ["reach": 3]),
        ]
        series = Analyst.series(.maths, state: store.state(on: monday.adding(days: 57)))
        #expect(series.count == 2 && abs(series[1].score - (70 + 45 + 30) / 3) < 0.01, "\(series)")
        #expect(MathsModule.label(.maths, state: store.state(on: monday.adding(days: 57))) == "Maths: numeracy 7, algebra 5, statistics 3")
        let levels = MathsPlan.levels(store.state(on: monday.adding(days: 57)))
        #expect(levels.map(\.strand) == [.numeracy, .classic] && levels[0].measured == 7 && levels[1].measured == 5)
        #expect(MathsPlan.series(.discrete, state: store.state(on: monday.adding(days: 57))).map(\.score) == [20, 30])
    }

    // MARK: Helpers

    /// A store past the assessment with every strand placed.
    func placedStore(numeracy: Int) -> Store {
        var store = Store(settings: Fixtures.settings([.maths, .writing]))
        let now = monday.date()
        store.sessions = [StudySession(purpose: .placement, start: now, end: now, plannedMinutes: 25, domains: [.maths, .writing], planned: true, ranToEnd: true)]
        store.tests = [
            TestResult(test: .numeracy, date: now, score: 0.7, detail: ["level": Double(numeracy)], placement: true),
            TestResult(test: .mathsPlacement, date: now, score: 6, detail: ["level": 3], placement: true),
            TestResult(test: .discrete, date: now, score: 2, detail: ["level": 1], placement: true),
            TestResult(test: .writing, date: now, score: 0.5, placement: true),
        ]
        for id in ["order-of-operations", "negative-numbers", "reading-charts"] {
            store.cards[.topic(id)] = MemoryCard(key: .topic(id), memory: Scheduler.known(stability: 30, at: now), introduced: now, knownBefore: true)
        }
        return store
    }

    /// Four weeks of steps, three strength sessions a week and most days' food.
    static func sampleData(ending last: Day) -> SystemData {
        var rng = SeededRandom(seed: 9)
        let steps = (0..<28).map { SystemData.Point(day: last.adding(days: -$0), value: Double(rng.int(4000...12_500))) }
        let training = (0..<28).filter { [1, 3, 5].contains($0 % 7) }.map { SystemData.Point(day: last.adding(days: -$0), value: 60) }
        var hits: [Day: Bool] = [:]
        for offset in 0..<28 where offset % 5 != 4 { hits[last.adding(days: -offset)] = rng.chance(0.6) }
        let protein = hits.keys.map { SystemData.Point(day: $0, value: Double(rng.int(90...180))) }
        return SystemData(steps: steps, training: training, protein: protein, calories: [], proteinHits: hits)
    }

    func balanced(_ text: String) -> Bool {
        var depth = 0
        for character in text {
            if character == "{" { depth += 1 }
            if character == "}" { depth -= 1 }
            if depth < 0 { return false }
        }
        return depth == 0
    }

    /// The value of a prompt that's a plain sum: "$47 + 8$", "$0.3 \times 0.4$", "About how much is $812 \div 19$?".
    func evaluate(_ prompt: String) -> Rational? {
        let pieces = prompt.components(separatedBy: "$")
        guard pieces.count == 3, pieces[0].isEmpty || pieces[0] == "About how much is ", pieces[2].isEmpty || pieces[2] == "?" else { return nil }
        let tokens = pieces[1].replacingOccurrences(of: #"\times"#, with: "*").replacingOccurrences(of: #"\div"#, with: "/")
            .replacingOccurrences(of: ",", with: "").split(separator: " ").map(String.init)
        if tokens.count == 1, tokens[0].hasSuffix("^{2}"), let base = Rational(parsing: String(tokens[0].dropLast(4))) { return base * base }
        guard tokens.count >= 3, tokens.count % 2 == 1, var value = Rational(parsing: tokens[0]) else { return nil }
        for index in stride(from: 1, to: tokens.count, by: 2) {
            guard let next = Rational(parsing: tokens[index + 1]) else { return nil }
            switch tokens[index] {
            case "+": value = value + next
            case "-": value = value - next
            case "*": value = value * next
            case "/": value = value / next
            default: return nil
            }
        }
        return value
    }

    /// "2,000", "90 million", "0.5".
    func amount(_ text: String) -> Double {
        if text.hasSuffix(" million") { return (Double(text.dropLast(8).replacingOccurrences(of: ",", with: "")) ?? 0) * 1_000_000 }
        if text.hasSuffix(" billion") { return (Double(text.dropLast(8).replacingOccurrences(of: ",", with: "")) ?? 0) * 1_000_000_000 }
        return Double(text.replacingOccurrences(of: ",", with: "")) ?? 0
    }
}

extension MathsTests {
    /// Every "$x \times y = z$" and "$x \div y = z$" (or + and -) in a worked solution.
    func sums(in steps: [String]) -> [(x: Rational, op: String, y: Rational, z: Rational)] {
        steps.flatMap { step in
            step.components(separatedBy: "$").enumerated().filter { $0.offset % 2 == 1 }.compactMap { _, maths -> (Rational, String, Rational, Rational)? in
                let tokens = maths.replacingOccurrences(of: ",", with: "").split(separator: " ").map(String.init)
                guard tokens.count == 5, tokens[3] == "=", let x = Rational(parsing: tokens[0]), let y = Rational(parsing: tokens[2]),
                      let z = Rational(parsing: tokens[4]) else { return nil }
                return (x, tokens[1], y, z)
            }
        }
    }

    @Test("the arithmetic in every worked step adds up, and 'make the ten' always crosses it")
    func workedSteps() {
        var checked = 0
        for skill in NumeracySkill.allCases {
            for level in 1...10 {
                for seed in 0..<200 {
                    let problem = skill.problem(level: level, seed: "\(seed)")
                    for sum in sums(in: problem.steps) {
                        let value: Rational? = switch sum.op {
                        case #"\times"#: sum.x * sum.y
                        case #"\div"#: sum.y == 0 ? nil : sum.x / sum.y
                        case "+": sum.x + sum.y
                        case "-": sum.x - sum.y
                        default: nil
                        }
                        guard let value else { continue }
                        checked += 1
                        #expect(value == sum.z, "\(skill) \(level) #\(seed): \(problem.prompt) → \(problem.steps)")
                    }
                    // A step never adds or takes away a negative or nothing.
                    #expect(!problem.steps.contains { $0.contains("$+ -") || $0.contains("$- -") || $0.contains("$+ 0$") || $0.contains("$- 0$") },
                            "\(skill) \(level) #\(seed): \(problem.steps)")
                }
            }
        }
        #expect(checked > 3000, "\(checked) sums checked")
    }

    @Test("a decimal product is worked on its digits as written: 0.5 × 3 starts from 5 × 3, not 1 × 3")
    func decimalDigits() throws {
        var checked = 0
        for skill in NumeracySkill.allCases {
            for level in 1...10 {
                for seed in 0..<200 {
                    let problem = skill.problem(level: level, seed: "\(seed)")
                    guard case .number(let answer, _) = problem.answer else { continue }
                    for step in problem.steps {
                        let places = step.contains("one decimal place back") ? 1 : step.contains("two decimal places back") ? 2 : 0
                        guard places > 0 else { continue }
                        let product = try #require(sums(in: [step]).first, "\(step)").z
                        let back = try #require(step.components(separatedBy: "back: $").last?.split(separator: "$").first.flatMap { Rational(parsing: String($0)) })
                        checked += 1
                        #expect(product / Rational(places == 1 ? 10 : 100) == back && back == answer, "\(skill) \(level) #\(seed): \(problem.prompt) → \(step)")
                    }
                }
            }
        }
        #expect(checked > 100, "\(checked) checked")
    }

    @Test("a price change shows its prices as decimals, never as fractions")
    func percentageChangePrices() throws {
        let topic = try #require(MathCurriculum.topic("percentages"))
        var halves = 0
        for seed in 0..<600 {
            let problem = topic.problem(seed: "\(seed)")
            guard problem.prompt.hasPrefix("A price goes from") else { continue }
            #expect(!problem.prompt.contains(#"\frac"#), "\(problem.prompt)")
            #expect(problem.steps.allSatisfy { !$0.contains(#"\frac{\frac"#) }, "\(problem.steps)")
            if problem.prompt.contains(".5$") { halves += 1 }
        }
        #expect(halves > 0, "some prices land on a half")
    }

    @Test("typed answers too big to work with are refused, never trap")
    func hugeTypedAnswers() {
        for text in ["-9223372036854775808", "-9223372036854775808/1", "1/-9223372036854775808", "-922337203685477580.8",
                     "-9,223,372,036,854,775,808", "1 1/9223372036854775807", "1000000000 1/10000000000", "999999999999999 1/999999999999999",
                     "99999999999999999999"] {
            #expect(Rational(parsing: text) == nil, "\(text)")
        }
        #expect(Rational(parsing: "9223372036854775807") == Rational(Int.max))
        #expect(Rational(parsing: "2 1/2") == Rational(5, 2) && Rational(parsing: "-2 1/2") == Rational(-5, 2))
        let question = Question(id: "q", key: .topic("x"), kind: .learn, instruction: "", prompt: .math(""), answer: .number(Rational(3, 4), tolerance: 0),
                                expectedSeconds: 10)
        #expect(!question.check(typed: "-9223372036854775808") && !question.check(typed: "1000000000 1/10000000000"))
        #expect(question.check(typed: "6/8"))
    }
}
