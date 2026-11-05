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

    @Test("a reviews-only course has no blocks, and its reviews come due like any others")
    func maintenance() throws {
        let settings = Fixtures.settings([.japanese, .maths, .reading], maintenance: [.spanish])
        var store = Store(settings: settings)
        let layout = WeekPlanner.layout(store.state(on: monday), settings: store.state(on: monday).week)
        #expect(!layout.blocks.contains { $0.domain == .spanish })
        #expect(layout.blocks.filter { $0.domain == .japanese }.count >= 2)

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

    @Test("tiers are saved by name and read back, for older builds; Main keeps the name Focus had")
    func secondarySaved() throws {
        var settings = Fixtures.settings([.japanese, .reading])
        settings.courses[.maths] = .secondary
        let written = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any]
        #expect(written?["courses"] as? [String: String] == ["japanese": "focus", "reading": "focus", "maths": "secondary"])
        #expect(try JSONDecoder().decode(MindSettings.self, from: JSONEncoder().encode(settings)) == settings)
        #expect(settings.studied == [.japanese, .maths, .reading])
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
        let plan = SessionPlanner.block(.spanish, state: state, catalogs: Catalogs())
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
