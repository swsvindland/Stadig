import XCTest

/// The first run: a schedule, sleep, and into the day.
final class FirstRunUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testSetupReachesToday() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        XCTAssertTrue(app.staticTexts["setup.title"].waitForExistence(timeout: 10))
        app.buttons["schedule.preset.alternateFridays"].tap()
        XCTAssertTrue(app.segmentedControls["schedule.whichWeek"].waitForExistence(timeout: 5))
        let start = app.buttons["setup.start"]
        while !start.isHittable { app.swipeUp() }
        start.tap()
        XCTAssertTrue(app.staticTexts["today.next"].waitForExistence(timeout: 10))
    }
}
