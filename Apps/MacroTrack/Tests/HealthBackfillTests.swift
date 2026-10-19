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

    func dose(taken: Bool, hour: Int) -> SupplementLog {
        let facts = SupplementFacts(
            id: "custom:Multi", name: "Multivitamin", unit: "tablet", ingredients: [SupplementIngredient(name: "Zinc", amount: 11, unit: "mg")],
            source: .custom)
        let date = today.at(hour: hour, minute: 0)
        return SupplementLog(supplement: Supplement(facts: facts), doseID: UUID(), date: date, count: 1, taken: taken, updatedAt: date)
    }

    func backfill() -> HealthBackfill { HealthBackfill(store: store, health: health, defaults: nil) }

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
        health.held[here.id] = HealthBackfill.version(here.updatedAt)

        let backfill = backfill()
        await backfill.pass(now: now)
        #expect(Set(health.savedFoods.map(\.id)) == [fromWatch.id, glass.id, taken.id])
        #expect(health.savedWeights == [typed.id])
        let water = try #require(health.savedFoods.first { $0.id == glass.id })
        #expect(water.micros["water"] == 250 && water.name == "Water")
        let food = try #require(health.savedFoods.first { $0.id == fromWatch.id })
        #expect(food.nutrients.kcal == 300 && food.version == HealthBackfill.version(fromWatch.updatedAt))
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
