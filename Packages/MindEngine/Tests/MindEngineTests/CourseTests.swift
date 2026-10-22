import Foundation
import SystemCore
import Testing

@testable import MindEngine

@Suite("Courses")
struct CourseTests {
    let monday = Fixtures.monday

    @Test("settings saved before courses read back with every subject as a Focus course and defaults for the rest")
    func oldSettings() throws {
        let json =
            #"{"id":"00000000-0000-0000-0000-00000000317D","domains":["japanese","maths","reading"],"schedule":{"daysPerWeek":4,"minutes":25,"preferredDays":[]},"readsKana":true,"mathsBackground":"calculus","genres":["fantasy"],"autoPrioritise":true,"reminders":false,"updatedAt":0}"#
        let settings = try JSONDecoder().decode(MindSettings.self, from: Data(json.utf8))
        #expect(settings.courses == [.japanese: .focus, .maths: .focus, .reading: .focus])
        #expect(settings.schedule.daysPerWeek == 4 && settings.mathsBackground == .calculus)
        #expect(settings.writingKinds == [.creative] && settings.mathsStrands == MathsStrand.allCases && settings.speaking)
        let again = try JSONDecoder().decode(MindSettings.self, from: JSONEncoder().encode(settings))
        #expect(again == settings)
    }

    @Test("the load check: the default four fit five days; more heavy courses than three, or more sessions than days, get a warning")
    func load() {
        var settings = Fixtures.settings([.japanese, .maths, .writing, .reading])
        #expect(CourseLoad.check(settings).warning == nil, "\(CourseLoad.check(settings))")
        settings.courses[.spanish] = .focus
        #expect(CourseLoad.check(settings).warning?.contains("Secondary") == true, "six sessions on five days")
        settings.courses[.spanish] = .secondary
        #expect(CourseLoad.check(settings).warning == nil, "a Secondary course takes no days")
        settings.courses[.spanish] = .maintenance
        #expect(CourseLoad.check(settings).warning == nil)
        settings.schedule = StudySchedule(daysPerWeek: 3)
        let check = CourseLoad.check(settings)
        #expect(check.sessionsNeeded == 4 && check.sessionsAvailable == 3 && check.warning != nil)
    }

    @Test("the load check: Secondary courses share one block a session, so each wants two of the week's days")
    func secondaryLoad() {
        var settings = Fixtures.settings([.japanese, .reading])
        settings.courses[.maths] = .secondary
        settings.courses[.writing] = .secondary
        #expect(CourseLoad.check(settings).warning == nil, "two Secondary courses on five days: two or three blocks each")
        settings.courses[.spanish] = .secondary
        let warning = CourseLoad.check(settings).warning
        #expect(warning?.contains("3 Secondary courses") == true && warning?.contains("1.7 times") == true, "\(warning ?? "")")
        settings.courses[.spanish] = nil
        settings.schedule = StudySchedule(daysPerWeek: 3)
        #expect(CourseLoad.check(settings).warning?.contains("Secondary") == true, "three days for three Main days and two Secondary")
    }

    @Test("Maintenance courses stay out of the split but their reviews ride in the warm-up")
    func maintenance() throws {
        let settings = Fixtures.settings([.japanese, .maths, .reading], maintenance: [.spanish])
        let week = Split.week(starting: monday, settings: settings)
        #expect(!week.values.contains { $0.contains(.spanish) })
        #expect(week.values.filter { $0 == [.japanese] }.count >= 2)

        var store = Store(settings: settings)
        let now = monday.date()
        var memory = Scheduler.known(stability: 2, at: now.addingTimeInterval(-3 * 86_400))
        memory.due = now
        let spanish = MemoryCard(key: .word(42, .spanish), memory: memory, introduced: now)
        store.cards[spanish.key] = spanish
        store.sessions = [
            StudySession(
                purpose: .placement, start: now, end: now, plannedMinutes: 25, domains: [.japanese], planned: true,
                ranToEnd: true)
        ]
        store.tests = [
            TestResult(test: .vocabulary, date: now, score: 300, language: .japanese),
            TestResult(test: .mathsPlacement, date: now, score: 4),
        ]
        let state = store.state(on: monday.adding(days: 2))
        #expect(state.due(on: state.today).contains { $0.key == spanish.key }, "Maintenance reviews are due like any others")
        #expect(!state.needsPlacement(.spanish, catalogs: Catalogs()), "a Maintenance language never places: its test cards nothing")
    }

