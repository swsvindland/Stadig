import Foundation
import HealthBridge
import NutritionEngine
import SystemCore
import SystemStore
import Testing

@testable import MacroTrack

/// Health as the backfill sees it: what it holds by sync identifier, and every write and delete.
final class FakeHealth: HealthCopies {
    var access = HealthAccessNow.writable
    /// Versions held, by id: this app's writes on any device.
    var held: [UUID: Int] = [:]
    var savedFoods: [HealthFood] = []
    var savedWeights: [UUID] = []
    var deleted: [UUID] = []
    var reads = 0

    func access() async -> HealthAccessNow { access }

    func versions(foods ids: [UUID]) async -> [UUID: Int]? {
        reads += 1
        return held.filter { ids.contains($0.key) }
    }

    func versions(weights ids: [UUID]) async -> [UUID: Int]? { held.filter { ids.contains($0.key) } }

    func save(foods: [HealthFood]) async {
        savedFoods += foods
        for food in foods { held[food.id] = food.version }
    }

    func save(weight id: UUID, date: Date, kg: Double, version: Int) async {
        savedWeights.append(id)
        held[id] = version
    }

    func delete(foods ids: [UUID]) async {
        deleted += ids
        for id in ids { held[id] = nil }
    }

    func delete(weight id: UUID) async {
        deleted.append(id)
        held[id] = nil
    }
}

/// What reaches Health from other devices: the Watch writes nothing there and the Mac can't, so
/// the iPhone writes what syncs in from them, once, by sync identifier.
@MainActor
struct HealthBackfillTests {
    let today = Day(year: 2026, month: 3, day: 9)
    var now: Date { today.at(hour: 20, minute: 0) }
    let store = RecordStore(name: "BackfillTests-\(UUID().uuidString)", cloudKitContainer: nil, inMemory: true)
    let health = FakeHealth()

    init() {
        store.save(MacroSettings(id: MacroSettings.singletonID, onboardedAt: today.adding(days: -20).at(hour: 9, minute: 0)))
    }

    func entry(_ name: String, daysAgo: Int = 0, hour: Int = 12) -> FoodEntry {
        let date = today.adding(days: -daysAgo).at(hour: hour, minute: 0)
        return FoodEntry(
            date: date, name: name, amountLabel: "1", nutrients: Nutrients(kcal: 300, protein: 20, carbs: 30, fat: 10), source: .recent,
            updatedAt: date)
    }

    func dose(taken: Bool, hour: Int, updatedAt: Date? = nil) -> SupplementLog {
        let facts = SupplementFacts(
            id: "custom:Multi", name: "Multivitamin", unit: "tablet", ingredients: [SupplementIngredient(name: "Zinc", amount: 11, unit: "mg")],
            source: .custom)
        let date = today.at(hour: hour, minute: 0)
        return SupplementLog(supplement: Supplement(facts: facts), doseID: UUID(), date: date, count: 1, taken: taken, updatedAt: updatedAt ?? date)
    }

    /// Times within one second, at fractions of a millisecond either side of a half, as `Date()`
    /// gives them when something is logged.
    var oddTimes: [Date] {
        let second = today.at(hour: 11, minute: 0).timeIntervalSince1970
        return [0.000_1, 0.000_49, 0.000_5, 0.000_51, 0.000_9, 0.123_456_7, 0.999_6].map { Date(timeIntervalSince1970: second + $0) }
    }

    /// One of each kind logged on this phone at `time`, and the versions the phone wrote to Health as
    /// it logged them, from the records in memory (the store rounds `updatedAt` as it saves).
    func loggedHere(at time: Date, version: (Date) -> Int) -> [UUID: Int] {
        let food = FoodEntry(
            date: time, name: "Lunch", amountLabel: "1", nutrients: Nutrients(kcal: 300, protein: 20, carbs: 30, fat: 10), source: .recent,
            updatedAt: time)
        let glass = WaterLog(date: time, ml: 250, updatedAt: time)
        let taken = dose(taken: true, hour: 11, updatedAt: time)
        let typed = WeighIn(date: time, kg: 82.4, updatedAt: time)
        store.save(food)
        store.save(glass)
        store.save(taken)
        store.save(typed)
        return [
            food.id: version(food.updatedAt), glass.id: version(glass.updatedAt), taken.id: version(taken.updatedAt),
            typed.id: version(typed.updatedAt),
        ]
    }

