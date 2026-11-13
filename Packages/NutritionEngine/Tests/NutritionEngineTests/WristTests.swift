import Foundation
import SystemCore
import Testing

@testable import NutritionEngine

/// What the Watch shows, from the same analysis the phone runs.
@Suite("Today on the wrist")
struct WristTests {
    let start = Day(year: 2026, month: 3, day: 2)
    /// A Monday, a training day for the test profile.
    var today: Day { start.adding(days: 35) }

    var cut: PhasePlan {
        PhasePlan(
            phases: [PlannedPhase(kind: .cut, weeks: 12, start: start.adding(days: 21))], headline: "", reasons: [], confidence: nil,
            arc: "", created: start.adding(days: 21).date())
    }

    /// Five weeks of full days (oats at 8, chicken at 12:30, salmon at 19) and morning weigh-ins at
    /// 84 kg, a cut from week four, and today's oats at 8 if `breakfast`.
    func state(
        plan: PhasePlan?? = nil, breakfast: Bool = true, hour: Int = 13, settings: MacroSettings? = nil, units: WeightUnit = .kg,
        supplements: [Supplement] = [], logs: [SupplementLog] = [], water: [WaterLog] = [], weighIns: [WeighIn]? = nil
    ) -> MacroState {
        var entries: [FoodEntry] = []
        var statuses: [DayStatus] = []
        func meal(_ name: String, _ day: Day, _ hour: Int, _ minute: Int, _ n: Nutrients) -> FoodEntry {
            let date = day.at(hour: hour, minute: minute)
            return FoodEntry(date: date, name: name, foodID: "usda:\(name)", amountLabel: "1 bowl", nutrients: n, source: .search, updatedAt: date)
        }
        let oats = Nutrients(kcal: 600, protein: 30, carbs: 90, fat: 14)
        for day in DayRange(start, today.adding(days: -1)).days {
            entries.append(meal("Oats", day, 8, 0, oats))
            entries.append(meal("Chicken and rice", day, 12, 30, Nutrients(kcal: 900, protein: 60, carbs: 110, fat: 20)))
            entries.append(meal("Salmon and potatoes", day, 19, 0, Nutrients(kcal: 1_100, protein: 50, carbs: 90, fat: 55)))
            statuses.append(DayStatus(day: day, state: .complete))
        }
        if breakfast { entries.append(meal("Oats", today, 8, 0, oats)) }
        var profile = profile()
        profile.units = UnitPreference(weight: units, length: .cm)
        return MacroState(
            profile: profile, settings: settings ?? MacroSettings(assessmentStart: start), entries: entries,
            weighIns: weighIns ?? DayRange(start, today).days.map { WeighIn(date: $0.at(hour: 7, minute: 0), kg: 84) },
            dayStatus: statuses, plan: plan ?? cut, supplements: supplements, supplementLogs: logs, water: water, today: today,
            now: today.at(hour: hour, minute: 0))
    }

    func wrist(_ state: MacroState) -> WristToday { WristToday(state: state, analysis: MacroAnalyst.analyse(state)) }

    @Test("calories and protein left against the targets the phone shows")
    func targets() throws {
        let state = state()
        let analysis = MacroAnalyst.analyse(state)
        let wrist = WristToday(state: state, analysis: analysis)
        let kcal = try #require(analysis.targets.kcal)
        #expect(wrist.mode == .phase && wrist.badge == "Cut")
        #expect(wrist.kcal.target == kcal && wrist.kcal.eaten == 600)
        #expect(wrist.kcal.left == analysis.remaining?.kcal)
        #expect(wrist.protein.target == analysis.targets.protein && wrist.protein.eaten == 30)
        #expect(wrist.carbs.target == analysis.targets.carbs && wrist.fat.eaten == 14)
        #expect(wrist.hasEntries && wrist.weighedToday && wrist.dayState == nil)
        // The complications read the same numbers.
        let snapshot = WristSnapshot(wrist)
        #expect(snapshot.kcal == wrist.kcal && snapshot.protein == wrist.protein && snapshot.day == today && snapshot.badge == "Cut")
        #expect(snapshot.water == wrist.water.map { MacroProgress(eaten: $0.total, target: $0.target) })
        #expect(snapshot.shape == nil)
    }

    @Test("Your shape's complication takes the stats board's scores, and nothing before any is published")
    func shape() throws {
        let summary = AppSummary(
            app: .macroTrack, updated: today.date(),
            stats: [
                StatReading(stat: .vitality, score: 71.6, label: "Good", trend: .onPace),
                StatReading(stat: .discipline, score: nil, label: "Not enough yet", trend: .notEnoughData),
            ])
        let lines = StatsBoard.lines(lift: nil, macro: summary, today: today)
        #expect(WristSnapshot.shape(lines) == [.vitality: 72])
        #expect(WristSnapshot.shape(StatsBoard.lines(lift: nil, macro: nil, today: today)) == nil)
        let wrist = wrist(state())
        let snapshot = WristSnapshot(wrist, shape: WristSnapshot.shape(lines))
        #expect(snapshot.shape == [.vitality: 72])
        #expect(try #require(WristSnapshot.decoded(try snapshot.encoded())).shape == snapshot.shape)
    }

