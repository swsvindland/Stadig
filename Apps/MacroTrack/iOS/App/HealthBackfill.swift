import Foundation
import HealthBridge
import NutritionEngine
import OSLog
import SystemCore
import SystemStore

#if canImport(HealthKit) && !os(macOS)
import HealthKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Puts into Apple Health, once, what was logged on a device that doesn't write there itself: the
/// Watch (which leaves Health to this app, so a food never arrives twice under two apps' names) and
/// the Mac (which has no Health). Each device that logs something writes it to Health as it logs;
/// this covers the rest as it syncs in.
///
/// Every food, glass of water, dose taken and weigh-in typed in over the last `window` days is
/// checked against Health by its sync identifier (the record's id, which every write here uses):
/// what Health already holds at that version, from this app on any device, is left alone, and the
/// rest is written. A ledger kept on this device remembers what's been handled, so each version is
/// looked up once and a sample the person deletes in Health isn't put back. When something handled
/// here is deleted on another device (an Undo on the Watch, a delete on the Mac), its copy in Health
/// goes too, but only on a deletion the store holds: a record that's merely missing (not synced
/// yet, an iCloud account change) or written by a newer app version this one can't read is left
/// alone in Health.
///
/// A pass runs at launch, when another device's changes arrive, each time the app comes to the
/// front, when the phone is unlocked and when Health is connected: a pass that found the phone
/// locked or Health not connected yet (`.later`) is tried again then, not left for the next import.
@MainActor
final class HealthBackfill {
    /// How far back things are checked: Health matters for the recent past, and the ledger stays small.
    static let window = 30
    static let ledgerKey = "health.backfill"

    let store: RecordStore
    let health: any HealthCopies
    /// Where the ledger is kept; nil keeps it for this run.
    private let defaults: UserDefaults?
    private(set) var ledger: [UUID: HealthLedgerEntry]
    private var running: Task<Void, Never>?
    private var runAgain = false
    private var storeObserver: AnyObject?
    private var unlockObserver: NotificationToken?

    /// The live one, over the app's store and this device's Health, with a first pass now; nil where
    /// there's no Health (the Mac).
    static func live(store: RecordStore) -> HealthBackfill? {
        guard HealthBridge.shared.isAvailable else { return nil }
        let backfill = HealthBackfill(store: store, health: LiveHealthCopies(), defaults: .standard)
        backfill.observe()
        backfill.run()
        return backfill
    }

    init(store: RecordStore, health: any HealthCopies, defaults: UserDefaults?) {
        self.store = store
        self.health = health
        self.defaults = defaults
        ledger = defaults.flatMap(Self.loadLedger) ?? [:]
    }

    /// A pass whenever another device's changes arrive (the store holds the observer weakly), and
    /// when the phone is unlocked, since Health can't be written while it's locked.
    func observe() {
        storeObserver = store.observeChanges { [weak self] in self?.run() }
        #if canImport(UIKit)
        unlockObserver = NotificationToken.observe(UIApplication.protectedDataDidBecomeAvailableNotification) { [weak self] in self?.run() }
        #endif
    }

    /// A pass now, or straight after the one running, so a burst of imports makes at most two.
    func run() {
        guard running == nil else {
            runAgain = true
            return
        }
        running = Task { [weak self] in
            repeat {
                self?.runAgain = false
                await self?.pass()
            } while self?.runAgain == true
            self?.running = nil
        }
    }

