import FoodDatabase
import Foundation
import MealPlanner
import NutritionEngine
import SystemCore
import Testing

@testable import MacroTrack

/// Where there's a sidebar (iPad, the Mac, Vision Pro) the logger is a pane of the Log tab, and the
/// supplements a screen of their own; without one, the same asks keep the phone's sheets.
@MainActor
struct SidebarTests {
    @Test func theLoggerIsAPaneOfTheLogTab() throws {
        let model = TestEnvironment().model()
        model.onboard()
        model.usesSidebar = true
        model.tab = .plan

        model.openLogger(.search)
        #expect(model.tab == .log)
        #expect(model.logger == .search)

        // A link from a widget does the same.
        model.logger = nil
        model.tab = .today
        DeepLink.open(try #require(URL(string: "macrotrack://log")), model: model)
        #expect(model.logger == .search && model.tab == .log)

        // An hour's + aims the open logger there, without a new one.
        let earlier = Date().addingTimeInterval(-3600)
        model.openLogger(.search, at: earlier)
        #expect(model.logger == .search && model.loggerTime == earlier)
    }

    /// The pane is part of the Log tab. Left open behind another tab it would go on logging at its
    /// picked hour, out of sight, and hold the toast where no one can see it or its Undo.
    @Test(arguments: [AppTab.today, .foods, .plan])
    func leavingTheLogClosesItsPane(_ destination: AppTab) {
        let model = TestEnvironment().model()
        model.onboard()
        model.usesSidebar = true
        model.openLogger(.search, at: model.today.at(hour: 19, minute: 0))

        model.tab = destination

        #expect(model.logger == nil)
        #expect(model.loggerTime == nil, "a one-tap log on this tab is for now")

        // Opening one from here goes back to the Log tab, as ever.
        model.openLogger(.search)
        #expect(model.tab == .log)
        #expect(model.logger == .search)
    }

    /// A sheet sits over whichever tab: a link can change the tab under it without closing it.
    @Test func withoutTheSidebarTheLoggerOutlastsATabChange() {
        let model = TestEnvironment().model()
        model.onboard()
        let dinner = model.today.at(hour: 19, minute: 0)
        model.tab = .log
        model.openLogger(.search, at: dinner)

        model.tab = .plan

        #expect(model.logger == .search)
        #expect(model.loggerTime == dinner)
    }

    /// `logger` is the way it opened with, so asking for that again changes nothing there: this is
    /// how a logger that's gone back to its search hears it.
    @Test func askingForAWayAgainIsHeard() {
        let model = TestEnvironment().model()
        model.onboard()
        model.openLogger(.scan)
        let first = model.loggerRequest
        #expect(first.mode == .scan)

        // As a widget's link and the menu ask, in place of any sheet up.
        model.dismissSheets()
        model.openLogger(.scan)

        #expect(model.logger == .scan)
        #expect(model.loggerRequest != first)
        #expect(model.loggerRequest.mode == .scan)
    }

    @Test func aPhotoDroppedOnAPhotoLoggerIsHeard() {
        let model = TestEnvironment().model()
        model.onboard()
        model.usesSidebar = true
        model.openLogger(.photoLibrary)
        let first = model.loggerRequest

        model.logDroppedPhoto(Data([0xFF, 0xD8, 0xFF]))

        #expect(model.loggerRequest != first, "nothing appears for it to read the photo on")
        #expect(model.loggerRequest.mode == .photoLibrary)
    }

    /// With a pane open an hour's + leaves it on whichever way it's on, or a review goes with it.
    @Test func anHourAimsAnOpenPaneWithoutChangingIt() {
        let model = TestEnvironment().model()
        model.onboard()
        model.usesSidebar = true
        model.openLogger(.camera)
        let first = model.loggerRequest
        let dinner = model.today.at(hour: 19, minute: 0)

        model.aimLogger(at: dinner)

        #expect(model.logger == .camera)
        #expect(model.loggerTime == dinner)
        #expect(model.loggerRequest != first, "it still has to show, over a food's amount")
        #expect(model.loggerRequest.mode == nil, "with no way of logging to go to")
    }

    @Test func anHourOpensTheSearchWithNothingOpen() {
        let model = TestEnvironment().model()
        model.onboard()
        model.usesSidebar = true
        let dinner = model.today.at(hour: 19, minute: 0)
        model.aimLogger(at: dinner)
        #expect(model.logger == .search && model.loggerTime == dinner)
        #expect(model.tab == .log)

        // Without a pane there's a sheet, which nothing reaches an hour past.
        let phone = TestEnvironment().model()
        phone.onboard()
        phone.aimLogger(at: dinner)
        #expect(phone.logger == .search && phone.loggerTime == dinner)
    }

    @Test func foodsStaysTheScreenForComparing() {
        let model = TestEnvironment().model()
        model.onboard()
        model.usesSidebar = true
        let before = model.foodSearchRequest
        model.go(to: .foods)
        #expect(model.tab == .foods)
        #expect(model.foodSearchRequest == before + 1, "the search field takes the cursor")
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
