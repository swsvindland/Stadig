import Foundation
import SystemCore
import Testing

@testable import NutritionEngine

@Suite("Own targets")
struct OwnTargetsTests {
    let start = Day(year: 2026, month: 1, day: 5)
    /// A coach's numbers: 180 g protein, 210 g carbs and 60 g fat are 2,100 kcal.
    let mine = MacroTargets.grams(protein: 180, carbs: 210, fat: 60)

    // MARK: The sheet's numbers

    @Test("The grams add up to the calories; calories move carbs and fat, never protein")
    func inStep() {
        #expect(mine.kcal == 2_100 && mine.inStep)
        let less = mine.calories(1_900)
        #expect(less.kcal == 1_900 && less.protein == 180 && less.inStep, "\(less)")
        #expect(less.carbs < mine.carbs && less.fat < mine.fat)
        // Carbs and fat keep the share of what's left that they had (840 kcal to 540).
        #expect(abs(less.carbs * 4 / (less.fat * 9) - 840.0 / 540) < 0.05, "\(less)")
        // Typed a digit at a time, each step starts from the numbers before typing, so the split
        // isn't lost on the way through "2" and "24".
        let typed = ["2", "24", "240", "2400"].compactMap(Double.init).map { mine.calories($0) }
        #expect(typed.last == mine.calories(2_400) && typed.last?.inStep == true)
        let shares = mine.shares
        #expect(abs(shares.protein + shares.carbs + shares.fat - 1) < 1e-9)
        #expect(abs(shares.protein - 720.0 / 2_100) < 1e-9)
    }

    @Test("With no carbs or fat to share it, fat takes about 27% of the calories")
    func nothingToShare() {
        let split = MacroTargets.grams(protein: 150, carbs: 0, fat: 0).calories(2_000)
        #expect(split == MacroTargets(kcal: 2_000, protein: 150, carbs: 215, fat: 60), "\(split)")
        #expect(split.inStep)
    }

    @Test("Numbers that can't be targets say why")
    func problems() {
        #expect(OwnTargets.problem(mine) == nil)
        #expect(OwnTargets.problem(MacroTargets.grams(protein: 100, carbs: 50, fat: 20)) == "At least 1,000 kcal a day.")
        #expect(OwnTargets.problem(MacroTargets.grams(protein: 400, carbs: 900, fat: 200)) == "At most 6,000 kcal a day.")
        // Calories typed under what protein alone comes to: carbs and fat are nothing, and it still doesn't add up.
        let short = MacroTargets.grams(protein: 300, carbs: 100, fat: 50).calories(1_100)
        #expect(short.carbs == 0 && short.fat == 0)
        #expect(OwnTargets.problem(short) == "Protein alone is 1,200 kcal, more than the calories.")
    }

    // MARK: Which targets are in force

    @Test("They're in force over the phase, the assessment and a deload's diet break, but not a life mode")
    func inForce() throws {
        let plan = MacroTargets(kcal: 2_150, protein: 165, carbs: 230, fat: 65)
        let own = OwnTargets.record(mine, on: start, expenditure: 2_600, plan: plan)
        let cut = PhasePlan(phases: [PlannedPhase(kind: .cut, weeks: 8, start: start)], headline: "", reasons: [], confidence: nil, arc: "")
        let day = start.adding(days: 3)
        let maintenance = MaintenanceEstimate(kcal: 2_600, low: 2_400, high: 2_800, basis: .data, days: 20, formula: 2_600)
        func targets(
            _ checkIn: CheckIn? = nil, assessing: Bool = false, periods: [LifeModePeriod] = [], deload: Bool = false, keepsOwn: Bool = true
        ) -> DailyTargets {
            Targets.today(
                day: day, assessing: assessing, plan: cut, override: nil, maintenance: maintenance, checkIn: checkIn ?? own, weightKg: 84,
                heightCm: 180, waistToHeight: nil, life: LifeModes.effects(on: day, periods: periods), deload: deload, keepsOwn: keepsOwn)
        }
        let set = targets()
        #expect(set.mode == .own && set.kcal == 2_100 && set.protein == 180 && set.carbs == 210 && set.fat == 60)
        #expect(set.note == Targets.ownNote)
        #expect(targets(assessing: true).mode == .own)
        #expect(targets(deload: true).mode == .own, "no diet break the person didn't ask for")
        let trip = LifeModePeriod(kind: .vacation, start: day, end: day.adding(days: 6), createdBy: .liftTrack)
        #expect(targets(periods: [trip]).mode == .vacation)
        let ill = LifeModePeriod(kind: .illness(.systemic), start: day, createdBy: .macroTrack)
        #expect(targets(periods: [ill]).mode == .illness)
        let busy = LifeModePeriod(kind: .crunch(CrunchDials()), start: day, end: day.adding(days: 5), createdBy: .liftTrack)
        #expect(targets(periods: [busy]).mode == .crunch)
        // What the plan would set: the numbers carried under the person's.
        let planned = targets(keepsOwn: false)
        #expect(planned.mode == .phase && planned.kcal == 2_150 && planned.protein == 165)
        // Set in the assessment, there are none to carry: the phase from the maintenance they carry.
        let bare = targets(OwnTargets.record(mine, on: start, expenditure: 2_600, plan: nil), keepsOwn: false)
        #expect(bare.kcal == Targets.calories(maintenance: 2_600, phase: cut.phases[0], weightKg: 84))
    }

