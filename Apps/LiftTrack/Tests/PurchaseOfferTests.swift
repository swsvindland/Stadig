import Foundation
import SystemCore
import SystemPurchases
import Testing

@testable import LiftTrack

/// When the offer comes up on opening the app. The rules behind it are `SystemPurchases`'s.
@MainActor
struct PurchaseOfferTests {
    @Test func theOfferComesUpOnOpeningOnceTheFreeDaysAreOver() {
        let model = TestApp().onboarded()
        model.purchases.simulate(.lapsed)
        model.askForPurchaseIfDue()
        #expect(model.sheet == .paywall)
    }

    @Test func nothingComesUpBeforeThen() {
        let model = TestApp().onboarded()
        for state in [Purchases.Simulated.free, .extended, .subscribed, .bought] {
            model.purchases.simulate(state)
            model.askForPurchaseIfDue()
            #expect(model.sheet == nil, "\(state)")
        }
    }

    @Test func itNeverComesUpOverOnboarding() {
        let model = TestApp().model()
        model.purchases.simulate(.lapsed)
        model.askForPurchaseIfDue()
        #expect(model.sheet == nil)
    }

    @Test func itWaitsForASessionToEnd() throws {
        let model = TestApp().onboarded()
        model.start(try #require(model.plan()))
        model.purchases.simulate(.lapsed)
        model.askForPurchaseIfDue()
        #expect(model.sheet == nil)
    }

    @Test func itWaitsForASheetThatsOpen() {
        let model = TestApp().onboarded()
        model.sheet = .checkIn
        model.purchases.simulate(.lapsed)
        model.askForPurchaseIfDue()
        #expect(model.sheet == .checkIn)
    }

    @Test func aPlanAfterTheFreeDaysStillAsks() {
        let model = TestApp().onboarded()
        model.purchases.simulate(.lapsed)
        #expect(!model.canPlanNextBlock)
        model.purchases.oneMoreDay()
        #expect(model.canPlanNextBlock)
    }
}
