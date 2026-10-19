import XCTest

/// The iPad's wide layout: the sidebar's planning destinations and the two-pane session. Skipped on
/// an iPhone, where none of it shows.
nonisolated final class WideLayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        #if os(iOS)
        try MainActor.assumeIsolated {
            try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "The wide layout is the iPad's")
        }
        #else
        throw XCTSkip("These drive the iPad's touch and hardware keyboard")
        #endif
    }

    @MainActor
    func testProgramSelectsASlotIntoTheInspector() {
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "program"])
        app.element("program.screen").waitToAppear(timeout: XCUIApplication.firstScreenTimeout)
        let table = app.element("program.table").waitToAppear()
        // A main lift's row: selecting it shows the slot in the inspector, with swaps.
        let bench = table.cells.containing(.staticText, identifier: "Barbell Bench Press").firstMatch
        bench.waitToAppear().tap()
        app.element("program.inspector").waitToAppear()
        XCTAssertTrue(app.buttons["program.swapOption"].firstMatch.waitForExistence(timeout: 10), "Swap candidates are offered")
    }

    @MainActor
    func testLibraryFiltersAndShowsAnExercise() {
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "library", "-exercise", "barbell-bench-press"])
        app.element("library.screen").waitToAppear(timeout: XCUIApplication.firstScreenTimeout)
        app.element("library.detail").waitToAppear()
        XCTAssertTrue(app.staticTexts["Your history"].waitForExistence(timeout: 10))

        // Set aside, then allowed back, from the detail's toolbar.
        app.buttons["library.setAside"].waitToAppear().tap()
        app.buttons["library.allowBack"].waitToAppear().tap()
        app.buttons["library.setAside"].waitToAppear()
    }

    @MainActor
    func testHistoryIsATable() {
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "history"])
        let table = app.element("history.table").waitToAppear(timeout: XCUIApplication.firstScreenTimeout)
        XCTAssertGreaterThan(table.cells.count, 5, "Every session and activity is a row")
    }

    @MainActor
    func testTheWideSessionLogsFromTheKeyboard() {
        let app = XCUIApplication.launched(["-seedSampleData", "-startSession"])
        app.element("session.outline").waitToAppear(timeout: XCUIApplication.firstScreenTimeout)
        // Through the warm-ups to the first rated set, then rate it with the 2 key: Just right.
        let rate = app.buttons["logger.ratingOrange"]
        for _ in 0..<40 where !rate.exists {
            if app.buttons["rest.skip"].exists {
                app.buttons["rest.skip"].tap()
            } else if app.buttons["logger.done"].exists {
                app.buttons["logger.done"].tap()
            } else {
                _ = rate.waitForExistence(timeout: 2)
            }
        }
        XCTAssertTrue(rate.exists, "Never reached a set to rate")
        app.typeKey("2", modifierFlags: [])
        // Rated: a rest starts, and Space ends it.
        app.buttons["rest.skip"].waitToAppear()
        app.typeKey(" ", modifierFlags: [])
        app.buttons["rest.skip"].waitToDisappear()
    }
}
