import XCTest

/// Getting around: the three tabs with eight weeks of study behind them. On an iPad the tabs are
/// reached through the sidebar.
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
}
