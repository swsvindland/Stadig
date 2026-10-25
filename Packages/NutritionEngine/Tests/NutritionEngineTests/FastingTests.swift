import Foundation
import SystemCore
import Testing

@testable import NutritionEngine

/// Fasts with a goal: what ends them, their phases, the days they mark fasted, what they do to the
/// scale and the check-in, and who they aren't offered to.
@Suite("Fasting")
struct FastingTests {
    let monday = Day(year: 2026, month: 3, day: 2)

    func at(_ day: Day, _ hours: Double) -> Date {
        day.at(hour: Int(hours), minute: Int(((hours - hours.rounded(.down)) * 60).rounded()))
    }

    func meal(_ date: Date, kcal: Double = 650, protein: Double = 35) -> FoodEntry {
        FoodEntry(
            date: date, name: "Meal", amountLabel: "1", nutrients: Nutrients(kcal: kcal, protein: protein, carbs: kcal / 8, fat: kcal / 30),
            source: .search, updatedAt: date)
    }

    @Test("the phases by hours since the last meal")
    func phases() {
        #expect(FastPhase.at(hours: 0) == .digesting)
        #expect(FastPhase.at(hours: 3.9) == .digesting)
        #expect(FastPhase.at(hours: 4) == .insulinLow)
        #expect(FastPhase.at(hours: 12) == .fatBurning)
        #expect(FastPhase.at(hours: 30) == .ketosis)
        #expect(FastPhase.at(hours: 100) == .deepKetosis)
        #expect(FastPhase.deepKetosis.next == nil && FastPhase.fatBurning.next == .ketosis)
    }

    @Test("a meal after the start ends a fast; coffee, a meal before it, or no meal at all don't; Undo of the meal puts it back")
    func runs() throws {
        let start = at(monday, 20)
        let fast = Fast(start: start, goalHours: 16)
        let now = at(monday.adding(days: 1), 14)
        let coffee = meal(at(monday.adding(days: 1), 7), kcal: 5, protein: 0)
        let dinner = meal(at(monday, 19))
        #expect(Fasting.active(Fasting.runs([fast], entries: [dinner, coffee], now: now))?.fast == fast)
        let breakfast = meal(at(monday.adding(days: 1), 11))
        let ended = try #require(Fasting.runs([fast], entries: [dinner, coffee, breakfast], now: now).first)
        #expect(ended.end == breakfast.date && ended.duration(at: now) == 15 * 3600.0)
        #expect(Fasting.active([ended]) == nil)
        // Ended by hand, before any meal.
        var byHand = fast
        byHand.end = at(monday.adding(days: 1), 10)
        #expect(Fasting.runs([byHand], entries: [breakfast], now: now).first?.end == byHand.end)
        // A meal logged for later than now (a time picked ahead) hasn't ended it yet.
        let later = meal(at(monday.adding(days: 1), 18))
        #expect(Fasting.runs([fast], entries: [later], now: now).first?.isRunning == true)
    }

    @Test("dessert added to the meal a fast began from moves its start; a meal after ends it, also with older fasts on record")
    func foodAroundTheStart() throws {
        let tuesday = monday.adding(days: 1)
        let older = Fast(start: at(monday, 20), goalHours: 16)
        let dinner = meal(at(tuesday, 19))
        let fast = Fast(start: at(tuesday, 19), goalHours: 16)
        let dessert = meal(at(tuesday, 19.5), kcal: 400)
        let breakfast = meal(at(monday.adding(days: 2), 8))
        let now = at(monday.adding(days: 2), 7)
        let running = try #require(Fasting.runs([older, fast], entries: [dinner, dessert], now: now).last)
        #expect(running.isRunning && running.fast.start == dessert.date)
        let ended = try #require(Fasting.runs([older, fast], entries: [dinner, dessert, breakfast], now: at(monday.adding(days: 2), 9)).last)
        #expect(ended.end == breakfast.date && !ended.endedByHand)
        // A snack 50 minutes after the start is a meal of its own: it ends the fast.
        let snack = meal(at(tuesday, 19 + 50.0 / 60), kcal: 200)
        #expect(Fasting.runs([older, fast], entries: [dinner, snack], now: now).last?.end == snack.date)
        // Started by hand after a coffee, a sandwich 20 minutes on ends it: the coffee wasn't a meal.
        let coffee = meal(at(tuesday, 19), kcal: 5, protein: 0)
        let byHand = Fast(start: at(tuesday, 19 + 10.0 / 60), goalHours: 16)
        let sandwich = meal(at(tuesday, 19.5), kcal: 450)
        #expect(Fasting.runs([byHand], entries: [coffee, sandwich], now: now).first?.end == sandwich.date)
    }

