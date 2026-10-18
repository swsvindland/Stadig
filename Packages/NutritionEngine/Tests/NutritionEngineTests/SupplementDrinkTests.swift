import Foundation
import SystemCore
import Testing

@testable import NutritionEngine

@Suite("Supplements and drinks")
struct SupplementDrinkTests {
    // A Monday; the test profile trains four days a week: Monday, Tuesday, Thursday, Friday.
    let today = Day(year: 2026, month: 3, day: 9)

    func facts(_ name: String, count: Double = 1, unit: String = "capsule", _ lines: [(String, Double, String)]) -> SupplementFacts {
        SupplementFacts(
            id: "dsld:\(name)", name: name, servingCount: count, unit: unit,
            ingredients: lines.map { SupplementIngredient(name: $0.0, amount: $0.1, unit: $0.2) }, source: .dsld)
    }

    var fishOil: Supplement {
        Supplement(
            facts: facts(
                "Fish Oil", count: 2, unit: "softgel",
                [
                    ("Calories", 20, "kcal"), ("Total Fat", 2, "g"),
                    ("EPA", 650, "mg"), ("DHA", 450, "mg"),
                ]),
            doses: [Dose(time: .morning, count: 2)])
    }
    var multi: Supplement {
        Supplement(
            facts: facts("Multivitamin", unit: "tablet", [("Vitamin D3", 1000, "IU"), ("Magnesium", 50, "mg"), ("Zinc", 11, "mg")]),
            doses: [Dose(time: .morning), Dose(time: .evening)])
    }
    var preWorkout: Supplement {
        Supplement(
            facts: facts("Pre-workout", unit: "scoop", [("Calories", 5, "kcal"), ("Caffeine Anhydrous", 300, "mg")]),
            doses: [Dose(time: .afternoon, days: .trainingDays)])
    }
    var sleep: Supplement {
        Supplement(
            facts: facts("Sleep", count: 2, unit: "gummy", [("Magnesium", 100, "mg"), ("Melatonin", 3, "mg")]),
            doses: [Dose(time: .bedtime, count: 2)])
    }

