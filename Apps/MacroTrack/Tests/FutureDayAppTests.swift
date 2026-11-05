import Foundation
import NutritionEngine
import SystemCore
import SystemStore
import Testing

@testable import MacroTrack

/// A day to come: food goes on it like any other, and nothing that has to have happened does.
@MainActor
struct FutureDayAppTests {
    func food(_ name: String, kcal: Double, at date: Date) -> FoodEntry {
        FoodEntry(
            date: date, name: name, amountLabel: "1 serving", nutrients: Nutrients(kcal: kcal, protein: kcal / 20, carbs: kcal / 8, fat: kcal / 30),
            source: .search)
    }

    func model() -> (AppModel, Day) {
        let model = TestEnvironment().model()
        model.onboard()
        let tomorrow = model.today.adding(days: 1)
        model.show(day: tomorrow)
        return (model, tomorrow)
    }

    @Test func foodGoesOnADayToComeAndCountsForNothingYet() {
        let (model, tomorrow) = model()
        model.log([food("Pasta", kcal: 700, at: tomorrow.at(hour: 19, minute: 0))])
        #expect(model.allEntries(on: tomorrow).map(\.name) == ["Pasta"])
        #expect(model.entries(on: tomorrow).isEmpty)
        #expect(model.dayIntake(on: tomorrow).later.kcal == 700)
        #expect(model.analysis?.intakeByDay[tomorrow] == nil)
    }

    @Test func aLoggerOnADayToComeLogsToThatDay() {
        let (model, tomorrow) = model()
        #expect(Day(model.logDate()) == tomorrow)
    }

    @Test func aDayToComeCantBeMarked() {
        let (model, tomorrow) = model()
        model.setState(.complete, for: tomorrow)
        #expect(model.state(of: tomorrow) == nil)
    }

    @Test func waterWaitsForItsDay() {
        let (model, _) = model()
        model.addWater(ml: 250)
        #expect(model.water.isEmpty)
        #expect(model.toast == nil)
    }

    @Test func aWeighInWaitsForItsDay() {
        let (model, tomorrow) = model()
        let before = model.weighIns.count
        model.weighIn(kg: 80, date: tomorrow.at(hour: 7, minute: 0))
        #expect(model.weighIns.count == before)
    }

    @Test func dosesWaitForTheirDay() throws {
        let (model, tomorrow) = model()
        let facts = SupplementFacts(
            id: "custom:Multi", name: "Multi", unit: "tablet", ingredients: [SupplementIngredient(name: "Zinc", amount: 11, unit: "mg")],
            source: .custom)
        model.store.save(Supplement(facts: facts))
        model.reload()
        let supplement = try #require(model.supplements.first)

        model.takeExtra(supplement)
        model.take(model.doses(on: tomorrow), on: tomorrow)

        #expect(model.supplementLogs.isEmpty)
    }

    @Test func aDayToComeHasNothingToCatchUp() {
        let (model, tomorrow) = model()
        let week = (2...8).map { model.today.adding(days: -$0) }
        for day in week { model.log([food("Soup", kcal: 400, at: day.at(hour: 13, minute: 0))]) }
        model.selectedDay = tomorrow
        #expect(model.catchUp.isEmpty)
        #expect(model.usualLogTimes() == [tomorrow.at(hour: 13, minute: 0)], "its usual times are all there to pick")
    }

    @Test func todaysUsualTimesStopAtNow() {
        let model = TestEnvironment().model()
        model.onboard()
        let late = Date().addingTimeInterval(3 * 3600)
        let week = (2...8).map { model.today.adding(days: -$0) }
        for day in week { model.log([food("Soup", kcal: 400, at: day.at(sameTimeAs: late))]) }
        #expect(model.usualLogTimes(now: Date()).allSatisfy { $0 <= Date() })
    }

    @Test func aDayToComeOpensOnItsFirstFood() {
        let (model, tomorrow) = model()
        model.log([food("Pasta", kcal: 700, at: tomorrow.at(hour: 19, minute: 30))])
        let groups = DayHours.groups(on: tomorrow, entries: model.allEntries(on: tomorrow))
        #expect(DayHours.opening(groups, now: Date())?.hour == 19)
    }

    @Test func midnightBringsItBackToToday() {
        let (model, tomorrow) = model()
        model.tab = .plan
        #expect(model.selectedDay == model.today)
        #expect(model.selectedDay != tomorrow)
    }
}
