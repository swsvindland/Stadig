import Foundation
import MindEngine
import SystemCore
import SystemStore
import Testing

@testable import MindTrack

/// The app model over an in-memory store and a temporary shared container: setup, a session from
/// start to stored history, books and settings, and what survives a relaunch.
@MainActor
struct AppModelTests {
    @Test func aFreshModelIsNotOnboarded() {
        let model = TestApp.model()
        #expect(!model.onboarded)
        #expect(model.settings == nil)
        #expect(model.analysis == nil)
        #expect(model.state == nil)
        #expect(model.run == nil)
        #expect(model.today == Day(TestApp.wednesday))
    }

    /// Days start at 4 a.m.: half past midnight on Thursday is still Wednesday, a session then is
    /// Wednesday's, and Thursday begins at 4. With days starting at midnight it's Thursday's.
    @Test func aSessionAfterMidnightCountsForTheEvening() throws {
        let wednesday = Day(year: 2026, month: 10, day: 14)
        let clock = TestClock(wednesday.adding(days: 1).at(hour: 0, minute: 30))
        let model = TestApp.onboardedModel(clock: clock)
        #expect(model.dayStart == MindSettings.standardDayStart)
        #expect(model.today == wednesday)
        model.startToday()
        Student.answer(model, steps: 12, clock: clock)
        model.endSession()
        let session = try #require(model.sessions.last)
        #expect(session.day(startingAt: model.dayStart) == wednesday)
        #expect(model.analysis?.doneToday.map(\.id) == [session.id])

        clock.advance(4 * 3600)
        model.refreshDay()
        #expect(model.today == wednesday.adding(days: 1))
        #expect(model.analysis?.doneToday.isEmpty == true, "Thursday's own session hasn't happened")

        var settings = try #require(model.settings)
        settings.dayStart = 0
        model.save(settings: settings)
        #expect(model.today == wednesday.adding(days: 1))
        #expect(model.analysis?.doneToday.map(\.id) == [session.id], "by the calendar it was Thursday's")
    }