    /// One pass over the window ending `now`.
    func pass(now: Date = Date()) async {
        let since = Day(now).adding(days: -Self.window)
        let settings = MacroSettings.inForce(store.all(MacroSettings.self))
        let entries = store.all(FoodEntry.self)
        let water = store.all(WaterLog.self)
        let doses = store.all(SupplementLog.self)
        let weighIns = store.all(WeighIn.self)
        let items = Self.items(entries: entries, water: water, doses: doses, weighIns: weighIns, since: since, setUp: settings?.onboardedAt)
        let pending = items.filter { item in ledger[item.id].map { !Self.isCurrent($0.version, item.version) } ?? true }
        let gone = Self.gone(
            ledger: ledger, items: items, since: since, unmarked: { unmarked(of: $0) }, deleted: { deletions(of: $0) })
        defer { keep(since: since) }
        guard !pending.isEmpty || !gone.isEmpty else { return }

        // Someone who doesn't write to Health from Stadig Macro wants none of this: what's here now
        // counts as handled, so turning it on later doesn't pour in the past.
        guard settings?.saveToHealth ?? true else {
            for item in pending { ledger[item.id] = HealthLedgerEntry(item, written: false) }
            return
        }
        switch await health.access() {
        case .later:
            return
        case .never:
            for item in pending { ledger[item.id] = HealthLedgerEntry(item, written: false) }
            return
        case .writable:
            break
        }

        if !gone.isEmpty {
            await health.delete(foods: gone.filter { $0.source != .weighIn }.map(\.id))
            for item in gone where item.source == .weighIn { await health.delete(weight: item.id) }
            for item in gone { ledger[item.id] = nil }
        }
        guard !pending.isEmpty else { return }
        // Nil when Health couldn't be read: the next pass tries again rather than write blind.
        guard let foods = await health.versions(foods: pending.filter { $0.source != .weighIn }.map(\.id)),
            let weights = await health.versions(weights: pending.filter { $0.source == .weighIn }.map(\.id))
        else { return }
        let plan = Self.plan(pending, held: foods.merging(weights) { max($0, $1) })
        for item in plan.handled { ledger[item.id] = HealthLedgerEntry(item, written: false) }
        guard !plan.write.isEmpty else { return }
        await health.save(foods: plan.write.compactMap(\.food))
        for item in plan.write {
            if case .weight(let kg, let date) = item.kind { await health.save(weight: item.id, date: date, kg: kg, version: item.version) }
            ledger[item.id] = HealthLedgerEntry(item, written: true)
        }
        appLog.info("Health: wrote \(plan.write.count) things logged on other devices")
    }

    /// The records of a kind still in the store whose Health copy should go anyway: a dose marked
    /// not taken. Nothing else qualifies: an entry dated back out of the window, say, keeps its copy.
    private func unmarked(of source: HealthCopy.Source) -> Set<UUID> {
        guard source == .dose else { return [] }
        return Set(store.all(SupplementLog.self).filter { !$0.taken }.map(\.id))
    }

    /// A kind's deletions, read from its whole history, so they're asked for only when something
    /// handled has gone missing.
    private func deletions(of source: HealthCopy.Source) -> Set<UUID> {
        switch source {
        case .entry: store.deletedIDs(FoodEntry.self)
        case .water: store.deletedIDs(WaterLog.self)
        case .dose: store.deletedIDs(SupplementLog.self)
        case .weighIn: store.deletedIDs(WeighIn.self)
        }
    }

