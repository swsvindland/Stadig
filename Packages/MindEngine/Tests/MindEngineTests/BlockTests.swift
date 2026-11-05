import Foundation
import SystemCore
import Testing

@testable import MindEngine

@Suite("One-course blocks")
struct BlockTests {
    let monday = Fixtures.monday
    let deck = Fixtures.deck()
    var catalogs: Catalogs { Fixtures.catalogs(deck) }

    /// A person a few weeks in, with cards in two courses, every course placed by a first week of
    /// blocks.
    func placed() -> (store: Store, student: Student, day: Day) {
        var store = Store(settings: Fixtures.settings())
        store.weekSettings = WeekSettings(blocks: [.japanese: 4, .reading: 3, .maths: 2, .writing: 1], since: monday)
        var student = Student(vocabulary: 500, mathsLevel: 4, writingLevel: 4, deck: deck)
        for offset in 0..<14 { store.studyAll(on: monday.adding(days: offset), student: &student, deck: deck) }
        return (store, student, monday.adding(days: 14))
    }

    @Test func aBlockIsOneCourse() {
        let (store, _, day) = placed()
        for domain in [Domain.japanese, .maths, .writing, .reading] {
            let plan = SessionPlanner.block(domain, state: store.state(on: day), catalogs: catalogs)
            #expect(plan.domains == [domain])
            #expect(plan.parts.allSatisfy { $0.domain == domain })
            #expect(plan.planned)
        }
    }

    @Test func aBlockIsAFullBlock() {
        let (store, _, day) = placed()
        let plan = SessionPlanner.block(.japanese, state: store.state(on: day), catalogs: catalogs)
        #expect(plan.minutes == 25)
        #expect(plan.headline == "Japanese · 25 min")
    }

    @Test func aBlocksReviewsAreItsOwnCourses() {
        let (store, _, _) = placed()
        let later = monday.adding(days: 21)
        let state = store.state(on: later)
        #expect(!state.due(on: later, catalogs: catalogs, in: .japanese).isEmpty)
        #expect(!state.due(on: later, catalogs: catalogs, in: .maths).isEmpty)
        let plan = SessionPlanner.block(.japanese, state: state, catalogs: catalogs)
        let part = plan.parts[0]
        #expect(part.kind == .reviews)
        #expect(part.domain == .japanese)
        var run = StudyRun(plan: plan, state: state, catalogs: catalogs, now: state.now)
        var student = Student(vocabulary: 500, mathsLevel: 4, writingLevel: 4, deck: deck)
        _ = student.run(&run, from: state.now)
        #expect(run.changedCards.allSatisfy { $0.domain == .japanese })
    }

    @Test func aWarmUpStaysUnderItsShare() {
        let (store, _, _) = placed()
        let later = monday.adding(days: 40)
        let plan = SessionPlanner.block(.japanese, state: store.state(on: later), catalogs: catalogs)
        #expect((plan.parts.first { $0.kind == .reviews }?.minutes ?? 0) <= 9)
    }

    @Test func readingHasNoReviewsAndKeepsItsOwnLength() {
        let (store, _, day) = placed()
        let plan = SessionPlanner.block(.reading, state: store.state(on: day), catalogs: catalogs)
        #expect(!plan.parts.contains { $0.kind == .reviews })
        #expect(plan.minutes == plan.parts.map(\.minutes).reduce(0, +))
        #expect(plan.headline == "Reading · \(plan.minutes) min")
    }

    @Test func aCoursesFirstBlockIsItsPlacementAlone() {
        var store = Store(settings: Fixtures.settings())
        store.weekSettings = WeekSettings(blocks: [.maths: 2], since: monday)
        let plan = SessionPlanner.block(.maths, state: store.state(on: monday), catalogs: catalogs)
        #expect(plan.kind == .placement)
        #expect(plan.domains == [.maths])
        #expect(plan.parts.allSatisfy { $0.domain == .maths && $0.kind == .placement })
        #expect(plan.minutes == plan.parts.map(\.minutes).reduce(0, +))
    }

    @Test func aLanguagesFirstBlockAlsoTeaches() {
        var store = Store(settings: Fixtures.settings())
        store.weekSettings = WeekSettings(blocks: [.japanese: 2], since: monday)
        let plan = SessionPlanner.block(.japanese, state: store.state(on: monday), catalogs: catalogs)
        #expect(plan.kind == .placement)
        #expect(plan.parts.contains { $0.kind == .learn })
    }

