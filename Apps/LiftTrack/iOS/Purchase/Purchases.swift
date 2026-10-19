import Foundation
import Observation
import StoreKit
import SystemCore

/// The one-time unlock. No subscription. The assessment, logging, export and backup always work
/// without it: your data is yours. Generating real training blocks after the assessment needs it.
@MainActor @Observable
final class Purchases {
    /// Off while the app is in testing (it isn't in App Store Connect yet): everything is unlocked,
    /// StoreKit is never asked, and the Unlock rows are hidden. Turn on before release.
    static let enabled = false

    static let productID = "dev.svindland.stadig.lift.unlock"

    private(set) var product: Product?
    private(set) var unlocked = false
    private(set) var purchasing = false
    var error: String?

    @ObservationIgnored private var updates: Task<Void, Never>?

    init() {
        if !Self.enabled { unlocked = true }
        #if DEBUG
        if LaunchOptions.current.has("-unlocked") { unlocked = true }
        #endif
    }

    func start() async {
        // Tests and UI tests never ask StoreKit.
        guard Self.enabled, !LaunchOptions.current.isQuiet else { return }
        if updates == nil {
            updates = Task { [weak self] in
                for await update in Transaction.updates {
                    if case .verified(let transaction) = update {
                        await transaction.finish()
                        await self?.refresh()
                    }
                }
            }
        }
        do {
            product = try await Product.products(for: [Self.productID]).first
        } catch {
            self.error = error.localizedDescription
        }
        await refresh()
    }

    func refresh() async {
        guard Self.enabled else {
            unlocked = true
            return
        }
        var owned = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement, transaction.productID == Self.productID, transaction.revocationDate == nil {
                owned = true
            }
        }
        #if DEBUG
        if LaunchOptions.current.has("-unlocked") { owned = true }
        #endif
        unlocked = owned
    }

    /// Buys the unlock through the view's purchase action (`@Environment(\.purchase)`), which shows the
    /// App Store's sheet over the right window or scene on every platform.
    func buy(using purchase: (Product) async throws -> Product.PurchaseResult) async {
        guard let product else { return }
        purchasing = true
        defer { purchasing = false }
        do {
            let result = try await purchase(product)
            if case .success(let verification) = result, case .verified(let transaction) = verification {
                await transaction.finish()
            }
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            self.error = error.localizedDescription
        }
        await refresh()
    }
}