    @Test("a Maintenance course with nothing learned is placed once, one a session, and what it found comes back as reviews")
    func maintenanceFromNothing() throws {
        let deck = Fixtures.deck()
        let settings = Fixtures.settings([.japanese, .reading], maintenance: [.maths, .writing], readsKana: false)
        let fresh = try #require(SessionPlanner.today(Store(settings: settings).state(on: monday), catalogs: Fixtures.catalogs(deck)))
        #expect(
            Set(fresh.parts.filter { $0.kind == .placement }.compactMap(\.domain)) == [.maths, .writing, .reading], "a first session places them")

        // Someone a week in when they went to Maintenance: placed in the next sessions.
        var store = Store(settings: Fixtures.settings([.japanese, .reading], readsKana: false))
        var student = Student(vocabulary: 0, mathsLevel: 5, writingLevel: 2, deck: deck)
        for offset in 0..<7 { store.study(on: monday.adding(days: offset), student: &student, deck: deck) }
        store.settings = settings
        var placed: [Domain] = []
        for offset in 7..<28 {
            guard let run = store.study(on: monday.adding(days: offset), student: &student, deck: deck) else { continue }
            let placements = run.plan.parts.filter { $0.kind == .placement }.compactMap(\.domain)
            #expect(placements.count <= 1, "one a session: \(placements)")
            #expect(!run.plan.domains.contains(.maths) && !run.plan.domains.contains(.writing), "no block of their own")
            placed += placements
        }
        #expect(placed == [.maths, .writing])
        let reviews = store.sessions.flatMap(\.attempts).filter { $0.kind == .review }
        #expect(reviews.contains { $0.key.domain == .maths } && reviews.contains { $0.key.domain == .writing })
    }

    @Test("Secondary courses have no days: they take turns at a short block after the day's Main course, placed first")
    func secondary() throws {
        let deck = Fixtures.deck()
        var settings = Fixtures.settings([.japanese, .reading])
        settings.courses[.maths] = .secondary
        settings.courses[.writing] = .secondary
        let week = Split.week(starting: monday, settings: settings)
        #expect(week.values.allSatisfy { $0 == [.japanese] || $0 == [.reading] }, "\(week)")

        var store = Store(settings: settings)
        var student = Student(vocabulary: 400, mathsLevel: 4, writingLevel: 2, deck: deck)
        let first = try #require(store.study(on: monday, student: &student, deck: deck))
        #expect(first.plan.kind == .placement)
        #expect(Set(first.plan.parts.filter { $0.kind == .placement }.compactMap(\.domain)) == [.japanese, .maths, .writing, .reading])
        var blocks: [Domain] = []
        for offset in 1..<15 {
            guard let run = store.study(on: monday.adding(days: offset), student: &student, deck: deck), run.plan.kind == .regular else {
                continue
            }
            let secondary = run.plan.domains.filter { settings.mode($0) == .secondary }
            #expect(secondary.count == 1, "one Secondary block a session: \(run.plan.domains)")
            guard let course = secondary.first else { continue }
            blocks.append(course)
            let block = run.plan.parts.filter { $0.domain == course }
            let minutes = block.map(\.minutes).reduce(0, +)
            // The first writing is the term's benchmark piece, whatever the slot.
            #expect((5...9).contains(minutes) || block.contains { $0.kind == .test(.writingBenchmark) }, "\(course): \(block)")
            #expect(run.plan.parts.last?.domain == course, "the block comes after the Main course")
            #expect(run.plan.headline.hasPrefix(run.plan.domains[0].label) && run.plan.headline.contains(course.label))
        }
        #expect(blocks.count >= 8)
        #expect(zip(blocks, blocks.dropFirst()).allSatisfy { $0 != $1 }, "they take turns: \(blocks)")
        let learned = store.cards.values.filter { $0.domain == .maths && $0.memory != nil && !$0.knownBefore }
        #expect(!learned.isEmpty, "maths keeps moving in its blocks")
    }

    @Test("a Secondary language learns new words paced for its block, not a whole session")
    func secondaryLanguage() {
        let deck = Fixtures.deck()
        var settings = Fixtures.settings([.reading])
        settings.courses[.japanese] = .secondary
        var store = Store(settings: settings)
        store.tests = [TestResult(test: .vocabulary, date: monday.date(), score: 300, language: .japanese)]
        let state = store.state(on: monday.adding(days: 1))
        var notes: [String] = []
        let block = LanguageModule.mainParts(.japanese, minutes: 7, kind: .regular, state: state, catalogs: Fixtures.catalogs(deck), notes: &notes)
        let learn = block.first { $0.kind == .learn }
        #expect(learn.map { $0.items <= 5 } == true, "\(block)")
        settings.courses[.japanese] = .focus
        store.settings = settings
        let main = LanguageModule.mainParts(
            .japanese, minutes: 20, kind: .regular, state: store.state(on: monday.adding(days: 1)), catalogs: Fixtures.catalogs(deck),
            notes: &notes)
        #expect(main.first { $0.kind == .learn }?.items == LanguagePlan.baseNewWords)
    }

    @Test("Secondary is saved by name and read back; Main keeps the name Focus had")
    func secondarySaved() throws {
        var settings = Fixtures.settings([.japanese, .reading])
        settings.courses[.maths] = .secondary
        let written = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any]
        #expect(written?["courses"] as? [String: String] == ["japanese": "focus", "reading": "focus", "maths": "secondary"])
        #expect(try JSONDecoder().decode(MindSettings.self, from: JSONEncoder().encode(settings)) == settings)
        #expect(settings.focus == [.japanese, .reading] && settings.secondary == [.maths] && settings.studied == [.japanese, .maths, .reading])
    }

    @Test("two Focus languages each get days of their own, never back to back")
    func twoLanguages() {
        let settings = Fixtures.settings([.japanese, .spanish, .maths, .reading], days: 6)
        let week = Split.week(starting: monday, settings: settings)
        let groups = week.keys.sorted().map { week[$0]! }
        #expect(groups.filter { $0 == [.japanese] }.count >= 2 && groups.filter { $0 == [.spanish] }.count >= 1)
        #expect(zip(groups, groups.dropFirst()).allSatisfy { $0 != $1 }, "\(groups)")
    }

    @Test("card keys know their language, and a language's results count only for it")
    func languageKeys() {
        #expect(CardKey.word(7, .spanish).raw == "es.word.7")
        #expect(CardKey.word(7, .spanish).domain == .spanish && CardKey.word(7, .spanish).wordID == 7)
        #expect(CardKey.word(7).domain == .japanese && CardKey.kana("あ").language == .japanese)
        #expect(CardKey.practice(.spanish, "sentences").domain == .spanish && CardKey.practice(.spanish, "sentences").wordID == nil)
        #expect(CardKey.topic("limits").language == nil)
        let old = TestResult(test: .vocabulary, date: Date(), score: 900)
        #expect(old.domain == .japanese, "results saved before languages were tagged are Japanese")
        let spanish = TestResult(test: .vocabulary, date: Date(), score: 400, language: .spanish)
        #expect(LanguagePlan.frontier([old, spanish], .spanish) == 400 && LanguagePlan.frontier([old, spanish], .japanese) == 900)
    }

    @Test("a Spanish course without its catalog plans nothing new, and asks for no placement it can't give")
    func missingCatalog() {
        var store = Store(settings: Fixtures.settings([.spanish, .maths]))
        store.tests = [TestResult(test: .mathsPlacement, date: monday.date(), score: 4)]
        store.sessions = [
            StudySession(
                purpose: .placement, start: monday.date(), end: monday.date(), plannedMinutes: 25, domains: [.maths],
                planned: true, ranToEnd: true)
        ]
        let state = store.state(on: monday.adding(days: 1))
        #expect(!state.needsPlacement(.spanish, catalogs: Catalogs()))
        let plan = SessionPlanner.plan(.regular, domains: [.spanish], state: state, catalogs: Catalogs())
        #expect(plan.parts.first { $0.kind == .learn }?.detail.contains("isn't installed") == true)
    }
}

