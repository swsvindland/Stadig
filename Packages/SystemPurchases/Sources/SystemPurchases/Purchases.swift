import Foundation
import OSLog
import Observation
import StoreKit
import SystemCore
import SystemStore

private let log = Logger(subsystem: "dev.svindland.stadig", category: "Purchases")

/// What an app sells and how it says so.
public struct PurchaseConfiguration: Sendable {
    public struct Benefit: Sendable, Hashable {
        public var text: String
        public var symbol: String

        public init(_ text: String, symbol: String) {
            self.text = text
            self.symbol = symbol
        }
    }

    /// What people read: "Stadig Lift".
    public var appName: String
    /// Off while an app isn't in App Store Connect: everything is unlocked, StoreKit is never asked
    /// and nothing offers a purchase. `Scripts/xcode-cloud.sh` refuses a release archive with it off.
    public var enabled: Bool
    /// The app's part of its product ids: "lift".
    public var slug: String
    public var benefits: [Benefit]

    public init(appName: String, enabled: Bool, slug: String, benefits: [Benefit]) {
        self.appName = appName
        self.enabled = enabled
        self.slug = slug
        self.benefits = benefits
    }

    public func productID(_ plan: Plan) -> String {
        switch plan {
        case .oneTime: "dev.svindland.stadig.\(slug).unlock"
        case .monthly: "dev.svindland.stadig.\(slug).monthly"
        }
    }
}

/// The two ways to pay. There's deliberately no App Store free trial on the subscription: App Store
/// Connect's lengths go from two weeks to a month, so it can't offer 21 days, and the free days come
/// before either option anyway.
public enum Plan: CaseIterable, Sendable {
    case oneTime, monthly
}

/// One app's purchases: what the App Store says is paid for, the prices, and the free days and extra
/// days around them. Purchases are never decided here: `owned` is only what StoreKit reports.
@MainActor @Observable
public final class Purchases {
    public let configuration: PurchaseConfiguration
    @ObservationIgnored private let store: RecordStore
    @ObservationIgnored private let options: LaunchOptions
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let readEntitlements: @Sendable () async -> Set<String>

    /// Nil until the App Store has answered.
    private var owned: Ownership?
    private var products: [Plan: Product] = [:]
    public private(set) var purchasing = false
    public private(set) var loadingProducts = false
    /// The App Store couldn't be asked for prices, or doesn't know these products yet.
    public private(set) var pricesUnavailable = false
    public var message: String?

    #if DEBUG
    /// Set by `simulate`: the state came from a test or launch argument, so StoreKit keeps out of it.
    private var simulated = false
    #endif

    @ObservationIgnored private var updates: Task<Void, Never>?

    /// `entitlements` stands in for the App Store in tests.
    public init(
        _ configuration: PurchaseConfiguration, store: RecordStore, options: LaunchOptions = .current, now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current, entitlements: (@Sendable () async -> Set<String>)? = nil
    ) {
        self.configuration = configuration
        self.store = store
        self.options = options
        self.now = now
        self.calendar = calendar
        readEntitlements = entitlements ?? Self.currentEntitlements
        if !configuration.enabled { owned = Ownership(lifetime: true) }
        #if DEBUG
        // A run that keeps nothing (tests, UI tests, `-inMemoryStore`) never reaches StoreKit. It
        // starts paid for, so checking anything else needn't think about money, unless it asks for
        // a state of its own (`-access`).
        if let name = options.value(after: "-access"), let state = Simulated(rawValue: name) {
            simulate(state)
        } else if options.has("-unlocked") || options.usesInMemoryStore {
            simulate(.bought)
        }
        #endif
    }

    isolated deinit {
        updates?.cancel()
    }

    private var record: AccessRecord? { store.all(AccessRecord.self).first }

    /// Where this person stands, as of now. Reads the clock, so it's asked for when it matters
    /// (a tap, the app coming to the front) rather than kept.
    public var standing: Standing {
        Access.standing(owned: owned, record: record, now: now(), calendar: calendar)
    }

    /// May they use what's paid for? The free parts of each app don't ask.
    public var unlocked: Bool { standing.unlocked }

    /// The offer that ends onboarding still needs an answer.
    public var firstChoiceDue: Bool { standing == .undecided }

    /// Opening the app should bring the offer up.
    public var offerDue: Bool { standing == .lapsed }

    /// May the paywall just be closed? When the offer is due it's answered: bought, or one more day.
    public var canPutOff: Bool {
        switch standing {
        case .undecided, .lapsed: false
        default: true
        }
    }

    /// Bought outright with the subscription still renewing: nothing stops it charging but them.
    public var stillSubscribed: Bool { owned?.lifetime == true && owned?.subscribed == true }

    public func price(_ plan: Plan) -> String? {
        #if DEBUG
        if simulated { return plan == .oneTime ? "$29.99" : "$2.99" }
        #endif
        return products[plan]?.displayPrice
    }

    // MARK: The App Store

