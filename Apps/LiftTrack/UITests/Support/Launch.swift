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

    /// Opens a tab by its label: the test plan pins English.
    @MainActor
    func openTab(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        tabBars.buttons[name].waitToAppear(file: file, line: line).tap()
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
