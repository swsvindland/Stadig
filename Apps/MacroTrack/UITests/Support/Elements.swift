import XCTest

extension XCUIApplication {
    /// Any element with this accessibility identifier, whatever kind it is.
    @MainActor
    func element(_ identifier: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Where Today logs: the composer at the foot of Today's thread, on a phone and an iPad alike.
    @MainActor
    var todayLogging: XCUIElement { element("today.composer") }

    /// The food search's field. In portrait an iPad's Foods has no room for it beside the tab bar
    /// along the top, so the toolbar keeps it behind its search button, which opens it.
    @MainActor
    func foodSearchField(file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        // The pane beside the log has a field of its own.
        let pane = element("logger.search")
        if pane.waitForExistence(timeout: 2) { return pane }
        let field = searchFields.firstMatch
        if Self.isPad, !field.waitForExistence(timeout: 5) {
            buttons["Search"].firstMatch.waitToAppear(file: file, line: line).tap()
        }
        return field.waitToAppear(file: file, line: line)
    }

    /// Closes an iPad's number pad, which iPadOS shows in a popover beside a number field a moment
    /// after typing starts: a tap anywhere else only closes the popover, so the tap meant for the
    /// next field or button would do nothing. With no pad (a keyboard docked along the bottom leaves
    /// other taps alone) there's nothing to close. The tap lands on the navigation bar over the field
    /// typed in, the lowest of those above it: under a sheet the bars behind it are higher up, and a
    /// tap on one of them lands outside the sheet. (With the pad up nothing behind it is hittable,
    /// so that can't tell them apart.) It lands at the spot nearest the bar's middle that's clear of
    /// its buttons and the pad: a sheet's bar can have a menu where the title goes, as the logger's
    /// time does.
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
}

extension XCUIElement {
    /// Taps a text field and types into it.
    @MainActor
    func type(_ text: String) {
        tap()
        typeText(text)
    }

    /// Waits for the element to go away, as a sheet does once it's dismissed.
    @MainActor
    func waitToDisappear(timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: self)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: timeout), .completed, "\(self) is still there", file: file, line: line)
    }
}