    @Test func aReviewWeekBlockTeachesNothingNew() {
        var (store, _, day) = placed()
        store.calendar = SystemCalendar(currentBlock: nil, deloads: [DayRange(day, day.adding(days: 6))], checkIns: [], publishedBy: .liftTrack)
        let plan = SessionPlanner.block(.japanese, state: store.state(on: day), catalogs: catalogs)
        #expect(plan.kind == .review)
        #expect(!plan.parts.contains { $0.kind == .learn })
    }

    @Test func aQuickReviewOfOneCourseKeepsToIt() {
        let (store, _, _) = placed()
        let later = monday.adding(days: 21)
        let state = store.state(on: later)
        let plan = SessionPlanner.plan(.extra, domains: [.maths], state: state, catalogs: catalogs)
        #expect(plan.parts.first?.domain == .maths)
        var run = StudyRun(plan: plan, state: state, catalogs: catalogs, now: state.now)
        var student = Student(vocabulary: 500, mathsLevel: 4, writingLevel: 4, deck: deck)
        _ = student.run(&run, from: state.now)
        #expect(run.changedCards.allSatisfy { $0.domain == .maths })
    }

    @Test func theFirstBlockOfAllFollowsOnboardingOnAPackedDay() throws {
        var store = Store(settings: Fixtures.settings())
        var week = WeekSettings(blocks: [.japanese: 4], since: monday)
        for part in DayPart.allCases { week.setOverride(false, .monday, part) }
        store.weekSettings = week
        let blocks = WeekPlanner.layout(store.state(on: monday), settings: week).blocks(on: monday)
        #expect(blocks.map(\.domain) == [.japanese])
    }

    @Test func aReviewLimitGrowsWithTheBlocks() {
        var store = Store(settings: Fixtures.settings())
        store.weekSettings = WeekSettings(blocks: [.japanese: 4, .spanish: 1], since: monday)
        let state = store.state(on: monday)
        #expect(LanguagePlan.reviewLimit(.japanese, state: state) > LanguagePlan.reviewLoadLimit)
        #expect(LanguagePlan.reviewLimit(.spanish, state: state) < LanguagePlan.reviewLoadLimit)
        store.weekSettings = nil
        #expect(LanguagePlan.reviewLimit(.japanese, state: store.state(on: monday)) == LanguagePlan.reviewLoadLimit)
    }

    @Test func aSecondBlockTheSameDayAsksDifferentQuestions() {
        let (store, _, day) = placed()
        var next = store
        let state = next.state(on: day)
        let plan = SessionPlanner.block(.maths, state: state, catalogs: catalogs)
        var run = StudyRun(plan: plan, state: state, catalogs: catalogs, now: state.now)
        let first = run.seed
        var student = Student(vocabulary: 500, mathsLevel: 4, writingLevel: 4, deck: deck)
        _ = student.run(&run, from: state.now)
        next.save(run)
        let second = StudyRun(plan: plan, state: next.state(on: day), catalogs: catalogs, now: state.now)
        #expect(second.seed != first)
    }

    /// Twelve weeks of Japanese 4, Reading 4, Maths 2, Writing 1 around a busy week.
    @Test func twelveWeeksOfBlocksKeepWordsComingWithoutABacklog() {
        var store = Store(settings: Fixtures.settings())
        store.commitments = WeekCommitments(days: [
            .monday: [Commitment(title: "Lift", part: .early, minutes: 90), Commitment(title: "BJJ", part: .evening, minutes: 60)],
            .wednesday: [Commitment(title: "Lift", part: .early, minutes: 90), Commitment(title: "BJJ", part: .evening, minutes: 60)],
        ])
        store.weekSettings = WeekSettings(blocks: [.japanese: 4, .reading: 4, .maths: 2, .writing: 1], since: monday)
        var student = Student(vocabulary: 300, mathsLevel: 4, writingLevel: 4, deck: deck)
        var perWeek: [Int] = []
        for week in 0..<12 {
            let before = store.cards.values.filter { $0.domain == .japanese && $0.memory != nil }.count
            for offset in 0..<7 { store.studyAll(on: monday.adding(weeks: week).adding(days: offset), student: &student, deck: deck) }
            perWeek.append(store.cards.values.filter { $0.domain == .japanese && $0.memory != nil }.count - before)
        }
        let end = monday.adding(weeks: 12)
        let state = store.state(on: end)
        #expect(state.due(on: end, catalogs: catalogs, in: .japanese).count < LanguagePlan.reviewLimit(.japanese, state: state))
        // Review weeks teach nothing; the loading weeks never stall.
        let loading = perWeek.filter { $0 > 0 }
        #expect(loading.count >= 8)
        #expect(loading.suffix(4).allSatisfy { $0 >= 16 }, "\(perWeek)")
    }
}

