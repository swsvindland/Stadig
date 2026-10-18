import Foundation
import Observation
import OSLog
import MindEngine
import SystemAI
import SystemCore
import SystemStore

let appLog = Logger(subsystem: "dev.svindland.stadig.mind", category: "app")

enum AppTab: Hashable {
    case today, plan, progress
}

/// Which session and which of its steps a screen shows.
struct StepScreen: Hashable {
    let session: UUID
    let step: Int
}

/// The app's state: Mind Track's own synced records, what Lift Track and the hub published, the
/// analysis computed from all of it, and the session in progress.
@MainActor @Observable
final class AppModel {
    static let shared = AppModel(launch: .current)

    let store: RecordStore
    let shared: SharedContainer
    /// Pieces being written, kept on the device until they're handed in.
    let drafts: WritingDrafts
    /// The time now: `Date()`, or a fixed clock in tests.
    let now: () -> Date
    /// The language packs the build ships, the writing bank and the reading ladder, with the
    /// numbers Lift Track and Macro Track publish for statistics problems.
    private(set) var catalogs: Catalogs
    let purchases = Purchases()
    let speech = Speech()

    // Records.
    private(set) var settings: MindSettings?
    private(set) var cards: [MemoryCard] = []
    private(set) var sessions: [StudySession] = []
    private(set) var tests: [TestResult] = []
    private(set) var books: [Book] = []
    private(set) var reflections: [Reflection] = []
    private(set) var pieces: [WritingPiece] = []
    private(set) var comparisons: [BlindComparison] = []
    /// Books looked up by ISBN, cover or search, kept so a lookup happens once.
    private(set) var bookMeta: [BookMeta] = []
    private(set) var lifeModes: [LifeModePeriod] = []

    // From the other apps and the hub.
    private(set) var calendar: SystemCalendar?
    private(set) var recommendations: [Recommendation] = []

    // Derived.
    /// Everything the engine plans from, as of the last recompute. A session starts from a fresh one.
    private(set) var state: StudyState?
    private(set) var analysis: MindAnalysis?
    /// Each course's score over time, for the Progress charts: worked out once a recompute rather
    /// than on every redraw of the tab.
    private(set) var series: [Domain: [(day: Day, score: Double)]] = [:]

    // Presentation.
    var tab: AppTab = .today
    /// The session on screen, if one is running.
    var run: StudyRun?
    var showSettings = false
    var showPaywall = false
    /// The language an episode (or conversation) is being logged for.
    var episodeLanguage: Language?
    var showShelf = false
    var today: Day

    /// The running session's screen: a new one for each step the run hands out (its `stepNumber`),
    /// kept while that step is answered. The session's id is part of it, so another session (started
    /// here, or a check-in set up by `-checkIn`) opens on a screen of its own, even when its first
    /// step looks like the last one's.
    var stepScreen: StepScreen? { run.map { StepScreen(session: $0.session.id, step: $0.stepNumber) } }

    @ObservationIgnored private var sharedObserver: AnyObject?
    @ObservationIgnored private var storeObserver: AnyObject?
    @ObservationIgnored private var dayObservers: [NotificationToken] = []
    @ObservationIgnored private var lastRevision = -1
    /// The store's `revision(of:)` for each kind when it was last read, so a save re-reads only its kind.
    @ObservationIgnored private var readRevisions: [String: Int] = [:]
    @ObservationIgnored private var savedCards: [CardKey: MemoryCard] = [:]
    @ObservationIgnored private var lastPublished: AppSummary?

