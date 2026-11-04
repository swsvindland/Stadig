import XCTest

/// The iPad's regular-width layout: the sidebar's destinations, tables and inspectors. The iPhone
/// keeps its tab bar (AppUITests), so these skip there.
nonisolated final class RegularWidthUITests: XCTestCase {
    @MainActor
    override func setUp() async throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "the regular-width layout is the iPad's")
    }

    @MainActor
    func testFoodsFindsAndLogsAFood() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "foods"])

        app.element("foods.table").waitToAppear()
        let search = app.foodSearchField()
        search.tap()
        search.typeText("banana raw")
        // The best match is selected, with its portion and nutrients beside the table.
        let log = app.element("foods.log").waitToAppear()
        XCTAssertTrue(log.label.contains("kcal"), log.label)
        log.tap()

        let toast = app.element("toast.message").waitToAppear()
        XCTAssertTrue(toast.label.contains("Logged"), toast.label)
    }

    @MainActor
    func testFoodsListsSavedMealsAndLogsOneFromItsInspector() {
        continueAfterFailure = false
        // The sample saves its breakfast and lunch as meals.
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "foods"])

        app.element("foods.scope").waitToAppear().buttons["Meals"].tap()
        app.element("foods.meal", labelContaining: "Chicken and rice").waitToAppear().tap()
        let log = app.element("savedMeal.log").waitToAppear()
        XCTAssertTrue(log.label.contains("3 foods"), log.label)
        // One food left out for this time.
        app.element("savedMeal.include").tap()
        XCTAssertTrue(app.element("savedMeal.log", labelContaining: "2 of 3").waitToAppear().exists)
        log.tap()

        app.element("toast.message", labelContaining: "Logged Chicken and rice, 2 of 3").waitToAppear()
    }

    @MainActor
    func testTheLogHasColumnsAndEditsAnEntry() {
        continueAfterFailure = false
        // Yesterday has the sample's meals in it.
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "log", "-daysAgo", "1"])

        app.element("log.list").waitToAppear()
        XCTAssertTrue(app.element("toolbar.logFood").waitToAppear().exists, "every way to log is in the toolbar")
        app.shot("log-wide")

        app.scrollTo(app.element("log.entry")).waitToAppear().tap()
        app.element("entryEditor.save").waitToAppear()
        app.element("entryEditor.cancel").tap()
        app.element("entryEditor.save").waitToDisappear()
    }

    @MainActor
    func testHistoryShowsEveryDayAndTheSelectedDaysLog() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "history"])

        let table = app.element("history.table").waitToAppear()
        XCTAssertGreaterThan(table.cells.count, 20, "three and a half weeks of days")
        // Show in Log ends the day's log, at the foot of the pane: up from the screen's edge.
        let day = app.element("history.day").waitToAppear()
        day.swipeUp(velocity: .slow)
        app.element("history.showInLog").waitToAppear().tap()
        app.element("log.list").waitToAppear()
    }

    @MainActor
    func testTheMealPlanShowsTheWeekGroceriesAndPrepTogether() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-seedMealPlan", "-tab", "mealplan"])

        app.element("mealPlan.week").waitToAppear()
        XCTAssertTrue(app.element("mealPlan.groceries").exists, "the grocery list is beside the week, not behind a picker")
        XCTAssertFalse(app.element("mealPlan.page").exists)
    }
}
