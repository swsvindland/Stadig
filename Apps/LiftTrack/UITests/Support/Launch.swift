import XCTest

extension XCUIApplication {
    /// Launches the app for a UI test: `-uiTesting` (an in-memory store, no permission prompts, no
    /// animations) plus the DEBUG launch arguments that set up the screen under test.
    @MainActor
    static func launched(_ arguments: [String] = []) -> XCUIApplication {
        dismissLeftoverSystemAlert()
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + arguments
        app.launch()
        return app
    }

    /// A permission alert left on screen by a launch outside the tests (the app never asks under
    /// `-uiTesting`) would sit over every screen; declined, it's gone.
    @MainActor
    private static func dismissLeftoverSystemAlert() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let decline = springboard.alerts.buttons["Don’t Allow"]
        if decline.exists { decline.tap() }
    }

    /// Opens a tab or a sidebar destination by its label (the test plan pins English): from the tab
    /// bar on an iPhone, and on an iPad from the sidebar, since the tab bar along its top shows a
    /// section's name ("Training", "Records") in place of the tabs in it.
    @MainActor
    func openTab(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        if Self.isPad {
            openInSidebar(name, file: file, line: line)
        } else {
            tabBars.buttons[name].waitToAppear(file: file, line: line).tap()
        }
    }

    /// The tab bar's button for a tab. An iPad's bar along the top has the tabs outside a section
    /// (Today) and each section's name (Training, Records) rather than the tabs in it.
    @MainActor
    func tabButton(_ name: String) -> XCUIElement {
        Self.isPad ? buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch : tabBars.buttons[name]
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

    /// Closes an iPad's number pad, which iPadOS shows in a popover beside a number field: a tap
    /// anywhere else only closes the popover, so the tap meant for the next button would do
    /// nothing. The tap lands on the frontmost navigation bar's middle, where there's nothing else.
    @MainActor
    func closeNumberPad() {
        guard Self.isPad, keyboards.firstMatch.exists else { return }
        navigationBars.allElementsBoundByIndex.last?.tap()
    }

    /// An iPad, where the regular-width layout runs: the tab bar along the top, the sidebar and the
    /// desktop destinations.
    @MainActor
    static var isPad: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        false
        #endif
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

    /// Swipes `container` until the element is on screen: a list only builds the rows it shows.
    /// Slowly, so the list has stopped before the element is tapped, and back down when the row
    /// went past the middle.
    @MainActor
    @discardableResult
    func scrolledTo(in container: XCUIElement, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        for _ in 0..<15 where !(exists && isHittable) {
            if exists && frame.maxY < container.frame.midY { container.swipeDown(velocity: .slow) } else { container.swipeUp(velocity: .slow) }
        }
        XCTAssertTrue(exists && isHittable, "\(self) isn't on screen after scrolling", file: file, line: line)
        return self
    }

    /// Waits for the element to go, failing the test if it's still there.
    @MainActor
    func waitToDisappear(timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: self)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: timeout), .completed, "\(self) never went away", file: file, line: line)
    }
}

extension XCUIApplication {
    /// The first element of any kind with the identifier: toolbar items, menu items and rows come
    /// through as different element types depending on where SwiftUI puts them.
    @MainActor
    func element(_ identifier: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// A seeded launch runs weeks of sessions through the real engines first: the first screen gets
    /// longer than the rest.
    static let firstScreenTimeout: TimeInterval = 40
}