    @Test("a fast with no meal logged long past its goal ends at its goal, and only a fast ended by hand counts beyond it")
    func pastTheGoal() throws {
        let fast = Fast(start: at(monday, 20), goalHours: 16)
        let brunch = meal(at(monday.adding(days: 2), 11))
        let forgotten = try #require(Fasting.runs([fast], entries: [brunch], now: at(monday.adding(days: 2), 12)).first)
        #expect(forgotten.end == fast.goalEnd && forgotten.vouched(at: Date()) == 16 * 3600.0)
        // Still within 12 hours of the goal, it runs on.
        #expect(Fasting.runs([fast], entries: [], now: at(monday.adding(days: 1), 20)).first?.isRunning == true)
        // Lunch 4 hours past the goal ends it there, vouched for to the goal; by hand, all of it.
        let lunch = meal(at(monday.adding(days: 1), 16))
        let late = try #require(Fasting.runs([fast], entries: [lunch], now: at(monday.adding(days: 1), 17)).first)
        #expect(late.end == lunch.date && late.duration(at: Date()) == 20 * 3600.0 && late.vouched(at: Date()) == 16 * 3600.0)
        var watched = fast
        watched.end = lunch.date
        let byHand = try #require(Fasting.runs([watched], entries: [], now: at(monday.adding(days: 1), 17)).first)
        #expect(byHand.endedByHand && byHand.vouched(at: Date()) == 20 * 3600.0)
    }

    @Test("a running fast's elapsed time, phase, next phase and goal")
    func status() {
        let fast = Fast(start: at(monday, 20), goalHours: 18)
        let s = Fasting.status(fast, now: at(monday.adding(days: 1), 10))
        #expect(s.hours == 14 && s.phase == .fatBurning)
        #expect(s.nextPhaseAt == at(monday.adding(days: 1), 20))
        #expect(abs(s.progress - 14.0 / 18) < 1e-9 && !s.goalReached && s.remaining == 4 * 3600.0)
        #expect(Fasting.status(fast, now: at(monday.adding(days: 1), 15)).goalReached)
    }

    @Test("a new fast starts at the end of the last meal, when that was in the last day")
    func suggestedStart() {
        let entries = [meal(at(monday, 18)), meal(at(monday, 18.5)), meal(at(monday, 21), kcal: 10)]
        #expect(Fasting.suggestedStart(entries: entries, now: at(monday, 22)) == at(monday, 18.5))
        let now = at(monday.adding(days: 2), 9)
        #expect(Fasting.suggestedStart(entries: entries, now: now) == now)
    }

    @Test("whole days inside a fast are fasted; a fast forgotten past its goal stops marking them")
    func fastedDays() {
        let today = monday.adding(days: 10)
        let now = at(today, 9)
        // 8 PM Monday to 8 AM Wednesday: Tuesday is whole.
        let thirtySix = FastRun(fast: Fast(start: at(monday, 20), goalHours: 36), end: at(monday.adding(days: 2), 8))
        #expect(Fasting.fastedDays([thirtySix], today: today, now: now) == [monday.adding(days: 1)])
        // Sixteen hours never covers a day.
        let sixteen = FastRun(fast: Fast(start: at(monday, 20), goalHours: 16), end: at(monday.adding(days: 1), 12))
        #expect(Fasting.fastedDays([sixteen], today: today, now: now).isEmpty)
        // A 24-hour goal left running for days: its coverage stops 12 hours past the goal.
        let forgotten = FastRun(fast: Fast(start: at(monday, 0), goalHours: 24), end: nil)
        #expect(Fasting.fastedDays([forgotten], today: today, now: now) == [monday])
        // A fast still running counts only the days before today.
        let running = FastRun(fast: Fast(start: at(today.adding(days: -3), 19), goalHours: 96), end: nil)
        #expect(Fasting.fastedDays([running], today: today, now: now) == [today.adding(days: -2), today.adding(days: -1)])
    }