@Suite("Blocks on Today and in Discipline")
struct BlockAnalysisTests {
    let monday = Fixtures.monday
    let deck = Fixtures.deck()
    var catalogs: Catalogs { Fixtures.catalogs(deck) }

    func student() -> Student { Student(vocabulary: 300, mathsLevel: 4, writingLevel: 4, deck: deck) }

    func busy(_ blocks: [Domain: Int] = [.japanese: 4, .reading: 4, .maths: 2, .writing: 1]) -> Store {
        var store = Store(settings: Fixtures.settings())
        store.weekSettings = WeekSettings(blocks: blocks, since: monday)
        store.commitments = WeekCommitments(days: [
            .monday: [Commitment(title: "Lift", part: .early, minutes: 90), Commitment(title: "BJJ", part: .evening, minutes: 60)]
        ])
        return store
    }

    func block(_ domain: Domain, on day: Day, finished: Bool = true) -> StudySession {
        let start = day.at(hour: 19, minute: 0)
        return StudySession(
            purpose: .regular, start: start, end: start.addingTimeInterval(1500), plannedMinutes: 25, domains: [domain], planned: true,
            activeSeconds: finished ? 1500 : 60, ranToEnd: finished)
    }

    @Test func todayListsItsBlocksAndTheFirstOneToDo() {
        var store = busy()
        var student = student()
        for offset in 0..<7 { store.studyAll(on: monday.adding(days: offset), student: &student, deck: deck) }
        let day = monday.adding(days: 8)
        var analysis = Analyst.analyse(store.state(on: day), catalogs: catalogs)
        #expect(analysis.blocks.count >= 2)
        #expect(analysis.today?.domains == [analysis.blocks[0].domain])
        #expect(analysis.blocks == analysis.blocks.sorted { $0.part < $1.part })
        let first = analysis.blocks[0].domain
        store.sessions.append(block(first, on: day))
        analysis = Analyst.analyse(store.state(on: day), catalogs: catalogs)
        #expect(analysis.blocks[0].done && analysis.blocks[0].plan == nil)
        #expect(analysis.today?.domains == [analysis.blocks[1].domain])
    }

    @Test func aPackedDaySaysWhatFillsIt() {
        var store = busy()
        var student = student()
        for offset in 0..<7 { store.studyAll(on: monday.adding(days: offset), student: &student, deck: deck) }
        let packed = monday.adding(weeks: 1)
        let analysis = Analyst.analyse(store.state(on: packed), catalogs: catalogs)
        #expect(analysis.blocks.isEmpty)
        #expect(analysis.today == nil)
        #expect(analysis.commitments.map(\.title) == ["Lift", "BJJ"])
        #expect(analysis.week[0].status == .rest)
    }

    @Test func thereIsNoSuchThingAsAMissedDay() {
        let store = busy()
        let analysis = Analyst.analyse(store.state(on: monday.adding(days: 3)), catalogs: catalogs)
        // Nothing happened on Monday, Tuesday or Wednesday, and it says nothing about it.
        #expect(analysis.week.prefix(3).allSatisfy { $0.status == .rest })
        #expect(analysis.blocks.count + analysis.layout.blocks.filter { $0.day > monday.adding(days: 3) }.count == 11)
    }

    @Test func aQuestForEachBlockInItsPartOfTheDay() {
        var store = busy()
        var student = student()
        for offset in 0..<7 { store.studyAll(on: monday.adding(days: offset), student: &student, deck: deck) }
        let day = monday.adding(days: 8)
        let analysis = Analyst.analyse(store.state(on: day), catalogs: catalogs)
        let quests = analysis.quests.filter { $0.id.hasPrefix("mind.block.") }
        #expect(quests.count == analysis.blocks.count)
        #expect(Set(quests.map(\.timeOfDay)) == Set(analysis.blocks.map { Optional($0.part.timeOfDay) }))
    }

    // MARK: Discipline