    func backfill() -> HealthBackfill { HealthBackfill(store: store, health: health, defaults: nil) }

    func later(_ name: String, hour: Int = 22) -> FoodEntry {
        let date = today.at(hour: hour, minute: 0)
        return FoodEntry(
            date: date, name: name, amountLabel: "1", nutrients: Nutrients(kcal: 300, protein: 20, carbs: 30, fat: 10), source: .recent,
            updatedAt: now)
    }

    @Test("food logged for later waits for its time, then goes in dated when it was eaten")
    func laterFoodWaits() async throws {
        let dinner = later("Dinner")
        store.save(dinner)
        let backfill = backfill()

        await backfill.pass(now: now)
        #expect(health.savedFoods.isEmpty)
        #expect(backfill.ledger[dinner.id] == nil)

        let after = today.at(hour: 22, minute: 1)
        await backfill.pass(now: after)
        #expect(health.savedFoods.map(\.id) == [dinner.id])
        #expect(health.savedFoods.first?.date == dinner.date)
    }

    @Test("food moved ahead of now loses its copy, and gets it back at its new time")
    func movedAhead() async throws {
        let lunch = entry("Lunch")
        store.save(lunch)
        let backfill = backfill()
        await backfill.pass(now: now)
        #expect(health.held[lunch.id] != nil)

        store.save(lunch.edited(at: now) { $0.date = today.at(hour: 22, minute: 0) })
        await backfill.pass(now: now)
        #expect(health.held[lunch.id] == nil)
        #expect(backfill.ledger[lunch.id] == nil)

        await backfill.pass(now: today.at(hour: 22, minute: 1))
        #expect(health.held[lunch.id] != nil)
    }

    @Test("food moved ahead on another device before this one noted it still loses its copy")
    func movedAheadUnledgered() async throws {
        let lunch = entry("Lunch")
        // Written as it was logged here, and moved on the Mac before a pass noted it.
        health.held[lunch.id] = lunch.updatedAt.healthVersion
        store.save(lunch.edited(at: now) { $0.date = today.at(hour: 22, minute: 0) })

        await backfill().pass(now: now)

        #expect(health.held[lunch.id] == nil)
        #expect(health.deleted == [lunch.id])
    }

    @Test("later food isn't looked up again until it changes")
    func laterLookedUpOnce() async throws {
        let dinner = later("Dinner")
        store.save(dinner)
        let backfill = backfill()
        await backfill.pass(now: now)
        let lookups = health.reads
        #expect(lookups > 0)
        await backfill.pass(now: now)
        #expect(health.reads == lookups)
    }

    @Test("what's for later doesn't reach someone who turned Health off")
    func laterWithHealthOff() async throws {
        var settings = MacroSettings(id: MacroSettings.singletonID, onboardedAt: today.adding(days: -20).at(hour: 9, minute: 0), saveToHealth: false)
        // Past the one `init` saved, or the store keeps that one.
        settings.updatedAt = Date().addingTimeInterval(1)
        store.save(settings)
        store.save(later("Dinner"))
        await backfill().pass(now: now)
        #expect(health.savedFoods.isEmpty)
        #expect(health.reads == 0)
    }

