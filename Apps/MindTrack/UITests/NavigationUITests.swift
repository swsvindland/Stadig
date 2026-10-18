import XCTest

/// Getting around: the three tabs with eight weeks of study behind them, Settings, and the links the
/// widget and Shortcuts open.
nonisolated final class NavigationUITests: XCTestCase {
    @MainActor
    func testSeededLaunchShowsEachTab() {
        let app = XCUIApplication.launched(["-seedSampleData"])
        app.element("today.settings").waitToAppear()
        XCTAssertTrue(app.navigationBars["Today"].exists)

        app.tabBars.buttons["Plan"].tap()
        app.element("plan.phase").waitToAppear(timeout: 10)
        XCTAssertTrue(app.navigationBars["Plan"].exists)

        app.tabBars.buttons["Progress"].tap()
        app.element("progress.stat.intelligence").waitToAppear(timeout: 10)
        app.scroll(to: app.element("progress.discipline"))

        app.tabBars.buttons["Today"].tap()
        app.element("today.settings").waitToAppear(timeout: 10)
    }

    @MainActor
    func testSettingsOpensAndCloses() {
        let app = XCUIApplication.launched(["-seedSampleData"])
        app.element("today.settings").waitToAppear().tap()
        let done = app.buttons["settings.done"].waitToAppear(timeout: 10)
        XCTAssertTrue(app.navigationBars["Settings"].exists)
        XCTAssertTrue(app.segmentedControls["settings.course.maths"].exists || app.buttons["settings.course.maths"].exists)
        done.tap()
        done.waitToDisappear()
        XCTAssertTrue(app.element("today.settings").isHittable)
    }

    @MainActor
    func testLinksOpenTheirTabs() {
        let app = XCUIApplication.launched(["-seedSampleData"])
        app.element("today.settings").waitToAppear()

        app.open(URL(string: "mindtrack://plan")!)
        app.element("plan.phase").waitToAppear(timeout: 10)
        XCTAssertTrue(app.tabBars.buttons["Plan"].isSelected)

        app.open(URL(string: "mindtrack://progress")!)
        app.element("progress.stat.intelligence").waitToAppear(timeout: 10)
        XCTAssertTrue(app.tabBars.buttons["Progress"].isSelected)

        app.open(URL(string: "mindtrack://today")!)
        app.element("today.settings").waitToAppear(timeout: 10)
        XCTAssertTrue(app.tabBars.buttons["Today"].isSelected)
    }
}