    /// Twenty sessions out of twenty under the old rule must not read as 20 of 64 the day blocks begin.
    @Test func theDayBlocksBeginChangesNoScore() {
        let settings = Fixtures.settings()
        var store = Store(settings: settings)
        let upgrade = monday.adding(days: 28)
        // Every old study day (five a week) had its one mixed session, all before blocks began.
        for offset in 0..<28 where settings.schedule.studyDays.contains(monday.adding(days: offset).weekday) {
            let start = monday.adding(days: offset).at(hour: 19, minute: 0)
            store.sessions.append(
                StudySession(
                    purpose: .regular, start: start, end: start.addingTimeInterval(1500), plannedMinutes: 25, domains: [.japanese, .maths],
                    planned: true, activeSeconds: 1500, ranToEnd: true))
        }
        store.weekSettings = WeekSettings.seeded(from: settings, since: upgrade, now: upgrade.date())
        let score = Analyst.discipline(store.state(on: upgrade))
        // Four weeks of old study days, less the Monday the window has just passed.
        #expect(score.planned == 19)
        #expect(score.completed == 19)
        #expect(score.rate == 1)
    }

    @Test func aWeekOfEveryBlockDoneIsAFullScore() {
        var store = busy()
        var student = student()
        for offset in 0..<14 { store.studyAll(on: monday.adding(days: offset), student: &student, deck: deck) }
        let score = Analyst.discipline(store.state(on: monday.adding(days: 14)))
        #expect(score.rate == 1)
        #expect(score.planned >= 20)
    }

    @Test func aMissedBlockCountsOnlyOnceTheWeekIsOver() {
        var store = busy([.japanese: 2])
        store.sessions = [block(.japanese, on: monday)]
        // Midweek, one done and one still to come: nothing's been missed.
        #expect(Analyst.discipline(store.state(on: monday.adding(days: 3))).rate == 1)
        // The week over, one of two.
        let score = Analyst.discipline(store.state(on: monday.adding(days: 8)))
        #expect(score.planned == 2)
        #expect(score.completed == 1)
    }

    @Test func aPartSessionDoesntCount() {
        var store = busy([.japanese: 1])
        store.sessions = [block(.japanese, on: monday, finished: false)]
        #expect(Analyst.discipline(store.state(on: monday.adding(days: 8))).completed == 0)
    }

    @Test func extraBlocksOfACourseDontMakeUpForAnother() {
        var store = busy([.japanese: 1, .maths: 1])
        store.sessions = [block(.japanese, on: monday), block(.japanese, on: monday.adding(days: 1))]
        let score = Analyst.discipline(store.state(on: monday.adding(days: 8)))
        #expect(score.planned == 2)
        #expect(score.completed == 1)
    }

    @Test func aPastWeeksTargetDoesntMoveWhenTheCountsChange() {
        var store = busy([.japanese: 2])
        store.weekSettings?.record(WeekTarget(total: 2, counts: [.japanese: 2], days: 7), for: monday)
        store.weekSettings?.setBlocks(7, for: .japanese)
        store.sessions = [block(.japanese, on: monday)]
        #expect(Analyst.discipline(store.state(on: monday.adding(days: 8))).planned == 2)
    }

    @Test func turningACourseDownDoesntRescoreItsWeeks() {
        var store = busy([.japanese: 2])
        store.weekSettings?.record(WeekTarget(total: 2, counts: [.japanese: 2], days: 7), for: monday)
        store.sessions = [block(.japanese, on: monday), block(.japanese, on: monday.adding(days: 1))]
        store.weekSettings?.setBlocks(0, for: .japanese)
        let score = Analyst.discipline(store.state(on: monday.adding(days: 8)))
        #expect(score.planned == 2)
        #expect(score.completed == 2)
    }

    /// A lagging course's extra block is in what the week kept, so doing it all is a full score.
    @Test func aWeekWithALaggingCoursesExtraBlockDoneIsFull() {
        var store = busy([.japanese: 1])
        store.weekSettings?.record(WeekTarget(total: 2, counts: [.japanese: 2], days: 7), for: monday)
        store.sessions = [block(.japanese, on: monday), block(.japanese, on: monday.adding(days: 1))]
        let score = Analyst.discipline(store.state(on: monday.adding(days: 8)))
        #expect(score.planned == 2)
        #expect(score.completed == 2)
    }

    /// Illness entered on Monday for the back half of last week.
    @Test func aPauseEnteredAfterwardsTakesItsShareOffTheWeek() {
        var store = busy([.japanese: 7])
        store.weekSettings?.record(WeekTarget(total: 7, counts: [.japanese: 7], days: 7), for: monday)
        for offset in 0..<3 { store.sessions.append(block(.japanese, on: monday.adding(days: offset))) }
        store.lifeModes = [
            LifeModePeriod(kind: .vacation, start: monday.adding(days: 3), end: monday.adding(days: 6), createdBy: .knowledge)
        ]
        let score = Analyst.discipline(store.state(on: monday.adding(days: 8)))
        #expect(score.planned == 3)
        #expect(score.completed == 3)
    }

