import FoodDatabase
import Foundation
import MealPlanner
import NutritionEngine
import SystemCore
import Testing

@testable import MacroTrack

/// Where there's a sidebar (iPad, the Mac, Vision Pro) finding a food and the supplements are
/// screens of their own rather than sheets; without one, the same asks keep the phone's sheets.
@MainActor
struct SidebarTests {
    @Test func findingAFoodOpensTheFoodsScreenWithItsSearch() throws {
        let model = TestEnvironment().model()
        model.onboard()
        model.usesSidebar = true
        let before = model.foodSearchRequest

        model.openLogger(.search)
        #expect(model.tab == .foods)
        #expect(model.logger == nil)
        #expect(model.foodSearchRequest == before + 1, "the search field takes the cursor")

        // A link from a widget does the same.
        DeepLink.open(try #require(URL(string: "macrotrack://log")), model: model)
        #expect(model.logger == nil && model.tab == .foods)

        // The other ways to log, and a search at a moment's time (+ on a moment), are still the logger.
        model.openLogger(.describe)
        #expect(model.logger == .describe)
        let earlier = Date().addingTimeInterval(-3600)
        model.openLogger(.search, at: earlier)
        #expect(model.logger == .search && model.loggerTime == earlier)
    }

    @Test func withoutTheSidebarSearchIsTheLogger() {
        let model = TestEnvironment().model()
        model.onboard()
        model.openLogger(.search)
        #expect(model.logger == .search)
        #expect(model.tab == .today)
    }

    @Test func theSupplementsAreADestinationWithTheSidebar() {
        let model = TestEnvironment().model()
        model.onboard()
        model.usesSidebar = true
        model.showSupplements = true
        #expect(model.tab == .supplements)
        #expect(!model.showSupplements, "no sheet as well")

        model.usesSidebar = false
        model.showSupplements = true
        #expect(model.showSupplements)
    }

    @Test(arguments: AppTab.allCases)
    func goingToADestination(_ destination: AppTab) {
        let model = TestEnvironment().model()
        model.onboard()
        model.usesSidebar = true
        model.go(to: destination)
        #expect(model.tab == destination)
        #expect(model.logger == nil)
    }

    /// An iPhone with a keyboard: ⌘2 and the rest open the nearest thing the tab bar has.
    @Test func goingToASidebarOnlyDestinationWithoutTheSidebar() {
        let model = TestEnvironment().model()
        model.onboard()
        model.go(to: .foods)
        #expect(model.logger == .search && model.tab == .today)
        model.logger = nil
        model.go(to: .supplements)
        #expect(model.showSupplements && model.tab == .today)
        model.showSupplements = false
        model.go(to: .mealPlan)
        #expect(model.tab == .plan)
        model.go(to: .history)
        #expect(model.tab == .progress)
        model.go(to: .today)
        #expect(model.tab == .today)
        #expect(AppTab.allCases.filter(\.isSidebarOnly) == [.foods, .mealPlan, .supplements, .history])
    }

    @Test func aDroppedPhotoOpensThePhotoLoggerOnce() {
        let model = TestEnvironment().model()
        model.onboard()
        model.selectedDay = model.today.adding(days: -1)
        model.showWeighIn = true
        let photo = Data([0xFF, 0xD8, 0xFF])

        model.logDroppedPhoto(photo)
        #expect(model.logger == .photoLibrary)
        #expect(!model.showWeighIn, "in place of the sheet that was up")
        #expect(model.selectedDay == model.today)
        #expect(model.takeDroppedPhoto() == photo)
        #expect(model.takeDroppedPhoto() == nil, "read once")
    }

    @Test func aDaysEntriesFollowLogsAndDeletes() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let yesterday = model.today.adding(days: -1)
        let banana = try model.entry(foodID: Foods.bananaID, grams: 120)
        let older = try model.entry(foodID: Foods.bananaID, grams: 80, date: yesterday.at(hour: 8, minute: 0))
        let version = model.analysisVersion
        model.log([banana, older])
        #expect(model.entries(on: model.today).map(\.id) == [banana.id])
        #expect(model.entries(on: yesterday).map(\.id) == [older.id])
        #expect(model.analysisVersion > version, "screens built from the analysis hear about it")

        model.delete(entries: [banana.id])
        #expect(model.entries(on: model.today).isEmpty)
        #expect(model.entries(on: yesterday).count == 1)
    }

    @Test func personalFoodsKnowWhenTheyWereLastLogged() async throws {
        let model = TestEnvironment().model()
        model.onboard()
        let banana = try model.entry(foodID: Foods.bananaID, grams: 120)
        model.log([banana])
        for _ in 0..<200 where model.personalFood(Foods.bananaID) == nil { try await Task.sleep(for: .milliseconds(20)) }
        let personal = try #require(model.personalFood(Foods.bananaID))
        // The store keeps whole milliseconds.
        let logged = try #require(personal.lastLogged)
        #expect(abs(logged.timeIntervalSince(banana.date)) < 0.001)
        let recent = FoodBrowser.listings(.recent, query: "", personal: model.personal, custom: [])
        #expect(recent.first?.food.id == Foods.bananaID)
    }

    @Test func aWeeksLoggedMealsAtOnce() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let plan = model.makeMealPlan(preferences: PlanPreferences(), start: model.today.adding(days: -1))
        let meal = try #require(plan.meals(on: model.today).first)
        #expect(model.loggedMeals(in: plan).isEmpty)

        model.logPlanned(meal, in: plan)
        let current = try #require(model.mealPlans.first { $0.id == plan.id })
        #expect(model.loggedMeals(in: current) == [meal.id])
        #expect(model.isLogged(meal, in: current))

        // Undone, it isn't logged any more, either way of asking.
        if let toast = model.toast { model.undo(toast) }
        #expect(model.loggedMeals(in: current).isEmpty)
        #expect(!model.isLogged(meal, in: current))
    }
}
