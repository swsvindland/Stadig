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

    /// An amount part typed, dates being picked: open in a screen's own state, where the model only
    /// hears of them. A paywall that can't be put off would take them away.
    @Test func itWaitsForAScreensOwnSheet() {
        let model = TestEnvironment().model()
        model.onboard()
        model.purchases.simulate(.lapsed)
        let sheet = UUID()

        model.noteWork(sheet, open: true, covering: true)
        model.askForPurchaseIfDue()
        #expect(!model.showPaywall)

        model.noteWork(sheet, open: false, covering: false)
        model.askForPurchaseIfDue()
        #expect(model.showPaywall)
    }

    /// A food open beside the log is as much in the way as a sheet, though nothing covers the toast.
    @Test func itWaitsForAPane() {
        let model = TestEnvironment().model()
        model.onboard()
        model.purchases.simulate(.lapsed)
        model.noteWork(UUID(), open: true, covering: false)
        model.askForPurchaseIfDue()
        #expect(!model.showPaywall)
        #expect(!model.toastCovered)
    }
}
