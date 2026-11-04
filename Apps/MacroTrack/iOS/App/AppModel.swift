import FoodDatabase
import Foundation
import HealthBridge
import MealPlanner
import NutritionEngine
import OSLog
import Observation
import SystemCore
import SystemPurchases
import SystemStore

let appLog = Logger(subsystem: "dev.svindland.stadig.macro", category: "app")

/// Where the app is. The iPhone's tab bar has Today, Log, Plan and Progress; the sidebar on iPad,
/// the Mac and Vision Pro adds the rest, which are whole screens only where there's room for them.
enum AppTab: String, Hashable, CaseIterable {
    case today, log, foods, mealPlan, supplements, plan, progress, history

    var title: String {
        switch self {
        case .today: "Today"
        case .log: "Log"
        case .foods: "Foods"
        case .mealPlan: "Meal Plan"
        case .supplements: "Supplements"
        case .plan: "Plan"
        case .progress: "Progress"
        case .history: "History"
        }
    }

    /// Only in the sidebar: in a compact width (an iPhone, a narrow iPad window) they're reached
    /// another way (the logger, the Plan tab, the supplements sheet).
    var isSidebarOnly: Bool {
        switch self {
        case .foods, .mealPlan, .supplements, .history: true
        case .today, .log, .plan, .progress: false
        }
    }

    /// The nearest thing the tab bar has, for a window narrowed to no room for the sidebar.
    var compactFallback: AppTab {
        switch self {
        case .mealPlan: .plan
        case .history: .progress
        case .foods: .log
        case .supplements: .today
        case .today, .log, .plan, .progress: self
        }
    }

    /// Screens that log to a day other than today. Leaving them goes back to today: the one rule that
    /// stops a food landing on the wrong day.
    var keepsDay: Bool { self == .log || self == .foods }
}

/// The ways into logging. Each opens straight to its first step.
enum LogMode: String, Identifiable, Hashable {
    case search, scan, camera, photoLibrary, describe, quickAdd
    var id: String { rawValue }
}

/// What a day adds up to so far, and what's logged for later.
struct DayIntake: Equatable {
    var eaten: Nutrients
    var later: Nutrients
    var all: Nutrients { eaten + later }
}

/// A short confirmation after logging, with Undo.
struct Toast: Identifiable, Equatable {
    var id = UUID()
    var message: String
    var undo: [UUID] = []
    /// Glasses of water and supplement doses the Undo takes back.
    var undoWater: [UUID] = []
    var undoDoses: [UUID] = []
    /// Entries just deleted, which the Undo brings back.
    var deleted: [FoodEntry] = []
    /// A fast just started (Undo removes it) or ended (Undo runs it again).
    var fast: FastUndo?
    /// A saved meal just deleted, which the Undo brings back.
    var deletedMeal: SavedMeal?
    /// Entries as they were before an edit, which the Undo puts back.
    var restore: [FoodEntry] = []

    enum FastUndo: Equatable {
        case started(UUID)
        case ended(Fast)
    }

    var canUndo: Bool {
        !undo.isEmpty || !undoWater.isEmpty || !undoDoses.isEmpty || !deleted.isEmpty || fast != nil || deletedMeal != nil || !restore.isEmpty
    }
}

/// The app's state: Stadig Macro's own synced records, what Stadig Lift and the hub published, what
/// Health knows, and the analysis computed from all of it.
@MainActor @Observable
final class AppModel {
    static let shared = AppModel(launch: .current)
    /// What Health records this app wrote carry as their source: the current id and the one it had
    /// before the 2026-10 rename, so samples saved before it still count as the app's own.
    static let ownBundlePrefixes = ["dev.svindland.stadig.macro", "dev.svindland.macrotrack"]
    static let tabKey = "app.tab"

    let store: RecordStore
    let shared: SharedContainer
    /// Where the widgets' snapshot goes: the App Group, or a fresh folder when nothing is kept.
    let widgetURL: URL?
    /// Whether this model talks to the notification center and WidgetKit: not in tests or UI tests.
    let usesSystemServices: Bool
    let catalog: FoodCatalog
    let purchases: Purchases
    let ai = MealAIService()
    /// The NIH supplement labels, when the build ships them.
    let supplementCatalog: SupplementCatalog?

    // Records.
    private(set) var profile: SharedProfile?
    private(set) var settings = MacroSettings()
    /// The log, split at the last time the clock was read: what's been eaten and what's for later.
    private(set) var foodLog = FoodLog([], now: Date())
    /// What's been eaten, oldest first. Food for later is in `foodLog`, and in `allEntries(on:)`.
    var entries: [FoodEntry] { foodLog.eaten }
    /// All the log by day, oldest first within each: a day's log without walking years of them.
    private var entriesByDay: [Day: [FoodEntry]] = [:]
    private(set) var weighIns: [WeighIn] = []
    private(set) var dayStatus: [DayStatus] = []
    private(set) var plan: PhasePlan?
    private(set) var checkIns: [CheckIn] = []
    private(set) var customFoods: [CustomFoodRecord] = []
    /// The person's numbers for catalog foods whose packages said otherwise, by the catalog's id
    /// (which the corrected food keeps).
    private(set) var corrections: [String: Food] = [:]
    private(set) var favorites: Set<String> = []
    private(set) var lifeModes: [LifeModePeriod] = []
    /// Meal plans, oldest first: the current or next one is the one shown.
    private(set) var mealPlans: [MealPlan] = []
    /// The supplement stack, by name, and every dose taken or skipped.
    private(set) var supplements: [Supplement] = []
    private(set) var supplementLogs: [SupplementLog] = []
    private(set) var water: [WaterLog] = []
    /// Fasts started on purpose, oldest first.
    private(set) var fasts: [Fast] = []
    /// Foods eaten together, saved under a name to log in one tap.
    private(set) var savedMeals: [SavedMeal] = []

    // From the other apps and the hub.
    private(set) var lift: AppSummary?
    private(set) var calendar: SystemCalendar?
    /// A profile another app wrote before Stadig Macro was set up: onboarding reuses it.
    private(set) var sharedProfile: SharedProfile?

    // Derived.
    private(set) var analysis: MacroAnalysis? {
        didSet { analysisVersion &+= 1 }
    }
    /// Bumped whenever the analysis is recomputed, for screens that derive something heavy from it
    /// off the main thread (the history) and need to know when to again.
    private(set) var analysisVersion = 0
    private(set) var logAgain: [LogAgainItem] = []
    /// Every saved meal, best first for now.
    private(set) var mealSuggestions: [MealSuggestion] = []
    /// Log Again, saved meals and "Same as" for the time the open logger logs at, when that isn't
    /// now (a picked time, or a past day): lunch for noon, even when caught up at 9 PM.
    private(set) var timedSuggestions: TimedSuggestions?
    /// The times of day this person usually eats, on the selected day, with what they last ate at
    /// each: the past day's catch-up, and times to pick in the logger.
    private(set) var usualTimes: [UsualMeal] = []
    /// Foods this person logs, for search ranking and last-used portions.
    private(set) var personal: [PersonalFood] = [] {
        didSet { personalVersion &+= 1 }
    }
    /// Bumped when the personal foods are rebuilt, for lists made from them off the main thread.
    private(set) var personalVersion = 0
    /// The one food that best fixes this week's shortest nutrient, ready to log.
    private(set) var microFix: MicroFix?
    /// A fermented food to log, while the week has had too few.
    private(set) var fermentedFix: FermentedFix?