    @Test("a long fast's scale days run to three days after it; a short one has none; the check-in waits while they last")
    func waterDays() {
        let end = at(monday.adding(days: 3), 20)
        let run = FastRun(fast: Fast(start: at(monday, 20), goalHours: 72), end: end)
        let days = Fasting.waterDays([run], now: at(monday.adding(days: 9), 9))
        #expect(days == Set(DayRange(monday.adding(days: 1), monday.adding(days: 6)).days))
        let short = FastRun(fast: Fast(start: at(monday, 20), goalHours: 18), end: at(monday.adding(days: 1), 14))
        #expect(Fasting.waterDays([short], now: at(monday.adding(days: 9), 9)).isEmpty)
        #expect(Fasting.recentLongFast([run], today: monday.adding(days: 6), now: at(monday.adding(days: 6), 9)) != nil)
        #expect(Fasting.recentLongFast([run], today: monday.adding(days: 7), now: at(monday.adding(days: 7), 9)) == nil)
        // Still running and past a day: the check-in waits now.
        let running = FastRun(fast: Fast(start: at(monday, 20), goalHours: 48), end: nil)
        #expect(Fasting.recentLongFast([running], today: monday.adding(days: 2), now: at(monday.adding(days: 2), 8)) != nil)
        #expect(Fasting.recentLongFast([running], today: monday.adding(days: 1), now: at(monday.adding(days: 1), 8)) == nil)
    }

    @Test("the estimate learns around a long fast as if it were eaten at maintenance: its days out, its deficit off the readings before it")
    func adjustment() {
        let run = FastRun(fast: Fast(start: at(monday, 20), goalHours: 48), end: at(monday.adding(days: 2), 20))
        // Tuesday fasted; Wednesday only the meal that ended it; Thursday to Saturday eaten as usual, Friday not logged.
        let usable: [Day: Double] = [
            monday: 2600, monday.adding(days: 1): 0, monday.adding(days: 2): 600, monday.adding(days: 3): 2700, monday.adding(days: 5): 2600,
        ]
        let today = monday.adding(days: 8)
        let a = Fasting.adjustment([run], usable: usable, maintenance: 2600, today: today, now: at(today, 9))
        #expect(a.excluded == Set(DayRange(monday.adding(days: 1), monday.adding(days: 5)).days))
        // 2,600 + 2,000 − 100, and nothing for the unlogged day.
        #expect(abs((a.deficits.first?.kg ?? 0) - 4500 / Energy.kcalPerKg) < 1e-9)
        let before = WeighIn(date: at(monday, 7), kg: 84)
        let after = WeighIn(date: at(monday.adding(days: 7), 7), kg: 83.4)
        #expect(a.adjusted([before, after]).map(\.kg) == [84 - 4500 / Energy.kcalPerKg, 83.4])
        let short = FastRun(fast: Fast(start: at(monday, 20), goalHours: 16), end: at(monday.adding(days: 1), 12))
        #expect(Fasting.adjustment([short], usable: usable, maintenance: 2600, today: today, now: at(today, 9)).isEmpty)
    }

