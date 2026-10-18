import Foundation
import Testing
import SystemCore
@testable import MindEngine

@Suite("Courses")
struct CourseTests {
    let monday = Fixtures.monday

    @Test("settings saved before courses read back with every subject as a Focus course and defaults for the rest")
    func oldSettings() throws {
        let json = #"{"id":"00000000-0000-0000-0000-00000000317D","domains":["japanese","maths","reading"],"schedule":{"daysPerWeek":4,"minutes":25,"preferredDays":[]},"readsKana":true,"mathsBackground":"calculus","genres":["fantasy"],"autoPrioritise":true,"reminders":false,"updatedAt":0}"#
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
        #expect(CourseLoad.check(settings).warning?.contains("Maintenance") == true, "six sessions on five days")
        settings.courses[.spanish] = .maintenance
        #expect(CourseLoad.check(settings).warning == nil)
        settings.schedule = StudySchedule(daysPerWeek: 3)
        let check = CourseLoad.check(settings)
        #expect(check.sessionsNeeded == 4 && check.sessionsAvailable == 3 && check.warning != nil)
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
        store.sessions = [StudySession(purpose: .placement, start: now, end: now, plannedMinutes: 25, domains: [.japanese], planned: true,
                                       ranToEnd: true)]
        store.tests = [TestResult(test: .vocabulary, date: now, score: 300, language: .japanese),
                       TestResult(test: .mathsPlacement, date: now, score: 4)]
        let state = store.state(on: monday.adding(days: 2))
        #expect(state.due(on: state.today).contains { $0.key == spanish.key }, "Maintenance reviews are due like any others")
        #expect(!state.needsPlacement(.spanish, catalogs: Catalogs()), "Maintenance courses never place")
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
        store.sessions = [StudySession(purpose: .placement, start: monday.date(), end: monday.date(), plannedMinutes: 25, domains: [.maths],
                                       planned: true, ranToEnd: true)]
        let state = store.state(on: monday.adding(days: 1))
        #expect(!state.needsPlacement(.spanish, catalogs: Catalogs()))
        let plan = SessionPlanner.plan(.regular, domains: [.spanish], state: state, catalogs: Catalogs())
        #expect(plan.parts.first { $0.kind == .learn }?.detail.contains("isn't installed") == true)
    }
}