    /// Drops what's left the window, and keeps the ledger on the device when it changed.
    private func keep(since: Day) {
        ledger = ledger.filter { $0.value.day >= since }
        guard let defaults else { return }
        // Keyed by the id's text, keys sorted, so the same ledger encodes the same and isn't rewritten.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        do {
            let data = try encoder.encode(Dictionary(uniqueKeysWithValues: ledger.map { ($0.key.uuidString, $0.value) }))
            if defaults.data(forKey: Self.ledgerKey) != data { defaults.set(data, forKey: Self.ledgerKey) }
        } catch {
            appLog.error("Couldn't keep the Health ledger: \(error.localizedDescription)")
        }
    }

    private static func loadLedger(_ defaults: UserDefaults) -> [UUID: HealthLedgerEntry]? {
        guard let data = defaults.data(forKey: ledgerKey) else { return nil }
        do {
            let stored = try JSONDecoder().decode([String: HealthLedgerEntry].self, from: data)
            return Dictionary(stored.compactMap { key, entry in UUID(uuidString: key).map { ($0, entry) } }) { first, _ in first }
        } catch {
            appLog.error("Couldn't read the Health ledger, so starting it again: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: Rules

    /// What belongs in Health from the window: every food entry, glass of water and dose taken, and
    /// the weigh-ins typed in (those read from Health are there already). A weigh-in the person
    /// ignored isn't written, but isn't taken out either, as on the device that logged it; nor is
    /// the one setup saved at `setUp`, which is often Health's own latest reading.
    static func items(
        entries: [FoodEntry], water: [WaterLog], doses: [SupplementLog], weighIns: [WeighIn], since: Day, setUp: Date?
    ) -> [HealthCopy] {
        var items: [HealthCopy] = []
        // The same samples, at the same versions, as the device that logged them would have written.
        for entry in entries where entry.day >= since {
            let food = AppModel.healthFood(entry)
            items.append(HealthCopy(id: entry.id, version: food.version, day: entry.day, source: .entry, kind: .food(food)))
        }
        for glass in water where glass.day >= since {
            let food = AppModel.healthFood(glass)
            items.append(HealthCopy(id: glass.id, version: food.version, day: glass.day, source: .water, kind: .food(food)))
        }
        for dose in doses where dose.day >= since && dose.taken {
            let food = AppModel.healthFood(dose)
            items.append(HealthCopy(id: dose.id, version: food.version, day: dose.day, source: .dose, kind: .food(food)))
        }
        for weighIn in weighIns where weighIn.day >= since && weighIn.source == .manual {
            if let setUp, abs(weighIn.date.timeIntervalSince(setUp)) < 5 * 60 { continue }
            items.append(
                HealthCopy(
                    id: weighIn.id, version: weighIn.updatedAt.healthVersion, day: weighIn.day, source: .weighIn,
                    kind: .weight(kg: weighIn.kg, date: weighIn.date), writable: !weighIn.excluded))
        }
        return items
    }

    /// Of what's pending: what Health already holds at that version or later (or shouldn't get),
    /// which is only noted, and what to write.
    static func plan(_ pending: [HealthCopy], held: [UUID: Int]) -> (handled: [HealthCopy], write: [HealthCopy]) {
        var handled: [HealthCopy] = []
        var write: [HealthCopy] = []
        for item in pending {
            if let version = held[item.id], isCurrent(version, item.version) {
                handled.append(item)
            } else if item.writable {
                write.append(item)
            } else {
                handled.append(item)
            }
        }
        return (handled, write)
    }

    /// What the ledger handled, within the window, whose Health copy should go: still in the store
    /// but no longer something for Health (`unmarked`: a dose marked not taken), or deleted on some
    /// device (`deleted`: the store holds the deletion). Anything else no longer wanted keeps its
    /// copy: a record that's only missing, one this app version can't read, or one dated back out
    /// of the window.
    ///
    /// `unmarked` and `deleted` are asked only about the kinds of what the ledger handled and isn't
    /// wanted any more, and `deleted` only about those not unmarked, so a pass with nothing gone
    /// reads no history.
    static func gone(
        ledger: [UUID: HealthLedgerEntry], items: [HealthCopy], since: Day, unmarked: (HealthCopy.Source) -> Set<UUID>,
        deleted: (HealthCopy.Source) -> Set<UUID>
    ) -> [HealthGone] {
        let wanted = Set(items.map(\.id))
        let unwanted = ledger.filter { id, entry in entry.day >= since && !wanted.contains(id) }
        guard !unwanted.isEmpty else { return [] }
        let off = Set(unwanted.values.map(\.source)).reduce(into: Set<UUID>()) { $0.formUnion(unmarked($1)) }
        let rest = unwanted.filter { !off.contains($0.key) }
        let deletions = Set(rest.values.map(\.source)).reduce(into: Set<UUID>()) { $0.formUnion(deleted($1)) }
        return unwanted.filter { off.contains($0.key) || deletions.contains($0.key) }
            .map { HealthGone(id: $0.key, source: $0.value.source) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// Whether a version held for something, in Health or in the ledger, is this version or later.
    /// Before versions were rounded as the store rounds them (`Date.healthVersion`), this app
    /// truncated them, so a sample written then as something was logged can be a millisecond below
    /// the version worked out from the stored record. It's the same edit, and isn't written again.
    static func isCurrent(_ held: Int, _ version: Int) -> Bool { held >= version - 1 }
}

extension Date {
    /// This date as a sample's version in Health: whole milliseconds since 1970, rounded as the
    /// store rounds `updatedAt` when it saves a record. So the version written as something is
    /// logged and the one the backfill works out from the stored record are the same.
    var healthVersion: Int { Int((timeIntervalSince1970 * 1000).rounded()) }
}

/// One thing that belongs in Health, from the record it came from.
struct HealthCopy: Hashable, Sendable {
    enum Source: String, Codable, Hashable, Sendable { case entry, water, dose, weighIn }
    enum Kind: Hashable, Sendable {
        case food(HealthFood)
        case weight(kg: Double, date: Date)
    }

    var id: UUID
    var version: Int
    var day: Day
    var source: Source
    var kind: Kind
    /// False for what's kept out of Health though it's handled: an ignored weigh-in.
    var writable = true

    var food: HealthFood? {
        if case .food(let food) = kind { return food }
        return nil
    }
}

/// Something handled that's no longer in the store.
struct HealthGone: Hashable, Sendable {
    var id: UUID
    var source: HealthCopy.Source
}

/// What the ledger keeps of a thing it handled: the version, whether this device wrote it, its day
/// (for leaving the window) and its kind.
struct HealthLedgerEntry: Codable, Hashable, Sendable {
    var version: Int
    var written: Bool
    var day: Day
    var source: HealthCopy.Source

    init(_ item: HealthCopy, written: Bool) {
        version = item.version
        self.written = written
        day = item.day
        source = item.source
    }
}

/// Whether Health can be written now, later (the device is locked, or Health not yet connected) or
/// not at all (no Health, or no permission).
enum HealthAccessNow: Sendable {
    case writable, later, never
}

/// Health as the backfill needs it, so tests can stand in for it.
protocol HealthCopies {
    func access() async -> HealthAccessNow
    /// The highest version Health holds of each of these foods (and drinks and doses), from this
    /// app on any device; nil when the read failed.
    func versions(foods ids: [UUID]) async -> [UUID: Int]?
    func versions(weights ids: [UUID]) async -> [UUID: Int]?
    func save(foods: [HealthFood]) async
    func save(weight id: UUID, date: Date, kg: Double, version: Int) async
    func delete(foods ids: [UUID]) async
    func delete(weight id: UUID) async
}

/// This device's Health: writes through HealthBridge (by sync identifier, replacing earlier
/// versions), and reads of what's there by the same identifiers.
struct LiveHealthCopies: HealthCopies {
    func save(foods: [HealthFood]) async { await HealthBridge.shared.saveFoods(foods) }

    func save(weight id: UUID, date: Date, kg: Double, version: Int) async {
        await HealthBridge.shared.saveWeight(id: id, date: date, kg: kg, version: version)
    }

    func delete(foods ids: [UUID]) async { await HealthBridge.shared.deleteFoods(ids: ids) }

    func delete(weight id: UUID) async { await HealthBridge.shared.deleteWeight(id: id) }

    #if canImport(HealthKit) && !os(macOS)
    private static let store = HKHealthStore()

    func access() async -> HealthAccessNow {
        guard HealthBridge.shared.isAvailable else { return .never }
        // Health's files are locked with the device, and a write then fails.
        #if canImport(UIKit)
        guard UIApplication.shared.isProtectedDataAvailable else { return .later }
        #endif
        switch Self.store.authorizationStatus(for: HKQuantityType(.dietaryEnergyConsumed)) {
        case .sharingAuthorized: return .writable
        // Not asked yet: things wait until the person connects Health.
        case .notDetermined: return .later
        default: return .never
        }
    }

    func versions(foods ids: [UUID]) async -> [UUID: Int]? {
        await Self.versions(of: HKCorrelationType(.food), ids: ids)
    }

    func versions(weights ids: [UUID]) async -> [UUID: Int]? {
        await Self.versions(of: HKQuantityType(.bodyMass), ids: ids)
    }

    /// The highest sync version Health holds for each id, a few hundred ids a query.
    private static func versions(of type: HKSampleType, ids: [UUID]) async -> [UUID: Int]? {
        var found: [UUID: Int] = [:]
        for start in stride(from: 0, to: ids.count, by: 400) {
            let chunk = ids[start..<min(ids.count, start + 400)].map(\.uuidString)
            let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: chunk)
            let descriptor = HKSampleQueryDescriptor(predicates: [.sample(type: type, predicate: predicate)], sortDescriptors: [])
            do {
                for sample in try await descriptor.result(for: store) {
                    guard let text = sample.metadata?[HKMetadataKeySyncIdentifier] as? String, let id = UUID(uuidString: text) else { continue }
                    let version = (sample.metadata?[HKMetadataKeySyncVersion] as? NSNumber)?.intValue ?? 0
                    found[id] = max(found[id] ?? 0, version)
                }
            } catch {
                appLog.error("Health: couldn't read what's there: \(error.localizedDescription)")
                return nil
            }
        }
        return found
    }
    #else
    func access() async -> HealthAccessNow { .never }
    func versions(foods ids: [UUID]) async -> [UUID: Int]? { nil }
    func versions(weights ids: [UUID]) async -> [UUID: Int]? { nil }
    #endif
}