extension CourseTests {
    @Test("settings from a newer version decode: unknown courses, strands, kinds and genres are kept aside and written back")
    func newerSettings() throws {
        let json =
            #"{"id":"00000000-0000-0000-0000-00000000317D","courses":{"japanese":"focus","piano":"focus","maths":"paused","reading":"maintenance"},"schedule":{"daysPerWeek":4,"minutes":25,"preferredDays":[]},"mathsStrands":["numeracy","geometry","classic"],"writingKinds":["poetry","practical"],"genres":["fantasy","romance"],"updatedAt":0}"#
        let settings = try JSONDecoder().decode(MindSettings.self, from: Data(json.utf8))
        #expect(settings.courses == [.japanese: .focus, .reading: .maintenance])
        #expect(settings.mathsStrands == [.numeracy, .classic] && settings.writingKinds == [.practical] && settings.genres == [.fantasy])

        // Saving here (after a change) keeps what this version can't read.
        var edited = settings
        edited.speaking = false
        let written = try JSONSerialization.jsonObject(with: JSONEncoder().encode(edited)) as? [String: Any]
        let courses = try #require(written?["courses"] as? [String: String])
        #expect(courses == ["japanese": "focus", "piano": "focus", "maths": "paused", "reading": "maintenance"])
        #expect(written?["mathsStrands"] as? [String] == ["numeracy", "classic", "geometry"])
        #expect(written?["writingKinds"] as? [String] == ["practical", "poetry"])
        #expect(written?["genres"] as? [String] == ["fantasy", "romance"])
        let again = try JSONDecoder().decode(MindSettings.self, from: JSONEncoder().encode(edited))
        #expect(again == edited)
    }

