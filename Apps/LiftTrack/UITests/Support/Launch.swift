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

    /// Closes an iPad's number pad, which iPadOS shows in a popover beside a number field a moment
    /// after typing starts: a tap anywhere else only closes the popover, so the tap meant for the
    /// next field or button would do nothing. With no pad (a keyboard docked along the bottom leaves
    /// other taps alone) there's nothing to close. The tap lands on the navigation bar over the field
    /// typed in, the lowest of those above it: under a sheet (Measurements) the bars behind it are
    /// higher up, and a tap on one of them lands outside the sheet. (With the pad up nothing behind
    /// it is hittable, so that can't tell them apart.) It lands at the spot nearest the bar's middle
    /// that's clear of its buttons and the pad, so a sheet's Cancel and Save are never in the way.
    @MainActor
    func closeNumberPad(file: StaticString = #filePath, line: UInt = #line) {
        let pad = popovers.containing(.key, identifier: nil).firstMatch
        guard Self.isPad, pad.waitForExistence(timeout: 3) else { return }
        let field = descendants(matching: .any).matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch.frame
        let bars = navigationBars.allElementsBoundByIndex.map { ($0, $0.frame) }.filter { _, frame in
            frame.minX <= field.midX && field.midX <= frame.maxX && frame.maxY <= field.minY
        }
        guard let (bar, frame) = bars.max(by: { $0.1.maxY < $1.1.maxY }) else {
            return XCTFail("No navigation bar above the field being typed in, to close the number pad", file: file, line: line)
        }
        let taken = bar.buttons.allElementsBoundByIndex.map { $0.frame.insetBy(dx: -8, dy: 0) } + [pad.frame]
        // From the middle out, a twentieth of the bar at a time: 0.5, 0.45, 0.55, … 0.1, 0.9.
        let spots: [CGFloat] =
            [0.5]
            + (1...8).flatMap { (step: Int) -> [CGFloat] in
                let offset = 0.05 * CGFloat(step)
                return [0.5 - offset, 0.5 + offset]
            }
        let clear = spots.first { dx in
            let spot = CGPoint(x: frame.minX + frame.width * dx, y: frame.midY)
            return !taken.contains { $0.contains(spot) }
        }
        guard let clear else { return XCTFail("No spot on \(bar) clear of its buttons and the number pad", file: file, line: line) }
        bar.coordinate(withNormalizedOffset: CGVector(dx: clear, dy: 0.5)).tap()
        pad.waitToDisappear(timeout: 5, file: file, line: line)
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