    /// The app's model as launched. Tests, UI tests and `-inMemoryStore` get a store in memory and a
    /// shared container and drafts folder of their own in a fresh temporary folder, so they never
    /// touch the person's data, the App Group the other apps read, or iCloud.
    convenience init(launch: LaunchOptions) {
        let memory = launch.usesInMemoryStore
        let store = RecordStore(name: "MindTrack", cloudKitContainer: memory ? nil : "iCloud.dev.svindland.stadig.mind", inMemory: memory)
        #if DEBUG
        // Before the first read, so nothing of the old data is published on the way out. The
        // writing drafts go too, or they'd come back with their tasks.
        if launch.has("-resetData") {
            store.eraseAll()
            let drafts = WritingDrafts.defaultFolder
            if !memory, FileManager.default.fileExists(atPath: drafts.path(percentEncoded: false)) {
                do {
                    try FileManager.default.removeItem(at: drafts)
                } catch {
                    appLog.error("Couldn't erase the writing drafts: \(error.localizedDescription)")
                }
            }
        }
        #endif
        if memory {
            let scratch = URL.temporaryDirectory.appending(path: "MindTrack \(UUID().uuidString)", directoryHint: .isDirectory)
            let shared = SharedContainer(directory: scratch.appending(path: "Shared", directoryHint: .isDirectory))
            self.init(store: store, shared: shared, drafts: WritingDrafts(folder: scratch.appending(path: "Writing drafts", directoryHint: .isDirectory)))
        } else {
            self.init(store: store, shared: SharedContainer(), drafts: WritingDrafts(folder: WritingDrafts.defaultFolder))
        }
    }

    /// Everything that touches disk or the system comes in, so a test builds one over an in-memory
    /// store and a temporary shared container. `now` is the clock every date the model makes reads.
    init(store: RecordStore, shared: SharedContainer, drafts: WritingDrafts, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.shared = shared
        self.drafts = drafts
        self.now = now
        today = Day(now())
        catalogs = Catalogs(decks: LanguageDeck.bundled())
        reload()
        sharedObserver = SharedContainer.observeChanges { [weak self] in self?.readShared() }
        // Another device's changes, as CloudKit imports them while the app is open: a stale copy
        // left on screen would be saved back over them.
        storeObserver = store.observeChanges { [weak self] in self?.reloadIfChanged() }
        // Midnight, or a new time zone, with the app open: plan for the new day.
        dayObservers = [.NSCalendarDayChanged, .NSSystemTimeZoneDidChange].map { name in
            NotificationToken.observe(name) { [weak self] in self?.refreshDay() }
        }
    }

    var onboarded: Bool { settings?.onboardedAt != nil }

    /// A course's score over time, as of the last recompute.
    func series(_ domain: Domain) -> [(day: Day, score: Double)] {
        if let kept = series[domain] { return kept }
        return state.map { Analyst.series(domain, state: $0) } ?? []
    }

    /// Every AI call goes through this: Apple's on-device model first, Private Cloud Compute for
    /// heavier jobs when the setting allows it. Nothing core waits on it.
    var ai: SystemAI { SystemAI(allowCloud: settings?.allowCloudAI ?? true) }

    // MARK: Loading

    /// Re-reads the kinds of record that changed since the last read, then recomputes.
    func reload() {
        if needsReading(MindSettings.self) { settings = store.all(MindSettings.self).first }
        if needsReading(MemoryCard.self) { cards = store.all(MemoryCard.self) }
        if needsReading(StudySession.self) { sessions = store.all(StudySession.self).sorted { $0.start < $1.start } }
        if needsReading(TestResult.self) { tests = store.all(TestResult.self).sorted { $0.date < $1.date } }
        if needsReading(Book.self) { books = store.all(Book.self) }
        if needsReading(Reflection.self) { reflections = store.all(Reflection.self).sorted { $0.date < $1.date } }
        if needsReading(WritingPiece.self) { pieces = store.all(WritingPiece.self).sorted { $0.date < $1.date } }
        if needsReading(BlindComparison.self) { comparisons = store.all(BlindComparison.self).sorted { $0.date < $1.date } }
        if needsReading(BookMeta.self) { bookMeta = store.all(BookMeta.self) }
        readShared(recompute: false)
        recompute()
        // After the life modes that arrived from the other apps are kept, so they don't count as new.
        lastRevision = store.revision
    }

    private func needsReading<T: StoredRecord>(_ type: T.Type) -> Bool {
        let revision = store.revision(of: type)
        guard readRevisions[T.kind] != revision else { return false }
        readRevisions[T.kind] = revision
        return true
    }

    func reloadIfChanged() {
        if store.revision != lastRevision, run == nil { reload() }
    }

    /// The day moved on (midnight, a new time zone) since the plan was made.
    func refreshDay() {
        if today != Day(now()) { recompute() }
    }

