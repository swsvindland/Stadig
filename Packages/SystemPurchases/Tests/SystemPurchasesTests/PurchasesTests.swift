import Foundation
import Synchronization
import SystemCore
import SystemStore
import Testing

@testable import SystemPurchases

/// A clock a test moves by hand.
@MainActor
private final class Clock {
    var now = Date(timeIntervalSince1970: 1_793_000_000)
    func advance(days: Int = 0, hours: Int = 0) {
        now = now.addingTimeInterval(Double(days) * 86_400 + Double(hours) * 3_600)
    }
}

/// What the App Store would say is paid for.
private final class AppStoreStub: Sendable {
    private let ids = Mutex<Set<String>>([])
    func set(_ new: Set<String>) { ids.withLock { $0 = new } }
    var current: Set<String> { ids.withLock { $0 } }
}

@MainActor
@Suite("Purchases")
struct PurchasesTests {
    private let clock = Clock()
    private let appStore = AppStoreStub()
    private let store = RecordStore(name: "PurchasesTests-\(UUID().uuidString)", cloudKitContainer: nil, inMemory: true)
    private static let configuration = PurchaseConfiguration(appName: "Stadig Test", enabled: true, slug: "test", benefits: [])
    private static let oneTime = configuration.productID(.oneTime)
    private static let monthly = configuration.productID(.monthly)

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private func make(enabled: Bool = true, options: LaunchOptions = LaunchOptions(arguments: [])) -> Purchases {
        var configuration = Self.configuration
        configuration.enabled = enabled
        let appStore = appStore
        let clock = clock
        return Purchases(
            configuration, store: store, options: options, now: { clock.now }, calendar: utc,
            entitlements: { appStore.current })
    }

    @Test("Product ids are the app's")
    func productIDs() {
        #expect(Self.oneTime == "dev.svindland.stadig.test.unlock")
        #expect(Self.monthly == "dev.svindland.stadig.test.monthly")
    }

    @Test("Before the App Store answers, nobody meets the paywall")
    func beforeTheAnswer() async {
        let purchases = make()
        #expect(purchases.standing == .checking)
        #expect(purchases.unlocked)
        #expect(!purchases.offerDue)
        #expect(!purchases.firstChoiceDue)
        await purchases.refresh()
        #expect(purchases.firstChoiceDue)
        #expect(!purchases.unlocked)
    }

    @Test("Free days start on the button, and pressing it again doesn't start them over")
    func freeDays() async {
        let purchases = make()
        await purchases.refresh()
        purchases.startFreeDays()
        #expect(purchases.standing == .free(daysLeft: 21))
        #expect(purchases.unlocked)
        clock.advance(days: 5)
        purchases.startFreeDays()
        #expect(purchases.standing == .free(daysLeft: 16))
    }

    @Test("The free days are kept: another launch, or another device on the same store, agrees")
    func kept() async {
        let first = make()
        await first.refresh()
        first.startFreeDays()
        clock.advance(days: 3)
        let second = make()
        await second.refresh()
        #expect(second.standing == .free(daysLeft: 18))
    }

    @Test("Once the free days are up the offer is due, and has to be answered")
    func lapsing() async {
        let purchases = make()
        await purchases.refresh()
        purchases.startFreeDays()
        #expect(!purchases.offerDue)
        #expect(purchases.canPutOff)
        clock.advance(days: 21)
        #expect(purchases.offerDue)
        #expect(!purchases.canPutOff)
    }

    @Test("One more day answers it for a day, and can be asked for again")
    func oneMoreDay() async {
        let purchases = make()
        await purchases.refresh()
        purchases.startFreeDays()
        clock.advance(days: 30)
        for _ in 0..<5 {
            #expect(purchases.offerDue)
            purchases.oneMoreDay()
            #expect(!purchases.offerDue)
            #expect(purchases.unlocked)
            #expect(purchases.canPutOff)
            clock.advance(hours: 23)
            #expect(!purchases.offerDue)
            clock.advance(hours: 1)
        }
    }

    @Test("Three months of someone who opens it twice a day and never pays: asked at most once a day, never locked out")
    func aSimulatedPersonWhoNeverPays() async {
        let purchases = make()
        await purchases.refresh()
        purchases.startFreeDays()
        var asked: [Int] = []
        for day in 0..<90 {
            // Morning and evening.
            for _ in 0..<2 {
                if purchases.offerDue {
                    asked.append(day)
                    purchases.oneMoreDay()
                }
                #expect(purchases.unlocked)
                clock.advance(hours: 12)
            }
        }
        #expect(asked.first == 21)
        #expect(asked.count == 69)
        #expect(Set(asked).count == asked.count)
    }

