import Foundation
import SystemPurchases
import Testing

@testable import MacroTrack

/// When the offer comes up on opening the app. The rules behind it are `SystemPurchases`'s.
@MainActor
struct PurchaseOfferTests {
    @Test func theOfferComesUpOnOpeningOnceTheFreeDaysAreOver() {
        let model = TestEnvironment().model()
        model.onboard()
        model.purchases.simulate(.lapsed)
        model.askForPurchaseIfDue()
        #expect(model.showPaywall)
    }

    @Test func nothingComesUpBeforeThen() {
        let model = TestEnvironment().model()
        model.onboard()
        for state in [Purchases.Simulated.free, .extended, .subscribed, .bought] {
            model.purchases.simulate(state)
            model.askForPurchaseIfDue()
            #expect(!model.showPaywall, "\(state)")
        }
    }

    @Test func itNeverComesUpOverOnboarding() {
        let model = TestEnvironment().model()
        model.purchases.simulate(.lapsed)
        model.askForPurchaseIfDue()
        #expect(!model.showPaywall)
    }

    @Test func itWaitsForASheetThatsOpen() {
        let model = TestEnvironment().model()
        model.onboard()
        model.showWeighIn = true
        model.purchases.simulate(.lapsed)
        model.askForPurchaseIfDue()
        #expect(!model.showPaywall)
    }
}
