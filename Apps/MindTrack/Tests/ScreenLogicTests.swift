import Foundation
import MindEngine
import SystemCore
import SystemStore
import Testing

@testable import MindTrack

/// Which onboarding pages appear, and the maths strands it saves.
@MainActor
struct OnboardingLogicTests {
    func settings(_ courses: [Domain: CourseMode]) -> MindSettings { MindSettings(courses: courses) }

    @Test func eachFocusCourseGetsItsOwnPage() {
        #expect(OnboardingView.pages(for: MindSettings()) == [.welcome, .courses, .schedule, .languages, .maths, .writing, .reading, .ready])
        #expect(OnboardingView.pages(for: settings([.maths: .focus])) == [.welcome, .courses, .schedule, .maths, .ready])
        // A Maintenance course is reviews only: nothing to set up.
        #expect(
            OnboardingView.pages(for: settings([.reading: .focus, .japanese: .maintenance])) == [.welcome, .courses, .schedule, .reading, .ready])
        #expect(OnboardingView.pages(for: settings([.spanish: .focus])) == [.welcome, .courses, .schedule, .languages, .ready])
        #expect(OnboardingView.pages(for: settings([:])) == [.welcome, .courses, .schedule, .ready])
    }

    @Test func movingStaysWithinTheSetup() {
        let pages = OnboardingView.pages(for: settings([.maths: .focus]))
        #expect(OnboardingView.page(from: .welcome, moving: 1, in: pages) == .courses)
        #expect(OnboardingView.page(from: .schedule, moving: 1, in: pages) == .maths)
        #expect(OnboardingView.page(from: .maths, moving: 1, in: pages) == .ready)
        #expect(OnboardingView.page(from: .ready, moving: 1, in: pages) == .ready)
        #expect(OnboardingView.page(from: .welcome, moving: -1, in: pages) == .welcome)
        // A page whose course was turned off counts from the start.
        #expect(OnboardingView.page(from: .writing, moving: 1, in: pages) == .courses)
    }

    @Test func numeracyStaysFirstAndOn() {
        var settings = MindSettings(mathsStrands: [.numeracy, .classic])
        #expect(MathsChoices.toggled(.numeracy, in: settings) == [.numeracy, .classic], "numeracy can't be switched off")
        #expect(MathsChoices.toggled(.discrete, in: settings) == [.numeracy, .classic, .discrete], "one switched on goes last")
        settings.mathsStrands = [.numeracy, .classic, .discrete]
        #expect(MathsChoices.toggled(.classic, in: settings) == [.numeracy, .discrete])
        #expect(MathsChoices.both(settings))
        #expect(MathsChoices.ordered(first: .discrete) == [.numeracy, .discrete, .classic])
        #expect(MathsChoices.ordered(first: .classic) == [.numeracy, .classic, .discrete])
    }
}

/// The life-mode editor: SystemCore's editing rules over what Settings' menu starts (a period with
/// no end yet), and End today.
@MainActor
struct LifeModeEditorTests {
    let today = Day(year: 2026, month: 10, day: 14)

    func trip(start: Day, end: Day?) -> LifeModePeriod { LifeModePeriod(kind: .vacation, start: start, end: end, createdBy: .knowledge) }

    @Test func aTripStartedFromTheMenuIsSavedForAWeek() throws {
        let model = TestApp.onboardedModel()
        // The menu gives no end; the editor shows a week and saves what it shows, whatever the toggle
        // a trip doesn't have would say.
        var trip = trip(start: model.today, end: nil)
        #expect(trip.editorEnd == model.today.adding(days: 6))
        trip.moveStart(to: model.today.adding(days: 2))
        let saved = trip.edited(openEnded: true)
        #expect(saved.end == model.today.adding(days: 8), "the week follows a moved start")
        #expect(model.save(lifeMode: saved))
        let kept = try #require(model.lifeModes.first { $0.id == trip.id })
        #expect(kept.end == model.today.adding(days: 8))
    }