    public func start() async {
        guard configuration.enabled, !options.isQuiet else { return }
        #if DEBUG
        if simulated { return }
        #endif
        // Entitlements are on the device: they answer before the products, which need the network.
        await refresh()
        if updates == nil {
            updates = Task { [weak self] in
                for await update in Transaction.updates {
                    guard case .verified(let transaction) = update else {
                        log.error("An App Store update didn't verify")
                        continue
                    }
                    await transaction.finish()
                    await self?.refresh()
                }
            }
        }
        await loadProducts()
    }

    /// Asks the App Store what's paid for. On each return to the app too: a subscription that ended
    /// sends no update.
    public func refresh() async {
        guard configuration.enabled else { return }
        #if DEBUG
        if simulated { return }
        #endif
        let ids = await readEntitlements()
        owned = Ownership(lifetime: ids.contains(configuration.productID(.oneTime)), subscribed: ids.contains(configuration.productID(.monthly)))
    }

    private static func currentEntitlements() async -> Set<String> {
        var ids: Set<String> = []
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement, transaction.revocationDate == nil { ids.insert(transaction.productID) }
        }
        return ids
    }

    /// Fetches the prices. The paywall asks again each time it opens, and from its Try Again.
    public func loadProducts() async {
        guard configuration.enabled, products.count < Plan.allCases.count, !loadingProducts else { return }
        #if DEBUG
        if simulated { return }
        #endif
        loadingProducts = true
        defer { loadingProducts = false }
        do {
            let found = try await Product.products(for: Plan.allCases.map(configuration.productID))
            for plan in Plan.allCases {
                if let product = found.first(where: { $0.id == configuration.productID(plan) }) { products[plan] = product }
            }
            pricesUnavailable = products.count < Plan.allCases.count
            if pricesUnavailable { log.error("The App Store has \(found.count) of \(Plan.allCases.count) products") }
        } catch {
            log.error("Couldn't load products: \(String(describing: error), privacy: .public)")
            pricesUnavailable = true
        }
    }

    /// Buys through the view's purchase action (`@Environment(\.purchase)`), which shows the App
    /// Store's sheet over the right window or scene on every platform (Vision Pro has no bare
    /// `purchase()`).
    public func buy(_ plan: Plan, using purchase: (Product) async throws -> Product.PurchaseResult) async {
        #if DEBUG
        if simulated {
            simulate(plan == .oneTime ? .bought : .subscribed)
            return
        }
        #endif
        guard let product = products[plan] else { return }
        purchasing = true
        defer { purchasing = false }
        message = nil
        do {
            switch try await purchase(product) {
            case .success(.verified(let transaction)):
                await transaction.finish()
            case .success(.unverified(_, let failure)):
                message = "The App Store couldn't confirm the purchase: \(failure.localizedDescription)"
            case .pending:
                // Ask to Buy: it arrives through `Transaction.updates` once it's approved.
                message = "Waiting for approval. \(configuration.appName) unlocks as soon as it's given."
            case .userCancelled:
                break
            @unknown default:
                break
            }
            await refresh()
        } catch {
            log.error("Purchase failed: \(String(describing: error), privacy: .public)")
            message = error.localizedDescription
        }
    }

    public func restore() async {
        message = nil
        do {
            try await AppStore.sync()
            await refresh()
            // Silence here reads as a broken button.
            if owned?.lifetime != true, owned?.subscribed != true { message = "No purchase found on this Apple Account." }
        } catch {
            log.error("Restore failed: \(String(describing: error), privacy: .public)")
            message = error.localizedDescription
        }
    }

    // MARK: The free days

    /// "Free for 21 days". Nothing to sign up for: the date is all there is. Never starts them over.
    public func startFreeDays() {
        var updated = record ?? AccessRecord(updatedAt: now())
        guard updated.freeSince == nil else { return }
        updated.freeSince = now()
        updated.updatedAt = now()
        store.save(updated)
    }

    /// "Just one more day": no offer until it's up. It can be asked for every day, for good.
    public func oneMoreDay() {
        var updated = record ?? AccessRecord(updatedAt: now())
        updated.extendedUntil = Access.extended(from: now(), calendar: calendar)
        updated.updatedAt = now()
        store.save(updated)
    }
}

#if DEBUG
extension Purchases {
    /// A state to start in, for tests and `-access <state>` (each app's doc lists them).
    public enum Simulated: String, Sendable {
        case undecided, free, lapsed, extended, subscribed, bought
    }

    /// Puts this model in a state without the App Store: prices are made up, and buying just works.
    public func simulate(_ state: Simulated) {
        simulated = true
        owned = Ownership(lifetime: state == .bought, subscribed: state == .subscribed)
        let time = now()
        func daysAgo(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: time) ?? time }
        switch state {
        case .bought, .subscribed:
            break
        case .undecided:
            store.delete(AccessRecord.self, id: AccessRecord.singletonID)
        case .free:
            store.save(AccessRecord(freeSince: daysAgo(9), updatedAt: time))
        case .lapsed:
            store.save(AccessRecord(freeSince: daysAgo(30), updatedAt: time))
        case .extended:
            store.save(AccessRecord(freeSince: daysAgo(30), extendedUntil: Access.extended(from: time, calendar: calendar), updatedAt: time))
        }
    }
}
#endif
