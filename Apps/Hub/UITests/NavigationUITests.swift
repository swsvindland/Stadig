import XCTest

/// A walk through the tabs with a seeded week.
final class NavigationUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-seedSampleData"]
        app.launch()
        XCTAssertTrue(app.staticTexts["today.next"].waitForExistence(timeout: 10))
        app.buttons["Week"].tap()
        XCTAssertTrue(app.buttons["week.day.Mon"].waitForExistence(timeout: 5))
        app.buttons["Rhythm"].tap()
        XCTAssertTrue(app.buttons["schedule.adjust"].waitForExistence(timeout: 5))
        app.buttons["Today"].tap()
        app.buttons["today.plansChanged"].tap()
        XCTAssertTrue(app.buttons["plans.out"].waitForExistence(timeout: 5))
    }
}
