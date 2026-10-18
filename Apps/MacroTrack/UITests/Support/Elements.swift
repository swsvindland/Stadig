import XCTest

extension XCUIApplication {
    /// Any element with this accessibility identifier, whatever kind it is.
    @MainActor
    func element(_ identifier: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The first element with this identifier whose label contains `text` (case-insensitive).
    @MainActor
    func element(_ identifier: String, labelContaining text: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    /// Scrolls the screen up until the element is on it and can be tapped, or gives up after a few
    /// drags. Each drag holds at its end, so the list stops where it's let go: a tap on a list
    /// that's still gliding only stops it.
    @MainActor
    @discardableResult
    func scrollTo(_ element: XCUIElement, drags: Int = 10) -> XCUIElement {
        var left = drags
        while !(element.exists && element.isHittable), left > 0 {
            let start = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let end = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
            left -= 1
        }
        return element
    }
}

extension XCUIElement {
    /// Taps a text field and types into it.
    @MainActor
    func type(_ text: String) {
        tap()
        typeText(text)
    }

    /// Waits for the label to stop being `old`, as when a number on screen updates.
    @MainActor
    func waitForLabel(toChangeFrom old: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let changed = NSPredicate(format: "label != %@", old)
        let expectation = XCTNSPredicateExpectation(predicate: changed, object: self)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, "\(self) still reads \(old)", file: file, line: line)
    }

    /// Waits for the element to go away, as a sheet does once it's dismissed.
    @MainActor
    func waitToDisappear(timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: self)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: timeout), .completed, "\(self) is still there", file: file, line: line)
    }
}
