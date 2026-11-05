import XCTest

extension XCUIApplication {
    /// Launches the app for a UI test: `-uiTesting` (an in-memory store, no permission prompts, no
    /// animations) plus the DEBUG launch arguments that set up the screen under test.
    @MainActor
    static func launched(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + arguments
        app.launch()
        return app
    }

    /// An iPad, where the wide layout runs: the tab bar along the top, the sidebar and the Library's
    /// destinations.
    @MainActor
    static var isPad: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        false
        #endif
    }

    /// Opens a tab or a sidebar destination by its label (the test plan pins English): from the tab
    /// bar on an iPhone, and on an iPad from the sidebar, which has every destination (the tab bar
    /// along the top shows the Library section's name in place of Shelf, Writing and Courses).
    @MainActor
    func openTab(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        if Self.isPad {
            openInSidebar(name, file: file, line: line)
        } else {
            tabBars.buttons[name].waitToAppear(file: file, line: line).tap()
        }
    }

    /// Opens a destination from an iPad's sidebar: shown with the toggle at the start of the tab bar,
    /// a row tapped, then hidden again if it still covers the screen (in portrait it slides over).
    @MainActor
    func openInSidebar(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        // The toggle is "ToggleSideBar" in the tab bar and "ToggleSidebar" on the sidebar itself.
        let toggle = buttons.matching(NSPredicate(format: "identifier ==[c] 'ToggleSidebar'")).firstMatch
        let row = collectionViews.cells.matching(NSPredicate(format: "label == %@", name)).firstMatch
        if !(row.exists && row.isHittable) { toggle.waitToAppear(file: file, line: line).tap() }
        row.waitToAppear(file: file, line: line).tap()
        if row.exists && row.isHittable && toggle.exists && toggle.label == "Hide Sidebar" { toggle.tap() }
    }
}

extension XCUIElement {
    /// Waits for the element, failing the test with a useful message if it never appears.
    @MainActor
    @discardableResult
    func waitToAppear(timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(waitForExistence(timeout: timeout), "\(self) never appeared", file: file, line: line)
        return self
    }
}
