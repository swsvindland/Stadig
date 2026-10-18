import Foundation
import SystemCore
import Testing

@testable import NutritionEngine

@Suite("Food quality")
struct QualityTests {
    let today = Day(year: 2026, month: 3, day: 10)

    func entry(_ day: Day, _ name: String, kcal: Double, _ processing: Processing?, fermented: Bool? = false, foodID: String? = nil) -> FoodEntry {
        FoodEntry(
            date: day.date().addingTimeInterval(12 * 3600), name: name, foodID: foodID ?? name, amountLabel: "1",
            nutrients: Nutrients(kcal: kcal, protein: 20, carbs: 30, fat: 10), processing: processing, fermented: fermented,
            source: .search)
    }

    @Test("the share of calories in each group, and where the ultra-processed ones came from")
    func shares() throws {
        let days = (1...5).map { today.adding(days: -$0) }
        let entries = days.flatMap { day in
            [
                entry(day, "Pop-Tarts", kcal: 600, .ultraProcessed),
                entry(day, "Cola", kcal: 300, .ultraProcessed),
                entry(day, "Chicken and rice", kcal: 1000, .whole),
                entry(day, "Cheddar", kcal: 100, .processed),
            ]
        }
        let report = QualityAnalyst.report(entries: entries, complete: Set(days), today: today)
        #expect(report.days.count == 5 && report.known && report.coverage == 1)
        #expect(abs((report.share(.ultraProcessed) ?? 0) - 0.45) < 1e-9)
        #expect(abs((report.share(.whole) ?? 0) - 0.5) < 1e-9)
        #expect(report.ultraStatus == .off, "45% is well over the 30% worth acting on")
        let top = try #require(report.ultraSources.first)
        #expect(top.name == "Pop-Tarts" && abs(top.kcal - 600) < 1e-9 && abs(top.share - 0.3) < 1e-9)
        #expect(report.ultraSources.map(\.name) == ["Pop-Tarts", "Cola"])
    }

    @Test("between the aim and the limit is fair, not an action")
    func fair() {
        let days = (1...4).map { today.adding(days: -$0) }
        let entries = days.flatMap { [entry($0, "Protein bar", kcal: 250, .ultraProcessed), entry($0, "Steak and potatoes", kcal: 750, .whole)] }
        #expect(QualityAnalyst.report(entries: entries, complete: Set(days), today: today).ultraStatus == .fair)
        let lighter = days.flatMap { [entry($0, "Protein bar", kcal: 150, .ultraProcessed), entry($0, "Steak and potatoes", kcal: 850, .whole)] }
        #expect(QualityAnalyst.report(entries: lighter, complete: Set(lighter.map(\.day)), today: today).ultraStatus == .good)
    }

    @Test("unknown until enough is logged, and enough of it says how processed it is")
    func unknown() {
        let two = (1...2).map { today.adding(days: -$0) }
        let few = two.map { entry($0, "Cola", kcal: 2000, .ultraProcessed) }
        #expect(QualityAnalyst.report(entries: few, complete: Set(two), today: today).ultraStatus == .unknown)

        let days = (1...5).map { today.adding(days: -$0) }
        let quickAdds = days.flatMap { [entry($0, "Quick add", kcal: 1500, nil, fermented: nil), entry($0, "Cola", kcal: 500, .ultraProcessed)] }
        let report = QualityAnalyst.report(entries: quickAdds, complete: Set(days), today: today)
        #expect(!report.known && report.ultraStatus == .unknown && abs(report.coverage - 0.25) < 1e-9)
        // Partial and in-progress days don't count: a half-logged day skews the shares.
        let today = entry(self.today, "Cola", kcal: 2000, .ultraProcessed)
        #expect(QualityAnalyst.report(entries: [today], complete: [self.today], today: self.today).days.isEmpty)
    }

    @Test("fermented foods by day, from the food or else its name")
    func fermented() {
        let days = (1...6).map { today.adding(days: -$0) }
        var entries = days.map { entry($0, "Chicken and rice", kcal: 1500, .whole) }
        entries.append(entry(days[0], "Greek yogurt", kcal: 150, .whole, fermented: true))
        entries.append(entry(days[0], "Kefir", kcal: 100, .whole, fermented: true))
        // A custom food says nothing, so its name decides.
        entries.append(entry(days[2], "Mum's kimchi", kcal: 30, nil, fermented: nil))
        entries.append(entry(days[3], "Frozen yogurt", kcal: 200, nil, fermented: nil))
        let report = QualityAnalyst.report(entries: entries, complete: Set(days), today: today)
        #expect(report.fermentedDays == 2, "two foods on one day count once, and frozen yogurt not at all")
        #expect(report.fermentedStatus == .fair, "2 of 6 days is about 2 a week")
        #expect(report.fermentedFoods.count == 3)

        let none = QualityAnalyst.report(entries: days.map { entry($0, "Chicken and rice", kcal: 1500, .whole) }, complete: Set(days), today: today)
        #expect(none.fermentedDays == 0 && none.fermentedStatus == .off)

        let most = days.prefix(4).map { entry($0, "Skyr", kcal: 120, .whole, fermented: true) } + entries
        #expect(QualityAnalyst.report(entries: most, complete: Set(days), today: today).fermentedStatus == .good)
    }

    @Test("fermented names across languages, but not baked, frozen or coated")
    func names() {
        for name in ["Greek Yogurt", "Yaourt nature", "Joghurt mild", "Kefir", "Sauerkraut", "Kimchi", "White miso", "Skyr", "Kombucha"] {
            #expect(Fermented.isFermented(name), "\(name)")
        }
        for name in ["Frozen yogurt", "Yogurt covered raisins", "Yogurt granola bar", "Miso soup", "Chicken breast", "Yogurt ice cream"] {
            #expect(!Fermented.isFermented(name), "\(name)")
        }
    }

    @Test("what was logged keeps how processed it was, through copies and export")
    func carried() throws {
        let e = entry(today, "Cola", kcal: 150, .ultraProcessed, fermented: false)
        let copy = LogAgain.copy(e, to: Date())
        #expect(copy.processing == .ultraProcessed && copy.fermented == false)
        let decoded = try JSONDecoder().decode(FoodEntry.self, from: JSONEncoder().encode(e))
        #expect(decoded.processing == .ultraProcessed)
        // Entries saved before processing was kept still read.
        var old = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(e)) as? [String: Any])
        old["processing"] = nil
        old["fermented"] = nil
        let legacy = try JSONDecoder().decode(FoodEntry.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(legacy.processing == nil && legacy.fermented == nil)
        let diary = try #require(NutritionExport.tables(entries: [e], weighIns: [], checkIns: [], days: []).first)
        let column = try #require(diary.header.firstIndex(of: "nova"))
        #expect(diary.rows.first?[column] == "4")
    }
}