    @Test func theAppAsLaunchedForTestsKeepsNothing() {
        // The unit-test host counts as a test launch: memory only, a shared folder of its own.
        let launch = LaunchOptions(arguments: ["MindTrack"], environment: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"])
        #expect(launch.usesInMemoryStore && launch.isQuiet)
        let model = AppModel(launch: launch)
        #expect(model.store.syncStatus == "Memory only")
        #expect(!model.shared.isAppGroup, "never the App Group the other apps read")
        #expect(model.shared.directory.path(percentEncoded: false).hasPrefix(URL.temporaryDirectory.path(percentEncoded: false)))
        #expect(!AppModel.shared.shared.isAppGroup, "the test host's own model is a test one too")
        #expect(AppModel.shared.store.syncStatus == "Memory only")
        #expect(model.arrival == nil, "nothing kept, so nothing coming from iCloud to wait for")
    }

    @Test func simulatedICloudDataWaitsUntilSetUpAsNew() async throws {
        let launch = LaunchOptions(
            arguments: ["MindTrack", "-simulateICloudData"], environment: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"])
        let model = AppModel(launch: launch)
        let arrival = try #require(model.arrival)
        for _ in 0..<200 where arrival.phase == .looking {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(arrival.phase == .arriving)
        #expect(arrival.isWaiting)
        arrival.setUpAsNew()
        #expect(!arrival.isWaiting)
    }

    @Test func onboardingSavesTheSetupAndStartsTheFirstSession() throws {
        let clock = TestClock()
        let store = TestApp.store()
        let model = TestApp.model(store: store, clock: clock)
        let book = Book(title: "The Hobbit", author: "J. R. R. Tolkien", tier: 4, pages: 310, genres: [.fantasy], status: .readBefore)
        model.completeOnboarding(TestApp.settings([.maths, .reading]), booksRead: [book])

        #expect(model.onboarded)
        #expect(model.settings?.onboardedAt == clock.now)
        #expect(model.settings?.studied == [.maths, .reading])
        #expect(model.books.map(\.title) == ["The Hobbit"])
        let analysis = try #require(model.analysis)
        #expect(analysis.phase.isAssessment, "the first two weeks find the level")
        // The onboarding is the first session.
        let run = try #require(model.run)
        #expect(run.step != nil)

        // What was set up is there after a relaunch.
        let relaunched = TestApp.model(store: store, clock: clock)
        #expect(relaunched.onboarded)
        #expect(relaunched.settings?.studied == [.maths, .reading])
        #expect(relaunched.books.count == 1)
    }

    @Test func onboardingKeepsASetupThatArrivedFromAnotherDevice() throws {
        let clock = TestClock()
        let store = TestApp.store()
        let model = TestApp.model(store: store, clock: clock)
        #expect(!model.onboarded)
        // iCloud brings this person's setup from their iPad while onboarding is on screen here.
        let started = clock.now.addingTimeInterval(-20 * 86_400)
        store.save(TestApp.settings([.writing], onboarded: started))

        model.completeOnboarding(
            TestApp.settings([.maths, .japanese]),
            booksRead: [
                Book(title: "Dune", author: "Frank Herbert", tier: 6, pages: 600, genres: [.sciFi], status: .readBefore)
            ])

        let settings = try #require(model.settings)
        #expect(settings.onboardedAt == started, "the program keeps its start: the assessment isn't run again")
        #expect(settings.studied == [.writing])
        #expect(model.books.isEmpty, "onboarding's books aren't added on top of the synced setup")
    }

    @Test func seedingSampleDataGivesAnAnalysisAndTodaysPlan() throws {
        let model = TestApp.model()
        SampleData.seedIfEmpty(model)
        #expect(model.onboarded)
        #expect(model.sessions.count > 30)
        #expect(!model.tests.isEmpty)
        let analysis = try #require(model.analysis)
        #expect(!analysis.stats.isEmpty)
        #expect(!analysis.phase.isAssessment, "eight weeks in, the assessment is long over")
        let plan = try #require(analysis.today, "a Wednesday is a study day")
        #expect(!plan.parts.isEmpty)
        #expect(plan.minutes > 0)
        // The Progress charts read series worked out once, the same as the engine's.
        let state = try #require(model.state)
        for domain in state.settings.domains {
            #expect(model.series(domain).map(\.day) == Analyst.series(domain, state: state).map(\.day), "\(domain)")
        }
        #expect(!model.series(.writing).isEmpty)
        // Seeding twice changes nothing.
        let sessions = model.sessions.count
        SampleData.seedIfEmpty(model)
        #expect(model.sessions.count == sessions)
    }

    @Test func todaysSessionIsKeptOnceFinished() throws {
        let clock = TestClock()
        let store = TestApp.store()
        let model = TestApp.onboardedModel(store: store, clock: clock)
        let plan = try #require(model.analysis?.today)
        #expect(model.run == nil)

        model.startToday()
        let run = try #require(model.run)
        #expect(run.plan.domains == plan.domains)
        let taken = Student.answer(model, steps: 12, clock: clock)
        #expect(taken > 0)
        let answered = try #require(model.run).answered.count
        #expect(answered > 0)
        clock.advance(30)
        model.endSession()

        #expect(model.run == nil)
        #expect(model.sessions.count == 1)
        let session = try #require(model.sessions.first)
        #expect(session.attempts.count == answered)
        #expect(session.end != nil)
        #expect(model.analysis?.doneToday.count == 1)

        // A relaunch reads the same history.
        let relaunched = TestApp.model(store: store, clock: clock)
        #expect(relaunched.sessions.map(\.id) == [session.id])
        #expect(relaunched.sessions.first?.attempts.count == answered)
        #expect(relaunched.cards.count == model.cards.count)
    }

    @Test func aSessionLeftHalfwayKeepsWhatItLearned() throws {
        let clock = TestClock()
        let store = TestApp.store()
        let model = TestApp.onboardedModel(store: store, clock: clock)
        model.startToday()
        Student.answer(model, steps: 10, clock: clock)
        let run = try #require(model.run)
        #expect(!run.answered.isEmpty)

        // The app is closed mid-session (iOS ends it in the background): every answer was saved.
        let relaunched = TestApp.model(store: store, clock: clock)
        #expect(relaunched.sessions.count == 1)
        #expect(relaunched.sessions.first?.attempts.count == run.answered.count)
        let changed = Set(run.changedCards)
        #expect(Set(relaunched.cards.map(\.key)).isSuperset(of: changed))
    }

    @Test func savingAStepWritesOnlyWhatChanged() throws {
        let clock = TestClock()
        let model = TestApp.onboardedModel([.maths, .writing, .reading], clock: clock)
        model.startToday()
        Student.answer(model, steps: 8, clock: clock)
        let store = model.store
        let before = (
            cards: store.revision(of: MemoryCard.self), tests: store.revision(of: TestResult.self), books: store.revision(of: Book.self),
            reflections: store.revision(of: Reflection.self), pieces: store.revision(of: WritingPiece.self),
            sessions: store.revision(of: StudySession.self)
        )
        // A save with nothing new in it (the clock moved): only the session is written again.
        clock.advance(5)
        let now = clock.now
        model.act { $0.tick(now: now) }
        #expect(store.revision(of: StudySession.self) > before.sessions)
        #expect(store.revision(of: MemoryCard.self) == before.cards)
        #expect(store.revision(of: TestResult.self) == before.tests, "a test result isn't saved twice")
        #expect(store.revision(of: Book.self) == before.books)
        #expect(store.revision(of: Reflection.self) == before.reflections)
        #expect(store.revision(of: WritingPiece.self) == before.pieces)
    }

    @Test func answeringKeepsTheStepAndMovingOnHandsOutANewOne() throws {
        let clock = TestClock()
        let model = TestApp.onboardedModel(clock: clock)
        model.startToday()
        let question = try #require(Student.toQuestion(model, clock: clock))
        let shown = try #require(model.stepScreen)

        clock.advance(4)
        let now = clock.now
        if let index = question.correctChoice {
            model.act { $0.choose(index, now: now) }
        } else if case .number(let value, _) = question.answer {
            model.act { $0.type(value.description, now: now) }
        }
        #expect(model.run?.feedback != nil)
        #expect(model.stepScreen == shown, "the answered question keeps its screen")

        model.act { $0.next(after: question.id, now: now + 2) }
        let next = try #require(model.stepScreen)
        #expect(next != shown)
        #expect(next.session == shown.session)
        #expect(model.run?.feedback == nil)
    }

    @Test func movingOnFromAQuestionTwiceSkipsNothing() throws {
        // Continue tapped as the auto-advance lands (or twice): both move on from the question
        // they were shown, so only the first does.
        let clock = TestClock()
        let model = TestApp.onboardedModel(clock: clock)
        model.startToday()
        let question = try #require(Student.toQuestion(model, clock: clock))
        clock.advance(4)
        let now = clock.now
        if let index = question.correctChoice {
            model.act { $0.choose(index, now: now) }
        } else if case .number(let value, _) = question.answer {
            model.act { $0.type(value.description, now: now) }
        }
        model.act { $0.next(after: question.id, now: now + 1) }
        let after = try #require(model.run)
        model.act { $0.next(after: question.id, now: now + 2) }
        #expect(model.run?.stepNumber == after.stepNumber, "the second move found another step and left it")
        #expect(model.run?.step == after.step)
    }

    @Test func aNewSessionGetsANewScreen() throws {
        // Every session hands out step 0 first: the next one mustn't open on the last one's screen
        // (with what was typed there).
        let clock = TestClock()
        let model = TestApp.onboardedModel([.maths, .reading], clock: clock)
        #expect(model.stepScreen == nil)
        model.startToday()
        let first = try #require(model.stepScreen)
        Student.answer(model, steps: 3, clock: clock)
        model.endSession()
        #expect(model.stepScreen == nil)

        model.startBlock(.maths)
        let second = try #require(model.stepScreen)
        #expect(second.step == first.step, "both on their first step")
        #expect(second != first)
    }

    @Test func aCheckInSetUpOverARunningSessionGetsAScreenOfItsOwn() throws {
        // `-onboarded -checkIn writing` starts the first session, then replaces it with a check-in.
        let model = TestApp.onboardedModel([.maths, .writing])
        model.startToday()
        let session = model.run?.session.id
        let shown = try #require(model.stepScreen)
        model.debugCheckIn([.maths])
        #expect(model.run?.plan.kind == .checkIn)
        #expect(model.run?.session.id != session)
        #expect(model.stepScreen != shown, "the check-in's first step doesn't inherit the session's screen")
    }

    @Test func startingASessionWhileOneIsOpenLeavesItAlone() throws {
        // On the Mac, Today's actions, Study Anyway and the menu bar stay in reach beside the
        // session's window: none of them replaces the session that's running.
        let clock = TestClock()
        let model = TestApp.onboardedModel([.maths, .writing], clock: clock)
        model.startToday()
        Student.answer(model, steps: 6, clock: clock)
        let run = try #require(model.run)
        let screen = model.stepScreen
        let saved = model.store.revision

        model.startBlock(.writing)
        model.startExtraReview(minutes: 10)
        model.startToday()
        #expect(model.run?.session.id == run.session.id)
        #expect(model.run?.stepNumber == run.stepNumber)
        #expect(model.run?.answered.count == run.answered.count)
        #expect(model.run?.changedCards == run.changedCards)
        #expect(model.stepScreen == screen)
        #expect(model.store.revision == saved, "nothing was saved for a second session")
        #expect(!model.showPaywall)

        model.endSession()
        #expect(model.sessions.map(\.id) == [run.session.id])
    }

    @Test func booksAndRestoresWaitWhileASessionIsOpen() async throws {
        // The session's reading block saves the book it began with: a change made beside it (the
        // Mac's shelf, a reader started on Progress) would be written over. So would a restore.
        let clock = TestClock()
        let model = TestApp.onboardedModel([.reading], clock: clock)
        let book = Book(title: "Persuasion", author: "Jane Austen", tier: 6, pages: 250, genres: [.classics], status: .reading)
        model.save(book: book)
        model.startToday()
        #expect(model.sessionOpen && model.booksLocked)

        var finished = try #require(model.books.first)
        finished.status = .finished
        finished.finished = model.today
        model.save(book: finished)
        model.startReading(Book(title: "Emma", author: "Jane Austen", tier: 6, pages: 470, genres: [.classics], status: .reading))
        #expect(model.books.map(\.title) == ["Persuasion"])
        #expect(model.books.first?.status == .reading, "not finished behind the session's back")
        #expect(model.store.all(Book.self).map(\.status) == [.reading])
        // Refused before the file is read: any backup would be.
        let backup = TestApp.folder().appending(path: "Stadig Mind.mindbackup")
        await #expect(throws: AppModel.SessionOpenError.self) { try await model.restore(from: backup) }

        model.endSession()
        #expect(!model.booksLocked)
        model.save(book: finished)
        #expect(model.books.first?.status == .finished, "once it's over, the shelf works as before")
    }

    @Test func endingTwiceEndsOnce() throws {
        // End, closing the Mac's session window and quitting can each ask, one after another.
        let clock = TestClock()
        let store = TestApp.store()
        let model = TestApp.onboardedModel(store: store, clock: clock)
        model.startToday()
        Student.answer(model, steps: 6, clock: clock)
        clock.advance(30)
        model.endSession()
        let session = try #require(model.sessions.first)
        let saved = store.revision

        clock.advance(60)
        model.endSession()
        #expect(store.revision == saved, "nothing is saved the second time")
        #expect(model.sessions.map(\.id) == [session.id])
        #expect(model.sessions.first?.end == session.end)
    }

    @Test func quittingEndsTheOpenSessionAsClosingItsWindowDoes() throws {
        // ⌘Q needn't run the session window's onDisappear: the model hears the quit itself.
        let quit = Notification.Name("MindTrackTests.quit.\(UUID().uuidString)")
        let clock = TestClock()
        let store = TestApp.store()
        store.save(TestApp.settings([.maths], onboarded: clock.now.addingTimeInterval(-86_400)))
        let model = AppModel(
            store: store, shared: TestApp.sharedContainer(),
            drafts: WritingDrafts(folder: TestApp.folder().appending(path: "Drafts", directoryHint: .isDirectory)), now: { clock.now },
            quit: quit)
        model.startToday()
        Student.answer(model, steps: 6, clock: clock)
        let answered = try #require(model.run).answered.count
        let before = try #require(model.run).session.activeSeconds
        clock.advance(40)

        NotificationCenter.default.post(name: quit, object: nil)
        #expect(model.run == nil)
        let session = try #require(model.sessions.first)
        #expect(session.end == clock.now)
        #expect(session.attempts.count == answered)
        #expect(session.activeSeconds == before + 40, "the minutes since the last answer count")

        // Closing the window after (or quitting again) finds nothing to end.
        let saved = store.revision
        NotificationCenter.default.post(name: quit, object: nil)
        model.endSession()
        #expect(store.revision == saved && model.sessions.count == 1)
    }

    @Test func aBookmarkStaysWithinTheBook() throws {
        let model = TestApp.onboardedModel([.reading])
        let book = Book(title: "Persuasion", author: "Jane Austen", tier: 6, pages: 250, genres: [.classics], status: .reading, page: 240)
        var shorter = book
        shorter.pages = 200
        model.save(book: shorter)
        #expect(model.books.first?.page == 200, "another edition with fewer pages brings the bookmark down")
        var backwards = try #require(model.books.first)
        backwards.page = -4
        model.save(book: backwards)
        #expect(model.books.first?.page == 0)
    }

    @Test func startingABookSetsAsideTheOneInTheSameLanguage() {
        let model = TestApp.onboardedModel([.reading])
        let first = Book(title: "Persuasion", author: "Jane Austen", tier: 6, pages: 250, genres: [.classics], status: .reading)
        model.save(book: first)
        let second = Book(title: "Emma", author: "Jane Austen", tier: 6, pages: 470, genres: [.classics], status: .reading)
        model.startReading(second)
        #expect(model.books.first { $0.id == first.id }?.status == .abandoned)
        #expect(model.books.first { $0.id == second.id }?.status == .reading)
    }

    @Test func changingTheScheduleKeepsTheOldOneForEarlierDays() throws {
        let model = TestApp.onboardedModel()
        var settings = try #require(model.settings)
        let old = settings.schedule
        settings.schedule = StudySchedule(daysPerWeek: old.daysPerWeek == 3 ? 4 : 3, minutes: old.minutes)
        model.save(settings: settings)

        let saved = try #require(model.settings)
        #expect(saved.schedule.daysPerWeek == settings.schedule.daysPerWeek)
        #expect(saved.schedule(on: model.today.adding(days: -1)) == old, "Discipline judges yesterday by yesterday's schedule")
        #expect(saved.schedule(on: model.today) == settings.schedule)

        // A change that leaves the schedule alone records nothing.
        var genres = saved
        genres.genres = [.crime]
        model.save(settings: genres)
        #expect(model.settings?.earlierSchedules == saved.earlierSchedules)
    }

    @Test func anEpisodeIsLoggedAsAPlainCheckIn() throws {
        let clock = TestClock()
        let model = TestApp.onboardedModel([.japanese], clock: clock)
        model.logEpisode(rating: 2, title: "Midnight Diner", language: .japanese)
        let test = try #require(model.tests.last)
        #expect(test.test == .episode)
        #expect(test.score == 2.0 / 3)
        #expect(test.language == .japanese)
        #expect(test.date == clock.now)
    }

    @Test func aChangeFromAnotherDeviceReachesTheOpenApp() async throws {
        // Two stores on one file stand in for CloudKit importing another device's edit.
        let name = "MindTrackTests-\(UUID().uuidString)"
        defer { removeStoreFiles(name) }
        let store = RecordStore(name: name, cloudKitContainer: nil)
        let model = TestApp.onboardedModel(store: store)
        #expect(model.books.isEmpty)

        let elsewhere = RecordStore(name: name, cloudKitContainer: nil)
        elsewhere.save(Book(title: "Middlemarch", author: "George Eliot", tier: 8, pages: 880, genres: [.classics], status: .reading))
        NotificationCenter.default.post(name: Notification.Name("NSPersistentStoreRemoteChangeNotification"), object: nil)
        for _ in 0..<100 where model.books.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(model.books.map(\.title) == ["Middlemarch"], "the model reloads when the store says changes landed")
    }

    @Test func aModelDeallocatesWhenDropped() {
        weak var dropped: AppModel?
        do {
            let clock = TestClock()
            let model = TestApp.onboardedModel(clock: clock)
            model.startToday()
            Student.answer(model, steps: 4, clock: clock)
            model.endSession()
            model.readShared()
            dropped = model
            #expect(dropped != nil)
        }
        #expect(dropped == nil, "its store, shared-container and day observers don't keep it alive")
    }

    private func removeStoreFiles(_ name: String) {
        let folder = URL.applicationSupportDirectory.appending(path: "SystemStore", directoryHint: .isDirectory)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        for file in files where file.hasPrefix(name) {
            try? FileManager.default.removeItem(at: folder.appending(path: file))
        }
    }
}
