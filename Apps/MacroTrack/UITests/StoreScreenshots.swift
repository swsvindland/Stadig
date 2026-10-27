import XCTest

/// The App Store screenshots, not a test of anything: `Scripts/store-screenshots.sh` runs these on
/// its own iPhone and iPad simulators with STORE_SCREENSHOTS naming a folder, and each saves its
/// screen there for `storeassets` to frame. Skipped in every other run.
nonisolated final class StoreScreenshots: XCTestCase {
    /// The sample person with the recommended plan started, so Today has targets.
    static let seed = ["-seedSampleData", "-seedPlan"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["STORE_SCREENSHOTS"] == nil, "Only Scripts/store-screenshots.sh takes the screenshots")
    }

    /// Saves the screen as `phone/<name>.png` or `tablet/<name>.png` (the iPhone and iPad run at
    /// once), once what's on it has stopped moving: scroll indicators fading, a chart's first layout.
    @MainActor
    func save(_ name: String) throws {
        let folder = URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["STORE_SCREENSHOTS"]))
            .appendingPathComponent(XCUIApplication.isPad ? "tablet" : "phone")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Thread.sleep(forTimeInterval: 2)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
    }

    /// Today with a saved meal just logged from Log Again, so the ring and the timeline have a meal.
    @MainActor
    func testToday() throws {
        let app = XCUIApplication.launched(Self.seed)
        app.element("today.calories").waitToAppear()
        let meal = app.buttons.matching(identifier: "today.logMeal").firstMatch
        if meal.waitForExistence(timeout: 5) {
            meal.tap()
            app.element("toast.message").waitToAppear().waitToDisappear()
        }
        try save("today")
    }

    /// The search's results for a common food, over the offline catalogs: the iPhone's logger, and on
    /// the iPad Foods, with the best match's portion and nutrients in the inspector.
    @MainActor
    func testSearch() throws {
        let app = XCUIApplication.launched(Self.seed + (XCUIApplication.isPad ? ["-tab", "foods"] : ["-log", "search"]))
        let search = app.foodSearchField()
        search.tap()
        // A fresh simulator's keyboard opens with a tip about swipe typing over the results.
        let tip = app.buttons["Continue"]
        if tip.waitForExistence(timeout: 2) { tip.tap() }
        search.typeText("greek yogurt")
        if XCUIApplication.isPad {
            app.element("foods.log").waitToAppear()
            // The iPad's on-screen keyboard would cover the table.
            let hide = app.keyboards.buttons["Hide keyboard"]
            if hide.exists { hide.tap() }
        } else {
            app.element("logger.food").waitToAppear()
        }
        try save("search")
    }

    /// The live label scan, from the simulator's stand-in for the camera, partway down the panel
    /// with values read and checked.
    @MainActor
    func testScan() throws {
        _ = XCUIApplication.launched(Self.seed + ["-log", "scan", "-liveScanDemo"])
        Thread.sleep(forTimeInterval: 8)
        try save("scan")
    }

    @MainActor
    func testPlan() throws {
        let app = XCUIApplication.launched(Self.seed + ["-tab", "plan"])
        app.element("plan.currentPhase").waitToAppear()
        try save("plan")
    }

    @MainActor
    func testProgress() throws {
        let app = XCUIApplication.launched(Self.seed + ["-tab", "progress"])
        app.element("progress.trendWeight").waitToAppear()
        try save("progress")
    }

    /// A week of meal prep: the iPhone's week from the Plan tab, and the iPad's Meal Plan destination,
    /// the week beside its groceries.
    @MainActor
    func testMealPrep() throws {
        if XCUIApplication.isPad {
            let app = XCUIApplication.launched(Self.seed + ["-seedMealPlan", "-tab", "mealplan"])
            app.element("mealPlan.week").waitToAppear()
        } else {
            let app = XCUIApplication.launched(Self.seed + ["-seedMealPlan", "-tab", "plan"])
            app.buttons["Week"].waitToAppear().tap()
            // The iPhone's meal plan is pages (Week, Groceries, Prep) under a picker.
            app.element("mealPlan.page").waitToAppear()
        }
        try save("meal-prep")
    }
}