    @Test("Buying ends the asking; a subscription that ends brings it back")
    func paying() async {
        let purchases = make()
        await purchases.refresh()
        purchases.startFreeDays()
        clock.advance(days: 30)
        #expect(purchases.offerDue)

        appStore.set([Self.monthly])
        await purchases.refresh()
        #expect(purchases.standing == .subscribed)
        #expect(!purchases.offerDue)

        appStore.set([])
        await purchases.refresh()
        #expect(purchases.offerDue)

        appStore.set([Self.oneTime])
        await purchases.refresh()
        #expect(purchases.standing == .bought)
        #expect(!purchases.offerDue)
    }

    @Test("Someone who buys over a subscription is told it's still running")
    func boughtOverASubscription() async {
        let purchases = make()
        appStore.set([Self.monthly])
        await purchases.refresh()
        #expect(!purchases.stillSubscribed)
        appStore.set([Self.monthly, Self.oneTime])
        await purchases.refresh()
        #expect(purchases.standing == .bought)
        #expect(purchases.stillSubscribed)
    }

    @Test("An app with purchases switched off is simply unlocked")
    func switchedOff() async {
        let purchases = make(enabled: false)
        await purchases.refresh()
        #expect(purchases.standing == .bought)
        #expect(!purchases.firstChoiceDue)
    }

    @Test("Tests and UI tests start paid for, unless they ask for a state")
    func quietLaunches() async {
        #expect(make(options: LaunchOptions(arguments: ["-uiTesting"])).standing == .bought)
        #expect(make(options: LaunchOptions(arguments: ["-unlocked"])).standing == .bought)
        #expect(make(options: LaunchOptions(arguments: ["-inMemoryStore", "-seedSampleData"])).standing == .bought)
        #expect(make(options: LaunchOptions(arguments: ["-uiTesting", "-access", "undecided"])).standing == .undecided)
        #expect(make(options: LaunchOptions(arguments: ["-uiTesting", "-access", "lapsed"])).offerDue)
        #expect(make(options: LaunchOptions(arguments: ["-uiTesting", "-access", "free"])).standing == .free(daysLeft: 12))
        #expect(make(options: LaunchOptions(arguments: ["-uiTesting", "-access", "subscribed"])).standing == .subscribed)
    }

    @Test("A simulated purchase goes through, with made-up prices, and never touches StoreKit")
    func simulatedBuying() async {
        let purchases = make(options: LaunchOptions(arguments: ["-uiTesting", "-access", "lapsed"]))
        #expect(purchases.price(.oneTime) == "$29.99")
        #expect(purchases.price(.monthly) == "$2.99")
        await purchases.buy(.monthly) { _ in throw CancellationError() }
        #expect(purchases.standing == .subscribed)
    }
}

@Suite("The StoreKit files")
struct StoreKitFileTests {
    private static let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    @Test(
        "Each app's file sells what its configuration asks for", arguments: [("LiftTrack", "lift"), ("MacroTrack", "macro"), ("MindTrack", "mind")])
    func products(app: String, slug: String) throws {
        let url = Self.repo.appending(path: "Apps/\(app)/\(app).storekit")
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let configuration = PurchaseConfiguration(appName: app, enabled: true, slug: slug, benefits: [])

        let products = try #require(json["products"] as? [[String: Any]])
        #expect(products.count == 1)
        #expect(products.first?["productID"] as? String == configuration.productID(.oneTime))
        #expect(products.first?["type"] as? String == "NonConsumable")

        let groups = try #require(json["subscriptionGroups"] as? [[String: Any]])
        #expect(groups.count == 1)
        let subscriptions = try #require(groups.first?["subscriptions"] as? [[String: Any]])
        #expect(subscriptions.count == 1)
        let monthly = try #require(subscriptions.first)
        #expect(monthly["productID"] as? String == configuration.productID(.monthly))
        #expect(monthly["recurringSubscriptionPeriod"] as? String == "P1M")
        // The free days are the app's: an App Store trial on top would give people two.
        #expect(monthly["introductoryOffer"] is NSNull)
    }
}
