import XCTest

/// Getting around: the three tabs with eight weeks of study behind them, Settings, and the links the
/// widget and Shortcuts open. On an iPad the tabs are reached through the sidebar.
nonisolated final class NavigationUITests: XCTestCase {
    @MainActor
    func testSeededLaunchShowsEachTab() {
        let app = XCUIApplication.launched(["-seedSampleData"])
        app.element("today.settings").waitToAppear()
        XCTAssertTrue(app.navigationBars["Today"].exists)

        app.openTab("Plan")
        app.element("plan.phase").waitToAppear(timeout: 10)
        XCTAssertTrue(app.navigationBars["Plan"].exists)

        app.openTab("Progress")
        app.element("progress.stat.intelligence").waitToAppear(timeout: 10)
        app.scroll(to: app.element("progress.discipline"))

        app.openTab("Today")
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
        XCTAssertTrue(app.tabButton("Plan").isSelected)

        app.open(URL(string: "mindtrack://progress")!)
        app.element("progress.stat.intelligence").waitToAppear(timeout: 10)
        XCTAssertTrue(app.tabButton("Progress").isSelected)

        app.open(URL(string: "mindtrack://today")!)
        app.element("today.settings").waitToAppear(timeout: 10)
        XCTAssertTrue(app.tabButton("Today").isSelected)
    }
}
