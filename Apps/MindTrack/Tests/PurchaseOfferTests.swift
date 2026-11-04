import Foundation
import MindEngine
import SystemPurchases
import Testing

@testable import MindTrack

/// When the offer comes up on opening the app. The rules behind it are `SystemPurchases`'s.
@MainActor
struct PurchaseOfferTests {
    @Test func theOfferComesUpOnOpeningOnceTheFreeDaysAreOver() {
        let model = TestApp.onboardedModel()
        model.purchases.simulate(.lapsed)
        model.askForPurchaseIfDue()
        #expect(model.showPaywall)
    }

    @Test func nothingComesUpBeforeThen() {
        let model = TestApp.onboardedModel()
        for state in [Purchases.Simulated.free, .extended, .subscribed, .bought] {
            model.purchases.simulate(state)
            model.askForPurchaseIfDue()
            #expect(!model.showPaywall, "\(state)")
        }
    }

    @Test func itNeverComesUpOverOnboarding() {
        let model = TestApp.model()
        model.purchases.simulate(.lapsed)
        model.askForPurchaseIfDue()
        #expect(!model.showPaywall)
    }

    @Test func itWaitsForASessionToEnd() {
        let model = TestApp.onboardedModel()
        model.startToday()
        #expect(model.sessionOpen)
        model.purchases.simulate(.lapsed)
        model.askForPurchaseIfDue()
        #expect(!model.showPaywall)
    }

    @Test func theFreeDaysRunOnTheModelsClock() {
        let clock = TestClock()
        let model = TestApp.onboardedModel(clock: clock)
        model.purchases.simulate(.undecided)
        model.purchases.startFreeDays()
        #expect(model.purchases.standing == .free(daysLeft: 21))
        clock.now = clock.now.addingTimeInterval(21 * 86_400 + 3_600)
        #expect(model.purchases.offerDue)
    }

    /// A session past the assessment waits at the same gate it always did, and one more day opens it.
    @Test func aSessionAfterTheAssessmentAsksThenOneMoreDayLetsItStart() {
        let clock = TestClock()
        let model = TestApp.onboardedModel(clock: clock)
        clock.now = clock.now.addingTimeInterval(40 * 86_400)
        model.refreshDay()
        model.purchases.simulate(.lapsed)
        model.startToday()
        #expect(model.showPaywall)
        #expect(model.run == nil)

        model.showPaywall = false
        model.purchases.oneMoreDay()
        model.startToday()
        #expect(model.run != nil)
    }
}