    @Test("the day's doses come by time of day, pre-workout only on training days")
    func schedule() {
        let stack = [sleep, preWorkout, multi, fishOil]
        let monday = SupplementPlan.due(on: today, stack: stack, logs: [], training: true)
        #expect(
            monday.map { "\($0.dose.time.rawValue) \($0.supplement.name)" }
                == ["morning Fish Oil", "morning Multivitamin", "afternoon Pre-workout", "evening Multivitamin", "bedtime Sleep"])
        let rest = SupplementPlan.due(on: today.adding(days: 2), stack: stack, logs: [], training: false)
        #expect(!rest.contains { $0.supplement.name == "Pre-workout" })
        #expect(multi.scheduleLabel == "1 tablet · morning and evening")
        #expect(preWorkout.scheduleLabel == "1 scoop · afternoon, training days")
        #expect(SupplementPlan.isTrainingDay(today, profile: profile(), lift: nil))
        #expect(!SupplementPlan.isTrainingDay(today.adding(days: 2), profile: profile(), lift: nil))
        // Every other day, and chosen weekdays.
        let alternate = DoseDays.everyOtherDay(from: today)
        #expect(
            alternate.isDue(on: today, training: false) && !alternate.isDue(on: today.adding(days: 1), training: false)
                && alternate.isDue(on: today.adding(days: -2), training: false))
        #expect(DoseDays.weekdays([.monday, .thursday]).isDue(on: today, training: false))
        // Paused supplements aren't due.
        var paused = fishOil
        paused.paused = true
        #expect(SupplementPlan.due(on: today, stack: [paused], logs: [], training: true).isEmpty)
    }

    @Test("a dose taken holds what the label says for its count, and stays on the day if the plan changes")
    func logging() throws {
        let multi = multi
        let morning = multi.doses[0]
        let log = SupplementLog(supplement: multi, doseID: morning.id, date: today.date().addingTimeInterval(8 * 3600), count: 1)
        #expect(log.amounts["vitaminD"] == 25 && log.amounts["zinc"] == 11)
        let fish = SupplementLog(supplement: fishOil, doseID: nil, date: today.date().addingTimeInterval(9 * 3600), count: 1)
        #expect(abs(fish.amounts["omega3"]! - 0.55) < 1e-9, "one softgel of a two-softgel serving")
        #expect(fish.nutrients?.kcal == 10)
        let due = SupplementPlan.due(on: today, stack: [multi], logs: [log], training: false)
        #expect(due.first { $0.dose.id == morning.id }?.taken == true)
        #expect(due.first { $0.dose.time == .evening }?.open == true)
        // Taken off the plan afterwards: the morning dose still shows as taken on its day.
        var changed = multi
        changed.doses = [Dose(time: .evening)]
        let after = SupplementPlan.due(on: today, stack: [changed], logs: [log], training: false)
        #expect(after.count == 2 && after.first?.taken == true)
        let skipped = SupplementLog(supplement: multi, doseID: morning.id, date: Date(), day: today, count: 1, taken: false)
        #expect(skipped.amounts.isEmpty && SupplementPlan.amounts([skipped]).isEmpty)
        #expect(SupplementPlan.extras(on: today, logs: [fish, log]).map(\.name) == ["Fish Oil"])
    }

    func entry(
        _ day: Day, _ name: String, kcal: Double, hour: Double = 12, grams: Double? = nil, micros: [String: Double]? = nil,
        fluid: Double? = nil
    ) -> FoodEntry {
        FoodEntry(
            date: day.date().addingTimeInterval(hour * 3600), name: name, amountLabel: "1", grams: grams,
            nutrients: Nutrients(kcal: kcal, protein: 30, carbs: 60, fat: 20), micros: micros, fluid: fluid, source: .search)
    }

    @Test("supplements count toward the week's vitamins without being scaled like food")
    func microReport() throws {
        let days = (1...5).map { today.adding(days: -$0) }
        // Half the calories list vitamin D; the food gives 3 µg a day of the listed half.
        let entries = days.flatMap { [entry($0, "Salmon", kcal: 1200, micros: ["vitaminD": 3]), entry($0, "Bar", kcal: 1200)] }
        let without = MicroAnalyst.report(entries: entries, complete: Set(days), profile: profile(), kcal: 2400, today: today)
        #expect(without.reading("vitaminD")?.status == .low, "6 µg estimated of 15")
        let logs = days.map { SupplementLog(supplement: multi, doseID: multi.doses[0].id, date: $0.date().addingTimeInterval(8 * 3600), count: 1) }
        let with = MicroAnalyst.report(entries: entries, supplements: logs, complete: Set(days), profile: profile(), kcal: 2400, today: today)
        let vitaminD = try #require(with.reading("vitaminD"))
        #expect(vitaminD.status == .ok)
        #expect(abs(vitaminD.daily! - 31) < 0.001, "3 / 0.5 from food, plus 25 from the multivitamin, not 56")
        #expect(vitaminD.supplemented == 25 && vitaminD.sources.first == "Multivitamin")
        // Food listing no zinc at all: a supplement alone that meets the target is enough to say.
        #expect(with.reading("zinc")?.status == .ok && with.reading("zinc")?.fraction != nil)
        // Days that weren't complete don't count.
        let stray = SupplementLog(supplement: multi, doseID: nil, date: today.date(), count: 1)
        #expect(
            MicroAnalyst.report(entries: [], supplements: [stray], complete: [], profile: profile(), kcal: 2400, today: today)
                .reading("vitaminD")?.status == .unknown)
    }

    @Test("past a safe upper limit from supplements is flagged first; food alone never is")
    func upperLimits() throws {
        let days = (1...4).map { today.adding(days: -$0) }
        let entries = days.map { entry($0, "Spinach and salmon bowl", kcal: 2400, micros: ["vitaminD": 20, "magnesium": 500]) }
        let foodOnly = MicroAnalyst.report(entries: entries, complete: Set(days), profile: profile(), kcal: 2400, today: today)
        #expect(foodOnly.reading("magnesium")?.overUpper == false)
        let megaD = Supplement(facts: facts("Vitamin D3 5000 IU", unit: "softgel", [("Vitamin D3", 5000, "IU")]))
        let magnesium = Supplement(facts: facts("Magnesium Glycinate", count: 2, [("Magnesium", 400, "mg")]))
        let logs = days.flatMap { day in
            [
                SupplementLog(supplement: megaD, doseID: nil, date: day.date().addingTimeInterval(8 * 3600), count: 1),
                SupplementLog(supplement: magnesium, doseID: nil, date: day.date().addingTimeInterval(22 * 3600), count: 2),
            ]
        }
        let report = MicroAnalyst.report(entries: entries, supplements: logs, complete: Set(days), profile: profile(), kcal: 2400, today: today)
        let d = try #require(report.reading("vitaminD"))
        #expect(d.overUpper && d.upper == 100 && abs(d.measured - 145) < 0.001)
        let mg = try #require(report.reading("magnesium"))
        #expect(mg.overUpper, "400 mg from supplements is over the 350 mg supplemental limit")
        #expect(report.flagged.prefix(2).allSatisfy { $0.overUpper })
        // Under the supplemental limit, food on top doesn't push it over.
        let small = Supplement(facts: facts("Magnesium", [("Magnesium", 200, "mg")]))
        let fine = MicroAnalyst.report(
            entries: entries, supplements: days.map { SupplementLog(supplement: small, doseID: nil, date: $0.date(), count: 1) },
            complete: Set(days), profile: profile(), kcal: 2400, today: today)
        #expect(fine.reading("magnesium")?.overUpper == false)
    }

    @Test("a supplement's calories count only on days with food")
    func intake() {
        let settings = MacroSettings(onboardedAt: today.adding(days: -30).date(), assessmentStart: today.adding(days: -30))
        let yesterday = today.adding(days: -1)
        let log = SupplementLog(supplement: fishOil, doseID: nil, date: yesterday.date().addingTimeInterval(8 * 3600), count: 2)
        let lonely = SupplementLog(supplement: fishOil, doseID: nil, date: today.adding(days: -2).date().addingTimeInterval(8 * 3600), count: 2)
        let state = MacroState(
            profile: profile(), settings: settings, entries: [entry(yesterday, "Oats", kcal: 400)],
            supplementLogs: [log, lonely], today: today)
        let analysis = MacroAnalyst.analyse(state)
        #expect(analysis.intakeByDay[yesterday]?.kcal == 420)
        #expect(analysis.intakeByDay[today.adding(days: -2)] == nil)
    }

    @Test("caffeine still active at bedtime, and a cut-back a step a week")
    func caffeine() throws {
        let doses = [
            CaffeineDose(id: UUID(), date: today.date().addingTimeInterval(7 * 3600), mg: 100, name: "Coffee"),
            CaffeineDose(id: UUID(), date: today.date().addingTimeInterval(15 * 3600), mg: 200, name: "Energy drink"),
        ]
        let bedtime = today.date().addingTimeInterval(22.5 * 3600)
        let left = Caffeine.active(doses, at: bedtime)
        #expect(abs(left - (100 * pow(0.5, 15.5 / 5) + 200 * pow(0.5, 7.5 / 5))) < 0.001)
        #expect(left > Caffeine.bedtimeConcern)

        let plan = CaffeineCutBack(start: today, from: 400, goal: 200)
        #expect(plan.step == 80 && plan.weeks == 3)
        #expect(plan.limit(on: today) == 320 && plan.limit(on: today.adding(days: 6)) == 320)
        #expect(plan.limit(on: today.adding(days: 7)) == 240 && plan.limit(on: today.adding(days: 14)) == 200)
        #expect(plan.limit(on: today.adding(days: 60)) == 200 && plan.reachesGoal == today.adding(days: 14))
        #expect(CaffeineCutBack(start: today, from: 100, goal: 50).step == 25)

        // The report: today's drinks and pre-workout, against the week's step.
        let entries = [
            entry(today, "Coffee", kcal: 2, hour: 7, micros: ["caffeine": 95]),
            entry(today.adding(days: -1), "Coffee", kcal: 2, hour: 7, micros: ["caffeine": 190]),
            entry(today.adding(days: -2), "Energy drink", kcal: 10, hour: 14, micros: ["caffeine": 300]),
            entry(today.adding(days: -3), "Coffee", kcal: 2, hour: 7, micros: ["caffeine": 95]),
        ]
        let pre = SupplementLog(supplement: preWorkout, doseID: nil, date: today.date().addingTimeInterval(15 * 3600), count: 1)
        let report = Caffeine.report(
            day: today, entries: entries, supplements: [pre], bedtime: bedtime, limit: 400,
            cutBack: CaffeineCutBack(start: today.adding(days: -7), from: 400, goal: 200), complete: [])
        #expect(report.total == 395 && report.limit == 240 && report.over)
        #expect(report.doses.map(\.name) == ["Coffee", "Pre-workout"])
        #expect(abs(report.weekAverage! - 195) < 0.001, "three days with caffeine logged")
        #expect(report.cutoff == bedtime.addingTimeInterval(-8 * 3600))
    }

    @Test("caffeine is estimated for drinks logged without it, by name")
    func caffeineEstimates() {
        #expect(abs(Caffeine.estimate(name: "Iced latte", brand: nil, grams: 473)! - 151.4) < 0.1)
        #expect(abs(Caffeine.estimate(name: "Pacific Punch", brand: "Monster Energy", grams: 473)! - 160.8) < 0.1)
        #expect(Caffeine.estimate(name: "Decaf coffee", brand: nil, grams: 350)! < 5)
        #expect(Caffeine.estimate(name: "Peppermint tea", brand: nil, grams: 250) == 0)
        #expect(Caffeine.estimate(name: "Coffee cake", brand: nil, grams: 80) == nil)
        #expect(Caffeine.estimate(name: "Orange juice", brand: nil, grams: 250) == nil)
    }

    @Test("drinks are told from foods named after them")
    func drinks() {
        for name in [
            "Beverages, coffee, brewed, prepared with tap water", "Milk, whole, 3.25% milkfat", "Monster Energy Zero Sugar",
            "Iced coffee", "Coffee with milk", "Chocolate milk", "Sparkling water", "Water, bottled, generic", "Protein shake",
            "Orange juice", "Kombucha", "Diet Coke", "Cold brew",
        ] {
            #expect(Hydration.isDrink(name), "\(name)")
        }
        for name in [
            "Coffee cake", "Milk chocolate", "Coffee ice cream", "Cereals, oats, regular and quick, cooked with water",
            "Oats cooked with milk", "Watermelon", "Tuna, canned in water", "Beverages, coffee, instant, regular, powder",
            "Steak", "Beer", "Tea biscuits", "Milk thistle",
        ] {
            #expect(!Hydration.isDrink(name), "\(name)")
        }
        let entries = [
            entry(today, "Coffee", kcal: 2, grams: 237), entry(today, "Oats", kcal: 300, grams: 80),
            entry(today, "Can", kcal: 10, grams: 473, fluid: 473), entry(today.adding(days: -1), "Coffee", kcal: 2, grams: 237),
        ]
        let water = [
            WaterLog(date: today.date().addingTimeInterval(9 * 3600), ml: 500), WaterLog(date: today.date().addingTimeInterval(13 * 3600), ml: 250),
        ]
        let day = Hydration.day(today, water: water, entries: entries, target: Hydration.target(sex: .male))
        #expect(day.water == 750 && day.drinks == 710 && day.total == 1460 && day.target == 3000)
    }

    @Test("supplements and water go to the CSV export")
    func export() {
        let log = SupplementLog(supplement: multi, doseID: nil, date: today.date().addingTimeInterval(8 * 3600), count: 1)
        let tables = NutritionExport.tables(
            entries: [entry(today, "Coffee", kcal: 2, grams: 237)], weighIns: [], checkIns: [], days: [],
            supplements: [log], water: [WaterLog(date: today.date(), ml: 500)])
        #expect(tables.map(\.name) == ["diary", "weight", "targets", "days", "supplements", "water"])
        let supplements = tables[4]
        #expect(supplements.header.contains("vitaminD_ug") && supplements.rows.first?[2] == "Multivitamin")
        let diary = tables[0]
        #expect(diary.rows.first?[diary.header.firstIndex(of: "fluid_ml")!] == "237")
    }

    var losAngeles: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    @Test("export times are on the clock of the day next to them, not UTC")
    func exportTimes() throws {
        let calendar = losAngeles
        let day = Day(year: 2026, month: 10, day: 17)
        let dinner = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 20)))
        let entry = FoodEntry(
            date: dinner, day: day, name: "Dinner", amountLabel: "1 plate",
            nutrients: Nutrients(kcal: 700, protein: 40, carbs: 70, fat: 25), source: .search)
        let tables = NutritionExport.tables(
            entries: [entry], weighIns: [], checkIns: [], days: [],
            supplements: [SupplementLog(supplement: multi, doseID: nil, date: dinner, day: day, count: 1)],
            water: [WaterLog(date: dinner, day: day, ml: 500)], calendar: calendar)
        for table in tables where table.header.starts(with: ["day", "time"]) {
            #expect(table.rows.first.map { Array($0.prefix(2)) } == ["2026-10-17", "20:00:00"], "\(table.name)")
        }
        #expect(tables.filter { $0.header.starts(with: ["day", "time"]) }.map(\.name) == ["diary", "supplements", "water"])
    }

    @Test("bedtime is by the clock on the days clocks change")
    func bedtimeAcrossDST() throws {
        let calendar = losAngeles
        let state = MacroState(profile: profile(), settings: MacroSettings(), today: today)
        // Spring forward (a 23-hour day) and fall back (25 hours), at the default 22:30.
        for day in [Day(year: 2026, month: 3, day: 8), Day(year: 2026, month: 11, day: 1), Day(year: 2026, month: 6, day: 1)] {
            let bedtime = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: state.bedtime(on: day, calendar: calendar))
            #expect(bedtime.hour == 22 && bedtime.minute == 30 && bedtime.day == day.dayOfMonth, "\(day): \(bedtime)")
        }
        // After midnight, it's that night's: early the next morning.
        var late = MacroSettings()
        late.doseTimes = [.bedtime: 60 + 15]
        let night = MacroState(profile: profile(), settings: late, today: today).bedtime(on: Day(year: 2026, month: 3, day: 7), calendar: calendar)
        let parts = calendar.dateComponents([.day, .hour, .minute], from: night)
        #expect(parts.day == 8 && parts.hour == 1 && parts.minute == 15, "\(parts)")
    }

    @Test("bedtime is the same moment on a phone set to the Buddhist calendar")
    func bedtimeOnABuddhistCalendar() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = losAngeles.timeZone
        let state = MacroState(profile: profile(), settings: MacroSettings(), today: today)
        let day = Day(year: 2026, month: 10, day: 18)
        #expect(state.bedtime(on: day, calendar: buddhist) == state.bedtime(on: day, calendar: losAngeles))
        #expect(Day(state.bedtime(on: day, calendar: buddhist), calendar: buddhist) == day)
    }
}
