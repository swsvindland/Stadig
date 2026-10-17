import Foundation
import Observation
import OSLog
import MindEngine
import SystemCore
import SystemStore

let appLog = Logger(subsystem: "dev.svindland.mindtrack", category: "app")

enum AppTab: Hashable {
    case today, plan, progress
}

/// The app's state: Mind Track's own synced records, what Lift Track and the hub published, the
/// analysis computed from all of it, and the session in progress.
@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    let store: RecordStore
    let shared: SharedContainer
    /// The Japanese catalog, when the build ships it.
    let deck: JapaneseDeck?
    let purchases = Purchases()
    let speech = Speech()

    // Records.
    private(set) var settings: MindSettings?
    private(set) var cards: [MemoryCard] = []
    private(set) var sessions: [StudySession] = []
    private(set) var tests: [TestResult] = []
    private(set) var books: [Book] = []
    private(set) var reflections: [Reflection] = []
    private(set) var lifeModes: [LifeModePeriod] = []

    // From the other apps and the hub.
    private(set) var calendar: SystemCalendar?
    private(set) var recommendations: [Recommendation] = []

    // Derived.
    private(set) var analysis: MindAnalysis?

    // Presentation.
    var tab: AppTab = .today
    /// The session on screen, if one is running.
    var run: StudyRun?
    var showSettings = false
    var showPaywall = false
    var showEpisode = false
    var showShelf = false
    var today: Day = .today

    @ObservationIgnored private var sharedObserver: AnyObject?
    @ObservationIgnored private var lastRevision = -1
    @ObservationIgnored private var savedCards: [CardKey: MemoryCard] = [:]
    @ObservationIgnored private var lastPublished: AppSummary?

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let memory = arguments.contains("-inMemoryStore")
        store = RecordStore(name: "MindTrack", cloudKitContainer: memory ? nil : "iCloud.dev.svindland.mindtrack", inMemory: memory)
        shared = SharedContainer()
        deck = JapaneseDeck.bundled()
        #if DEBUG
        if arguments.contains("-resetData") { store.eraseAll() }
        #endif
        reload()
        sharedObserver = SharedContainer.observeChanges { [weak self] in self?.readShared() }
    }

    var onboarded: Bool { settings?.onboardedAt != nil }

    // MARK: Loading

    /// Reads everything from the store and recomputes.
    func reload() {
        lastRevision = store.revision
        settings = store.all(MindSettings.self).first
        cards = store.all(MemoryCard.self)
        sessions = store.all(StudySession.self).sorted { $0.start < $1.start }
        tests = store.all(TestResult.self).sorted { $0.date < $1.date }
        books = store.all(Book.self)
        reflections = store.all(Reflection.self).sorted { $0.date < $1.date }
        readShared(recompute: false)
        recompute()
    }

    func reloadIfChanged() {
        if store.revision != lastRevision, run == nil { reload() }
    }

    /// What Lift Track and the hub published, and life modes set anywhere.
    func readShared(recompute again: Bool = true) {
        let calendar = shared.read(.calendar)
        let recommendations = (shared.read(.recommendations) ?? []).filter { $0.to == .knowledge }
        var merged: [UUID: LifeModePeriod] = [:]
        for period in store.all(LifeModeRecord.self).map(\.period) + (shared.read(.lifeModes) ?? []) {
            if let existing = merged[period.id], existing.updatedAt >= period.updatedAt { continue }
            merged[period.id] = period
        }
        let lifeModes = merged.values.sorted { $0.start < $1.start }
        guard calendar != self.calendar || recommendations != self.recommendations || lifeModes != self.lifeModes else { return }
        self.calendar = calendar
        self.recommendations = recommendations
        self.lifeModes = lifeModes
        if again { recompute() }
    }

    var state: StudyState? {
        guard let settings else { return nil }
        return StudyState(settings: settings, cards: cards, sessions: sessions, tests: tests, books: books, reflections: reflections,
                          lifeModes: lifeModes, calendar: calendar, recommendations: recommendations, today: today, now: Date())
    }

    func recompute() {
        today = .today
        guard let state, onboarded else {
            analysis = nil
            return
        }
        let analysis = Analyst.analyse(state, deck: deck)
        self.analysis = analysis
        publish(state, analysis)
    }

    /// Mind Track's summary for the hub, written only when it changes.
    private func publish(_ state: StudyState, _ analysis: MindAnalysis) {
        var summary = Analyst.appSummary(state, analysis)
        summary.updated = lastPublished?.updated ?? summary.updated
        for i in summary.stats.indices { summary.stats[i].updated = lastPublished?.stats.first { $0.stat == summary.stats[i].stat }?.updated ?? summary.stats[i].updated }
        guard summary != lastPublished else { return }
        summary.updated = Date()
        do {
            try shared.write(summary, to: .summary(.knowledge), by: .knowledge)
            lastPublished = summary
        } catch {
            appLog.error("Couldn't publish the summary: \(error.localizedDescription)")
        }
    }

    // MARK: Onboarding

    func completeOnboarding(_ settings: MindSettings, booksRead: [Book]) {
        var settings = settings
        settings.onboardedAt = Date()
        settings.updatedAt = Date()
        store.save(settings)
        store.save(booksRead)
        reload()
        // The onboarding is the first session.
        startToday()
    }

    func save(settings: MindSettings) {
        var settings = settings
        settings.updatedAt = Date()
        store.save(settings)
        reload()
    }

    // MARK: Sessions

    func startToday() {
        guard let state, let plan = analysis?.today ?? SessionPlanner.today(state, deck: deck) else { return }
        start(plan)
    }

    /// A few minutes of reviews, on a rest or paused day.
    func startExtraReview(minutes: Int = 5) {
        guard let state else { return }
        start(SessionPlanner.plan(.extra, domains: [], state: state, deck: deck, minutes: minutes))
    }

    /// A session of one domain on demand, outside the plan.
    func startSession(_ domains: [Domain]) {
        guard let state else { return }
        var plan = SessionPlanner.plan(state.phase.isReview ? .review : .regular, domains: domains, state: state, deck: deck)
        plan.planned = analysis?.today.map { Set($0.domains) == Set(domains) } ?? false
        start(plan)
    }

    private func start(_ plan: SessionPlan) {
        guard let state else { return }
        // The assessment and check-ins are free; sessions after the assessment need the unlock.
        if !purchases.unlocked, !state.phase.isAssessment, plan.kind != .checkIn {
            showPaywall = true
            return
        }
        savedCards = Dictionary(cards.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        run = StudyRun(plan: plan, state: state, deck: deck, now: Date())
    }

    /// Applies an action to the running session and keeps what changed.
    func act(_ action: (inout StudyRun) -> Void) {
        guard var current = run else { return }
        action(&current)
        run = current
        persist(current, finished: false)
    }

    func endSession() {
        guard var current = run else { return }
        current.finish(now: Date())
        persist(current, finished: true)
        run = nil
        reload()
    }

    /// Saves the session and only the cards, books and results that changed since the last save,
    /// so a session interrupted halfway keeps what it learned.
    private func persist(_ run: StudyRun, finished: Bool) {
        var session = run.session
        session.updatedAt = Date()
        store.save(session)
        let changed = run.changedCards.compactMap { run.cards[$0] }.filter { savedCards[$0.key] != $0 }
        if !changed.isEmpty {
            store.save(changed)
            for card in changed { savedCards[card.key] = card }
        }
        let newTests = run.newTests.filter { test in !tests.contains { $0.id == test.id } }
        if !newTests.isEmpty {
            store.save(newTests)
            tests += newTests
        }
        let books = run.books.filter { run.changedBooks.contains($0.id) }
        if !books.isEmpty { store.save(books) }
        let reflections = run.newReflections.filter { r in !self.reflections.contains { $0.id == r.id } }
        if !reflections.isEmpty {
            store.save(reflections)
            self.reflections += reflections
        }
        lastRevision = store.revision
    }

    // MARK: Books

    func save(book: Book) {
        var book = book
        book.updatedAt = Date()
        store.save(book)
        reload()
    }

    func start(book: LadderBook) {
        for var current in books where current.status == .reading {
            current.status = .abandoned
            current.finished = today
            current.updatedAt = Date()
            store.save(current)
        }
        save(book: book.book(status: .reading, started: today))
    }

    // MARK: Tests outside sessions

    /// An episode watched without subtitles: 0 (lost) to 3 (followed nearly all of it).
    func logEpisode(rating: Int, title: String?) {
        var detail: [String: Double] = ["rating": Double(rating)]
        if let title, !title.isEmpty { detail["titled"] = 1 }
        store.save(TestResult(test: .episode, date: Date(), score: Double(rating) / 3, detail: detail))
        reload()
    }

    // MARK: Life modes (shared with the other apps)

    func save(lifeMode period: LifeModePeriod) {
        var period = period
        period.updatedAt = Date()
        store.save(LifeModeRecord(period))
        var all = shared.read(.lifeModes) ?? []
        all.removeAll { $0.id == period.id }
        all.append(period)
        try? shared.write(all, to: .lifeModes, by: .knowledge)
        reload()
    }

    func delete(lifeMode id: UUID) {
        store.delete(LifeModeRecord.self, id: id)
        var all = shared.read(.lifeModes) ?? []
        all.removeAll { $0.id == id }
        try? shared.write(all, to: .lifeModes, by: .knowledge)
        reload()
    }

    // MARK: Your data

    func exportCSV() throws -> [URL] {
        let folder = URL.temporaryDirectory.appending(path: "Mind Track Export \(Day.today.iso)")
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try MindExport.tables(sessions: sessions, cards: cards, tests: tests, books: books, reflections: reflections).map { table in
            var csv = CSVTable(header: table.header)
            for row in table.rows { csv.append(row) }
            let url = folder.appending(path: "\(table.name).csv")
            try csv.data.write(to: url)
            return url
        }
    }

    func backupFile() throws -> URL {
        let data = try store.exportBackup(app: .knowledge, shared: shared)
        let url = URL.temporaryDirectory.appending(path: "Mind Track \(Day.today.iso).mindbackup")
        try data.write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    func restore(from url: URL) throws -> BackupSummary {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let summary = try store.importBackup(try Data(contentsOf: url), shared: shared)
        reload()
        return summary
    }

    #if DEBUG
    func eraseEverything() {
        store.eraseAll()
        reload()
    }

    /// Answers `count` steps of the running session: right, except every third question.
    func debugSteps(_ count: Int) {
        for n in 0..<count {
            act { run in
                let now = Date()
                switch run.step {
                case .lesson: run.next(now: now)
                case .question(let question):
                    if run.feedback != nil { run.next(now: now); return }
                    let right = n % 3 != 2
                    if let index = question.correctChoice { run.choose(right ? index : (index + 1) % question.choices.count, now: now) }
                    else if case .number(let value, _) = question.answer { run.type(right ? value.description : "0", now: now) }
                case .pickBook(let options): if let first = options.first { run.pickBook(first, now: now) }
                default: break
                }
            }
        }
    }

    /// For sample data: saves records straight to the store.
    func seed(settings: MindSettings, cards: [MemoryCard], sessions: [StudySession], tests: [TestResult], books: [Book],
              reflections: [Reflection]) {
        store.save(settings)
        store.save(cards)
        store.save(sessions)
        store.save(tests)
        store.save(books)
        store.save(reflections)
        reload()
    }
    #endif
}