    // Presentation.
    /// Where the app is, kept for the next launch. Links, widgets, Siri and controls land where they
    /// always did, whatever this says.
    var tab: AppTab = .today {
        didSet {
            guard tab != oldValue else { return }
            defaults?.set(tab.rawValue, forKey: Self.tabKey)
            if oldValue.keepsDay, !tab.keepsDay {
                selectedDay = today
                clearSelection()
            }
        }
    }
    /// The logger on screen. Closing it, by Done, a swipe or a link opening something else, drops
    /// its picked time here rather than in the sheet's onDismiss, which runs after the close
    /// animation: a "+" on a moment tapped meanwhile would lose its time to it.
    var logger: LogMode? {
        didSet { if logger == nil { loggerTime = nil } }
    }
    /// When a logger's foods were eaten; nil is now (or this time of day, on a past day). Only while
    /// the logger is open: it's cleared when the logger closes or the day changes, so a later one-tap
    /// log doesn't land at a time picked hours (or a day) before.
    var loggerTime: Date? {
        didSet { if loggerTime != oldValue { refreshTimedSuggestions() } }
    }
    var showSettings = false
    var showPaywall = false
    var showWeighIn = false
    /// The fast screen: start one, or follow the one running.
    var showFast = false
    /// The supplements screen: a sheet, or where the sidebar has it, that destination.
    var showSupplements: Bool {
        get { supplementsSheet }
        set {
            if newValue && usesSidebar {
                supplementsSheet = false
                tab = .supplements
            } else {
                supplementsSheet = newValue
            }
        }
    }
    private var supplementsSheet = false
    /// Whether the window has the sidebar's destinations (regular width: iPad, the Mac, Vision Pro),
    /// so finding a food or the supplements opens their screens rather than a sheet. The root view
    /// keeps it current; it's false for a model no screen shows (tests).
    var usesSidebar = false
    /// Asks the Foods screen to put the cursor in its search field (⌘F, Log Food, a widget's search).
    private(set) var foodSearchRequest = 0
    /// The foods picked out on the Log tab.
    var selection = LogSelection()
    /// Asks the Log tab to go to the hour a day opens on: back from a while away, or a tap on today.
    private(set) var logAnchorRequest = 0
    /// Asks Today to scroll to the day's supplements (a tap on a reminder): by evening the food
    /// above them can be a long way down.
    var supplementsScrollRequest = 0
    var toast: Toast?
    /// A photo dropped on the window, waiting for the photo logger to read it.
    @ObservationIgnored private var droppedPhoto: Data?
    var today: Day = .today
    /// The day the Log tab shows and everything logs to: today, unless the Log tab or Foods has moved
    /// it. It's the one place the day is kept, and it comes back to today on leaving those two, on
    /// launch, at midnight, on coming back after a while away, and from anywhere outside the app.
    var selectedDay: Day = .today {
        didSet {
            guard selectedDay != oldValue else { return }
            loggerTime = nil
            refreshCatchUp()
        }
    }

    /// The shared container mirrored to the person's other devices through the family's CloudKit
    /// database; nil when nothing is kept (tests, UI tests, `-inMemoryStore`).
    @ObservationIgnored private(set) var family: FamilySync?
    /// On a launch that found Stadig Macro not set up: the person's log and targets on its way from iCloud,
    /// which onboarding waits for. Nil when there was nothing to look for.
    private(set) var arrival: ICloudArrival?
    /// Puts what the Watch and the Mac logged into Health, once, as it syncs in (HealthBackfill.swift);
    /// nil when nothing is kept, and where there's no Health.
    @ObservationIgnored private(set) var healthBackfill: HealthBackfill?
    @ObservationIgnored private var sharedObserver: AnyObject?
    @ObservationIgnored private var storeObserver: AnyObject?
    @ObservationIgnored private var healthObserver: AnyObject?
    @ObservationIgnored private var healthReads = HealthReads()
    /// Where the last read of Health's weigh-ins left off, kept on this device; nil reads them all.
    @ObservationIgnored private(set) var weightAnchor: Data?
    @ObservationIgnored private var lastRevision = -1
    /// The store's `revision(of:)` for each kind when it was last read, so a save re-reads only its kind.
    @ObservationIgnored private var readRevisions: [String: Int] = [:]
    @ObservationIgnored private var foodCache: [String: Food] = [:]
    @ObservationIgnored private var personalTask: Task<Void, Never>?
    @ObservationIgnored private var fixTask: Task<Void, Never>?
    @ObservationIgnored private var fixKey: String?
    @ObservationIgnored private var fermentedTask: Task<Void, Never>?
    @ObservationIgnored private var plannerCache: MealPlanner?
    /// Wakes the model when a food's time comes, and when the day or the clock changes.
    @ObservationIgnored private var foodClock: FoodClock?
    /// Whether the analysis and the suggestions are worked out off the main thread: on, once launch
    /// is done, so a tap never waits on years of log. Off in tests, where the numbers are there as
    /// soon as a write returns, and for launch itself, so the first frame has them.
    @ObservationIgnored var backgroundAnalysis = false
    /// The analysis running now, and which recompute it was for: a newer one's replaces it.
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var analysisGeneration = 0
    /// When the app last left the front, to know a while away from a glance at a message.
    @ObservationIgnored private var wentAway: Date?
    @ObservationIgnored private var targetsByDay: (version: Int, targets: [Day: DailyTargets]) = (0, [:])
    /// Where "Not now" on a suggestion is remembered between launches; nil keeps it for this run.
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var hiddenUntil: [String: Date] = [:]
    /// Bumped by "another plan", so each shuffle is a different week.
    @ObservationIgnored var planVariation = 0

    /// Stadig Macro's own synced store and the App Group, or, when nothing is to be kept (tests, UI
    /// tests, `-inMemoryStore`), an in-memory store and a fresh folder for the shared files and the
    /// widgets' snapshot, so a test or a sample run never writes where the other apps and the
    /// widgets read.
    convenience init(launch: LaunchOptions) {
        // Tests and UI tests: no Health prompts, reads or writes, from before anything asks.
        if launch.isQuiet { HealthBridge.shared.disable() }
        let memory = launch.usesInMemoryStore
        let store = RecordStore(name: "MacroTrack", cloudKitContainer: memory ? nil : "iCloud.dev.svindland.stadig.macro", inMemory: memory)
        let (shared, widgetURL) = Self.sharing(keepingNothing: memory)
        #if DEBUG
        if launch.has("-resetData") { store.eraseAll() }
        #endif
        self.init(store: store, shared: shared, widgetURL: widgetURL, defaults: memory ? nil : .standard, usesSystemServices: !launch.isQuiet)
        if !memory {
            family = FamilySync(shared: shared)
            healthBackfill = HealthBackfill.live(store: store)
        }
        #if DEBUG
        // The wait a second device shows while its data comes down, over a store that never gets any.
        if launch.has("-simulateICloudData"), !onboarded { arrival = ICloudArrival(store: store) { .records } }
        #endif
    }

    /// Where the shared files and the widgets' snapshot go: the App Group, or a fresh folder of the
    /// launch's own when nothing is kept, never the App Group (a simulator may hand out a folder for
    /// any group id, so a made-up one isn't enough).
    static func sharing(keepingNothing: Bool) -> (SharedContainer, URL?) {
        guard keepingNothing else { return (SharedContainer(), MacroSnapshot.appGroupURL) }
        let folder = URL.temporaryDirectory.appending(path: "MacroTrack \(UUID().uuidString)", directoryHint: .isDirectory)
        let shared = SharedContainer(directory: folder.appending(path: "SystemShared", directoryHint: .isDirectory))
        return (shared, folder.appending(path: "widget.json"))
    }

    /// A model over these: what tests build, over an in-memory store and a temporary container.
    init(
        store: RecordStore, shared: SharedContainer, widgetURL: URL?, defaults: UserDefaults? = nil,
        catalog: FoodCatalog = .standard(), supplementCatalog: SupplementCatalog? = .standard(), usesSystemServices: Bool = false,
        backgroundAnalysis: Bool = false
    ) {
        self.store = store
        self.shared = shared
        self.widgetURL = widgetURL
        self.defaults = defaults
        self.catalog = catalog
        self.supplementCatalog = supplementCatalog
        self.usesSystemServices = usesSystemServices
        purchases = Purchases(.macro, store: store)
        weightAnchor = defaults?.data(forKey: Self.weightAnchorKey)
        tab = defaults?.string(forKey: Self.tabKey).flatMap(AppTab.init(rawValue:)) ?? .today
        foodClock = FoodClock { [weak self] in self?.refreshDay() }
        reload()
        self.backgroundAnalysis = backgroundAnalysis
        // A second device or a reinstall: onboarding waits while the person's data comes down.
        if !onboarded { arrival = ICloudArrival.start(for: store) }
        sharedObserver = SharedContainer.observeChanges { [weak self] in self?.readShared() }
        // Another device's changes, as CloudKit imports them while the app is open or woken for them.
        storeObserver = store.observeChanges { [weak self] in self?.reloadIfChanged() }
        // Open the catalogs and warm the search index off the main thread, so the first search is instant.
        let catalog = catalog
        Task.detached(priority: .utility) { catalog.prewarm() }
    }

    var onboarded: Bool { profile != nil && settings.onboardedAt != nil }

    var units: UnitPreference { profile?.units ?? .regional }

    // MARK: Loading

