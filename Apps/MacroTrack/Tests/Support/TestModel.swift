import FoodDatabase
import Foundation
import HealthBridge
import NutritionEngine
import SystemCore
import SystemStore

@testable import MacroTrack

/// Where a test's model keeps things: an in-memory store with no iCloud, and a fresh folder for
/// the shared files and the widgets' snapshot. Nothing reaches the real App Group, iCloud or Health.
@MainActor
struct TestEnvironment {
    let folder: URL
    let store: RecordStore
    let shared: SharedContainer
    let widgetURL: URL

    init(store: RecordStore? = nil) {
        // The test host disables Health at launch; this keeps a test honest on its own too.
        HealthBridge.shared.disable()
        folder = URL.temporaryDirectory.appending(path: "MacroTrackTests \(UUID().uuidString)", directoryHint: .isDirectory)
        self.store = store ?? RecordStore(name: "MacroTrackTests-\(UUID().uuidString)", cloudKitContainer: nil, inMemory: true)
        shared = SharedContainer(directory: folder.appending(path: "SystemShared", directoryHint: .isDirectory))
        widgetURL = folder.appending(path: "widget.json")
    }

    /// A model over this environment. Another model over the same store reads what the first wrote,
    /// as the app does after a relaunch.
    func model() -> AppModel {
        AppModel(store: store, shared: shared, widgetURL: widgetURL, defaults: nil, catalog: Catalogs.food, supplementCatalog: nil)
    }
}

/// The catalogs every test shares: opening them is the slow part, and they're read-only.
enum Catalogs {
    static let food = FoodCatalog.standard()
}

/// USDA foods the tests log, from the catalog bundled in FoodDatabase (always there).
enum Foods {
    /// Bananas, raw: 89 kcal and 1.09 g protein per 100 g.
    static let bananaID = "usda:173944"
    /// Brewed coffee, with "1 cup (8 fl oz)" at 237 g.
    static let coffeeID = "usda:171890"
}

extension SharedProfile {
    /// Someone set up in kilograms, as onboarding leaves them.
    static func sample(createdBy app: AppID = .macroTrack, updatedAt: Date = Date()) -> SharedProfile {
        SharedProfile(
            goals: [.leaner], schedule: TrainingSchedule(daysPerWeek: 4), experience: .intermediate, sex: .male, birthYear: 1990,
            heightCm: 180, units: UnitPreference(weight: .kg, length: .cm), createdBy: app, updatedAt: updatedAt)
    }
}

extension AppModel {
    /// Through onboarding with the sample profile and a first weigh-in.
    func onboard(history: DietHistory = .none, weightKg: Double? = 82) {
        completeOnboarding(profile: .sample(), history: history, weightKg: weightKg)
    }

    /// A catalog food at a weight in grams, ready to log.
    func entry(foodID: String, grams: Double, source: EntrySource = .search, date: Date? = nil) throws -> FoodEntry {
        let food = try requireFood(foodID)
        let unit = try requireUnit(food, "g")
        return entry(for: food, count: grams, unit: unit, source: source, date: date)
    }

    func requireFood(_ id: String) throws -> Food {
        guard let food = food(id: id) else { throw TestFailure("\(id) isn't in the catalog") }
        return food
    }

    func requireUnit(_ food: Food, _ id: String) throws -> PortionUnit {
        guard let unit = FoodUnits.units(for: food).first(where: { $0.id == id }) else { throw TestFailure("\(food.name) has no \(id) unit") }
        return unit
    }
}

struct TestFailure: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

/// Waits on the main actor, letting other work run, until `condition` holds or the time runs out.
@MainActor
func eventually(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition() {
        if clock.now > deadline { return false }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return true
}

extension TimeZone {
    static let newYork = TimeZone(identifier: "America/New_York") ?? .gmt
}

extension Calendar {
    /// Gregorian in a time zone: how the tests build fixed dates.
    static func gregorian(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

/// A fixed moment, by the clock in a time zone.
func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, in timeZone: TimeZone = .newYork) -> Date {
    Calendar.gregorian(timeZone).date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
}