    @Test("what came from the Watch and the Mac goes to Health once; what's there already doesn't")
    func writesOnce() async throws {
        let here = entry("Logged on this phone", hour: 8)
        let fromWatch = entry("Logged on the Watch")
        let old = entry("Long ago", daysAgo: 45)
        let glass = WaterLog(date: today.at(hour: 10, minute: 0), ml: 250, updatedAt: today.at(hour: 10, minute: 0))
        let taken = dose(taken: true, hour: 8)
        let skipped = dose(taken: false, hour: 21)
        let typed = WeighIn(date: today.at(hour: 7, minute: 0), kg: 82.4, updatedAt: today.at(hour: 7, minute: 0))
        let scale = WeighIn(date: today.at(hour: 6, minute: 50), kg: 82.1, source: .health(UUID()))
        store.save([here, fromWatch, old])
        store.save(glass)
        store.save([taken, skipped])
        store.save([typed, scale])
        // This phone wrote its own entry as it logged it.
        health.held[here.id] = AppModel.healthFood(here).version

        let backfill = backfill()
        await backfill.pass(now: now)
        #expect(Set(health.savedFoods.map(\.id)) == [fromWatch.id, glass.id, taken.id])
        #expect(health.savedWeights == [typed.id])
        let water = try #require(health.savedFoods.first { $0.id == glass.id })
        #expect(water.micros["water"] == 250 && water.name == "Water")
        let food = try #require(health.savedFoods.first { $0.id == fromWatch.id })
        #expect(food.nutrients.kcal == 300 && food.version == fromWatch.updatedAt.healthVersion)
        #expect(backfill.ledger[here.id]?.written == false && backfill.ledger[fromWatch.id]?.written == true)

        // Again: nothing new, and Health isn't even asked.
        let reads = health.reads
        await backfill.pass(now: now)
        #expect(health.savedFoods.count == 3 && health.savedWeights.count == 1 && health.reads == reads)
    }

    @Test("an edit elsewhere is written again; a delete elsewhere takes the copy out")
    func editsAndDeletes() async throws {
        var lunch = entry("Lunch")
        let breakfast = entry("Breakfast", hour: 8)
        let glasses = [9, 11].map { WaterLog(date: today.at(hour: $0, minute: 0), ml: 250) }
        store.save([lunch, breakfast])
        store.save(glasses)
        let backfill = backfill()
        await backfill.pass(now: now)
        #expect(health.savedFoods.count == 4)

        lunch.nutrients.kcal = 450
        lunch.updatedAt = lunch.updatedAt.addingTimeInterval(600)
        store.save(lunch)
        store.delete(FoodEntry.self, id: breakfast.id)
        store.delete(WaterLog.self, id: glasses[0].id)
        await backfill.pass(now: now)
        let rewritten = try #require(health.savedFoods.last)
        #expect(rewritten.id == lunch.id && rewritten.nutrients.kcal == 450)
        #expect(Set(health.deleted) == [breakfast.id, glasses[0].id])
        #expect(backfill.ledger[breakfast.id] == nil)

        // The last glass deleted is a deletion too, though no water is left.
        store.delete(WaterLog.self, id: glasses[1].id)
        await backfill.pass(now: now)
        #expect(health.deleted.contains(glasses[1].id))
    }

