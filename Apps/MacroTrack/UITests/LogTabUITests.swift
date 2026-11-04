import XCTest

/// The Log tab: a day hour by hour, with the week pinned over it.
nonisolated final class LogTabUITests: XCTestCase {
    @MainActor
    func testAnHoursPlusLogsAtThatHour() throws {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-seedPlan", "-tab", "log", "-daysAgo", "1"])
        app.element("log.list").waitToAppear()
        app.shot("log-yesterday")
        let plus = app.scrollTo(app.element("log.add.20")).waitToAppear()
        plus.tap()

        let search = app.foodSearchField()
        search.tap()
        search.typeText("banana")
        app.element("logger.addFood").waitToAppear().tap()
        app.element("toast.message").waitToAppear()
        app.element("logger.done").waitToAppear().tap()

        // The hour has a total now that it has food.
        let hour = app.scrollTo(app.element("log.hour.20")).waitToAppear()
        XCTAssertTrue(hour.staticTexts.matching(NSPredicate(format: "label CONTAINS 'kcal'")).firstMatch.waitToAppear().exists)
    }

    @MainActor
    func testTheWeekMovesTheDayAndTodayBringsItBack() throws {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-seedPlan", "-tab", "log"])
        let title = app.element("log.title").waitToAppear()
        XCTAssertTrue(title.label.hasPrefix("Today"), title.label)
        app.shot("log-today")

        app.descendants(matching: .any).matching(identifier: "log.day").element(boundBy: 3).tap()
        XCTAssertFalse(app.element("log.title").label.hasPrefix("Today"))
        app.element("log.backToToday").waitToAppear().tap()
        XCTAssertTrue(app.element("log.title").label.hasPrefix("Today"))
    }

    @MainActor
    func testLeavingTheLogGoesBackToToday() throws {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-seedPlan", "-tab", "log", "-daysAgo", "2"])
        XCTAssertFalse(app.element("log.title").waitToAppear().label.hasPrefix("Today"))

        app.openTab("Plan")
        app.openTab("Log")

        XCTAssertTrue(app.element("log.title").waitToAppear().label.hasPrefix("Today"))
    }

    @MainActor
    func testTheBarNamesTheDay() throws {
        try XCTSkipIf(XCUIApplication.isPad, "An iPad has no bar above the tabs")
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "log", "-daysAgo", "1"])
        let bar = app.element("quickLog.search").waitToAppear()
        app.shot("log-bar")
        XCTAssertTrue(bar.exists)
    }

    @MainActor
    func testTheDayIsChosenFromTheTitle() throws {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "log"])
        app.element("log.title").waitToAppear().tap()
        XCTAssertTrue(app.element("log.datePicker").waitToAppear().exists)
        app.shot("log-day-chooser")
    }
}
