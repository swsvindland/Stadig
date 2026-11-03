import FoodDatabase
import Foundation
import HealthBridge
import NutritionEngine
import SystemCore
import SystemStore

extension AppModel {
    // MARK: The stack

    /// Supplements being taken, by name.
    var activeSupplements: [Supplement] { supplements.filter { !$0.paused } }

    func save(supplement: Supplement) {
        var supplement = supplement
        supplement.updatedAt = Date()
        store.save(supplement)
        reload()
    }

    /// Takes a supplement out of the stack. Doses already taken keep counting on their days.
    func delete(supplement id: UUID) {
        store.delete(Supplement.self, id: id)
        reload()
    }

    func setPaused(_ paused: Bool, supplement: Supplement) {
        var supplement = supplement
        supplement.paused = paused
        save(supplement: supplement)
    }

    /// A supplement already in the stack, by any of its barcode's forms.
    func ownSupplement(barcode: String, symbology: Barcode.Symbology? = nil) -> Supplement? {
        let keys = Set(Barcode.keys(for: barcode, symbology: symbology))
        return supplements.first { $0.facts.barcode.map(keys.contains) ?? false }
    }

    /// A label from the NIH catalog. Packaged foods sold as supplements (protein powders, meal
    /// replacements) are foods when the food catalog knows them too.
    func supplementFacts(barcode: String, symbology: Barcode.Symbology? = nil) -> SupplementFacts? {
        supplementCatalog?.supplement(barcode: barcode, symbology: symbology)
    }

    /// Whether a scanned code is better logged as a supplement than as a food.
    func isSupplement(_ facts: SupplementFacts, food: Food?) -> Bool {
        guard food != nil else { return true }
        return (facts.nutrients?.kcal ?? 0) < 50
    }

    // MARK: Doses

    /// A tap on a reminder: Today on its day (not past today, for a model whose day has gone stale),
    /// in place of any sheet that's up, scrolled to the supplements, which sit below the food.
    func showDoses(on day: Day) {
        dismissSheets()
        selectedDay = min(day, today)
        tab = .today
        supplementsScrollRequest &+= 1
    }

    /// The doses due on a day, with whether each was taken.
    func doses(on day: Day) -> [DueDose] {
        let training = profile.map { SupplementPlan.isTrainingDay(day, profile: $0, lift: lift) } ?? false
        return SupplementPlan.due(on: day, stack: supplements, logs: supplementLogs, training: training)
    }

    /// When a dose marked now was taken: now today; on a day being caught up, its time of day there.
    func doseDate(_ time: DoseTime, on day: Day) -> Date {
        guard day != today else { return Date() }
        return day.at(minutes: settings.minutes(time))
    }

    /// Marks doses taken, replacing a skip. Shows Undo when there's more than one.
    func take(_ doses: [DueDose], on day: Day, message: String? = nil) {
        let open = doses.filter { !$0.taken }
        guard !open.isEmpty else { return }
        for dose in open {
            if let log = dose.log { store.delete(SupplementLog.self, id: log.id) }
        }
        let logs = open.map {
            SupplementLog(
                supplement: $0.supplement, doseID: $0.dose.id, date: doseDate($0.dose.time, on: day), day: day,
                count: $0.dose.count)
        }
        store.save(logs)
        reload()
        if open.count > 1 || message != nil {
            toast = Toast(message: message ?? "Took \(open.count) supplements", undoDoses: logs.map(\.id))
        }
        saveToHealth(logs)
    }

    /// Unmarks a dose: back to not known either way.
    func untake(_ dose: DueDose) {
        guard let log = dose.log else { return }
        delete(doses: [log.id])
    }

    /// Marks a dose deliberately skipped, so it stops asking.
    func skip(_ dose: DueDose, on day: Day) {
        if let log = dose.log { store.delete(SupplementLog.self, id: log.id) }
        store.save(
            SupplementLog(
                supplement: dose.supplement, doseID: dose.dose.id, date: doseDate(dose.dose.time, on: day), day: day,
                count: dose.dose.count, taken: false))
        reload()
        Task { await HealthBridge.shared.deleteFoods(ids: dose.log.map { [$0.id] } ?? []) }
    }

    /// A dose outside the plan: one more, now.
    func takeExtra(_ supplement: Supplement, count: Double? = nil) {
        let date = selectedDay == today ? Date() : doseDate(.morning, on: selectedDay)
        let log = SupplementLog(
            supplement: supplement, doseID: nil, date: date, day: selectedDay,
            count: count ?? supplement.doses.first?.count ?? supplement.facts.servingCount)
        store.save(log)
        reload()
        toast = Toast(message: "Took \(supplement.name) · \(log.amountLabel)", undoDoses: [log.id])
        saveToHealth([log])
    }

    func delete(doses ids: [UUID]) {
        for id in ids { store.delete(SupplementLog.self, id: id) }
        reload()
        Task { await HealthBridge.shared.deleteFoods(ids: ids) }
    }

    /// The open doses at a time of day, for a reminder's "Taken" and the Shortcut.
    func takeAll(at time: DoseTime, on day: Day) -> Int {
        let open = doses(on: day).filter { $0.dose.time == time && $0.open }
        take(open, on: day, message: open.count > 1 ? "Took \(open.count) \(time.label.lowercased()) supplements" : nil)
        return open.count
    }

    private func saveToHealth(_ logs: [SupplementLog]) {
        guard settings.saveToHealth else { return }
        let foods = logs.filter(\.taken).map(Self.healthFood)
        Task { await HealthBridge.shared.saveFoods(foods) }
    }

    /// The time of day it is now.
    var currentDoseTime: DoseTime {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return DoseTime.nearest(minutes: minutes, times: settings.doseTimes ?? [:])
    }
}