    @Test func aSickSundayDoesntEraseTheWeeksMisses() {
        var store = busy([.japanese: 3])
        store.lifeModes = [
            LifeModePeriod(kind: .illness(.systemic), start: monday.adding(days: 6), end: monday.adding(days: 6), createdBy: .knowledge)
        ]
        let score = Analyst.discipline(store.state(on: monday.adding(days: 8)))
        #expect(score.planned == 3)
        #expect(score.completed == 0)
    }

    @Test func pausedDaysLeaveTheWeekShorterNotMissed() {
        var store = busy([.japanese: 7])
        store.lifeModes = [LifeModePeriod(kind: .crunch(CrunchDials()), start: monday, end: monday.adding(days: 6), createdBy: .knowledge)]
        #expect(Analyst.discipline(store.state(on: monday.adding(days: 8))).planned == 0)
    }

    // MARK: Check-ins and reviews-only courses

    func checkInDay(_ store: inout Store) -> Day {
        // The last days of the first review week (days 49–55).
        monday.adding(days: 54)
    }

    @Test func eachCourseGetsItsOwnCheckIn() {
        var store = busy()
        var student = student()
        for offset in 0..<54 { store.studyAll(on: monday.adding(days: offset), student: &student, deck: deck) }
        let day = checkInDay(&store)
        let checkIns = SessionPlanner.checkIns(store.state(on: day), catalogs: catalogs)
        #expect(checkIns.count >= 3)
        #expect(checkIns.allSatisfy { $0.kind == .checkIn && $0.domains.count == 1 && !$0.parts.isEmpty })
        // Today lists them by name, so no two read alike.
        #expect(Set(checkIns.map(\.headline)).count == checkIns.count)
        #expect(checkIns.allSatisfy { $0.headline.hasPrefix($0.domains[0].label) })
    }

    @Test func aCheckInStartedAndEndedAtOnceDoesntUseItUp() {
        var store = busy()
        var student = student()
        for offset in 0..<54 { store.studyAll(on: monday.adding(days: offset), student: &student, deck: deck) }
        let day = checkInDay(&store)
        let start = day.at(hour: 9, minute: 0)
        store.sessions.append(
            StudySession(purpose: .checkIn, start: start, end: start.addingTimeInterval(5), plannedMinutes: 16, domains: [.japanese], planned: true))
        #expect(SessionPlanner.checkIns(store.state(on: day), catalogs: catalogs).contains { $0.domains == [.japanese] })
    }

    @Test func aReviewsOnlyCourseGetsItsOwnShortReview() throws {
        var store = busy([.japanese: 4, .maths: 2])
        var student = student()
        for offset in 0..<14 { store.studyAll(on: monday.adding(days: offset), student: &student, deck: deck) }
        store.weekSettings?.setBlocks(0, for: .japanese)
        var day = monday.adding(days: 14)
        var plan: SessionPlan?
        for _ in 0..<30 where plan == nil {
            plan = SessionPlanner.reviewsOnly(store.state(on: day), catalogs: catalogs).first { $0.domains == [.japanese] }
            day = day.adding(days: 1)
        }
        let review = try #require(plan)
        #expect(review.kind == .extra)
        #expect(!review.planned)
        #expect(review.headline.hasPrefix("Japanese reviews"))
        #expect(review.parts.allSatisfy { $0.domain == .japanese })
    }

    @Test func aReviewsOnlyCourseWithNothingLearnedPlacesThere() {
        var store = Store(settings: Fixtures.settings([.japanese], maintenance: [.maths]))
        store.weekSettings = WeekSettings(blocks: [.japanese: 4], since: monday)
        let plans = SessionPlanner.reviewsOnly(store.state(on: monday), catalogs: catalogs)
        #expect(plans.map(\.kind) == [.placement])
        #expect(plans.map(\.domains) == [[.maths]])
        #expect(plans.allSatisfy { !$0.planned })
    }

    // MARK: Conversations

    @Test func aConversationCountsAsABlockAndMovesNoStat() {
        var store = busy([.japanese: 2])
        store.sessions = [StudySession.conversation(.japanese, at: monday.at(hour: 8, minute: 30))]
        let week = WeekPlanner.layout(store.state(on: monday.adding(days: 1)), settings: store.weekSettings!)
        #expect(week.done[.japanese] == 1)
        #expect(week.blocks.filter { !$0.done }.count == 1)
        #expect(store.tests.isEmpty)
    }
}