    /// Re-reads the kinds of record that changed since the last read, then recomputes. Unchanged
    /// kinds aren't read or sorted again, but the analysis still runs over everything, so it's work
    /// in proportion to the history.
    /// `readingShared` false is for this model's own saves: a change to the shared files arrives by
    /// its own notification, and `refreshDay` looks again on the way back to the front.
    func reload(readingShared: Bool = true) {
        let interval = LogPath.begin("reload")
        defer { LogPath.end(interval) }
        if needsReading(ProfileRecord.self) { profile = store.all(ProfileRecord.self).first?.profile }
        if needsReading(MacroSettings.self) {
            settings = MacroSettings.inForce(store.all(MacroSettings.self)) ?? MacroSettings(id: MacroSettings.singletonID)
        }
        let entriesChanged = needsReading(FoodEntry.self)
        if entriesChanged {
            let reading = LogPath.begin("readEntries")
            let all = store.all(FoodEntry.self).sorted { $0.date < $1.date }
            entriesByDay = Dictionary(grouping: all, by: \.day)
            foodLog = FoodLog(sorted: all, now: Date())
            // A food deleted from under the selection, here or on another device, leaves it.
            if !selection.isEmpty { selection.ids.formIntersection(all.map(\.id)) }
            LogPath.end(reading)
        }
        if needsReading(WeighIn.self) { weighIns = store.all(WeighIn.self).sorted { $0.date < $1.date } }
        if needsReading(DayStatus.self) { dayStatus = store.all(DayStatus.self) }
        if needsReading(PhasePlan.self) { plan = store.all(PhasePlan.self).first }
        if needsReading(CheckIn.self) { checkIns = Self.ordered(store.all(CheckIn.self)) }
        let customChanged = needsReading(CustomFoodRecord.self)
        if customChanged { customFoods = store.all(CustomFoodRecord.self) }
        let correctionsChanged = needsReading(FoodCorrection.self)
        if correctionsChanged {
            corrections = Dictionary(store.all(FoodCorrection.self).map { ($0.food.id, $0.food) }, uniquingKeysWith: { first, _ in first })
        }
        let favoritesChanged = needsReading(FavoriteRecord.self)
        if favoritesChanged { favorites = Set(store.all(FavoriteRecord.self).map(\.foodID)) }
        if needsReading(Supplement.self) {
            supplements = store.all(Supplement.self).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        if needsReading(SupplementLog.self) { supplementLogs = store.all(SupplementLog.self).sorted { $0.date < $1.date } }
        if needsReading(WaterLog.self) { water = store.all(WaterLog.self).sorted { $0.date < $1.date } }
        if needsReading(Fast.self) { fasts = store.all(Fast.self).sorted { $0.start < $1.start } }
        if needsReading(SavedMeal.self) { savedMeals = store.all(SavedMeal.self) }
        if needsReading(MealPlan.self) { reloadMealPlans() }
        applyAISetting()
        if readingShared {
            let reading = LogPath.begin("readShared")
            readShared(recompute: false)
            LogPath.end(reading)
        }
        recompute()
        if entriesChanged || customChanged || favoritesChanged || correctionsChanged { refreshPersonal() }
        lastRevision = store.revision
    }

    /// Whether records of a kind changed since this model last read them, noting that it's reading them now.
    private func needsReading<T: StoredRecord>(_ type: T.Type) -> Bool {
        let revision = store.revision(of: type)
        guard readRevisions[T.kind] != revision else { return false }
        readRevisions[T.kind] = revision
        return true
    }

    func reloadMealPlans() {
        readRevisions[MealPlan.kind] = store.revision(of: MealPlan.self)
        mealPlans = store.all(MealPlan.self).sorted { $0.start < $1.start }
    }

    /// Check-ins by day, and within a day oldest first, as the analysis orders them: the last of a
    /// day is the one in force (a plan started after the day's check-in, or two devices before they synced).
    static func ordered(_ checkIns: [CheckIn]) -> [CheckIn] {
        checkIns.sorted { $0.day != $1.day ? $0.day < $1.day : $0.updatedAt < $1.updatedAt }
    }

    /// Picks up changes that arrived from iCloud.
    func reloadIfChanged() {
        if store.revision != lastRevision { reload() }
    }

    /// Catches up with the store and the calendar, for the ways in that don't make the scene active
    /// (Siri, Shortcuts, a notification's button), where `today` can still be yesterday.
    func refreshDay() {
        reloadIfChanged()
        readShared()
        if today != .today || foodLog.isStale(at: Date()) { recompute() }
    }

    /// New food saved and put in its place, as the store holds it (to the millisecond, which a
    /// fast's start is compared with): years of log aren't sorted and grouped again for one more. A
    /// big batch is left for `reload` to read whole.
    private func insert(_ new: [FoodEntry]) {
        let saving = LogPath.begin("save")
        let stored = store.insert(new).sorted { $0.date < $1.date }
        LogPath.end(saving)
        guard new.count <= 32 else { return }
        foodLog = foodLog.inserting(stored, now: Date())
        for entry in stored {
            var day = entriesByDay[entry.day] ?? []
            day.insert(entry, at: day.firstIndex { $0.date > entry.date } ?? day.endIndex)
            entriesByDay[entry.day] = day
        }
        readRevisions[FoodEntry.kind] = store.revision(of: FoodEntry.self)
    }

    /// Rebuilds the AI engine when the Private Cloud Compute setting changed: on this device, on
    /// another device (synced), or when a new device's synced opt-out arrives after launch.
    private func applyAISetting() {
        if ai.allowCloud != settings.allowCloudAI { ai.configure(catalog: catalog, allowCloud: settings.allowCloudAI) }
    }

    /// What other apps and the hub published. Our own writes notify us too, so this only
    /// recomputes when something actually changed.
    func readShared(recompute again: Bool = true) {
        let lift = shared.read(.summary(.liftTrack))
        let calendar = shared.read(.calendar)
        let sharedProfile = shared.read(.profile)
        let lifeModes = syncLifeModes()
        let adopted = adopt(sharedProfile)
        let changed = adopted || lift != self.lift || calendar != self.calendar || sharedProfile != self.sharedProfile || lifeModes != self.lifeModes
        guard changed else { return }
        self.lift = lift
        self.calendar = calendar
        self.sharedProfile = sharedProfile
        self.lifeModes = lifeModes
        if again { recompute() }
    }

    /// Takes up a newer shared profile once set up: units, sex, birth year, height and training days
    /// are edited in Stadig Lift, which writes them to the shared file. Onboarding reads the shared
    /// one itself.
    private func adopt(_ newer: SharedProfile?) -> Bool {
        guard onboarded, let newer, let profile, Self.milliseconds(newer.updatedAt) > Self.milliseconds(profile.updatedAt) else { return false }
        store.save(ProfileRecord(newer))
        self.profile = newer
        return true
    }

    /// Life modes from every app: the shared file and this app's synced copies merged, the newest
    /// edit or delete of each winning (deletes are kept as tombstones so they keep spreading). What
    /// came from elsewhere is kept here too, so it reaches this app on the person's other devices,
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
                try shared.write(merged, to: .lifeModes, by: .macroTrack)
            } catch {
                appLog.error("Couldn't share the life modes: \(error.localizedDescription)")
            }
        }
        return merged.live
    }

    /// Whole milliseconds, the precision the store and the shared container keep.
    private static func milliseconds(_ date: Date) -> Double { (date.timeIntervalSince1970 * 1000).rounded() }

    var state: MacroState? { state(now: Date()) }

    /// What the analysis reads at a moment. It's given all the log and keeps what's been eaten by then.
    func state(now: Date) -> MacroState? {
        guard let profile else { return nil }
        return MacroState(
            profile: profile, settings: settings, entries: foodLog.all, weighIns: weighIns, dayStatus: dayStatus, plan: plan,
            lifeModes: lifeModes, calendar: calendar, lift: lift, checkIns: checkIns, supplements: supplements,
            supplementLogs: supplementLogs, water: water, fasts: fasts, today: today, now: now)
    }

    func recompute() {
        let interval = LogPath.begin("recompute")
        defer { LogPath.end(interval) }
        if today != .today {
            selectedDay = .today
            today = .today
        }
        let now = Date()
        // Every recompute reads the clock, so this is where a food's time passing is noticed.
        if foodLog.isStale(at: now) {
            foodLog = foodLog.at(now)
            healthBackfill?.run()
        }
        defer { foodClock?.arm(for: foodLog.nextChange) }
        refreshCatchUp()
        analysisGeneration &+= 1
        analysisTask?.cancel()
        analysisTask = nil
        let state = state(now: now)
        let suggestions = suggestionEntries
        let eaten = entries
        let meals = savedMeals
        guard backgroundAnalysis, let state else {
            show(Self.worked(state, suggestions: suggestions, eaten: eaten, meals: meals, now: now))
            return
        }
        let generation = analysisGeneration
        analysisTask = Task.detached(priority: .userInitiated) { [weak self] in
            let derived = Self.worked(state, suggestions: suggestions, eaten: eaten, meals: meals, now: now)
            guard !Task.isCancelled else { return }
            await self?.show(derived, generation: generation)
        }
    }

    /// What a recompute works out from the whole log, which is why it can run off the main thread.
    private struct Derived: Sendable {
        var state: MacroState?
        var analysis: MacroAnalysis?
        var logAgain: [LogAgainItem]
        var meals: [MealSuggestion]
    }

    private nonisolated static func worked(
        _ state: MacroState?, suggestions: [FoodEntry], eaten: [FoodEntry], meals: [SavedMeal], now: Date
    ) -> Derived {
        let rankings = LogPath.begin("rankings")
        let logAgain = LogAgain.rank(suggestions, now: now)
        let ranked = SavedMeals.rank(meals, entries: eaten, now: now)
        LogPath.end(rankings)
        let interval = LogPath.begin("analyse")
        defer { LogPath.end(interval) }
        return Derived(state: state, analysis: state.map(MacroAnalyst.analyse), logAgain: logAgain, meals: ranked)
    }

    /// A finished analysis, unless a newer recompute has started since.
    private func show(_ derived: Derived, generation: Int) {
        guard generation == analysisGeneration else { return }
        analysisTask = nil
        show(derived)
    }

    private func show(_ derived: Derived) {
        logAgain = derived.logAgain
        mealSuggestions = derived.meals
        analysis = derived.analysis
        guard var state = derived.state, let found = derived.analysis else { return }
        // The weekly check-in applies itself: small, capped steps, explained on Today.
        if let due = found.dueCheckIn, plan != nil, onboarded {
            store.save(due)
            checkIns = Self.ordered(store.all(CheckIn.self))
            readRevisions[CheckIn.kind] = store.revision(of: CheckIn.self)
            lastRevision = store.revision
            if backgroundAnalysis {
                recompute()
                return
            }
            state = self.state(now: state.now) ?? state
            analysis = MacroAnalyst.analyse(state)
        }
        publish(state)
        refreshMicroFix()
        refreshFermentedFix()
        if usesSystemServices {
            SupplementReminders.schedule(self)
            FastReminders.schedule(self)
            FastActivityBridge.update(self)
        }
    }

    /// Waits until the analysis running now, and any a newer change starts meanwhile, has shown, or
    /// until `limit` has passed: Siri reads the numbers straight after a write, with nothing on screen
    /// to catch up.
    func analysisFinished(within limit: Duration) async {
        let clock = ContinuousClock()
        let deadline = clock.now + limit
        while analysisTask != nil, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Finds a fermented food to suggest, off the main thread, once the week is short of them.
    /// `force` searches again with the latest personal foods, keeping the current one on screen
    /// until the new one is found.
    private func refreshFermentedFix(force: Bool = false) {
        guard analysis?.quality.fermentedStatus == .off else {
            fermentedTask?.cancel()
            fermentedTask = nil
            fermentedFix = nil
            return
        }
        guard force || (fermentedFix == nil && fermentedTask == nil) else { return }
        fermentedTask?.cancel()
        let catalog = catalog
        let personal = personal
        fermentedTask = Task.detached(priority: .utility) { [weak self] in
            let fix = FermentedFix.find(personal: personal, catalog: catalog)
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.fermentedTask = nil
                if self.analysis?.quality.fermentedStatus == .off, self.fermentedFix != fix { self.fermentedFix = fix }
            }
        }
    }

    /// Finds a food for the shortest watched nutrient off the main thread, when it changes. `force`
    /// searches again with the latest personal foods, keeping the current one on screen meanwhile.
    private func refreshMicroFix(force: Bool = false) {
        let short = analysis?.micros.flagged.first { $0.nutrient.goal == .atLeast && $0.status == .low }
        guard let short, let target = short.target else {
            fixTask?.cancel()
            microFix = nil
            fixKey = nil
            return
        }
        guard force || fixKey != short.nutrient.key || microFix == nil else { return }
        // A fix for another nutrient is no use while this one is found.
        if fixKey != short.nutrient.key { microFix = nil }
        fixKey = short.nutrient.key
        fixTask?.cancel()
        let catalog = catalog
        let personal = personal
        fixTask = Task.detached(priority: .utility) { [weak self] in
            let fix = MicroFix.find(for: short.nutrient, target: target, personal: personal, catalog: catalog)
            await MainActor.run {
                guard let self, !Task.isCancelled, self.fixKey == short.nutrient.key, self.microFix != fix else { return }
                self.microFix = fix
            }
        }
    }

    @ObservationIgnored private var lastPublished: (nutrition: NutritionSummary, summary: AppSummary)?

    /// The phase and day-by-day nutrition for Stadig Lift and the hub, written only when they change.
    private func publish(_ state: MacroState) {
        let interval = LogPath.begin("publish")
        defer { LogPath.end(interval) }
        guard let analysis else { return }
        var nutrition = MacroAnalyst.nutritionSummary(state, analysis)
        var summary = MacroAnalyst.appSummary(state, analysis)
        if let last = lastPublished {
            nutrition.updated = last.nutrition.updated
            summary.updated = last.summary.updated
        }
        // Unchanged since the last publish: nothing to read or write. Otherwise the files are compared
        // too, so a launch doesn't rewrite them and wake the other apps for nothing.
        if lastPublished.map({ $0.nutrition != nutrition || $0.summary != summary }) ?? true {
            do {
                try shared.writeIfChanged(nutrition, to: .nutrition, by: .macroTrack, stamp: \.updated)
                try shared.writeIfChanged(summary, to: .summary(.macroTrack), by: .macroTrack, stamp: \.updated)
                lastPublished = (nutrition, summary)
            } catch {
                appLog.error("Couldn't publish the summary: \(error.localizedDescription)")
            }
        }
        WidgetBridge.update(self)
    }

    // MARK: Foods

    /// A food by id: the person's correction or own food first, as the store has it now (an edit on
    /// another device included), else the catalogs', which are cached.
    func food(id: String) -> Food? {
        if let corrected = corrections[id] { return corrected }
        if let own = customFoods.first(where: { $0.food.id == id }) { return own.food }
        if let cached = foodCache[id] { return cached }
        let found = catalog.food(id: id)
        if let found { foodCache[id] = found }
        return found
    }

    func food(barcode: String, symbology: Barcode.Symbology? = nil) -> Food? {
        let keys = Set(Barcode.keys(for: barcode, symbology: symbology) + [barcode])
        if let own = customFoods.first(where: { food in
            food.food.barcode.map { keys.contains($0) || Barcode.keys(for: $0).contains(where: keys.contains) } ?? false
        }) {
            return own.food
        }
        return catalog.food(barcode: barcode, symbology: symbology).map { corrected($0) }
    }

    // MARK: Corrections

    /// The person's numbers for a catalog food, when they corrected it; else the food as it is.
    func corrected(_ food: Food) -> Food { corrections[food.id] ?? food }

    /// Search results with the person's numbers in place of the catalog's.
    func corrected(_ matches: [FoodMatch]) -> [FoodMatch] { Self.corrected(matches, by: corrections) }

    /// The same, off the main thread, with the corrections as they were when the search began.
    nonisolated static func corrected(_ matches: [FoodMatch], by corrections: [String: Food]) -> [FoodMatch] {
        guard !corrections.isEmpty else { return matches }
        return matches.map { match in
            var match = match
            match.food = corrections[match.food.id] ?? match.food
            return match
        }
    }

    func isCorrected(_ foodID: String) -> Bool { corrections[foodID] != nil }

    /// Saves a food's numbers as the person corrected them: one of their own foods is changed in
    /// place, and a catalog food gets a correction under its own id, which its barcode, searches
    /// and Log Again use from now on. Entries already logged keep their numbers.
    @discardableResult
    func saveCorrection(_ food: Food) -> Food {
        if let id = CustomFoodRecord.recordID(fromFoodID: food.id) { return save(customFood: food, replacing: id) }
        let correction = FoodCorrection(food: food)
        store.save(correction)
        reload()
        return correction.food
    }

    /// Takes a correction away, so the catalog's numbers are used again; returns the catalog's food.
    @discardableResult
    func removeCorrection(of foodID: String) -> Food? {
        store.delete(FoodCorrection.self, id: FoodCorrection.id(for: foodID))
        reload()
        return food(id: foodID)
    }

    /// An entry with the person's numbers for its food, when they've corrected it since the entry
    /// was made: a copy logged again (Log Again, a moment, a saved meal, Same as yesterday) or a
    /// catalog match (a description, a photo) gets the same amount at their numbers. An entry
    /// whose amount isn't known keeps its own.
    func withCorrection(_ entry: FoodEntry) -> FoodEntry {
        guard let id = entry.foodID, let food = corrections[id], entry.grams != nil || entry.count != nil else { return entry }
        let amount = FoodUnits.logged(for: food, unitID: entry.unitID, count: entry.count, amount: entry.grams)
        var fresh = self.entry(
            for: food, count: amount.count, unit: amount.unit, source: entry.source, confidence: entry.confidence, date: entry.date)
        guard fresh.nutrients != entry.nutrients || fresh.name != entry.name || fresh.brand != entry.brand else { return entry }
        fresh.id = entry.id
        fresh.day = entry.day
        fresh.updatedAt = entry.updatedAt
        fresh.loggedAt = entry.loggedAt
        return fresh
    }

    /// The log as the suggestions read it: entries of a food corrected since carry the person's
    /// numbers, so a Log Again chip or "Same as yesterday" says what a tap logs. The analysis and
    /// the timeline keep the entries as logged.
    private var suggestionEntries: [FoodEntry] { corrections.isEmpty ? entries : entries.map(withCorrection) }

    /// Rebuilds the personal foods off the main thread: logged foods by frequency and recency,
    /// with the last portion used, plus favourites and the person's own foods.
    private func refreshPersonal() {
        personalTask?.cancel()
        let entries = entries
        let favorites = favorites
        let custom = customFoods.map(\.food)
        let corrected = corrections
        let catalog = catalog
        let known = foodCache
        personalTask = Task.detached(priority: .utility) { [weak self] in
            let now = Date()
            var byFood: [String: (score: Double, last: FoodEntry)] = [:]
            for entry in entries {
                guard let id = entry.foodID else { continue }
                if Task.isCancelled { return }
                let days = max(0, now.timeIntervalSince(entry.date) / 86400)
                let weight = pow(0.5, days / 30)
                var current = byFood[id] ?? (0, entry)
                current.score += weight
                if entry.date > current.last.date { current.last = entry }
                byFood[id] = current
            }
            // The person's corrections stand in for the catalog's foods, and count as their own
            // even before they're logged, so a search finds them first.
            var foods = corrected
            for food in custom { foods[food.id] = food }
            var result: [PersonalFood] = []
            let ids = Set(byFood.keys).union(favorites).union(custom.map(\.id)).union(corrected.keys)
            for id in ids.sorted(by: { (byFood[$0]?.score ?? 0) > (byFood[$1]?.score ?? 0) }).prefix(400) {
                if Task.isCancelled { return }
                guard let food = foods[id] ?? known[id] ?? catalog.food(id: id) else { continue }
                foods[id] = food
                let usage = byFood[id]
                result.append(
                    PersonalFood(
                        food: food, score: (usage?.score ?? 0) + (favorites.contains(id) ? 2 : 0), favorite: favorites.contains(id),
                        lastCount: usage?.last.count, lastUnitID: usage?.last.unitID, lastAmount: usage?.last.grams,
                        lastLogged: usage?.last.date))
            }
            // Only the catalog's foods are cached: a correction taken away gives the catalog's back.
            let found = foods.filter { corrected[$0.key] == nil }
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                let before = self.personal.map(Self.fixInput)
                self.personal = result
                self.foodCache.merge(found) { a, _ in a }
                // A fix found before these foods were known may have a better one now. The current
                // one stays on screen until the search is done.
                if result.map(Self.fixInput) != before {
                    self.refreshMicroFix(force: true)
                    self.refreshFermentedFix(force: true)
                }
            }
        }
    }

    /// What of a personal food the nutrient and fermented searches use: which food, in what order,
    /// at what usual portion.
    nonisolated private static func fixInput(_ p: PersonalFood) -> String {
        "\(p.food.id)|\(p.lastUnitID ?? "")|\(p.lastCount ?? 0)|\(p.lastAmount ?? 0)"
    }

    func personalFood(_ id: String) -> PersonalFood? { personal.first { $0.food.id == id } }

    func isFavorite(_ foodID: String) -> Bool { favorites.contains(foodID) }

    func toggleFavorite(_ foodID: String) {
        if favorites.contains(foodID) {
            store.delete(FavoriteRecord.self, id: FavoriteRecord.id(for: foodID))
        } else {
            store.save(FavoriteRecord(foodID: foodID))
        }
        reload()
    }

    /// Saves one of the person's own foods; `replacing` updates the food a save made earlier (a
    /// label corrected after saving it once) instead of adding a second with the same barcode.
    @discardableResult
    func save(customFood food: Food, replacing id: UUID? = nil) -> Food {
        let record = CustomFoodRecord(id: id ?? UUID(), food: food)
        store.save(record)
        reload()
        return record.food
    }

    // MARK: Logging

    /// Opens a logger, its foods eaten at `time` (nil is now). The time lasts while the logger is open.
    /// Where the sidebar has the Foods screen, a search at no particular time opens that instead.
    func openLogger(_ mode: LogMode, at time: Date? = nil) {
        if mode == .search, time == nil, usesSidebar {
            showFoods()
            return
        }
        loggerTime = time
        logger = mode
    }

    /// A day in the Log tab, where a day other than today is looked at.
    func show(day: Day) {
        tab = .log
        selectedDay = day
    }

    /// Back to today's log, at the hour it is.
    func showToday() {
        selectedDay = today
        logAnchorRequest &+= 1
    }

    /// How long away counts as a new visit: long enough that the day being looked at was for then.
    static let awayLimit: TimeInterval = 10 * 60

    func wentToBackground(at date: Date = Date()) { wentAway = date }

    /// After a while away the Log tab is back on today at the hour it is, unless something's open
    /// that's mid-way through a day.
    func cameToFront(at date: Date = Date()) {
        defer { wentAway = nil }
        guard let wentAway, date.timeIntervalSince(wentAway) >= Self.awayLimit, logger == nil, selection.isEmpty else { return }
        showToday()
    }

    /// A destination by name (the Go menu, ⌘1…⌘8). One only the sidebar has, asked for without one
    /// (an iPhone with a keyboard), opens its nearest equivalent instead.
    func go(to destination: AppTab) {
        guard destination.isSidebarOnly, !usesSidebar else {
            if destination == .foods { showFoods() } else { tab = destination }
            return
        }
        switch destination {
        case .foods: openLogger(.search)
        case .supplements: showSupplements = true
        default: tab = destination.compactFallback
        }
    }

    /// The Foods screen with the cursor in its search.
    func showFoods() {
        logger = nil
        tab = .foods
        foodSearchRequest &+= 1
    }

    /// A photo dropped on the window: the photo logger opens and reads it, as if it were chosen there.
    func logDroppedPhoto(_ data: Data) {
        dismissSheets()
        selectedDay = today
        droppedPhoto = data
        openLogger(.photoLibrary)
    }

    /// The dropped photo, once: the logger that reads it takes it.
    func takeDroppedPhoto() -> Data? {
        defer { droppedPhoto = nil }
        return droppedPhoto
    }

    /// Brings the offer up if it's due, on opening the app. Never over a sheet someone is in the
    /// middle of: it waits for the next time they open the app.
    func askForPurchaseIfDue() {
        guard onboarded, purchases.offerDue, logger == nil, !showWeighIn, !showFast, !showSupplements, !showSettings else { return }
        showPaywall = true
    }

    /// Closes whichever sheet is up, so one asked for from outside (a widget, a control, Siri) can
    /// open: only one shows at a time. A screen's own sheet (an entry being edited) gives way by
    /// itself when one of these presents: SwiftUI replaces it (LoggingUITests checks that).
    func dismissSheets() {
        logger = nil
        showWeighIn = false
        showFast = false
        showSupplements = false
        showSettings = false
        showPaywall = false
    }

    /// When something logged now was eaten: the time picked in the open logger, else now; on a
    /// past day being caught up, the same time of day there.
    func logDate() -> Date {
        if let loggerTime { return loggerTime }
        let now = Date()
        guard selectedDay != today else { return now }
        return selectedDay.at(sameTimeAs: now)
    }

    /// The selected day at a time of day, for the logger's time choices.
    func onSelectedDay(_ time: Date) -> Date {
        let clock = Calendar(identifier: .gregorian).dateComponents([.hour, .minute], from: time)
        return selectedDay.at(hour: clock.hour ?? 12, minute: clock.minute ?? 0)
    }

    /// A ready-to-save entry for a food and portion, timed for the selected day (or at `date`). A
    /// drink keeps its fluid, and its caffeine when the catalog didn't list it (a café latte, a can
    /// without it).
    func entry(for food: Food, count: Double, unit: PortionUnit, source: EntrySource, confidence: Double? = nil, date: Date? = nil) -> FoodEntry {
        let amount = FoodUnits.amount(count, unit)
        var micros = FoodUnits.micros(food, count: count, unit: unit)
        let drink =
            Hydration.isDrink("\(food.name) \(food.brand ?? "")")
            || (food.basis == .ml && !Self.notDrunk.contains { food.name.localizedCaseInsensitiveContains($0) })
        if drink, micros["caffeine"] == nil, let mg = Caffeine.estimate(name: food.name, brand: food.brand, grams: amount) {
            micros["caffeine"] = mg
        }
        return FoodEntry(
            date: date ?? logDate(), name: food.name, brand: food.brand, foodID: food.id,
            amountLabel: FoodUnits.entryLabel(for: food, count: count, unit: unit, estimate: confidence != nil),
            grams: amount, unitID: unit.id, count: count, nutrients: FoodUnits.nutrients(food, count: count, unit: unit),
            micros: micros, processing: food.processing, fermented: food.fermented,
            fluid: drink ? amount : nil, source: source, confidence: confidence)
    }

    /// Foods sold by the millilitre that aren't drunk.
    private static let notDrunk = [
        "oil", "sauce", "syrup", "vinegar", "dressing", "ketchup", "mayo", "honey", "cream", "creamer", "soup",
        "spray", "extract", "marinade", "gravy",
    ]

    /// Saves entries, shows "Logged … Undo", and writes them to Health. A meal logged during a fast
    /// ends it, and says so: the Undo puts the fast back with the food.
    func log(_ new: [FoodEntry], message: String? = nil) {
        let interval = LogPath.begin("log")
        defer { LogPath.end(interval) }
        // A food the person corrected is logged at their numbers, however it was found.
        let new = LogAgain.settled(corrections.isEmpty ? new : new.map(withCorrection), now: Date())
        guard !new.isEmpty else { return }
        let fasting = analysis?.fast
        insert(new)
        reload(readingShared: false)
        refreshPersonal()
        let kcal = new.map(\.nutrients.kcal).reduce(0, +)
        let text = message ?? (new.count == 1 ? "Logged \(new[0].name)" : "Logged \(new.count) foods")
        let caffeine = new.compactMap { $0.micros?["caffeine"] }.reduce(0, +)
        let detail = kcal < 15 && caffeine >= 1 ? "\(Format.whole(caffeine)) mg caffeine" : Format.kcal(kcal)
        let run = fasting.flatMap { fastRun($0.fast) }
        if let run, !run.isRunning, let end = run.end {
            toast = Toast(message: "\(text) · ended your \(Format.duration(run.duration(at: end))) fast", undo: new.map(\.id))
        } else {
            toast = Toast(message: "\(text) · \(detail)", undo: new.map(\.id))
        }
        syncHealth(new)
    }

    /// Health holds what's been eaten and nothing else, so these entries go in if their time has
    /// come, and any copy of one moved ahead of now comes out. The rest of the time, a food reaching
    /// its time is written by the backfill, dated when it was eaten.
    private func syncHealth(_ changed: [FoodEntry]) {
        let log = FoodLog(changed, now: Date())
        let eaten = log.eaten
        let later = log.upcoming.map(\.id)
        if settings.saveToHealth, !eaten.isEmpty { Task { await HealthBridge.shared.saveFoods(eaten.map(Self.healthFood)) } }
        if !later.isEmpty { Task { await HealthBridge.shared.deleteFoods(ids: later) } }
    }

    /// A fast as it stands now, from its own days: the analysis may not be back yet after a change.
    func fastRun(_ fast: Fast) -> FastRun? {
        let days = DayRange(Day(fast.start), today).days.flatMap { entries(on: $0) }
        return Fasting.runs([fast], entries: days, now: Date()).first
    }

    func update(_ entry: FoodEntry) {
        update([entry])
    }

    /// Saves edits together, with one write to Health. A `message` also says so, with an Undo that
    /// puts every entry back as it was.
    func update(_ edits: [FoodEntry], message: String? = nil) {
        guard !edits.isEmpty else { return }
        let before = entriesBefore(edits)
        let saved = edited(edits, from: before)
        store.save(saved)
        reload()
        syncHealth(saved)
        if let message { toast = Toast(message: message, restore: Array(before.values)) }
    }

    /// The entries as stored now, by id, of the ones about to be edited.
    private func entriesBefore(_ edits: [FoodEntry]) -> [UUID: FoodEntry] {
        let ids = Set(edits.map(\.id))
        return Dictionary(foodLog.all.lazy.filter { ids.contains($0.id) }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func edited(_ edits: [FoodEntry], from before: [UUID: FoodEntry]) -> [FoodEntry] {
        let now = Date()
        return edits.map { edit in (before[edit.id] ?? edit).edited(at: now) { $0 = edit } }
    }

    /// Entries back as they were before an edit, each on the day it was on, stamped now.
    private func restore(_ versions: [FoodEntry]) {
        let before = entriesBefore(versions)
        let days = Dictionary(versions.map { ($0.id, $0.day) }, uniquingKeysWith: { first, _ in first })
        let saved = edited(versions, from: before).map { entry in
            var entry = entry
            entry.day = days[entry.id] ?? entry.day
            return entry
        }
        store.save(saved)
        reload()
        syncHealth(saved)
    }

    /// Deletes entries (and their Health samples), with "Deleted … Undo": a whole moment goes in two taps.
    func delete(entries ids: [UUID]) {
        let gone = Set(ids)
        let removed = foodLog.all.filter { gone.contains($0.id) }
        store.delete(FoodEntry.self, ids: ids)
        reload()
        Task { await HealthBridge.shared.deleteFoods(ids: ids) }
        if !removed.isEmpty {
            toast = Toast(message: removed.count == 1 ? "Deleted \(removed[0].name)" : "Deleted \(removed.count) foods", deleted: removed)
        }
    }

    func undo(_ toast: Toast) {
        if !toast.undo.isEmpty { delete(entries: toast.undo) }
        if !toast.undoWater.isEmpty { delete(water: toast.undoWater) }
        if !toast.undoDoses.isEmpty { delete(doses: toast.undoDoses) }
        if !toast.deleted.isEmpty { bringBack(toast.deleted) }
        if let fast = toast.fast { undo(fast) }
        if let meal = toast.deletedMeal { save(meal) }
        if !toast.restore.isEmpty { restore(toast.restore) }
        self.toast = nil
    }

    /// Deleted entries saved again, stamped now: the store keeps whichever is newer, and the delete
    /// is newer than the entries as they were. Each is still as first logged, so a day caught up on
    /// Monday and undone on Thursday stays a day logged live.
    private func bringBack(_ deleted: [FoodEntry]) {
        let now = Date()
        let restored = deleted.map { $0.edited(at: now) }
        store.save(restored)
        reload()
        syncHealth(restored)
    }

    /// One tap from the Log again row: the same food and amount, now.
    func logAgain(_ item: LogAgainItem) {
        log([LogAgain.copy(item.template, to: logDate())])
    }

    /// A whole moment eaten again: yesterday's breakfast, or what was just logged an hour ago.
    func logAgain(_ moment: Moment, at date: Date? = nil) {
        let copies = LogAgain.copy(moment, to: date ?? logDate())
        log(copies, message: moment.entries.count == 1 ? nil : "Logged \(moment.entries.count) foods again")
    }

    /// What was eaten around now on a recent day, while nothing's logged near now today.
    var usualNow: Moment? {
        guard selectedDay == today else { return nil }
        let now = Date()
        let nearby = Timeline.moments(allEntries(on: today)).contains { abs($0.end.timeIntervalSince(now)) < 90 * 60 }
        return nearby ? nil : LogAgain.usualMoment(near: now, entries: suggestionEntries)
    }

    /// Reads the selected day's usual times again, then the logger's suggestions for its time.
    func refreshCatchUp() {
        let interval = LogPath.begin("refreshCatchUp")
        defer { LogPath.end(interval) }
        usualTimes = UsualMeals.on(selectedDay, entries: suggestionEntries, today: today)
        refreshTimedSuggestions()
    }

    /// Ranks the logger's suggestions for the time it logs at; nil while that's now, when the
    /// clock's own (`logAgain`, `mealSuggestions`, `usualNow`) are the same thing.
    func refreshTimedSuggestions() {
        guard loggerTime != nil || selectedDay != today else {
            timedSuggestions = nil
            return
        }
        let now = Date()
        let time = logDate()
        timedSuggestions = TimedSuggestions(
            time: time, logAgain: LogAgain.rank(suggestionEntries, now: now, at: time),
            meals: SavedMeals.rank(savedMeals, entries: entries, now: now, at: time),
            usual: LogAgain.usual(at: time, entries: suggestionEntries, today: today))
    }

    func quickAdd(name: String, nutrients: Nutrients, date: Date? = nil) {
        log([
            FoodEntry(
                date: date ?? logDate(), name: name.isEmpty ? "Quick add" : name, amountLabel: "1 serving", nutrients: nutrients,
                source: .quickAdd)
        ])
    }

    // What goes to Health for each kind of thing logged, here as it's logged and by the backfill for
    // what other devices logged (HealthBackfill.swift): one shape and one version, so the backfill
    // knows this device's own samples and leaves them alone.

    static func healthFood(_ e: FoodEntry) -> HealthFood {
        var micros = e.micros ?? [:]
        if let fluid = e.fluid { micros["water"] = fluid }
        return HealthFood(id: e.id, date: e.date, name: e.name, nutrients: e.nutrients, micros: micros, version: e.updatedAt.healthVersion)
    }

    static func healthFood(_ glass: WaterLog) -> HealthFood {
        HealthFood(
            id: glass.id, date: glass.date, name: "Water", nutrients: .zero, micros: ["water": glass.ml], version: glass.updatedAt.healthVersion)
    }

    static func healthFood(_ dose: SupplementLog) -> HealthFood {
        HealthFood(
            id: dose.id, date: dose.date, name: dose.name, nutrients: dose.nutrients ?? .zero, micros: dose.amounts,
            version: dose.updatedAt.healthVersion)
    }

    /// What's been eaten on a day.
    func entries(on day: Day) -> [FoodEntry] {
        let all = allEntries(on: day)
        return foodLog.nextChange == nil ? all : all.filter { !foodLog.isUpcoming($0) }
    }

    /// A day's whole log, eaten and still to come: what its rows show.
    func allEntries(on day: Day) -> [FoodEntry] { entriesByDay[day] ?? [] }

    /// A day's targets as they stood that day, for the Log tab's line. Kept until the analysis
    /// moves on: working one out reads the plan and every check-in.
    func targets(on day: Day) -> DailyTargets? {
        guard let analysis else { return nil }
        if day == today { return analysis.targets }
        if let known = analysis.dayTargets[day] { return known }
        if targetsByDay.version != analysisVersion { targetsByDay = (analysisVersion, [:]) }
        if let kept = targetsByDay.targets[day] { return kept }
        guard let state = state(now: Date()) else { return nil }
        let targets = MacroAnalyst.targets(on: day, state, analysis)
        targetsByDay.targets[day] = targets
        return targets
    }

    /// A day's food by whether it's happened yet, with the doses taken counted as eaten.
    func dayIntake(on day: Day, now: Date = Date()) -> DayIntake {
        let all = allEntries(on: day)
        let eaten = all.filter { $0.date <= now }
        let later = all.filter { $0.date > now }
        return DayIntake(eaten: Intake.total(eaten, doses: supplementLogs.filter { $0.day == day }), later: Intake.total(later))
    }

    func state(of day: Day) -> DayState? { dayStatus.first { $0.day == day }?.state }

    func setState(_ state: DayState?, for day: Day) {
        let existing = dayStatus.filter { $0.day == day }
        for e in existing { store.delete(DayStatus.self, id: e.id) }
        if let state { store.save(DayStatus(id: existing.first?.id ?? UUID(), day: day, state: state)) }
        reload()
    }

    /// The meal planner, with its building blocks read from the catalog once.
    var planner: MealPlanner {
        if let plannerCache { return plannerCache }
        let planner = MealPlanner(catalog: catalog)
        plannerCache = planner
        return planner
    }

    // MARK: Nutrients

    /// "Not now" on a nutrient's action hides it for three days.
    func hideNutrient(_ key: String, now: Date = Date()) {
        let until = now.addingTimeInterval(3 * 86400)
        hiddenUntil[key] = until
        defaults?.set(until, forKey: "hideNutrient.\(key)")
        recompute()
    }

    func isNutrientHidden(_ key: String, now: Date = Date()) -> Bool {
        let until = hiddenUntil[key] ?? defaults?.object(forKey: "hideNutrient.\(key)") as? Date
        return until.map { $0 > now } ?? false
    }

    // MARK: Weight

    var latestWeighIn: WeighIn? { weighIns.last { !$0.excluded } }

    func weighIn(kg: Double, date: Date = Date()) {
        let w = WeighIn(date: date, kg: kg)
        store.save(w)
        reload()
        toast = Toast(message: "Weighed in · \(Format.weight(kg, unit: units.weight))")
        if settings.saveToHealth {
            Task { await HealthBridge.shared.saveWeight(id: w.id, date: date, kg: kg, version: w.updatedAt.healthVersion) }
        }
    }

    /// Ignores (or restores) a weigh-in: a misread, or weighed after a big meal.
    func setExcluded(_ excluded: Bool, weighIn: WeighIn) {
        var w = weighIn
        w.excluded = excluded
        w.updatedAt = Date()
        store.save(w)
        reload()
    }

    func delete(weighIn: WeighIn) {
        if case .health = weighIn.source {
            setExcluded(true, weighIn: weighIn)
            return
        }
        store.delete(WeighIn.self, id: weighIn.id)
        reload()
        Task { await HealthBridge.shared.deleteWeight(id: weighIn.id) }
    }

    // MARK: Settings and profile

    func save(settings: MacroSettings) {
        var settings = settings
        // Later than the copy it edits, even one from a device whose clock runs ahead: the store
        // keeps the newest, so an edit stamped before it would be dropped and the toggle snap back.
        settings.updatedAt = max(Date(), settings.updatedAt.addingTimeInterval(0.001))
        store.save(settings)
        reload()
    }

    /// Changes the stored settings rather than the copy in memory, so an edit can't undo a change
    /// that synced in from another device a moment before.
    func updateSettings(_ change: (inout MacroSettings) -> Void) {
        var s = storedSettings
        change(&s)
        save(settings: s)
    }

    /// The settings as the store has them now.
    private var storedSettings: MacroSettings { MacroSettings.inForce(store.all(MacroSettings.self)) ?? settings }

    func save(profile: SharedProfile) {
        var profile = profile
        profile.updatedAt = Date()
        store.save(ProfileRecord(profile))
        share(profile)
        reload()
    }

    private func share(_ profile: SharedProfile) {
        do {
            try shared.write(profile, to: .profile, by: .macroTrack)
        } catch {
            appLog.error("Couldn't share the profile: \(error.localizedDescription)")
        }
    }

    /// Saves the shared setup answers and Stadig Macro's own, and starts the assessment. Read from
    /// the store, not the copies in memory: when setup was already done on another device and has
    /// just synced in, it's kept as it is (its profile, settings and assessment), not started again.
    func completeOnboarding(profile: SharedProfile, history: DietHistory, weightKg: Double?) {
        let synced = MacroSettings.inForce(store.all(MacroSettings.self))
        if synced?.onboardedAt == nil || store.all(ProfileRecord.self).isEmpty {
            var profile = profile
            profile.updatedAt = Date()
            store.save(ProfileRecord(profile))
            share(profile)
            var s = synced ?? MacroSettings(id: MacroSettings.singletonID)
            s.onboardedAt = Date()
            s.assessmentStart = .today
            s.dietHistory = history
            s.updatedAt = Date()
            store.save(s)
        }
        if let weightKg, !store.all(WeighIn.self).contains(where: { $0.day == .today }) {
            store.save(WeighIn(date: Date(), kg: weightKg))
        }
        reload()
    }

    // MARK: Plan

    /// Starts a plan: saves it with first targets straight from the maintenance estimate.
    func start(_ plan: PhasePlan) {
        guard let analysis else { return }
        var plan = plan
        plan.updatedAt = Date()
        for old in store.all(PhasePlan.self) where old.id != plan.id { store.delete(PhasePlan.self, id: old.id) }
        store.save(plan)
        let weight = analysis.trend.latest?.trend ?? latestWeighIn?.kg ?? 80
        // It has the day's id, so it replaces a check-in made today rather than sitting beside it
        // (on another device too). Earlier versions gave each a random id: those go.
        let first = CheckIns.start(plan, today: today, maintenance: analysis.maintenance.kcal, weightKg: weight, referenceKg: analysis.referenceKg)
        for old in store.all(CheckIn.self) where old.day == today && old.id != first.id { store.delete(CheckIn.self, id: old.id) }
        store.save(first)
        var s = storedSettings
        s.phaseOverride = nil
        s.updatedAt = Date()
        store.save(s)
        reload()
    }

    /// The suggested change to the plan, when a review rule fired.
    var planReview: PhasePlan? {
        guard let plan, let analysis else { return nil }
        return PhasePlanner.review(plan, input: analysis.plannerInput)
    }

    /// The recommendation, before a plan is started.
    var recommendation: PhasePlan? {
        guard plan == nil, let analysis else { return nil }
        return PhasePlanner.recommend(analysis.plannerInput)
    }

    // MARK: Life modes

    /// Saves a period (the dates put in order) and shares it with the other apps; one an editor
    /// shouldn't have offered (an open-ended trip, an injury with no body part) isn't saved.
    @discardableResult
    func save(lifeMode period: LifeModePeriod) -> Bool {
        var period = period.normalized()
        guard period.isValid else {
            appLog.error("Not saving an invalid \(period.kind.label, privacy: .public) period")
            return false
        }
        period.updatedAt = Date()
        store.save(LifeModeRecord(period))
        // Shared by the reload, merged with the file.
        reload()
        return true
    }

    /// A delete is kept as a tombstone and shared like an edit, so it reaches the app that made the
    /// period and the person's other devices instead of being brought back by their copies.
    func delete(lifeMode id: UUID) {
        guard let period = lifeModes.first(where: { $0.id == id }) else { return }
        store.save(LifeModeRecord(period.deleted(at: Date())))
        reload()
    }

    // MARK: Health

    func connectHealth() async {
        _ = await HealthBridge.shared.requestAuthorization(.nutrition)
        // What the Watch and the Mac logged before Health was connected waited for this.
        healthBackfill?.run()
        healthReads.permissionAsked()
        await refreshHealth()
        startHealthObserving()
    }

    /// Weigh-ins from a scale arrive while the app runs. Asks nothing: without permission the query
    /// just doesn't report, so it's started at every launch, not only by "Connect Apple Health".
    func startHealthObserving() {
        guard healthObserver == nil, HealthBridge.shared.isAvailable else { return }
        healthReads.observerStarted(at: Date())
        healthObserver = HealthBridge.shared.observeChanges { [weak self] in
            Task { @MainActor in await self?.refreshHealth(.changed) }
        }
    }

    /// `refreshHealth`, unless it ran in the last few minutes: for each return to the app, since the
    /// observer hears nothing while the app is suspended (a morning weigh-in on a smart scale).
    func refreshHealthIfStale(now: Date = Date()) async {
        await refreshHealth(.returned, now: now)
    }

    /// Weigh-ins other apps and scales wrote, back to two months before the assessment, those
    /// deleted in Health, and height.
    func refreshHealth() async { await refreshHealth(.asked) }

    private func refreshHealth(_ reason: HealthReads.Reason, now: Date = Date()) async {
        let health = HealthBridge.shared
        guard health.isAvailable, healthReads.shouldRead(reason, now: now) else { return }
        let since = (settings.assessmentStart ?? .today).adding(days: -60).date()
        let anchor = weightAnchor
        // Nil when the read failed: the anchor stays where it was and nothing changes.
        if let changes = await health.weighInChanges(after: anchor, since: since, ownBundlePrefixes: Self.ownBundlePrefixes) {
            let whole = healthReads.readsWholeWindow(since: since, anchored: anchor != nil)
            let window = whole ? await health.weighIns(since: since, ownBundlePrefixes: Self.ownBundlePrefixes) : []
            merge(changes, window: window)
            healthReads.windowRead(since: since)
        }
        // Taken again once Health answers, so a profile that arrived meanwhile isn't written over.
        if let before = newestProfile, before.heightCm == nil, let height = await health.latestHeight(), var newest = newestProfile,
            newest.heightCm == nil
        {
            newest.heightCm = height
            save(profile: newest)
        }
    }

    /// The newer of this app's profile and the shared one, so an edit made in Stadig Lift isn't
    /// written over with an older copy. Nil before setup.
    private var newestProfile: SharedProfile? {
        guard let own = profile else { return nil }
        return sharedProfile.map { $0.updatedAt > own.updatedAt ? $0 : own } ?? own
    }

    /// What a read of Health found: weigh-ins other apps and scales added (and any in `window`, the
    /// whole window read again) come in, and those deleted in Health leave, ignored or not. Only
    /// weigh-ins read from Health go, matched by sample id: one typed here has an id of its own. The
    /// anchor is kept on this device for the next read.
    func merge(_ changes: HealthWeightChanges, window: [HealthWeight] = []) {
        let gone = changes.deletedIDs
        let known = Set(weighIns.map(\.id))
        var seen = Set<UUID>()
        let new = (changes.added + window)
            .filter { !gone.contains($0.id) && !known.contains($0.id) && seen.insert($0.id).inserted }
            .map { WeighIn(id: $0.id, date: $0.date, kg: $0.kg, source: .health($0.id)) }
        let deleted = weighIns.filter { weighIn in
            guard case .health(let sample) = weighIn.source else { return false }
            return gone.contains(sample)
        }
        weightAnchor = changes.anchor
        defaults?.set(changes.anchor, forKey: Self.weightAnchorKey)
        guard !new.isEmpty || !deleted.isEmpty else { return }
        if !new.isEmpty { store.save(new) }
        for weighIn in deleted { store.delete(WeighIn.self, id: weighIn.id) }
        reload()
    }

    /// Where the anchor for Health's weigh-ins is kept. Not synced: it counts in this device's Health database.
    static let weightAnchorKey = "health.weightAnchor"

    /// The latest Health weight, for onboarding's prefill.
    func healthWeight() async -> Double? { await HealthBridge.shared.latestBodyweight()?.kg }

    // MARK: Data

    func exportCSV() throws -> [URL] {
        let folder = URL.temporaryDirectory.appending(path: "Stadig Macro Export \(Day.today.iso)")
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try NutritionExport.tables(
            entries: entries, weighIns: weighIns, checkIns: checkIns, days: dayStatus,
            supplements: supplementLogs, water: water, fasts: analysis?.fasts ?? []
        ).map { table in
            var csv = CSVTable(header: table.header)
            for row in table.rows { csv.append(row) }
            let url = folder.appending(path: "\(table.name).csv")
            try csv.data.write(to: url)
            return url
        }
    }

    func backupFile() throws -> URL {
        let data = try store.exportBackup(app: .macroTrack, shared: shared)
        let url = Self.backupURL()
        try data.write(to: url, options: .atomic)
        return url
    }

    /// `backupFile()` with the encoding and the write off the main actor: years of records take seconds.
    func backupFile() async throws -> URL {
        let data = try await store.exportBackup(app: .macroTrack, shared: shared)
        let url = Self.backupURL()
        try await Task.detached(priority: .userInitiated) { try data.write(to: url, options: .atomic) }.value
        return url
    }

    private static func backupURL() -> URL {
        URL.temporaryDirectory.appending(path: "Stadig Macro \(Day.today.iso).macrobackup")
    }

    /// Merges a backup in. Refuses another app's backup before writing anything.
    @discardableResult
    func restore(from url: URL) throws -> BackupSummary {
        let data = try Self.readBackup(url)
        // Reloaded even when it throws: the records may be in though the shared files failed.
        defer { reload() }
        return try store.importBackup(data, app: .macroTrack, shared: shared)
    }

    /// `restore(from:)` with the reading and decoding off the main actor, for a big backup.
    @discardableResult
    func restore(from url: URL) async throws -> BackupSummary {
        let data = try await Task.detached(priority: .userInitiated) { try Self.readBackup(url) }.value
        defer { reload() }
        return try await store.importBackup(data, app: .macroTrack, shared: shared)
    }

    nonisolated private static func readBackup(_ url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    #if DEBUG
    func eraseEverything() {
        store.eraseAll()
        reload()
    }
    #endif
}