    @Test("the assessment asks only for protein, and says which day it is")
    func assessment() {
        let wrist = wrist(state(plan: .some(nil)))
        #expect(wrist.mode == .assessment)
        #expect(wrist.kcal.target == nil && wrist.kcal.left == nil && wrist.kcal.fraction == nil && wrist.kcal.eaten == 600)
        #expect(wrist.protein.target != nil)
        #expect(wrist.badge == "Day 21 of 21")
    }

    @Test("a ring fills to its target and no further; a unit over is over")
    func progress() {
        #expect(MacroProgress(eaten: 1_150, target: 2_300).fraction == 0.5)
        #expect(MacroProgress(eaten: 2_600, target: 2_300).fraction == 1)
        #expect(MacroProgress(eaten: 2_600, target: 2_300).left == -300 && MacroProgress(eaten: 2_600, target: 2_300).isOver)
        #expect(!MacroProgress(eaten: 2_300.4, target: 2_300).isOver)
        #expect(MacroProgress(eaten: 0, target: 0).fraction == 0 && MacroProgress(eaten: 10, target: 0).fraction == 1)
        #expect(MacroProgress(eaten: 500, target: nil).fraction == nil && !MacroProgress(eaten: 500, target: nil).isOver)
    }

    @Test("log again ranks as the phone does, with yesterday's meal while nothing's logged near now")
    func logAgain() throws {
        let lunchtime = state(hour: 13)
        let wrist = wrist(lunchtime)
        #expect(wrist.logAgain == Array(LogAgain.rank(lunchtime.entries, now: lunchtime.now, limit: WristToday.logAgainCount)))
        #expect(wrist.logAgain.first?.template.name == "Chicken and rice", "lunch is nearest one o'clock")
        // Nothing two-food at lunch on recent days, so no "same as yesterday" from single meals.
        #expect(wrist.sameAsUsual == nil)

        // Yesterday's lunch was two foods: offered at lunchtime today, until something's logged nearby.
        var state = lunchtime
        let yesterday = today.adding(days: -1)
        state.entries.append(
            FoodEntry(
                date: yesterday.at(hour: 12, minute: 35), name: "Apple", amountLabel: "1",
                nutrients: Nutrients(kcal: 95, protein: 0, carbs: 25, fat: 0),
                source: .search))
        let usual = try #require(LogAgain.usualNow(entries: state.entries, now: state.now))
        #expect(usual.entries.map(\.name) == ["Chicken and rice", "Apple"])
        #expect(self.wrist(state).sameAsUsual == usual)
        state.entries.append(
            FoodEntry(
                date: today.at(hour: 12, minute: 15), name: "Soup", amountLabel: "1", nutrients: Nutrients(kcal: 300, protein: 10, carbs: 40, fat: 8),
                source: .search))
        #expect(LogAgain.usualNow(entries: state.entries, now: state.now) == nil)
    }

    @Test("water only when drinks are tracked, in the person's units")
    func water() {
        #expect(wrist(state()).water == nil)
        var settings = MacroSettings(assessmentStart: start)
        settings.tracksDrinks = true
        let glass = WaterLog(date: today.at(hour: 9, minute: 0), ml: 250)
        let metric = wrist(state(settings: settings, water: [glass]))
        #expect(metric.water?.water == 250 && metric.water?.target == 3_000)
        #expect(metric.glasses.map(\.label) == ["Glass", "Bottle"] && metric.glasses.map(\.ml) == [250, 500])
        #expect(wrist(state(settings: settings, units: .lb)).glasses.map(\.label) == ["8 oz", "16.9 oz"])
    }

    @Test("the doses due by now, and how many are still to come")
    func doses() {
        func facts(_ name: String) -> SupplementFacts {
            SupplementFacts(id: "custom:\(name)", name: name, servingCount: 1, unit: "capsule", ingredients: [], source: .custom)
        }
        let fish = Supplement(facts: facts("Fish oil"), doses: [Dose(time: .morning, count: 2)])
        let multi = Supplement(facts: facts("Multivitamin"), doses: [Dose(time: .morning), Dose(time: .evening)])
        let magnesium = Supplement(facts: facts("Magnesium"), doses: [Dose(time: .midday)])
        let pre = Supplement(facts: facts("Pre-workout"), doses: [Dose(time: .afternoon, days: .trainingDays)])
        let taken = SupplementLog(supplement: fish, doseID: fish.doses[0].id, date: today.at(hour: 8, minute: 5), count: 2)
        let stack = [fish, multi, magnesium, pre]
        // One o'clock is midday: the multi from this morning is still open, the fish oil is taken.
        let lunch = wrist(state(hour: 13, supplements: stack, logs: [taken]))
        #expect(lunch.doses.map(\.supplement.name) == ["Multivitamin", "Magnesium"])
        #expect(lunch.laterDoses == 2, "the pre-workout on a training day, and the evening multi")
        #expect(lunch.dosesToday == 5 && wrist(state()).dosesToday == 0)
        // First thing, only the morning's.
        let morning = wrist(state(hour: 7, supplements: stack))
        #expect(morning.doses.map(\.supplement.name) == ["Fish oil", "Multivitamin"] && morning.laterDoses == 3)
        // The person's own times move what "now" is: 10:30 is nearest midday by default, but still
        // morning when midday is 2 PM.
        let due = SupplementPlan.due(on: today, stack: stack, logs: [], training: true)
        #expect(SupplementPlan.dueNow(due, minutes: 10 * 60 + 30).now.map(\.supplement.name) == ["Fish oil", "Multivitamin", "Magnesium"])
        let late = SupplementPlan.dueNow(due, minutes: 10 * 60 + 30, times: [.midday: 14 * 60])
        #expect(late.now.map(\.supplement.name) == ["Fish oil", "Multivitamin"])
    }

