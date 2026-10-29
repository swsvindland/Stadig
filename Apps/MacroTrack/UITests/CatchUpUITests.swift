import XCTest

/// Catching up a day that wasn't logged as it happened: Today's "Catch up" opens yesterday with
/// each time this person usually eats, logged in a tap from what they last ate then; a time opens
/// the logger there, its meals ranked for that time and the other usual times a tap away; "Log
/// all" is the rest of the day at once.
nonisolated final class CatchUpUITests: XCTestCase {
    @MainActor
    func testCatchingUpYesterdayFromItsUsualTimes() {
        continueAfterFailure = false
        // The sample eats at 8, 12:30, 3:30, 4:30 and 7, with breakfast and lunch saved as meals.
        let app = XCUIApplication.launched(["-seedSampleData", "-sampleEmptyYesterday"])
        // An iPad's Today has its summary in a column beside the log: scroll that one.
        let summary = app.element("today.calories").waitToAppear()
        app.scrollTo(app.buttons["Catch up"], beside: summary).tap()

        let rows = app.descendants(matching: .any).matching(identifier: "catchUp.log")
        app.scrollTo(rows.firstMatch, beside: summary)
        let usual = rows.count
        XCTAssertEqual(usual, 5)

        // Breakfast as last eaten, in one tap.
        rows.firstMatch.tap()
        app.element("toast.message", labelContaining: "Logged").waitToAppear()
        XCTAssertEqual(rows.count, usual - 1)

        // Lunch's time opens the logger there: lunch comes first, whatever the clock says.
        app.scrollTo(app.element("catchUp.time"), beside: summary).tap()
        XCTAssertTrue(app.element("logger.savedMeal").waitToAppear().label.contains("Chicken and rice"))
        let times = app.descendants(matching: .any).matching(identifier: "logger.usualTime")
        XCTAssertEqual(times.count, usual)
        XCTAssertTrue(times.element(boundBy: 1).isSelected)

        // Another usual time is a tap, and the meals follow it.
        times.element(boundBy: 0).tap()
        XCTAssertTrue(app.element("logger.savedMeal", labelContaining: "Oats and yogurt").waitToAppear().isHittable)
        XCTAssertTrue(app.element("logger.savedMeal").label.contains("Oats and yogurt"))
        times.element(boundBy: 1).tap()
        app.element("logger.logMeal", labelContaining: "Chicken and rice").waitToAppear().tap()
        app.element("toast.message", labelContaining: "Logged Chicken and rice").waitToAppear()
        app.element("logger.done").tap()

        // Back on the day, the rest at once.
        XCTAssertEqual(rows.count, usual - 2)
        app.scrollTo(app.element("catchUp.logAll"), beside: summary).tap()
        app.element("toast.message", labelContaining: "Logged 3 meals").waitToAppear()
        XCTAssertEqual(rows.count, 0)
    }
}
