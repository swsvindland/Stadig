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

    /// Tomorrow is a tap away, and food logged there waits for its day.
    @MainActor
    func testADayAheadTakesFoodThatDoesntCountYet() throws {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-seedPlan", "-seedUpcoming", "-tab", "log"])
        app.element("log.title").waitToAppear()
        // The strip's last day is tomorrow.
        let days = app.descendants(matching: .any).matching(identifier: "log.day")
        days.element(boundBy: days.count - 1).tap()
        XCTAssertFalse(app.element("log.title").label.hasPrefix("Today"))
        app.shot("log-tomorrow")
        // It opens on its first food, whatever hour today was showing.
        XCTAssertTrue(app.element("log.hour.12").waitToAppear().isHittable, "the day's first food's hour is in view")

        XCTAssertTrue(app.scrollTo(app.logEntry(containing: "Chicken salad")).waitToAppear().label.contains("Later"), "marked as later")
        XCTAssertTrue(app.element("log.left").label.contains("left"), app.element("log.left").label)
        if !XCUIApplication.isPad { XCTAssertFalse(app.element("quickLog.weighIn").exists, "nothing to weigh yet") }

        app.scrollTo(app.element("log.add.20")).waitToAppear().tap()
        let search = app.foodSearchField()
        search.tap()
        search.typeText("banana")
        app.element("logger.addFood").waitToAppear().tap()
        app.element("toast.message").waitToAppear()
        app.element("logger.done").waitToAppear().tap()
        XCTAssertTrue(app.scrollTo(app.logEntry(containing: "Bananas")).waitToAppear().exists)
    }

    /// A hold picks a food out, and a tap on an hour's name picks out the rest; the bar swaps in, and
    /// an hour's + becomes where they go.
    @MainActor
    func testHoldingAFoodSelectsItAndAnHourTakesItThere() throws {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-seedPlan", "-tab", "log", "-daysAgo", "1"])
        let entry = app.scrollTo(app.element("log.entry")).waitToAppear()
        entry.press(forDuration: 0.7)

        let bar = app.element("selection.bar").waitToAppear()
        app.shot("selection-one")
        XCTAssertFalse(app.element("amount.panel").exists, "a hold doesn't open the amount")
        XCTAssertTrue(app.element("selection.clear").label.hasPrefix("1 "), app.element("selection.clear").label)

        app.element("log.hourName.8").tap()
        XCTAssertTrue(app.element("selection.clear").label.hasPrefix("3 "), app.element("selection.clear").label)
        app.shot("selection-hour")

        // A later, empty hour's arrow takes them there.
        app.scrollTo(app.element("log.add.20")).waitToAppear().tap()
        app.element("toast.message", labelContaining: "Moved 3 foods").waitToAppear()
        bar.waitToDisappear()
        app.shot("selection-moved")
        app.element("toast.undo").tap()
        app.element("toast.message").waitToDisappear()
    }

    @MainActor
    func testCopyingToChosenDatesKeepsTheSelection() throws {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-seedPlan", "-tab", "log", "-daysAgo", "1"])
        app.scrollTo(app.element("log.hourName.8")).waitToAppear().tap()
        app.element("selection.intent").waitToAppear().tap()
        XCTAssertEqual(app.element("selection.intent").label, "Copy")
        app.element("selection.dates").tap()

        let days = app.descendants(matching: .any).matching(identifier: "toDates.day")
        days.element(boundBy: 0).waitToAppear().tap()
        days.element(boundBy: 1).tap()
        app.shot("to-dates")
        app.element("toDates.done").tap()

        app.element("toast.message", labelContaining: "Copied 3 foods to 2 days").waitToAppear()
        XCTAssertTrue(app.element("selection.bar").exists, "a copy keeps the selection")
        app.element("selection.clear").tap()
        app.element("selection.bar").waitToDisappear()
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