    @Test("Their run begins where they were first set and ends with the plan's")
    func since() {
        let plans = CheckIn(day: start, expenditure: 2_600, kcal: 2_200, protein: 170, carbs: 230, fat: 70, status: .updated, reason: "")
        let set = OwnTargets.record(mine, on: start.adding(days: 3), expenditure: 2_600, plan: nil)
        let kept = OwnTargets.kept(set, planned: plans)
        let week = CheckIn(
            id: CheckIn.id(for: start.adding(days: 10)), day: start.adding(days: 10), expenditure: kept.expenditure, kcal: kept.kcal,
            protein: kept.protein, carbs: kept.carbs, fat: kept.fat, status: .manual, reason: kept.reason, plan: kept.plan)
        let today = start.adding(days: 12)
        #expect(OwnTargets.inForce([plans, set, week], due: nil, on: today)?.since == start.adding(days: 3))
        #expect(OwnTargets.inForce([plans, set, week], due: nil, on: start.adding(days: 1)) == nil, "before them, the plan's")
        let back = CheckIn(day: today, expenditure: 2_600, kcal: 2_200, protein: 170, carbs: 230, fat: 70, status: .updated, reason: "")
        #expect(OwnTargets.inForce([plans, set, week, back], due: nil, on: today) == nil)
    }

    // MARK: Weeks of them

    /// Someone with a true maintenance of 2,500 who sets a coach's 2,100 kcal and eats to it,
    /// logging most days and weighing in most mornings.
    struct Coached {
        let eater = SimulatedEater(maintenance: 2_500, startKg: 85, logging: 0.9, noiseKg: 0.4)
        let run: SimulatedEater.Run
        let mine = MacroTargets.grams(protein: 180, carbs: 210, fat: 60)
        var start: Day { eater.start }

        init() { run = eater.run(days: 21 + 63) { _, _ in 2_100 } }

        func state(_ day: Day, plan: PhasePlan? = nil, checkIns: [CheckIn]) -> MacroState {
            MacroState(
                profile: profile(), settings: MacroSettings(onboardedAt: start.date(), assessmentStart: start),
                entries: run.entries.filter { $0.day <= day }, weighIns: run.weighIns.filter { $0.day <= day },
                dayStatus: run.statuses.filter { $0.day < day }, plan: plan, checkIns: checkIns, today: day,
                now: day.date().addingTimeInterval(20 * 3600))
        }
    }

    @Test("Set at onboarding, they're the day's targets while the assessment learns maintenance as usual")
    func throughTheAssessment() throws {
        let coached = Coached()
        let set = OwnTargets.record(coached.mine, on: coached.start, expenditure: 2_600, plan: nil)
        let early = MacroAnalyst.analyse(coached.state(coached.start.adding(days: 3), checkIns: [set]))
        #expect(early.targets.mode == .own && early.targets.kcal == 2_100)
        #expect(early.assessment?.complete == false)
        #expect(early.own?.since == coached.start)
        #expect(early.planSource == .maintenance, "the assessment sets no calories: the reference is maintenance")
        #expect(early.planNumbers.kcal == (early.maintenance.kcal / 10).rounded() * 10)
        let first = MacroAnalyst.analyse(coached.state(coached.start, checkIns: [set]))
        #expect(first.assessment?.learned.first == "Log what you eat today, to your own targets.")
        // On the formula's guess alone there's no verdict, only what 2,100 aims for from it.
        #expect(early.pace == nil && early.ownAim.map { $0 < 0 } == true)

        let today = coached.start.adding(days: 22)
        let done = MacroAnalyst.analyse(coached.state(today, checkIns: [set]))
        #expect(done.assessment?.complete == true, "21 days, as without them")
        #expect(done.targets.mode == .own && done.dueCheckIn == nil, "no weekly check-in before there's a plan")
        #expect(abs(done.maintenance.kcal - 2_500) <= 250, "\(done.maintenance)")
        #expect(done.assessment?.learned.contains { $0.hasSuffix("a week on your own targets.") } == true, "\(done.assessment?.learned ?? [])")
        #expect(!PhasePlanner.recommend(done.plannerInput).phases.isEmpty)
        #expect(done.actions.contains { $0.kind == .planReady }, "the plan is ready to look at")
        // Eating to them, the trend does what they aim for.
        #expect(done.pace == .onPace, "\(String(describing: done.weeklyChange)) a week against \(String(describing: done.ownAim))")

        // Going back before a plan: the assessment again, its days its own.
        #expect(OwnTargets.back(done, checkIns: [set], today: today) == .remove([set.id]))
        let back = MacroAnalyst.analyse(coached.state(today, checkIns: []))
        #expect(back.targets.mode == .assessment && back.own == nil)
        #expect(OwnTargets.back(back, checkIns: [], today: today) == .nothing)
    }