    /// What Lift Track, Macro Track and the hub published, and life modes set anywhere.
    func readShared(recompute again: Bool = true) {
        let calendar = shared.read(.calendar)
        let recommendations = (shared.read(.recommendations) ?? []).filter { $0.to == .knowledge }
        let lifeModes = syncLifeModes()
        var systemData = SystemData(lift: shared.read(.summary(.liftTrack)), macro: shared.read(.summary(.macroTrack)), nutrition: shared.read(.nutrition))
        #if DEBUG
        if systemData.isEmpty, LaunchOptions.current.has("-seedSampleData") { systemData = SampleData.systemData(ending: today) }
        #endif
        guard calendar != self.calendar || recommendations != self.recommendations || lifeModes != self.lifeModes
            || systemData != catalogs.systemData else { return }
        self.calendar = calendar
        self.recommendations = recommendations
        self.lifeModes = lifeModes
        catalogs.systemData = systemData
        if again { recompute() }
    }

    /// Life modes from every app: the shared file and this app's synced copies merged, the newest
    /// edit or delete of each winning (deletes are kept as tombstones so they keep spreading). What
    /// came from elsewhere is kept here too, so it reaches Mind Track on the person's other devices,
    /// and the merged list goes back to the file, so the other apps hear about this app's changes and
    /// what iCloud brought. The file goes first so that on a tie its copy wins and no app rewrites it.
    private func syncLifeModes() -> [LifeModePeriod] {
        let own = store.all(LifeModeRecord.self).map(\.period)
        let file = shared.read(.lifeModes) ?? []
        let merged = LifeModePeriod.merge([file, own])
        let mine = Dictionary(own.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let arrived = merged.filter { mine[$0.id] != $0 }
        if !arrived.isEmpty { store.save(arrived.map(LifeModeRecord.init)) }
        if merged != file {
            do {
                try shared.write(merged, to: .lifeModes, by: .knowledge)
            } catch {
                appLog.error("Couldn't share the life modes: \(error.localizedDescription)")
            }
        }
        return merged.live
    }

    /// Everything the engine plans from, as of now.
    private func makeState() -> StudyState? {
        guard let settings else { return nil }
        return StudyState(settings: settings, cards: cards, sessions: sessions, tests: tests, books: books, reflections: reflections,
                          pieces: pieces, comparisons: comparisons, lifeModes: lifeModes, calendar: calendar, recommendations: recommendations,
                          today: today, now: now())
    }

    func recompute() {
        today = Day(now())
        state = makeState()
        guard let state, onboarded else {
            analysis = nil
            series = [:]
            return
        }
        let analysis = Analyst.analyse(state, catalogs: catalogs)
        self.analysis = analysis
        series = Dictionary(uniqueKeysWithValues: state.settings.domains.map { ($0, Analyst.series($0, state: state)) })
        publish(state, analysis)
    }

    /// Mind Track's summary for the hub, written only when it changes. A stat keeps the date it
    /// last changed; the summary's own date moves whenever anything in it does.
    private func publish(_ state: StudyState, _ analysis: MindAnalysis) {
        var summary = Analyst.appSummary(state, analysis)
        if lastPublished == nil { lastPublished = shared.read(.summary(.knowledge)) }
        for i in summary.stats.indices {
            guard let old = lastPublished?.stats.first(where: { $0.stat == summary.stats[i].stat }) else { continue }
            var unchanged = summary.stats[i]
            unchanged.updated = old.updated
            if unchanged == old { summary.stats[i].updated = old.updated }
        }
        do {
            try shared.writeIfChanged(summary, to: .summary(.knowledge), by: .knowledge, stamp: \.updated, now: now())
            lastPublished = summary
        } catch {
            appLog.error("Couldn't publish the summary: \(error.localizedDescription)")
        }
    }

    // MARK: Onboarding

    func completeOnboarding(_ settings: MindSettings, booksRead: [Book]) {
        // Set up already on another device, and iCloud brought it while this onboarding was on
        // screen: keep that setup (its start date, courses and books) rather than starting over.
        if store.get(MindSettings.self, id: MindSettings.singletonID)?.onboardedAt != nil {
            reload()
            startToday()
            return
        }
        var settings = settings
        settings.onboardedAt = now()
        settings.updatedAt = now()
        store.save(settings)
        store.save(booksRead)
        reload()
        // The onboarding is the first session.
        startToday()
    }

    func save(settings: MindSettings) {
        var settings = settings
        // Days before today keep being judged by the schedule they were planned with.
        if let previous = self.settings?.schedule { settings.recordScheduleChange(from: previous, on: today) }
        settings.updatedAt = now()
        store.save(settings)
        reload()
    }

    // MARK: Sessions

    func startToday() {
        // Never yesterday's plan, if the app was left open past midnight.
        refreshDay()
        guard let state = makeState(), let plan = analysis?.today ?? SessionPlanner.today(state, catalogs: catalogs) else { return }
        start(plan)
    }

    /// A few minutes of reviews, on a rest or paused day.
    func startExtraReview(minutes: Int = 5) {
        refreshDay()
        guard let state = makeState() else { return }
        start(SessionPlanner.plan(.extra, domains: [], state: state, catalogs: catalogs, minutes: minutes))
    }

    /// A session of one domain on demand, outside the plan.
    func startSession(_ domains: [Domain]) {
        refreshDay()
        guard let state = makeState() else { return }
        var plan = SessionPlanner.plan(state.phase.isReview ? .review : .regular, domains: domains, state: state, catalogs: catalogs)
        plan.planned = analysis?.today.map { Set($0.domains) == Set(domains) } ?? false
        start(plan)
    }

    private func start(_ plan: SessionPlan) {
        guard let state = makeState() else { return }
        // The assessment and check-ins are free; sessions after the assessment need the unlock.
        if !purchases.unlocked, !state.phase.isAssessment, plan.kind != .checkIn {
            showPaywall = true
            return
        }
        savedCards = Dictionary(cards.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        run = StudyRun(plan: plan, state: state, catalogs: catalogs, now: now())
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
        current.finish(now: now())
        persist(current, finished: true)
        run = nil
        reload()
    }

    /// Saves the session and only the cards, books and results that changed since the last save,
    /// so a session interrupted halfway keeps what it learned.
    private func persist(_ run: StudyRun, finished: Bool) {
        var session = run.session
        session.updatedAt = now()
        store.save(session)
        let changed = run.changedCards.compactMap { run.cards[$0] }.filter { savedCards[$0.key] != $0 }
        if !changed.isEmpty {
            store.save(changed)
            for card in changed { savedCards[card.key] = card }
        }
        saveChanged(run.newTests, into: &tests)
        let books = run.books.filter { run.changedBooks.contains($0.id) }
        if !books.isEmpty { store.save(books) }
        saveChanged(run.newReflections, into: &reflections)
        saveChanged(run.newPieces, into: &pieces)
        saveChanged(run.newComparisons, into: &comparisons)
        lastRevision = store.revision
    }

    /// Saves the records that are new or changed since they were last kept, and keeps them: so a
    /// result edited later in the session (a piece's notes, say) is saved again.
    private func saveChanged<T: StoredRecord & Equatable>(_ records: [T], into kept: inout [T]) {
        let changed = records.filter { record in kept.last { $0.id == record.id } != record }
        guard !changed.isEmpty else { return }
        store.save(changed)
        for record in changed {
            kept.removeAll { $0.id == record.id }
            kept.append(record)
        }
    }

    // MARK: Books

    func save(book: Book) { save(books: [book]) }

    /// Saves books together, each stamped now, then reloads once.
    func save(books: [Book]) {
        let now = self.now()
        store.save(
            books.map { book in
                // A page count lowered below the bookmark (another edition) brings the bookmark with it.
                var book = book.normalized()
                book.updatedAt = now
                return book
            })
        reload()
    }

    /// Starts a book. Whatever else is on the go in its language (English, for an English book) is
    /// set aside; readers in other languages carry on.
    func startReading(_ book: Book) {
        let others = books.filter { $0.status == .reading && $0.language == book.language && $0.id != book.id }.map { current in
            var current = current
            current.status = .abandoned
            current.finished = today
            return current
        }
        save(books: others + [book])
    }

    func start(book: LadderBook) {
        startReading(book.book(status: .reading, started: today))
    }

    /// A lookup kept for next time: one record per book, newest wins.
    func save(meta: BookMeta) {
        var meta = meta
        meta.updatedAt = now()
        store.save(meta)
        reload()
    }

    // MARK: Writing outside sessions

    /// A piece edited after its session: feedback arriving, a handwritten page read in later.
    func save(piece: WritingPiece) {
        var piece = piece
        piece.updatedAt = now()
        store.save(piece)
        reload()
    }

    // MARK: Tests outside sessions

    /// An episode watched without subtitles (or a real conversation): 0 (lost) to 3 (followed
    /// nearly all of it).
    func logEpisode(rating: Int, title: String?, language: Language, test: TestKind = .episode) {
        var detail: [String: Double] = ["rating": Double(rating)]
        if let title, !title.isEmpty { detail["titled"] = 1 }
        store.save(TestResult(test: test, date: now(), score: Double(rating) / 3, detail: detail, language: language))
        reload()
    }

    // MARK: Life modes (shared with the other apps)

    /// Saves a period and shares it with the other apps. One the editor shouldn't have offered (an
    /// end before the start, an open-ended trip) isn't saved: the other apps would read it as real.
    @discardableResult
    func save(lifeMode period: LifeModePeriod) -> Bool {
        var period = period
        guard period.isValid else {
            appLog.error("Not saving an invalid \(period.kind.label, privacy: .public) period")
            return false
        }
        period.updatedAt = now()
        store.save(LifeModeRecord(period))
        // Shared by the reload, merged with the file.
        reload()
        return true
    }

    /// A delete is kept as a tombstone and shared like an edit, so it reaches the app that made the
    /// period and the person's other devices instead of being brought back by their copies.
    func delete(lifeMode id: UUID) {
        guard let period = lifeModes.first(where: { $0.id == id }) else { return }
        store.save(LifeModeRecord(period.deleted(at: now())))
        reload()
    }

    // MARK: Your data

    func exportCSV() throws -> [URL] {
        let folder = URL.temporaryDirectory.appending(path: "Mind Track Export \(today.iso)")
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try MindExport.tables(sessions: sessions, cards: cards, tests: tests, books: books, reflections: reflections,
                                     pieces: pieces, comparisons: comparisons).map { table in
            var csv = CSVTable(header: table.header)
            for row in table.rows { csv.append(row) }
            let url = folder.appending(path: "\(table.name).csv")
            try csv.data.write(to: url)
            return url
        }
    }

    /// The JSON is built off the main actor: years of sessions take a while.
    func backupFile() async throws -> URL {
        let data = try await store.exportBackup(app: .knowledge, shared: shared)
        let url = URL.temporaryDirectory.appending(path: "Mind Track \(today.iso).mindbackup")
        try data.write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    func restore(from url: URL) async throws -> BackupSummary {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        do {
            let summary = try await store.importBackup(data, app: .knowledge, shared: shared)
            reload()
            return summary
        } catch {
            // The shared files can fail after the records were restored: show what did land.
            reload()
            throw error
        }
    }

    #if DEBUG
    func eraseEverything() {
        store.eraseAll()
        reload()
    }

    /// Answers `count` steps of the running session: right, except every third question.
    func debugSteps(_ count: Int) {
        for n in 0..<count {
            let now = self.now()
            act { run in
                switch run.step {
                case .lesson: run.next(now: now)
                case .question(let question):
                    if run.feedback != nil { run.next(now: now); return }
                    let right = n % 3 != 2
                    if let index = question.correctChoice { run.choose(right ? index : (index + 1) % question.choices.count, now: now) }
                    else if case .number(let value, _) = question.answer { run.type(right ? value.description : "0", now: now) }
                case .pickBook(let options): if let first = options.first { run.pickBook(first, now: now) }
                case .speak(let task):
                    if run.feedback != nil { run.next(now: now); return }
                    let said = n % 3 != 2 ? task.answer : ""
                    run.respond(task.mode == .say ? .spoken(transcript: said, seconds: 3) : .written(text: said.isEmpty ? "?" : said, source: .typed), now: now)
                case .passage(let passage): run.respond(.passageRead(seconds: Double(passage.words) / 4), now: now)
                default: break
                }
            }
        }
    }

    /// For sample data: saves records straight to the store.
    func seed(settings: MindSettings, cards: [MemoryCard], sessions: [StudySession], tests: [TestResult], books: [Book],
              reflections: [Reflection], pieces: [WritingPiece] = []) {
        store.save(settings)
        store.save(cards)
        store.save(sessions)
        store.save(tests)
        store.save(books)
        store.save(reflections)
        store.save(pieces)
        reload()
    }
    #endif
}
