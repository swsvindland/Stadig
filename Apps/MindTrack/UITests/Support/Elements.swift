import XCTest

extension XCUIApplication {
    /// The element with an accessibility identifier, whatever kind of element it is.
    @MainActor
    func element(_ identifier: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Swipes through a long page, list or form until the element is on screen: down the page
    /// unless the element is already above it.
    @MainActor
    @discardableResult
    func scroll(to element: XCUIElement, maxSwipes: Int = 20, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            // Slowly, so the page has stopped by the time the element is tapped: a tap on a page
            // still gliding stops it instead of reaching the element.
            if element.exists && element.frame.maxY < frame.midY { swipeDown(velocity: .slow) } else { swipeUp(velocity: .slow) }
            swipes += 1
        }
        XCTAssertTrue(element.exists, "\(element) not found after \(swipes) swipes", file: file, line: line)
        return element
    }

    /// Steps a course's amount down until it's off.
    @MainActor
    func turnOff(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let stepper = scroll(to: steppers[identifier], file: file, line: line)
        for _ in 0...8 where !stepper.spoken.contains("Off") { stepper.buttons.element(boundBy: 0).tap() }
    }
}

extension XCUIElement {
    /// What VoiceOver reads: the label, then the value (a LabeledContent row puts its detail there).
    @MainActor
    var spoken: String { [label, value as? String].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ") }

    /// Waits for the element to go, failing the test if it stays.
    @MainActor
    func waitToDisappear(timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: self)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: timeout), .completed, "\(self) is still there", file: file, line: line)
    }
}