    @Test("a first-version record with a subject listed twice migrates instead of trapping")
    func duplicateOldDomains() throws {
        let json = #"{"domains":["japanese","maths","japanese","piano"],"updatedAt":0}"#
        let settings = try JSONDecoder().decode(MindSettings.self, from: Data(json.utf8))
        #expect(settings.courses == [.japanese: .focus, .maths: .focus])
    }

    @Test("a session from a newer version keeps the courses this version knows")
    func newerSession() throws {
        let session = StudySession(
            purpose: .regular, start: monday.date(), end: monday.date() + 1500, plannedMinutes: 25, domains: [.japanese, .maths],
            planned: true, activeSeconds: 1500, ranToEnd: true, updatedAt: monday.date())
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any])
        #expect(try JSONDecoder().decode(StudySession.self, from: JSONEncoder().encode(session)) == session)
        object["domains"] = ["japanese", "piano", "maths"]
        let decoded = try JSONDecoder().decode(StudySession.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.domains == [.japanese, .maths] && decoded.counts && decoded.id == session.id)
    }

    @Test("a schedule change keeps the old one for the days before it, and settings without one read back with none")
    func scheduleHistory() throws {
        var settings = Fixtures.settings(days: 3)
        let change = monday.adding(days: 30)
        settings.schedule = StudySchedule(daysPerWeek: 4)
        settings.recordScheduleChange(from: StudySchedule(daysPerWeek: 3), on: change)
        // A second change the same day: the days before still had three.
        settings.schedule = StudySchedule(daysPerWeek: 5)
        settings.recordScheduleChange(from: StudySchedule(daysPerWeek: 4), on: change)
        #expect(settings.earlierSchedules == [MindSettings.EarlierSchedule(until: change, schedule: StudySchedule(daysPerWeek: 3))])
        #expect(settings.schedule(on: change.adding(days: -1)).daysPerWeek == 3 && settings.schedule(on: change).daysPerWeek == 5)
        let again = try JSONDecoder().decode(MindSettings.self, from: JSONEncoder().encode(settings))
        #expect(again == settings)

        // Long-gone changes are dropped as new ones come.
        settings.schedule = StudySchedule(daysPerWeek: 6)
        settings.recordScheduleChange(from: StudySchedule(daysPerWeek: 5), on: change.adding(days: 60))
        #expect(settings.earlierSchedules.map(\.until) == [change.adding(days: 60)])

        let old = #"{"courses":{"japanese":"focus"},"schedule":{"daysPerWeek":4,"minutes":25,"preferredDays":[]},"updatedAt":0}"#
        let decoded = try JSONDecoder().decode(MindSettings.self, from: Data(old.utf8))
        #expect(decoded.earlierSchedules.isEmpty && decoded.schedule(on: monday).daysPerWeek == 4)
    }
}
