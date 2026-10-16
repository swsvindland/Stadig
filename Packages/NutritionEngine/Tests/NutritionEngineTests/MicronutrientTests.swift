import Foundation
import Testing
import SystemCore
@testable import NutritionEngine

@Suite("Vitamins and minerals")
struct MicronutrientTests {
    let today = Day(year: 2026, month: 3, day: 10)

    func entry(_ day: Day, _ name: String, kcal: Double, fiber: Double? = nil, sodium: Double? = nil, micros: [String: Double]? = nil) -> FoodEntry {
        FoodEntry(date: day.date().addingTimeInterval(12 * 3600), name: name, amountLabel: "1",
                  nutrients: Nutrients(kcal: kcal, protein: 20, carbs: 30, fat: 10, fiber: fiber, sodium: sodium), micros: micros,
                  source: .search)
    }

    @Test("targets follow sex, age and calories")
    func targets() {
        #expect(Micronutrients.target("iron", sex: .female, age: 30, kcal: 2000) == 18)
        #expect(Micronutrients.target("iron", sex: .female, age: 55, kcal: 2000) == 8)
        #expect(Micronutrients.target("iron", sex: .male, age: 30, kcal: 2000) == 8)
        #expect(Micronutrients.target("potassium", sex: .male, age: 30, kcal: 2000) == 3400)
        #expect(Micronutrients.target("calcium", sex: .female, age: 52, kcal: 2000) == 1200)
        #expect(Micronutrients.target("fiber", sex: .male, age: 30, kcal: 2500) == 35)
        #expect(Micronutrients.target("saturatedFat", sex: .male, age: 30, kcal: 2700) == 30)
        // Unspecified takes the higher target, so nothing is flagged that might be fine.
        #expect(Micronutrients.target("magnesium", sex: .unspecified, age: 40, kcal: 2000) == 420)
    }

    @Test("a nutrient short all week is flagged, with where it came from")
    func lowIsFlagged() throws {
        let days = (1...5).map { today.adding(days: -$0) }
        let entries = days.flatMap { day in
            [entry(day, "Pop-Tarts", kcal: 800, fiber: 2, sodium: 600, micros: ["potassium": 150, "calcium": 50]),
             entry(day, "Protein shake", kcal: 600, fiber: 1, sodium: 300, micros: ["potassium": 400, "calcium": 500]),
             entry(day, "Chicken and rice", kcal: 900, fiber: 3, sodium: 700, micros: ["potassium": 600, "calcium": 40])]
        }
        let report = MicroAnalyst.report(entries: entries, complete: Set(days), profile: profile(), kcal: 2300, today: today)
        #expect(report.days.count == 5)
        let potassium = try #require(report.reading("potassium"))
        #expect(potassium.status == .low && abs((potassium.daily ?? 0) - 1150) < 1 && potassium.coverage == 1)
        #expect(potassium.sources.first == "Chicken and rice")
        let fiber = try #require(report.reading("fiber"))
        #expect(fiber.status == .low, "6 g of 32")
        #expect(report.reading("sodium")?.status == .ok, "1,600 mg is under 2,300")
        // Fibre is the furthest short, so it leads.
        #expect(report.flagged.first?.nutrient.key == "fiber")
        #expect(report.flagged.contains { $0.nutrient.key == "calcium" }, "590 mg of 1,000 is 59%: low")
    }

    @Test("too little data says unknown, never low")
    func unknownNotLow() throws {
        let days = (1...4).map { today.adding(days: -$0) }
        // Packaged foods without a potassium value make up most of the calories.
        let entries = days.flatMap { day in
            [entry(day, "Granola bar", kcal: 1500), entry(day, "Banana", kcal: 100, micros: ["potassium": 420])]
        }
        let report = MicroAnalyst.report(entries: entries, complete: Set(days), profile: profile(), kcal: 2300, today: today)
        let potassium = try #require(report.reading("potassium"))
        #expect(potassium.status == .unknown && potassium.daily == nil && potassium.coverage < 0.1)
        #expect(!report.flagged.contains { $0.nutrient.key == "potassium" })
    }

    @Test("foods without a value are assumed like the ones with, so short isn't overstated")
    func scaledForCoverage() throws {
        let days = (1...3).map { today.adding(days: -$0) }
        let entries = days.flatMap { day in
            [entry(day, "Potato", kcal: 1000, micros: ["potassium": 1600]), entry(day, "Mystery bar", kcal: 1000)]
        }
        let reading = try #require(MicroAnalyst.report(entries: entries, complete: Set(days), profile: profile(), kcal: 2000,
                                                       today: today).reading("potassium"))
        #expect(reading.measured == 1600 && reading.coverage == 0.5 && reading.daily == 3200 && reading.status == .ok)
    }

    @Test("over a limit is flagged only on what was measured")
    func limits() throws {
        let days = (1...3).map { today.adding(days: -$0) }
        let entries = days.map { entry($0, "Ramen", kcal: 2000, sodium: 3800) }
        let report = MicroAnalyst.report(entries: entries, complete: Set(days), profile: profile(), kcal: 2000, today: today)
        #expect(report.reading("sodium")?.status == .high)
        #expect(report.flagged.contains { $0.nutrient.key == "sodium" })
    }

    @Test("nothing is flagged before three complete days, and partial days aren't read")
    func needsDays() {
        let days = [today.adding(days: -1), today.adding(days: -2)]
        let entries = days.map { entry($0, "Pop-Tarts", kcal: 2000, fiber: 2, micros: ["potassium": 100]) }
        let report = MicroAnalyst.report(entries: entries + [entry(today.adding(days: -3), "Half a day", kcal: 500, fiber: 0)],
                                         complete: Set(days), profile: profile(), kcal: 2000, today: today)
        #expect(report.days.count == 2 && report.flagged.isEmpty)
    }

    @Test("the analysis carries the report")
    func inAnalysis() {
        let eater = SimulatedEater(maintenance: 2500, startKg: 80)
        let run = eater.run(days: 10) { _, _ in 2400 }
        let state = MacroState(profile: profile(), settings: MacroSettings(assessmentStart: eater.start), entries: run.entries,
                               weighIns: run.weighIns, dayStatus: run.statuses, today: eater.start.adding(days: 10))
        let a = MacroAnalyst.analyse(state)
        #expect(!a.micros.days.isEmpty)
        // The simulated foods list no vitamins: unknown, not low.
        #expect(a.micros.reading("potassium")?.status == .unknown)
    }
}