    @Test func anIllnessStartedFromTheMenuRunsUntilItsBetter() throws {
        let model = TestApp.onboardedModel()
        let ill = LifeModePeriod(kind: .illness(.systemic), start: model.today, createdBy: .knowledge)
        #expect(model.save(lifeMode: ill.edited(openEnded: true)))
        #expect(model.lifeModes.first { $0.id == ill.id }?.end == nil)
        #expect(model.analysis?.phase == .paused(.illness(.systemic)))
        // Switched to a date, it gets the end the picker shows.
        #expect(ill.edited(openEnded: false).end == model.today.adding(days: 6))
    }

    @Test func endingTodayOnlyEndsWhatHasStarted() {
        let started = trip(start: today.adding(days: -3), end: today.adding(days: 4))
        #expect(LifeModeEditor.endedToday(started, today: today)?.end == today)
        #expect(LifeModeEditor.endedToday(trip(start: today, end: today.adding(days: 2)), today: today)?.end == today)
        // A trip next week has nothing to end; ending it today would put the end before the start.
        #expect(LifeModeEditor.endedToday(trip(start: today.adding(days: 7), end: today.adding(days: 9)), today: today) == nil)
    }
}

/// mindtrack:// links from the widget and Shortcuts.
@MainActor
struct DeepLinkTests {
    let start = URL(string: "mindtrack://start")!

    @Test func nothingHappensBeforeSetup() {
        let model = TestApp.model()
        DeepLink.open(start, model: model)
        DeepLink.open(URL(string: "mindtrack://plan")!, model: model)
        #expect(model.run == nil)
        #expect(model.tab == .today)
    }

    @Test func tabsOpenAndUnknownLinksGoToToday() {
        let model = TestApp.onboardedModel()
        DeepLink.open(URL(string: "mindtrack://plan")!, model: model)
        #expect(model.tab == .plan)
        DeepLink.open(URL(string: "mindtrack://progress")!, model: model)
        #expect(model.tab == .progress)
        DeepLink.open(URL(string: "mindtrack://somewhere-new")!, model: model)
        #expect(model.tab == .today)
    }

    @Test func startOpensTodaysSession() throws {
        let model = TestApp.onboardedModel()
        let plan = try #require(model.analysis?.today)
        DeepLink.open(start, model: model)
        let run = try #require(model.run)
        #expect(run.plan.domains == plan.domains)
    }

    @Test func startLeavesASessionInProgressAlone() throws {
        let clock = TestClock()
        let model = TestApp.onboardedModel(clock: clock)
        model.startToday()
        Student.answer(model, steps: 3, clock: clock)
        let session = try #require(model.run).session.id
        let answered = try #require(model.run).answered.count
        DeepLink.open(start, model: model)
        #expect(model.run?.session.id == session)
        #expect(model.run?.answered.count == answered)
    }
}

/// Finding a book: the ladder and earlier lookups answer offline.
@MainActor
struct BookLookupTests {
    @Test func theLadderMatchesTitleAndAuthorWords() throws {
        let model = TestApp.model()
        let book = try #require(model.catalogs.ladder.books(in: nil).first)
        let byTitle = BookLookup.local(book.title, model: model)
        #expect(byTitle.ladder.contains { $0.id == book.id })
        // Any order, any case, words from the title and the author together.
        let lastName = try #require(book.author.components(separatedBy: " ").last)
        let firstWord = try #require(book.title.components(separatedBy: " ").first(where: { $0.count > 2 }))
        let mixed = BookLookup.local("\(lastName.uppercased()) \(firstWord.lowercased())", model: model)
        #expect(mixed.ladder.contains { $0.id == book.id })
        #expect(mixed.ladder.count <= 8)
    }

    @Test func accentsDontMatter() {
        let model = TestApp.model()
        model.save(meta: BookMeta(title: "Cien años de soledad", author: "Gabriel García Márquez", source: "test"))
        #expect(BookLookup.local("garcia marquez", model: model).found.map(\.title) == ["Cien años de soledad"])
        #expect(BookLookup.local("ANOS soledad", model: model).found.count == 1)
    }

