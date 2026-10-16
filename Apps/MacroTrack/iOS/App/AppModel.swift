import Foundation
import Observation
import OSLog
import FoodDatabase
import HealthBridge
import MealPlanner
import NutritionEngine
import SystemCore
import SystemStore

let appLog = Logger(subsystem: "dev.svindland.macrotrack", category: "app")

enum AppTab: Hashable {
    case today, plan, progress
}

/// The ways into logging. Each opens straight to its first step.
enum LogMode: String, Identifiable, Hashable {
    case search, scan, camera, photoLibrary, describe, quickAdd
    var id: String { rawValue }
}

/// A short confirmation after logging, with Undo.
struct Toast: Identifiable, Equatable {
    var id = UUID()
    var message: String
    var undo: [UUID] = []
}

/// The app's state: Macro Track's own synced records, what Lift Track and the hub published, what
/// Health knows, and the analysis computed from all of it.
@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    let store: RecordStore
    let shared: SharedContainer
    let catalog: FoodCatalog
    let purchases = Purchases()
    let ai = MealAIService()

    // Records.
    private(set) var profile: SharedProfile?
    private(set) var settings = MacroSettings()
    private(set) var entries: [FoodEntry] = []
    private(set) var weighIns: [WeighIn] = []
    private(set) var dayStatus: [DayStatus] = []
    private(set) var plan: PhasePlan?
    private(set) var checkIns: [CheckIn] = []
    private(set) var customFoods: [CustomFoodRecord] = []
    private(set) var favorites: Set<String> = []
    private(set) var lifeModes: [LifeModePeriod] = []
    /// Meal plans, oldest first: the current or next one is the one shown.
    private(set) var mealPlans: [MealPlan] = []

    // From the other apps and the hub.
    private(set) var lift: AppSummary?
    private(set) var calendar: SystemCalendar?
    /// A profile another app wrote before Macro Track was set up: onboarding reuses it.
    private(set) var sharedProfile: SharedProfile?

    // Derived.
    private(set) var analysis: MacroAnalysis?
    private(set) var logAgain: [LogAgainItem] = []
    /// Foods this person logs, for search ranking and last-used portions.
    private(set) var personal: [PersonalFood] = []
    /// The one food that best fixes this week's shortest nutrient, ready to log.
    private(set) var microFix: MicroFix?
    /// A fermented food to log, while the week has had too few.
    private(set) var fermentedFix: FermentedFix?

    // Presentation.
    var tab: AppTab = .today
    var logger: LogMode?
    /// When a logger's foods were eaten; nil is now (or this time of day, on a past day).
    var loggerTime: Date?
    var showSettings = false
    var showPaywall = false
    var showWeighIn = false
    var toast: Toast?
    var today: Day = .today
    /// The day Today shows and logs to: today, or a day being caught up.
    var selectedDay: Day = .today

    @ObservationIgnored private var sharedObserver: AnyObject?
    @ObservationIgnored private var healthObserver: AnyObject?
    @ObservationIgnored private var lastRevision = -1
    @ObservationIgnored private var foodCache: [String: Food] = [:]
    @ObservationIgnored private var personalTask: Task<Void, Never>?
    @ObservationIgnored private var fixTask: Task<Void, Never>?
    @ObservationIgnored private var fixKey: String?
    @ObservationIgnored private var fermentedTask: Task<Void, Never>?
    @ObservationIgnored private var plannerCache: MealPlanner?
    /// Bumped by "another plan", so each shuffle is a different week.
    @ObservationIgnored var planVariation = 0

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let memory = arguments.contains("-inMemoryStore")
        store = RecordStore(name: "MacroTrack", cloudKitContainer: memory ? nil : "iCloud.dev.svindland.macrotrack", inMemory: memory)
        shared = SharedContainer()
        catalog = FoodCatalog.standard()
        #if DEBUG
        if arguments.contains("-resetData") { store.eraseAll() }
        #endif
        reload()
        sharedObserver = SharedContainer.observeChanges { [weak self] in self?.readShared() }
        // Open the catalogs and warm the search index off the main thread, so the first search is instant.
        let catalog = catalog
        Task.detached(priority: .utility) { catalog.prewarm() }
    }

    var onboarded: Bool { profile != nil && settings.onboardedAt != nil }

    var units: UnitPreference { profile?.units ?? .regional }

    // MARK: Loading

    /// Reads everything from the store and recomputes. Cheap enough to call after every change.
    func reload() {
        lastRevision = store.revision
        profile = store.all(ProfileRecord.self).first?.profile
        settings = store.all(MacroSettings.self).first ?? MacroSettings()
        entries = store.all(FoodEntry.self).sorted { $0.date < $1.date }
        weighIns = store.all(WeighIn.self).sorted { $0.date < $1.date }
        dayStatus = store.all(DayStatus.self)
        plan = store.all(PhasePlan.self).first
        checkIns = store.all(CheckIn.self).sorted { $0.day < $1.day }
        customFoods = store.all(CustomFoodRecord.self)
        favorites = Set(store.all(FavoriteRecord.self).map(\.foodID))
        reloadMealPlans()
        readShared(recompute: false)
        recompute()
        refreshPersonal()
    }

    func reloadMealPlans() {
        mealPlans = store.all(MealPlan.self).sorted { $0.start < $1.start }
    }

    /// Picks up changes that arrived from iCloud.
    func reloadIfChanged() {
        if store.revision != lastRevision { reload() }
    }

    /// What other apps and the hub published. Our own writes notify us too, so this only
    /// recomputes when something actually changed.
    func readShared(recompute again: Bool = true) {
        let lift = shared.read(.summary(.liftTrack))
        let calendar = shared.read(.calendar)
        let sharedProfile = shared.read(.profile)
        var merged: [UUID: LifeModePeriod] = [:]
        for period in store.all(LifeModeRecord.self).map(\.period) + (shared.read(.lifeModes) ?? []) {
            if let existing = merged[period.id], existing.updatedAt >= period.updatedAt { continue }
            merged[period.id] = period
        }
        let lifeModes = merged.values.sorted { $0.start < $1.start }
        let changed = lift != self.lift || calendar != self.calendar || sharedProfile != self.sharedProfile || lifeModes != self.lifeModes
        guard changed else { return }
        self.lift = lift
        self.calendar = calendar
        self.sharedProfile = sharedProfile
        self.lifeModes = lifeModes
        if again { recompute() }
    }

    var state: MacroState? {
        guard let profile else { return nil }
        return MacroState(profile: profile, settings: settings, entries: entries, weighIns: weighIns, dayStatus: dayStatus, plan: plan,
                          lifeModes: lifeModes, calendar: calendar, lift: lift, checkIns: checkIns, today: today)
    }

    func recompute() {
        if today != .today {
            if selectedDay == today { selectedDay = .today }
            today = .today
        }
        logAgain = LogAgain.rank(entries, now: Date())
        guard let state else {
            analysis = nil
            return
        }
        let analysis = MacroAnalyst.analyse(state)
        self.analysis = analysis
        // The weekly check-in applies itself: small, capped steps, explained on Today.
        if let due = analysis.dueCheckIn, plan != nil, onboarded {
            store.save(due)
            checkIns = store.all(CheckIn.self).sorted { $0.day < $1.day }
            lastRevision = store.revision
            self.analysis = MacroAnalyst.analyse(self.state ?? state)
        }
        publish()
        refreshMicroFix()
        refreshFermentedFix()
    }

    /// Finds a fermented food to suggest, off the main thread, once the week is short of them.
    private func refreshFermentedFix() {
        guard analysis?.quality.fermentedStatus == .off else {
            fermentedFix = nil
            return
        }
        guard fermentedFix == nil, fermentedTask == nil else { return }
        let catalog = catalog, personal = personal
        fermentedTask = Task.detached(priority: .utility) { [weak self] in
            let fix = FermentedFix.find(personal: personal, catalog: catalog)
            await MainActor.run {
                guard let self else { return }
                self.fermentedTask = nil
                if self.analysis?.quality.fermentedStatus == .off { self.fermentedFix = fix }
            }
        }
    }

    /// Finds a food for the shortest watched nutrient off the main thread, when it changes.
    private func refreshMicroFix() {
        let short = analysis?.micros.flagged.first { $0.nutrient.goal == .atLeast }
        guard let short, let target = short.target else {
            microFix = nil
            fixKey = nil
            return
        }
        guard fixKey != short.nutrient.key || microFix == nil else { return }
        fixKey = short.nutrient.key
        fixTask?.cancel()
        let catalog = catalog, personal = personal
        fixTask = Task.detached(priority: .utility) { [weak self] in
            let fix = MicroFix.find(for: short.nutrient, target: target, personal: personal, catalog: catalog)
            await MainActor.run {
                guard let self, !Task.isCancelled, self.fixKey == short.nutrient.key else { return }
                self.microFix = fix
            }
        }
    }

    @ObservationIgnored private var lastPublished: (nutrition: NutritionSummary, summary: AppSummary)?

    /// The phase and day-by-day nutrition for Lift Track and the hub, written only when they change.
    private func publish() {
        guard let state, let analysis else { return }
        var nutrition = MacroAnalyst.nutritionSummary(state, analysis)
        var summary = MacroAnalyst.appSummary(state, analysis)
        if let last = lastPublished {
            nutrition.updated = last.nutrition.updated
            summary.updated = last.summary.updated
        }
        if lastPublished.map({ $0.nutrition != nutrition || $0.summary != summary }) ?? true {
            nutrition.updated = Date()
            summary.updated = Date()
            do {
                try shared.write(nutrition, to: .nutrition, by: .macroTrack)
                try shared.write(summary, to: .summary(.macroTrack), by: .macroTrack)
                lastPublished = (nutrition, summary)
            } catch {
                appLog.error("Couldn't publish the summary: \(error.localizedDescription)")
            }
        }
        WidgetBridge.update(self)
    }

    // MARK: Foods

    /// A food by id from the catalogs or the person's own foods.
    func food(id: String) -> Food? {
        if let cached = foodCache[id] { return cached }
        let found = customFoods.first { $0.food.id == id }?.food ?? catalog.food(id: id)
        if let found { foodCache[id] = found }
        return found
    }

    func food(barcode: String, symbology: Barcode.Symbology? = nil) -> Food? {
        let keys = Set(Barcode.keys(for: barcode, symbology: symbology) + [barcode])
        if let own = customFoods.first(where: { food in food.food.barcode.map { keys.contains($0) || Barcode.keys(for: $0).contains(where: keys.contains) } ?? false }) {
            return own.food
        }
        return catalog.food(barcode: barcode, symbology: symbology)
    }

    /// Rebuilds the personal foods off the main thread: logged foods by frequency and recency,
    /// with the last portion used, plus favourites and the person's own foods.
    private func refreshPersonal() {
        personalTask?.cancel()
        let entries = entries.filter { $0.foodID != nil }
        let favorites = favorites
        let custom = customFoods.map(\.food)
        let catalog = catalog
        let known = foodCache
        personalTask = Task.detached(priority: .utility) { [weak self] in
            let now = Date()
            var byFood: [String: (score: Double, last: FoodEntry)] = [:]
            for entry in entries {
                guard let id = entry.foodID else { continue }
                let days = max(0, now.timeIntervalSince(entry.date) / 86400)
                let weight = pow(0.5, days / 30)
                var current = byFood[id] ?? (0, entry)
                current.score += weight
                if entry.date > current.last.date { current.last = entry }
                byFood[id] = current
            }
            var foods: [String: Food] = [:]
            for food in custom { foods[food.id] = food }
            var result: [PersonalFood] = []
            let ids = Set(byFood.keys).union(favorites).union(custom.map(\.id))
            for id in ids.sorted(by: { (byFood[$0]?.score ?? 0) > (byFood[$1]?.score ?? 0) }).prefix(400) {
                if Task.isCancelled { return }
                guard let food = foods[id] ?? known[id] ?? catalog.food(id: id) else { continue }
                foods[id] = food
                let usage = byFood[id]
                result.append(PersonalFood(food: food, score: (usage?.score ?? 0) + (favorites.contains(id) ? 2 : 0), favorite: favorites.contains(id),
                                           lastCount: usage?.last.count, lastUnitID: usage?.last.unitID))
            }
            let found = foods
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.personal = result
                self.foodCache.merge(found) { a, _ in a }
                // A fix found before the person's own foods were known may have a better one now.
                self.microFix = nil
                self.refreshMicroFix()
                self.fermentedFix = nil
                self.refreshFermentedFix()
            }
        }
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

    @discardableResult
    func save(customFood food: Food) -> Food {
        let record = CustomFoodRecord(food: food)
        store.save(record)
        foodCache[record.food.id] = record.food
        reload()
        return record.food
    }

    // MARK: Logging

    /// When something logged now was eaten: the time picked in the logger, else now; on a past
    /// day being caught up, the same time of day there.
    func logDate() -> Date {
        if let loggerTime { return loggerTime }
        let now = Date()
        guard selectedDay != today else { return now }
        return selectedDay.date().addingTimeInterval(now.timeIntervalSince(Calendar.current.startOfDay(for: now)))
    }

    /// The selected day at a time of day, for the logger's time choices.
    func onSelectedDay(_ time: Date) -> Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: parts.hour ?? 12, minute: parts.minute ?? 0, second: 0, of: selectedDay.date()) ?? time
    }

    /// A ready-to-save entry for a food and portion, timed for the selected day.
    func entry(for food: Food, count: Double, unit: PortionUnit, source: EntrySource, confidence: Double? = nil) -> FoodEntry {
        FoodEntry(date: logDate(), name: food.name, brand: food.brand, foodID: food.id,
                         amountLabel: FoodUnits.entryLabel(for: food, count: count, unit: unit, estimate: confidence != nil),
                         grams: FoodUnits.amount(count, unit),
                         unitID: unit.id, count: count, nutrients: FoodUnits.nutrients(food, count: count, unit: unit),
                         micros: FoodUnits.micros(food, count: count, unit: unit), processing: food.processing,
                         fermented: food.fermented, source: source, confidence: confidence)
    }

    /// Saves entries, shows "Logged … Undo", and writes them to Health.
    func log(_ new: [FoodEntry], message: String? = nil) {
        guard !new.isEmpty else { return }
        store.save(new)
        reload()
        let kcal = new.map(\.nutrients.kcal).reduce(0, +)
        let text = message ?? (new.count == 1 ? "Logged \(new[0].name)" : "Logged \(new.count) foods")
        toast = Toast(message: "\(text) · \(Format.kcal(kcal))", undo: new.map(\.id))
        if settings.saveToHealth { Task { await HealthBridge.shared.saveFoods(new.map(Self.healthFood)) } }
    }

    func update(_ entry: FoodEntry) {
        var entry = entry
        entry.updatedAt = Date()
        entry.day = Day(entry.date)
        store.save(entry)
        reload()
        if settings.saveToHealth { Task { await HealthBridge.shared.saveFoods([Self.healthFood(entry)]) } }
    }

    func delete(entries ids: [UUID]) {
        for id in ids { store.delete(FoodEntry.self, id: id) }
        reload()
        Task { await HealthBridge.shared.deleteFoods(ids: ids) }
    }

    func undo(_ toast: Toast) {
        delete(entries: toast.undo)
        self.toast = nil
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
        let nearby = Timeline.moments(entries(on: today)).contains { abs($0.end.timeIntervalSince(now)) < 90 * 60 }
        return nearby ? nil : LogAgain.usualMoment(near: now, entries: entries)
    }

    func quickAdd(name: String, nutrients: Nutrients) {
        log([FoodEntry(date: logDate(), name: name.isEmpty ? "Quick add" : name, amountLabel: "1 serving", nutrients: nutrients,
                       source: .quickAdd)])
    }

    static func healthFood(_ e: FoodEntry) -> HealthFood {
        HealthFood(id: e.id, date: e.date, name: e.name, nutrients: e.nutrients, micros: e.micros ?? [:],
                   version: Int(e.updatedAt.timeIntervalSince1970 * 1000))
    }

    func entries(on day: Day) -> [FoodEntry] { entries.filter { $0.day == day } }

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
    func hideNutrient(_ key: String) {
        UserDefaults.standard.set(Date().addingTimeInterval(3 * 86400), forKey: "hideNutrient.\(key)")
        recompute()
    }

    func isNutrientHidden(_ key: String) -> Bool {
        (UserDefaults.standard.object(forKey: "hideNutrient.\(key)") as? Date).map { $0 > Date() } ?? false
    }

    // MARK: Weight

    var latestWeighIn: WeighIn? { weighIns.last { !$0.excluded } }

    func weighIn(kg: Double, date: Date = Date()) {
        let w = WeighIn(date: date, kg: kg)
        store.save(w)
        reload()
        toast = Toast(message: "Weighed in · \(Format.weight(kg, unit: units.weight))")
        if settings.saveToHealth {
            Task { await HealthBridge.shared.saveWeight(id: w.id, date: date, kg: kg, version: Int(Date().timeIntervalSince1970 * 1000)) }
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
        settings.updatedAt = Date()
        store.save(settings)
        reload()
    }

    func save(profile: SharedProfile) {
        var profile = profile
        profile.updatedAt = Date()
        store.save(ProfileRecord(profile))
        try? shared.write(profile, to: .profile, by: .macroTrack)
        reload()
    }

    /// Saves the shared setup answers and Macro Track's own, and starts the assessment.
    func completeOnboarding(profile: SharedProfile, history: DietHistory, weightKg: Double?) {
        var profile = profile
        profile.updatedAt = Date()
        store.save(ProfileRecord(profile))
        try? shared.write(profile, to: .profile, by: .macroTrack)
        var s = settings
        s.onboardedAt = Date()
        s.assessmentStart = .today
        s.dietHistory = history
        s.updatedAt = Date()
        store.save(s)
        if let weightKg, !weighIns.contains(where: { $0.day == .today }) {
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
        let phase = plan.phase(on: today)
        let kcal = Targets.calories(maintenance: analysis.maintenance.kcal, phase: phase, weightKg: weight)
        let m = Targets.macros(kcal: kcal, referenceKg: analysis.referenceKg, phase: phase?.kind)
        store.save(CheckIn(day: today, expenditure: analysis.maintenance.kcal, kcal: kcal, protein: m.protein, carbs: m.carbs, fat: m.fat,
                           status: .updated, reason: "Starting \(phase?.kind.label.lowercased() ?? "the plan") from maintenance of about \(Int(analysis.maintenance.kcal)) kcal."))
        var s = settings
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

    func save(lifeMode period: LifeModePeriod) {
        var period = period
        period.updatedAt = Date()
        store.save(LifeModeRecord(period))
        var all = shared.read(.lifeModes) ?? []
        all.removeAll { $0.id == period.id }
        all.append(period)
        try? shared.write(all, to: .lifeModes, by: .macroTrack)
        reload()
    }

    func delete(lifeMode id: UUID) {
        store.delete(LifeModeRecord.self, id: id)
        var all = shared.read(.lifeModes) ?? []
        all.removeAll { $0.id == id }
        try? shared.write(all, to: .lifeModes, by: .macroTrack)
        reload()
    }

    // MARK: Health

    func connectHealth() async {
        _ = await HealthBridge.shared.requestAuthorization(.nutrition)
        await refreshHealth()
        if healthObserver == nil {
            healthObserver = HealthBridge.shared.observeChanges { Task { @MainActor in await AppModel.shared.refreshHealth() } }
        }
    }

    /// Weigh-ins other apps and scales wrote, back to a month before the assessment, and height.
    func refreshHealth() async {
        let health = HealthBridge.shared
        guard health.isAvailable else { return }
        let start = (settings.assessmentStart ?? .today).adding(days: -60)
        let samples = await health.weighIns(since: start.date(), ownBundlePrefix: "dev.svindland.macrotrack")
        let known = Set(weighIns.map(\.id))
        let new = samples.filter { !known.contains($0.id) }.map { WeighIn(id: $0.id, date: $0.date, kg: $0.kg, source: .health($0.id)) }
        if !new.isEmpty { store.save(new) }
        if var profile, profile.heightCm == nil, let height = await health.latestHeight() {
            profile.heightCm = height
            save(profile: profile)
        }
        reload()
    }

    /// The latest Health weight, for onboarding's prefill.
    func healthWeight() async -> Double? { await HealthBridge.shared.latestBodyweight()?.kg }

    // MARK: Data

    func exportCSV() throws -> [URL] {
        let folder = URL.temporaryDirectory.appending(path: "Macro Track Export \(Day.today.iso)")
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try NutritionExport.tables(entries: entries, weighIns: weighIns, checkIns: checkIns, days: dayStatus).map { table in
            var csv = CSVTable(header: table.header)
            for row in table.rows { csv.append(row) }
            let url = folder.appending(path: "\(table.name).csv")
            try csv.data.write(to: url)
            return url
        }
    }

    func backupFile() throws -> URL {
        let data = try store.exportBackup(app: .macroTrack, shared: shared)
        let url = URL.temporaryDirectory.appending(path: "Macro Track \(Day.today.iso).macrobackup")
        try data.write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    func restore(from url: URL) throws -> BackupSummary {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let summary = try store.importBackup(data, shared: shared)
        reload()
        return summary
    }

    #if DEBUG
    func eraseEverything() {
        store.eraseAll()
        reload()
    }
    #endif
}