    @Test("Each weekly check-in keeps them while maintenance and the plan's numbers learn underneath")
    func weeksOfCheckIns() throws {
        let coached = Coached()
        let begun = coached.start.adding(days: 21)
        let plan = PhasePlan(
            phases: [PlannedPhase(kind: .cut, weeks: 12, start: begun)], headline: "", reasons: [], confidence: nil, arc: "",
            created: begun.date())
        // The plan starts from an overestimate of 2,800; the coach's numbers go in the same day.
        let first = CheckIns.start(plan, today: begun, maintenance: 2_800, weightKg: 83, referenceKg: 83)
        let before = MacroAnalyst.analyse(coached.state(begun, plan: plan, checkIns: [first]))
        #expect(before.own == nil && before.planSource == .plan && before.planNumbers == first.own, "the sheet starts from the plan's")
        let set = OwnTargets.record(coached.mine, before, today: begun)
        #expect(set.id == first.id, "today's check-in, replaced")
        #expect(set.plan == first.own && set.expenditure == first.expenditure, "the plan's numbers and maintenance carried under them")

        var checkIns = [set]
        var planned = [first.kcal]
        var expenditures = [set.expenditure]
        for week in 1...8 {
            let day = begun.adding(days: week * 7)
            let a = MacroAnalyst.analyse(coached.state(day, plan: plan, checkIns: checkIns))
            let due = try #require(a.dueCheckIn, "week \(week)")
            #expect(due.isOwn && due.own == coached.mine, "week \(week): \(due)")
            #expect(a.targets.mode == .own && a.targets.kcal == 2_100)
            let carried = try #require(due.plan)
            #expect(abs(carried.kcal - (planned.last ?? 0)) <= 150.01, "week \(week): \(planned) then \(carried.kcal)")
            #expect(a.planNumbers == carried, "Plan says what the plan would set")
            #expect(due.reason.contains("the plan would set \(Int(carried.kcal).formatted())"), "\(due.reason)")
            planned.append(carried.kcal)
            expenditures.append(due.expenditure)
            checkIns.append(due)
        }
        // The overestimate walks down toward the true 2,500 though the targets never moved, and the
        // plan's calories come down with it.
        #expect(abs((expenditures.last ?? 0) - 2_500) < 300 * 0.5, "\(expenditures)")
        #expect((planned.last ?? 0) < first.kcal, "\(planned)")

        let today = begun.adding(days: 8 * 7 + 3)
        let a = MacroAnalyst.analyse(coached.state(today, plan: plan, checkIns: checkIns))
        #expect(a.own?.since == begun)
        #expect(a.phase?.kind == .cut, "the plan's phase carries on")
        // Back to the plan's: its numbers as Plan showed them, from where its steps had got to.
        guard case .save(let back) = OwnTargets.back(a, checkIns: checkIns, today: today) else {
            Issue.record("going back saves the plan's targets")
            return
        }
        #expect(back.own == a.planNumbers && !back.isOwn && back.day == today && back.plan == nil)
        let after = MacroAnalyst.analyse(coached.state(today, plan: plan, checkIns: checkIns + [back]))
        #expect(after.targets.mode == .phase && after.targets.kcal == a.planNumbers.kcal && after.own == nil)
        #expect(after.dayTargets[today.adding(days: -2)]?.mode == .own, "the days before are judged by what was in force")
    }