    @Test func tooShortAQueryFindsNothing() {
        let model = TestApp.model()
        #expect(BookLookup.local("a", model: model).ladder.isEmpty)
        #expect(BookLookup.local("   ", model: model).ladder.isEmpty)
        #expect(BookLookup.local("zzzzqqqq", model: model).ladder.isEmpty)
    }
}

/// Today's action cards start what the action says, read from its command rather than its id.
@MainActor
struct TodayActionTests {
    @Test func aReviewActionStartsAReviewOfItsLength() throws {
        let model = TestApp.onboardedModel()
        #expect(ActionCard.buttonTitle(.extraReview(minutes: 10)) == "Ten minutes of reviews")
        #expect(ActionCard.buttonTitle(.extraReview(minutes: 5)) == "Five minutes of reviews", "worded like the Study anyway menu's")
        ActionCard.perform(.extraReview(minutes: 10), model: model)
        let run = try #require(model.run)
        #expect(run.plan.kind == .extra)
        #expect(run.plan.minutes == 10)
    }

    @Test func catchingUpStartsTheMissedDomains() throws {
        let model = TestApp.onboardedModel([.maths, .reading])
        ActionCard.perform(.catchUp([.reading]), model: model)
        #expect(try #require(model.run).plan.domains == [.reading])
    }

    @Test func anEpisodeIsLoggedForItsLanguage() {
        let model = TestApp.onboardedModel([.japanese, .spanish])
        ActionCard.perform(.episode(.spanish), model: model)
        #expect(model.episodeLanguage == .spanish)
        #expect(model.run == nil)
    }

    @Test func bookActionsOpenTheShelf() {
        for command in [MindAction.Command.pickBook, .stalledBook] {
            let model = TestApp.onboardedModel([.reading])
            ActionCard.perform(command, model: model)
            #expect(model.showShelf)
            #expect(model.run == nil)
        }
    }
}

/// The Plan tab's language card promises what the sessions' pacing gives.
@MainActor
struct LanguagePlanCardTests {
    @Test func newWordsFollowTheScheduledSessionLength() throws {
        for (minutes, words) in [(15, 9), (25, LanguagePlan.baseNewWords), (50, LanguagePlan.maxNewWords)] {
            let store = TestApp.store()
            var settings = TestApp.settings([.japanese], onboarded: TestApp.wednesday.addingTimeInterval(-86_400))
            settings.schedule.minutes = minutes
            store.save(settings)
            let model = TestApp.model(store: store)
            let state = try #require(model.state)
            let summary = try #require(model.analysis?.languages.first)
            let pace = LanguagePlanCard(summary: summary, state: state).pace
            #expect(pace.count == words, "\(minutes)-minute sessions")
            #expect(pace.reason == nil)
            #expect(pace.dueThisWeek == 0)
        }
    }

    @Test func aReviewWeekPromisesNothingNew() throws {
        // Set up and placed 50 days ago, with no Lift Track calendar: the sixth week after the
        // two-week assessment is a review week.
        let clock = TestClock(TestApp.wednesday.addingTimeInterval(-50 * 86_400))
        let model = TestApp.model(clock: clock)
        model.completeOnboarding(TestApp.settings([.japanese]), booksRead: [])
        Student.answer(model, steps: 400, clock: clock)
        model.endSession()
        clock.now = TestApp.wednesday
        model.refreshDay()
        let state = try #require(model.state)
        try #require(state.phase.isReview)
        let summary = try #require(model.analysis?.languages.first)
        let pace = LanguagePlanCard(summary: summary, state: state).pace
        #expect(pace.count == 0)
        #expect(pace.reason != nil, "the card says why")
        // Nor does the session teach any.
        let plan = try #require(model.analysis?.today)
        #expect(!plan.parts.contains { $0.kind == .learn }, "\(plan.parts.map(\.title))")
    }
}
