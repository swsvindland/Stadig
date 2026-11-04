import XCTest

/// The offer: the page that ends onboarding, and the prompt on opening once the free days are over.
/// `-access` says where the person stands; prices are made up and buying just works, so the App
/// Store stays out of it.
nonisolated final class PurchaseUITests: XCTestCase {
    @MainActor
    func testFreeDaysAnswerTheOfferThatEndsOnboarding() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-access", "undecided"])

        XCTAssertTrue(app.buttons["paywall.buy"].waitToAppear().label.contains("$29.99"))
        XCTAssertTrue(app.buttons["paywall.subscribe"].label.contains("$2.99"))
        XCTAssertFalse(app.buttons["paywall.notNow"].exists, "it's answered, not closed")
        app.buttons["paywall.free"].tap()

        app.element("today.calories").waitToAppear()
        XCTAssertFalse(app.buttons["paywall.free"].exists)
    }

    @MainActor
    func testOneMoreDayAnswersThePromptOnOpening() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-access", "lapsed"])

        let oneMoreDay = app.buttons["paywall.oneMoreDay"].waitToAppear()
        XCTAssertFalse(app.buttons["paywall.notNow"].exists, "it's answered, not closed")
        oneMoreDay.tap()

        oneMoreDay.waitToDisappear()
        app.element("today.calories").waitToAppear()
    }

    @MainActor
    func testBuyingAnswersThePromptOnOpening() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-access", "lapsed"])

        let buy = app.buttons["paywall.buy"].waitToAppear()
        buy.tap()

        buy.waitToDisappear()
        app.element("today.calories").waitToAppear()
    }

    @MainActor
    func testNoPromptDuringTheFreeDays() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-access", "free"])

        app.element("today.calories").waitToAppear()
        XCTAssertFalse(app.buttons["paywall.oneMoreDay"].waitForExistence(timeout: 2))
    }
}