    @Test("Stadig Lift sees the plan's phase, and days judged by the person's own targets")
    func whatStadigLiftSees() throws {
        let today = Day(year: 2026, month: 3, day: 2)
        let begun = today.adding(days: -28)
        let set = today.adding(days: -14)
        var entries: [FoodEntry] = []
        var statuses: [DayStatus] = []
        for offset in -28 ... -1 {
            let day = today.adding(days: offset)
            // At maintenance until the person's 2,100 kcal, then to them.
            let kcal = day < set ? 2_600.0 : 2_100
            for meal in 0..<4 {
                entries.append(
                    FoodEntry(
                        date: day.date().addingTimeInterval(Double(8 + 4 * meal) * 3600), name: "Meal \(meal)", amountLabel: "1",
                        nutrients: Nutrients(kcal: kcal / 4, protein: 45, carbs: kcal / 16, fat: kcal / 40), source: .search))
            }
            statuses.append(DayStatus(day: day, state: .complete))
        }
        let plan = PhasePlan(
            phases: [PlannedPhase(kind: .maintenance, weeks: 12, start: begun)], headline: "", reasons: [], confidence: nil, arc: "",
            created: begun.date())
        let plans = CheckIn(day: begun, expenditure: 2_600, kcal: 2_600, protein: 150, carbs: 330, fat: 80, status: .updated, reason: "")
        let own = OwnTargets.record(mine, on: set, expenditure: 2_600, plan: plans.own)
        func published(_ checkIns: [CheckIn]) -> NutritionSummary {
            let state = MacroState(
                profile: profile(), settings: MacroSettings(assessmentStart: begun.adding(days: -21)), entries: entries,
                dayStatus: statuses, plan: plan, checkIns: checkIns, today: today, now: today.date().addingTimeInterval(9 * 3600))
            return MacroAnalyst.nutritionSummary(state, MacroAnalyst.analyse(state))
        }
        let summary = published([plans, own])
        func hit(_ offset: Int) -> Bool? { summary.days.first { $0.day == today.adding(days: offset) }?.caloriesHit }
        #expect(hit(-5) == true, "2,100 eaten against their 2,100")
        #expect(hit(-20) == true, "2,600 against the plan's 2,600, before them")
        #expect(summary.phase?.kind == .maintenance, "the phase is still the plan's")
        // Without them, the same days were misses against the plan's 2,600.
        let without = published([plans])
        #expect(without.days.first { $0.day == today.adding(days: -5) }?.caloriesHit == false)
    }

    // MARK: Pace

    @Test("The pace is against what their calories aim for from maintenance; near it, they hold")
    func aim() {
        #expect(abs(OwnTargets.aim(kcal: 2_100, maintenance: 2_600) - -500.0 * 7 / 7_700) < 1e-9)
        #expect(OwnTargets.aim(kcal: 2_550, maintenance: 2_600) == 0, "within 5% is maintenance")
        #expect(OwnTargets.aim(kcal: 2_900, maintenance: 2_600) > 0)
        #expect(PhasePace.verdict(weeklyChange: -0.45, aim: -0.4545, weightKg: 84) == .onPace)
        #expect(PhasePace.verdict(weeklyChange: -0.1, aim: -0.4545, weightKg: 84) == .slower)
        #expect(PhasePace.verdict(weeklyChange: 0.1, aim: 0, weightKg: 84) == .onPace)
    }

    // MARK: Where they're said

    @Test("The Watch and the widgets badge the day as the person's")
    func badge() {
        let own = DailyTargets(mode: .own, kcal: 2_100, protein: 180, carbs: 210, fat: 60, note: Targets.ownNote)
        #expect(WristToday.badge(own, assessment: nil, phase: nil) == "Your targets")
    }

    // MARK: Stored

    @Test("Check-ins saved before own targets read as they were, carrying nothing")
    func olderCheckIns() throws {
        let plans = CheckIn(day: start, expenditure: 2_600, kcal: 2_200, protein: 170, carbs: 230, fat: 70, status: .updated, reason: "Weekly")
        let data = try JSONEncoder().encode(plans)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["plan"] == nil, "nothing new in what the plan's own check-ins save")
        let read = try JSONDecoder().decode(CheckIn.self, from: data)
        #expect(read == plans && read.plan == nil && !read.isOwn)
        // The person's, with the plan's numbers under them, come back whole.
        let own = OwnTargets.record(mine, on: start, expenditure: 2_600, plan: plans.own)
        let back = try JSONDecoder().decode(CheckIn.self, from: JSONEncoder().encode(own))
        #expect(back == own && back.isOwn && back.plan == plans.own)
    }
}
