import XCTest

/// The meal being logged and saved meals: foods added in the logger stay in sight under its search,
/// open to be saved as a meal, and the meal logs again in one tap from the logger's My Meals. A
/// meal logged food by food is saved from its menu on Today. (Today's chip for a meal eaten around
/// now needs an earlier day's meal at this hour: SavedMealAppTests covers it.)
nonisolated final class MealUITests: XCTestCase {
    /// Searches the open logger for a food and adds its first match with +.
    @MainActor
    func add(_ food: String, in app: XCUIApplication) {
        let search = app.foodSearchField()
        search.tap()
        search.typeText(food)
        app.element("logger.addFood").waitToAppear().tap()
        app.element("toast.message", labelContaining: "Logged").waitToAppear()
    }

    /// Names the meal in the alert Save as Meal asks with, and saves it.
    @MainActor
    func name(_ meal: String, in app: XCUIApplication) {
        let alert = app.alerts.firstMatch.waitToAppear()
        alert.textFields.firstMatch.typeText(meal)
        // The alert's button shows twice in the tree (as an action and as a button).
        alert.buttons["Save"].firstMatch.tap()
    }

    @MainActor
    func testFoodsAddedStayInSightAndSaveAsAMealThatLogsInOneTap() {
        continueAfterFailure = false
        // The sample's days end yesterday: today starts empty, with no meal under the search.
        let app = XCUIApplication.launched(["-seedSampleData", "-log", "search"])
        _ = app.foodSearchField()
        XCTAssertFalse(app.element("logger.meal").exists)

        add("banana", in: app)
        let tray = app.element("logger.meal").waitToAppear()
        XCTAssertTrue(tray.label.contains("1 food"), tray.label)
        add("almonds", in: app)
        XCTAssertTrue(app.element("logger.meal", labelContaining: "2 foods").waitToAppear().label.contains("Bananas"), tray.label)

        tray.tap()
        app.element("mealSheet.entry").waitToAppear()
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "mealSheet.entry").count, 2)
        app.element("mealSheet.saveMeal").waitToAppear().tap()
        name("Snack plate", in: app)
        app.element("mealSheet.saved", labelContaining: "Snack plate").waitToAppear()
        app.element("mealSheet.done").tap()
        app.element("logger.meal", labelContaining: "Snack plate").waitToAppear()

        // From My Meals, the whole meal in one tap: both foods again, in the same meal.
        app.element("logger.logMeal", labelContaining: "Snack plate").waitToAppear().tap()
        app.element("toast.message", labelContaining: "Logged Snack plate").waitToAppear()
        let twice = app.element("logger.meal", labelContaining: "Bananas, raw, Nuts, almonds, Bananas, raw").waitToAppear()
        XCTAssertTrue(twice.label.hasPrefix("Snack plate"), twice.label)
    }

    @MainActor
    func testAnHourOnTheLogSavesAsAMeal() throws {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "log", "-log", "search"])
        add("banana", in: app)
        add("almonds", in: app)
        app.element("logger.done").tap()

        // The hour's name, held, offers what's done with a meal.
        let hour = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'log.hourName.'")).firstMatch
        app.scrollTo(hour).waitToAppear().press(forDuration: 0.8)
        app.buttons["today.saveMeal"].waitToAppear().tap()
        name("Banana and almonds", in: app)
        app.element("toast.message", labelContaining: "Saved Banana and almonds · 2 foods").waitToAppear()
        app.element("toast.message").waitToDisappear()

        // Saved, the hour's menu no longer offers to save it.
        hour.press(forDuration: 0.8)
        app.element("log.hourMenu.repeat").waitToAppear()
        XCTAssertFalse(app.buttons["today.saveMeal"].exists)
    }
}