    @Test("the phone's own samples, logged at any fraction of a millisecond, aren't written again")
    func ownSamplesAtAnyTime() async throws {
        for time in oddTimes {
            let written = loggedHere(at: time) { $0.healthVersion }
            health.held.merge(written) { $1 }
        }
        // What the store reads back, rounded, has the version the phone wrote from the record in memory.
        for food in store.all(FoodEntry.self) { #expect(AppModel.healthFood(food).version == health.held[food.id]) }
        for glass in store.all(WaterLog.self) { #expect(AppModel.healthFood(glass).version == health.held[glass.id]) }
        let backfill = backfill()
        await backfill.pass(now: now)
        #expect(health.savedFoods.isEmpty && health.savedWeights.isEmpty)
        #expect(backfill.ledger.count == oddTimes.count * 4 && backfill.ledger.values.allSatisfy { !$0.written })
    }

    @Test("samples an earlier version wrote with a truncated version aren't written again")
    func truncatedVersionsAreCurrent() async {
        for time in oddTimes {
            // As every writer did before versions were rounded like the store's.
            let written = loggedHere(at: time) { Int($0.timeIntervalSince1970 * 1000) }
            health.held.merge(written) { $1 }
        }
        await backfill().pass(now: now)
        #expect(health.savedFoods.isEmpty && health.savedWeights.isEmpty)
    }

    @Test("a ledger an earlier version kept, a millisecond lower, isn't looked up again")
    func earlierLedgerIsCurrent() async throws {
        let suite = "BackfillTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let watch = entry("From the Watch")
        store.save(watch)
        await HealthBackfill(store: store, health: health, defaults: defaults).pass(now: now)
        #expect(health.savedFoods.map(\.id) == [watch.id])

        // The ledger as an earlier version kept it, its versions truncated from the stored date.
        let kept = try JSONDecoder().decode([String: HealthLedgerEntry].self, from: try #require(defaults.data(forKey: HealthBackfill.ledgerKey)))
        let earlier = kept.mapValues { entry in
            var entry = entry
            entry.version -= 1
            return entry
        }
        defaults.set(try JSONEncoder().encode(earlier), forKey: HealthBackfill.ledgerKey)
        // The person deletes the sample in Health; it stays deleted.
        health.held[watch.id] = nil
        let reads = health.reads
        await HealthBackfill(store: store, health: health, defaults: defaults).pass(now: now)
        #expect(health.reads == reads && health.savedFoods.count == 1)
    }

    @Test("the store's deletions are read only for the kinds of what's gone missing")
    func deletionsReadOnlyWhenNeeded() {
        let since = today.adding(days: -HealthBackfill.window)
        let lunch = entry("Lunch")
        let glass = WaterLog(date: today.at(hour: 9, minute: 0), ml: 250)
        let taken = dose(taken: true, hour: 8)
        let items = HealthBackfill.items(entries: [lunch], water: [glass], doses: [taken], weighIns: [], since: since, setUp: nil)
        let ledger = Dictionary(uniqueKeysWithValues: items.map { ($0.id, HealthLedgerEntry($0, written: true)) })
        var unmarkedAsked: [HealthCopy.Source] = []
        var deletedAsked: [HealthCopy.Source] = []

        // Everything handled is still wanted: no history is read.
        let none = HealthBackfill.gone(
            ledger: ledger, items: items, since: since,
            unmarked: { source in
                unmarkedAsked.append(source)
                return []
            },
            deleted: { source in
                deletedAsked.append(source)
                return []
            })
        #expect(none.isEmpty && unmarkedAsked.isEmpty && deletedAsked.isEmpty)

        // The dose unmarked (still in the store) and the glass gone: only water's deletions are read.
        let lunchOnly = items.filter { $0.id == lunch.id }
        let gone = HealthBackfill.gone(
            ledger: ledger, items: lunchOnly, since: since,
            unmarked: { source in
                unmarkedAsked.append(source)
                return source == .dose ? [taken.id] : []
            },
            deleted: { source in
                deletedAsked.append(source)
                return source == .water ? [glass.id] : []
            })
        #expect(Set(gone.map(\.id)) == [taken.id, glass.id])
        #expect(Set(unmarkedAsked) == [.dose, .water] && deletedAsked == [.water])

        // The glass only missing, with no deletion: it keeps its copy.
        let kept = HealthBackfill.gone(
            ledger: ledger, items: lunchOnly, since: since, unmarked: { $0 == .dose ? [taken.id] : [] }, deleted: { _ in [] })
        #expect(kept.map(\.id) == [taken.id])
    }

    @Test("an entry dated back out of the window keeps its copy in Health")
    func datedBack() async {
        var lunch = entry("Lunch")
        store.save(lunch)
        let backfill = backfill()
        await backfill.pass(now: now)
        #expect(health.savedFoods.map(\.id) == [lunch.id])
        lunch.date = today.adding(days: -45).at(hour: 12, minute: 0)
        lunch.day = Day(lunch.date)
        lunch.updatedAt = now
        store.save(lunch)
        await backfill.pass(now: now)
        #expect(health.deleted.isEmpty)
    }

    @Test("what's only missing, without a deletion, keeps its copy in Health")
    func missingIsNotDeleted() async throws {
        let suite = "BackfillTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let lunch = entry("Lunch")
        let glass = WaterLog(date: today.at(hour: 9, minute: 0), ml: 250)
        store.save(lunch)
        store.save(glass)
        await HealthBackfill(store: store, health: health, defaults: defaults).pass(now: now)
        #expect(health.savedFoods.count == 2)

        // The same device after an iCloud account change: the store starts empty, with no deletions
        // in it (rows written by a newer app version, which this one can't read, look the same).
        let emptied = RecordStore(name: "BackfillTests-\(UUID().uuidString)", cloudKitContainer: nil, inMemory: true)
        emptied.save(MacroSettings(id: MacroSettings.singletonID, onboardedAt: today.adding(days: -20).at(hour: 9, minute: 0)))
        let backfill = HealthBackfill(store: emptied, health: health, defaults: defaults)
        #expect(backfill.ledger.count == 2)
        await backfill.pass(now: now)
        #expect(health.deleted.isEmpty)
        #expect(health.held[lunch.id] != nil && health.held[glass.id] != nil)
    }

    @Test("a dose unmarked elsewhere takes its copy out")
    func unmarkedDose() async {
        var taken = dose(taken: true, hour: 8)
        store.save(taken)
        let backfill = backfill()
        await backfill.pass(now: now)
        #expect(health.savedFoods.map(\.id) == [taken.id])
        taken.taken = false
        taken.updatedAt = taken.updatedAt.addingTimeInterval(60)
        store.save(taken)
        await backfill.pass(now: now)
        #expect(health.deleted == [taken.id])
    }

    @Test("a locked phone waits; someone who doesn't write to Health gets nothing, now or later")
    func waitsOrSkips() async {
        let watch = entry("From the Watch")
        store.save(watch)
        let backfill = backfill()
        health.access = .later
        await backfill.pass(now: now)
        #expect(health.savedFoods.isEmpty && backfill.ledger.isEmpty)
        health.access = .writable
        await backfill.pass(now: now)
        #expect(health.savedFoods.map(\.id) == [watch.id])

        // Saving to Health switched off: what syncs in meanwhile is noted, never written.
        var settings = MacroSettings.inForce(store.all(MacroSettings.self)) ?? MacroSettings()
        settings.saveToHealth = false
        settings.updatedAt = Date()
        store.save(settings)
        let mac = entry("From the Mac", hour: 13)
        store.save(mac)
        await backfill.pass(now: now)
        settings.saveToHealth = true
        settings.updatedAt = Date().addingTimeInterval(1)
        store.save(settings)
        await backfill.pass(now: now)
        #expect(!health.savedFoods.contains { $0.id == mac.id })
    }

    @Test("setup's weigh-in stays out, and an ignored one is neither written nor taken out")
    func weighIns() async {
        let setUp = WeighIn(date: today.adding(days: -20).at(hour: 9, minute: 1), kg: 84)
        var misread = WeighIn(date: today.at(hour: 7, minute: 0), kg: 8.2)
        misread.excluded = true
        let typed = WeighIn(date: today.adding(days: -1).at(hour: 7, minute: 0), kg: 83.5)
        store.save([setUp, misread, typed])
        let backfill = backfill()
        await backfill.pass(now: now)
        #expect(health.savedWeights == [typed.id])
        #expect(backfill.ledger[misread.id] != nil && backfill.ledger[setUp.id] == nil)
        await backfill.pass(now: now)
        #expect(health.deleted.isEmpty)
    }

    @Test("the ledger is kept on the device between launches, and written only when it changes")
    func ledgerKept() async throws {
        let suite = "BackfillTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        store.save(entry("From the Watch"))
        let first = HealthBackfill(store: store, health: health, defaults: defaults)
        await first.pass(now: now)
        let kept = try #require(defaults.data(forKey: HealthBackfill.ledgerKey))
        let relaunched = HealthBackfill(store: store, health: health, defaults: defaults)
        #expect(relaunched.ledger == first.ledger && relaunched.ledger.count == 1)
        await relaunched.pass(now: now)
        #expect(health.savedFoods.count == 1 && defaults.data(forKey: HealthBackfill.ledgerKey) == kept)
    }
}