    @Test("the weigh-in dial starts at the last weigh-in, in the person's unit and step")
    func dial() {
        let kg = WeighInDial(unit: .kg, latestKg: 84.04, sex: .male)
        #expect(kg.step == 0.1 && kg.start == 84)
        #expect(kg.range == 20.1...399.9)
        #expect(kg.kilograms(84.26) == 84.3)
        #expect(kg.snapped(500) == 399.9 && kg.snapped(3) == 20.1)

        let lb = WeighInDial(unit: .lb, latestKg: 84, sex: .male)
        #expect(lb.step == 0.2)
        #expect(lb.start == 185.2, "84 kg is 185.19 lb, on the 0.2 lb grid")
        #expect(lb.range.lowerBound == 44.2 && lb.range.upperBound == 881.8)
        #expect(abs(lb.kilograms(185.2) - 84.005) < 0.001)
        #expect(Weight.isPlausible(kg: lb.kilograms(lb.range.lowerBound)) && Weight.isPlausible(kg: lb.kilograms(lb.range.upperBound)))

        // Before the first weigh-in, or after a typo, a typical weight.
        #expect(WeighInDial(unit: .kg, latestKg: nil, sex: .female).start == 68)
        #expect(WeighInDial(unit: .kg, latestKg: 4, sex: .male).start == 82)
        // The wrist uses the newest reading the trend counts: not one the person ignored.
        var ignored = WeighIn(date: today.at(hour: 7, minute: 30), kg: 90)
        ignored.excluded = true
        let weighIns = DayRange(start, today).days.map { WeighIn(date: $0.at(hour: 7, minute: 0), kg: 84) } + [ignored]
        #expect(wrist(state(weighIns: weighIns)).dial.start == 84)
        #expect(!wrist(state(weighIns: weighIns.filter { $0.day < today })).weighedToday)
        // The reading is set against the trend, as the phone's weigh-in is.
        let steady = state()
        let trend = try? #require(MacroAnalyst.analyse(steady).trend.latest?.trend)
        #expect(trend != nil && wrist(steady).trendKg == trend)
        #expect(abs((wrist(steady).trendKg ?? 0) - 84) < 0.5, "five weeks at 84 kg trend at 84")
    }

    @Test("past its day the snapshot shows nothing eaten yet, and reads back as written")
    func snapshot() throws {
        let snapshot = WristSnapshot(
            day: today, kcal: MacroProgress(eaten: 1_240, target: 2_300), protein: MacroProgress(eaten: 96, target: 170), badge: "Cut",
            updated: Date(timeIntervalSince1970: 1_775_000_000.123))
        var watered = snapshot
        watered.water = MacroProgress(eaten: 1_200, target: 3_000)
        #expect(watered.shown(on: today.adding(days: 1)).water == MacroProgress(eaten: 0, target: 3_000))
        let tomorrow = snapshot.shown(on: today.adding(days: 1))
        #expect(tomorrow.day == today.adding(days: 1) && tomorrow.kcal == MacroProgress(eaten: 0, target: 2_300))
        #expect(tomorrow.protein.left == 170 && tomorrow.badge == "Cut")
        #expect(snapshot.shown(on: today) == snapshot)

        let read = try #require(WristSnapshot.decoded(try snapshot.encoded()))
        #expect(read == snapshot)
        #expect(WristSnapshot.decoded(Data("{}".utf8)) == nil)
        var later = snapshot
        later.updated = later.updated.addingTimeInterval(60)
        #expect(!later.differs(from: snapshot))
        later.kcal.eaten += 100
        #expect(later.differs(from: snapshot))
    }

    @Test("the settings set up first are in force, else the newest")
    func settingsInForce() throws {
        let first = MacroSettings(onboardedAt: Date(timeIntervalSince1970: 1_000), updatedAt: Date(timeIntervalSince1970: 1_000))
        let second = MacroSettings(onboardedAt: Date(timeIntervalSince1970: 2_000), updatedAt: Date(timeIntervalSince1970: 3_000))
        let fresh = MacroSettings(updatedAt: Date(timeIntervalSince1970: 4_000))
        #expect(MacroSettings.inForce([second, fresh, first])?.id == first.id)
        let older = MacroSettings(updatedAt: Date(timeIntervalSince1970: 100))
        #expect(MacroSettings.inForce([older, fresh])?.id == fresh.id)
        #expect(MacroSettings.inForce([]) == nil)
    }
}