    @Test("notifications at each phase from 12 hours to the goal, salt at a day, and how to break a long one")
    func milestones() {
        let fast = Fast(start: at(monday, 20), goalHours: 48)
        let list = Fasting.milestones(fast)
        #expect(list.map(\.kind) == [.phase(.fatBurning), .phase(.ketosis), .goal])
        #expect(list.map(\.at) == [at(monday.adding(days: 1), 8), at(monday.adding(days: 1), 20), at(monday.adding(days: 2), 20)])
        #expect(list[0].title == "12 h in: fat burning")
        #expect(list[1].body.contains("pinch of salt"))
        #expect(list[2].title == "48 h fast done" && list[2].body.contains("something small"))
        let overnight = Fasting.milestones(Fast(start: at(monday, 20), goalHours: 13))
        #expect(overnight.map(\.kind) == [.phase(.fatBurning), .goal])
        #expect(overnight.last?.body.contains("logging a meal ends it") == true)
    }

    @Test("fasts over a day aren't offered under 18 or underweight, and longer ones say when to see a doctor")
    func safety() {
        var teen = profile()
        teen.birthYear = 2010
        #expect(FastSafety.block(profile: teen, weightKg: 70, today: monday) == .under18)
        #expect(FastSafety.longest(.under18) == 24)
        let thin = FastSafety.block(profile: profile(), weightKg: 58, today: monday)
        guard case .underweight(let bmi)? = thin else {
            Issue.record("expected underweight, got \(String(describing: thin))")
            return
        }
        #expect(abs(bmi - 17.9) < 0.1)
        #expect(FastSafety.block(profile: profile(), weightKg: 84, today: monday) == nil)
        #expect(FastSafety.longest(nil) == Fasting.maxHours)
        #expect(FastSafety.refeed(hours: 16) == nil)
        #expect(FastSafety.refeed(hours: 30)?.contains("ordinary meal") == true)
        #expect(FastSafety.refeed(hours: 130)?.contains("refeeding syndrome") == true)
        #expect(FastSafety.notes(goalHours: 96, phase: .cut).count == 1)
        #expect(FastSafety.notes(goalHours: 36, phase: .leanBulk).first?.contains("lean bulk") == true)
        #expect(FastSafety.notes(goalHours: 16, phase: .leanBulk).isEmpty)
    }

    @Test("the Watch's snapshot carries the fast for its complication; one written before fasts decodes without it")
    func snapshot() throws {
        let fast = Fast(start: at(monday, 20), goalHours: 16)
        var snapshot = WristSnapshot.sample(on: monday)
        snapshot.fastStart = fast.start
        snapshot.fastGoalHours = fast.goalHours
        let decoded = try #require(WristSnapshot.decoded(try snapshot.encoded()))
        #expect(decoded.fast(at: at(monday.adding(days: 1), 8))?.phase == .fatBurning)
        // The shape before fasts: the same keys with no fast ones.
        var json = try #require(try JSONSerialization.jsonObject(with: try snapshot.encoded()) as? [String: Any])
        json["fastStart"] = nil
        json["fastGoalHours"] = nil
        let legacy = try #require(WristSnapshot.decoded(try JSONSerialization.data(withJSONObject: json)))
        #expect(legacy.fastStart == nil && legacy.fast(at: Date()) == nil)
        // Settings saved before meal timing existed read as off, with alerts on.
        let settings = try JSONDecoder().decode(MacroSettings.self, from: JSONEncoder().encode(MacroSettings()))
        #expect(!settings.mealTiming && settings.fastAlerts == nil && settings.fastingScreenSeen == nil)
    }

    @Test("fasts go in the CSV export: start, end, hours and goal, the end blank while one runs")
    func export() throws {
        let done = FastRun(fast: Fast(start: at(monday, 20), goalHours: 16), end: at(monday.adding(days: 1), 12))
        let running = FastRun(fast: Fast(start: at(monday.adding(days: 2), 20), goalHours: 36), end: nil)
        let tables = NutritionExport.tables(
            entries: [], weighIns: [], checkIns: [], days: [], fasts: [done, running], now: at(monday.adding(days: 3), 8))
        let table = try #require(tables.first { $0.name == "fasts" })
        #expect(table.header == ["start", "end", "hours", "goal_hours"])
        #expect(table.rows.map { $0[2] } == ["16", "12"] && table.rows[1][1] == "")
        #expect(NutritionExport.tables(entries: [], weighIns: [], checkIns: [], days: []).allSatisfy { $0.name != "fasts" })
    }

