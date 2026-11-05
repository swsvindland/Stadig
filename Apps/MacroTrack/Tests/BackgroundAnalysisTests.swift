import Foundation
import NutritionEngine
import SystemCore
import SystemStore
import Testing

@testable import MacroTrack

/// The analysis off the main thread, as the app runs once it's launched: a write returns at once,
/// the numbers follow, and a newer write always wins.
@MainActor
struct BackgroundAnalysisTests {
    func food(_ name: String, kcal: Double, at date: Date = Date()) -> FoodEntry {
        FoodEntry(
            date: date, name: name, amountLabel: "1 serving", nutrients: Nutrients(kcal: kcal, protein: kcal / 20, carbs: kcal / 8, fat: kcal / 30),
            source: .search)
    }

    func model() -> AppModel {
        let model = TestEnvironment().model()
        model.onboard()
        model.backgroundAnalysis = true
        return model
    }

    @Test func theNumbersFollowAWrite() async {
        let model = model()
        model.log([food("Oats", kcal: 300)])
        #expect(model.allEntries(on: model.today).map(\.name) == ["Oats"], "the log itself is there at once")

        await model.analysisFinished(within: .seconds(30))

        #expect(model.analysis?.todayIntake.kcal == 300)
    }

    @Test func theLastWriteWins() async {
        let model = model()
        for kcal in [100.0, 200, 300, 400] { model.log([food("Food", kcal: kcal)]) }

        await model.analysisFinished(within: .seconds(30))

        #expect(model.analysis?.todayIntake.kcal == 1000)
    }

    @Test func aLogSeesItsOwnSuggestions() async {
        let model = model()
        model.log([food("Oats", kcal: 300)])
        await model.analysisFinished(within: .seconds(30))
        #expect(model.logAgain.map(\.template.name).contains("Oats"))
    }

    @Test func aMealStillSaysItEndedTheFast() async throws {
        let model = model()
        model.setTracksMealTiming(true)
        model.acknowledgeFastingScreen()
        await model.analysisFinished(within: .seconds(30))
        model.startFast(goalHours: 16)
        await model.analysisFinished(within: .seconds(30))
        #expect(model.analysis?.fast != nil)

        model.log([food("Dinner", kcal: 700)])

        #expect(model.toast?.message.contains("ended your") == true, "the toast can't wait for the analysis")
        await model.analysisFinished(within: .seconds(30))
        #expect(model.analysis?.fast == nil)
    }

    @Test func siriSpeaksTheFastItJustStarted() async {
        let model = model()
        let said = await model.startFastInWords(goalHours: 16, within: .seconds(60))
        #expect(said.contains("into your 16 h fast"), "not how things stood before it: \(said)")
    }

    @Test func aDueCheckInAppliesItselfOnce() async throws {
        let environment = TestEnvironment()
        let model = environment.model()
        model.onboard()
        let plan = try #require(model.recommendation)
        model.start(plan)
        model.backgroundAnalysis = true
        // Nothing in force for a week: the next recompute finds one due.
        for checkIn in model.checkIns { environment.store.delete(CheckIn.self, id: checkIn.id) }
        model.reload()

        await model.analysisFinished(within: .seconds(30))

        #expect(model.checkIns.count == 1)
        #expect(model.analysis?.dueCheckIn == nil)
    }

    @Test func waitingGivesUpAtItsLimit() async {
        let model = model()
        let clock = ContinuousClock()
        let waited = await clock.measure { await model.analysisFinished(within: .seconds(5)) }
        #expect(waited < .seconds(4), "with nothing running there's nothing to wait for")
    }

    @Test func anAnalysisInFlightDoesntKeepTheModel() async {
        weak var weakModel: AppModel?
        do {
            let model = model()
            model.log([food("Oats", kcal: 300)])
            weakModel = model
        }
        #expect(await eventually(timeout: .seconds(60)) { weakModel == nil })
    }

    @Test func aSavedFoodIsInPlaceWithoutAReadOfTheLog() {
        let model = TestEnvironment().model()
        model.onboard()
        let day = model.today.adding(days: -1)
        model.log([food("Lunch", kcal: 500, at: day.at(hour: 12, minute: 0))])
        model.log([food("Breakfast", kcal: 300, at: day.at(hour: 8, minute: 0))])
        model.log([food("Dinner", kcal: 700, at: day.at(hour: 19, minute: 0))])
        #expect(model.allEntries(on: day).map(\.name) == ["Breakfast", "Lunch", "Dinner"])
        #expect(model.foodLog.all.map(\.name) == ["Breakfast", "Lunch", "Dinner"])
        // And the same as a fresh read gives.
        let again = TestEnvironment(store: model.store).model()
        #expect(again.foodLog.all.map(\.id) == model.foodLog.all.map(\.id))
    }
}