    // MARK: In the analysis

    /// Five weeks of four 650 kcal meals a day, marked complete and weighed at 84 kg each morning,
    /// at maintenance; then the days `fasted` skips, and a fast from `fastStart`.
    func state(
        today: Day, now: Date, fast: Fast?, fasted: Set<Day> = [], markFasted: Bool = false, scale: [Day: Double] = [:], extra: [FoodEntry] = []
    ) -> MacroState {
        var entries: [FoodEntry] = extra
        var statuses: [DayStatus] = []
        for day in DayRange(monday, today.adding(days: -1)).days {
            if fasted.contains(day) {
                if markFasted { statuses.append(DayStatus(day: day, state: .fasting)) }
                continue
            }
            for hour in [8.0, 12, 16, 19.5] where fast.map({ at(day, hour) <= $0.start || at(day, hour) >= $0.goalEnd }) ?? true {
                entries.append(meal(at(day, hour)))
            }
            statuses.append(DayStatus(day: day, state: .complete))
        }
        let weighIns = DayRange(monday, today).days.map { WeighIn(date: at($0, 7), kg: scale[$0] ?? 84) }
        let plan = PhasePlan(
            phases: [PlannedPhase(kind: .maintenance, weeks: 12, start: monday.adding(days: 21))], headline: "", reasons: [],
            confidence: nil, arc: "", created: monday.adding(days: 21).date())
        let checkIn = CheckIn(
            day: monday.adding(days: 21), expenditure: 2600, kcal: 2600, protein: 150, carbs: 330, fat: 80, status: .updated, reason: "Start")
        return MacroState(
            profile: profile(), settings: MacroSettings(assessmentStart: monday), entries: entries, weighIns: weighIns, dayStatus: statuses,
            plan: plan, checkIns: [checkIn], fasts: fast.map { [$0] } ?? [], today: today, now: now)
    }

    @Test("a 60-hour fast: its whole days count as fasted at nothing eaten, the history calls them fasted, and nobody asks about yesterday")
    func fastedDaysInAnalysis() throws {
        let fast = Fast(start: at(monday.adding(days: 28), 19.5), goalHours: 60)
        let fasted: Set<Day> = [monday.adding(days: 29), monday.adding(days: 30)]
        // The morning of day 31, before breakfast ends it: still running.
        let during = state(today: monday.adding(days: 31), now: at(monday.adding(days: 31), 6), fast: fast, fasted: fasted)
        let a = MacroAnalyst.analyse(during)
        #expect(a.usable[monday.adding(days: 29)] == 0 && a.usable[monday.adding(days: 30)] == 0)
        #expect(a.fast?.phase == .ketosis)
        #expect(!a.actions.contains { $0.kind == .logYesterday })
        let rows = DayHistory.rows(during, a)
        #expect(rows.first { $0.day == monday.adding(days: 30) }?.status == .fasting)
        // The overnight fast into a normal day, in the history.
        #expect(rows.first { $0.day == monday.adding(days: 20) }?.overnightFast == 12.5 * 3600.0)
    }

    @Test("a 16-hour fast and then a day not logged: the day stays unknown and nothing about the scale or the estimate changes")
    func unloggedDayAfterAFast() {
        let today = monday.adding(days: 31)
        let now = at(today, 10)
        let fast = Fast(start: at(monday.adding(days: 28), 20), goalHours: 16)
        let unlogged: Set<Day> = [monday.adding(days: 29)]
        let with = MacroAnalyst.analyse(state(today: today, now: now, fast: fast, fasted: unlogged))
        let without = MacroAnalyst.analyse(state(today: today, now: now, fast: nil, fasted: unlogged))
        #expect(with.usable[monday.adding(days: 29)] == nil)
        #expect(with.fasts.first?.end == fast.goalEnd)
        #expect(with.maintenance == without.maintenance)
        #expect(with.trend.latest?.trend == without.trend.latest?.trend)
        #expect(!with.actions.contains { $0.kind == .fastWater })
    }

    @Test("a day marked fasted with a coffee logged still counts as fasted")
    func markedFastedWithCoffee() {
        let today = monday.adding(days: 31)
        let day = monday.adding(days: 30)
        let coffee = meal(at(day, 8), kcal: 20, protein: 1)
        let a = MacroAnalyst.analyse(state(today: today, now: at(today, 10), fast: nil, fasted: [day], markFasted: true, extra: [coffee]))
        #expect(a.usable[day] == 20)
        #expect(
            DayHistory.rows(state(today: today, now: at(today, 10), fast: nil, fasted: [day], markFasted: true, extra: [coffee]), a).first {
                $0.day == day
            }?.status == .fasting)
    }

    @Test("Stadig Lift hears about a running fast only while meal timing is on")
    func publishedToLiftTrack() {
        let today = monday.adding(days: 35)
        let fast = Fast(start: at(today.adding(days: -1), 20), goalHours: 36)
        var s = state(today: today, now: at(today, 10), fast: fast)
        s.settings.tracksMealTiming = true
        #expect(MacroAnalyst.nutritionSummary(s, MacroAnalyst.analyse(s)).fast == PublishedFast(start: fast.start, goalHours: 36))
        s.settings.tracksMealTiming = false
        #expect(MacroAnalyst.nutritionSummary(s, MacroAnalyst.analyse(s)).fast == nil)
        var ended = state(today: today, now: at(today, 10), fast: Fast(start: fast.start, goalHours: 36, end: at(today, 8)))
        ended.settings.tracksMealTiming = true
        #expect(MacroAnalyst.nutritionSummary(ended, MacroAnalyst.analyse(ended)).fast == nil)
    }

    @Test("a fast running through the afternoon keeps the protein nudge quiet")
    func quietDuringFast() {
        let today = monday.adding(days: 35)
        let lunch = [meal(at(today, 8), protein: 20), meal(at(today, 12), protein: 20)]
        let now = at(today, 16)
        let eating = MacroAnalyst.analyse(state(today: today, now: now, fast: nil, extra: lunch))
        #expect(eating.actions.contains { $0.kind == .protein })
        let fasting = MacroAnalyst.analyse(state(today: today, now: now, fast: Fast(start: at(today, 12), goalHours: 24), extra: lunch))
        #expect(fasting.fast != nil && !fasting.actions.contains { $0.kind == .protein })
    }

    @Test("the scale through a fast and the days after stays out of the trend, and the check-in waits")
    func scaleAndCheckIn() throws {
        // Day 32 19:30 to day 35 19:30; the scale drops 2 kg of water and glycogen and refills.
        let fast = Fast(start: at(monday.adding(days: 32), 19.5), goalHours: 72)
        let fasted: Set<Day> = [monday.adding(days: 33), monday.adding(days: 34)]
        let water: [Int: Double] = [33: -0.4, 34: -1.2, 35: -1.9, 36: -1.3, 37: -0.6, 38: -0.2]
        let scale = Dictionary(uniqueKeysWithValues: water.map { (monday.adding(days: $0.key), 84 + $0.value) })

        // Day 35's check-in, 62 hours in: it holds.
        let checkInDay = monday.adding(days: 35)
        let during = MacroAnalyst.analyse(state(today: checkInDay, now: at(checkInDay, 9.5), fast: fast, fasted: fasted, scale: scale))
        let held = try #require(during.dueCheckIn)
        #expect(held.status == .holding && held.reason.contains("long fast"))

        // Day 37, two days after: the trend holds at 84 while a manual fasted mark lets the water in.
        let after = monday.adding(days: 37)
        let handled = MacroAnalyst.analyse(
            state(today: after, now: at(after, 9), fast: fast, fasted: fasted, scale: scale))
        let manual = MacroAnalyst.analyse(
            state(today: after, now: at(after, 9), fast: nil, fasted: fasted, markFasted: true, scale: scale))
        let kept = try #require(handled.trend.latest?.trend)
        let dipped = try #require(manual.trend.latest?.trend)
        #expect(abs(kept - 84) < 0.05, "\(kept)")
        #expect(84 - dipped > 0.3, "\(dipped)")
        #expect(handled.actions.contains { $0.kind == .fastWater })
        #expect(handled.usable[monday.adding(days: 33)] == 0)
    }

    @Test("a simulated six weeks with a three-day fast: maintenance and the targets ride through the water")
    func simulated() throws {
        var rng = SplitMix(seed: 2026)
        let truth = 2600.0
        let start = monday
        let fast = Fast(start: at(start.adding(days: 32), 19.5), goalHours: 72)
        // Water and glycogen lost each morning of the fast and given back after.
        let water: [Int: Double] = [33: -0.4, 34: -1.2, 35: -1.9, 36: -1.3, 37: -0.6, 38: -0.2]
        var kg = 84.0
        var entries: [FoodEntry] = []
        var statuses: [DayStatus] = []
        var weighIns: [WeighIn] = []
        var trueKg: [Day: Double] = [:]
        for i in 0..<56 {
            let day = start.adding(days: i)
            trueKg[day] = kg
            weighIns.append(WeighIn(date: at(day, 7), kg: kg + (water[i] ?? 0) + rng.normal() * 0.25))
            var eaten = 0.0
            let share = max(1800, truth + rng.normal() * 250) / 4
            for hour in [8.0, 12, 16, 19.5] {
                let date = at(day, hour)
                guard date <= fast.start || date >= fast.goalEnd else { continue }
                entries.append(meal(date, kcal: share))
                eaten += share
            }
            if eaten > 0 { statuses.append(DayStatus(day: day, state: .complete)) }
            kg += (eaten - truth) / Energy.kcalPerKg
        }
        let plan = PhasePlan(
            phases: [PlannedPhase(kind: .maintenance, weeks: 12, start: start.adding(days: 21))], headline: "", reasons: [],
            confidence: nil, arc: "", created: start.adding(days: 21).date())
        var checkIns = [
            CheckIn(
                day: start.adding(days: 21), expenditure: truth, kcal: truth, protein: 150, carbs: 330, fat: 80, status: .updated, reason: "Start")
        ]
        func analyse(_ day: Day, hour: Double = 10) -> MacroAnalysis {
            let now = at(day, hour)
            return MacroAnalyst.analyse(
                MacroState(
                    profile: profile(), settings: MacroSettings(assessmentStart: start), entries: entries.filter { $0.date <= now },
                    weighIns: weighIns.filter { $0.day <= day }, dayStatus: statuses.filter { $0.day < day }, plan: plan,
                    checkIns: checkIns, fasts: [fast], today: day, now: now))
        }
        for week in 1...4 {
            let day = start.adding(days: 21 + week * 7)
            let a = analyse(day)
            let due = try #require(a.dueCheckIn)
            #expect(abs(due.kcal - checkIns.last!.kcal) <= 150.01, "week \(week)")
            if day == start.adding(days: 35) { #expect(due.status == .holding, "\(due.reason)") }
            checkIns.append(due)
        }
        // The trend shown never takes the water (it lags the fast's real loss until the scale
        // settles, then catches up), and the estimate stays where it was.
        for i in 33...50 {
            let day = start.adding(days: i)
            let a = analyse(day)
            let trend = try #require(a.trend.latest?.trend)
            let weight = trueKg[day] ?? 0
            #expect(trend > weight - 0.3, "day \(i): trend \(trend), true \(weight)")
            if i >= 45 { #expect(abs(trend - weight) < 0.4, "day \(i): trend \(trend), true \(weight)") }
            #expect(abs(a.maintenance.kcal - truth) <= 200, "day \(i): maintenance \(a.maintenance.kcal)")
        }
        #expect(abs(checkIns.last!.expenditure - truth) < 200, "\(checkIns.map(\.expenditure))")
    }
}
