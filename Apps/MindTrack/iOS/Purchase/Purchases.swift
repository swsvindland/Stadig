import Foundation
import Observation
import StoreKit
import SwiftUI
import SystemCore

/// The one-time unlock. No subscription. The assessment, every session in it, your history,
/// export and backup always work without it: your data is yours. Sessions after the
/// two-week assessment need it.
@MainActor @Observable
final class Purchases {
    /// Off while the app is in testing (it isn't in App Store Connect yet): everything is unlocked,
    /// StoreKit is never asked, and the Unlock rows are hidden. Turn on before release.
    static let enabled = false

    static let productID = "dev.svindland.stadig.mind.unlock"
    /// The last entitlement StoreKit confirmed, so a buyer isn't shown the paywall in the moment
    /// before it answers at launch (a session started from a link, say). StoreKit corrects it.
    private static let ownedKey = "purchases.unlocked"

    private(set) var product: Product?
    private(set) var unlocked = false
    private(set) var purchasing = false
    var error: String?

    @ObservationIgnored private var updates: Task<Void, Never>?

    init() {
        // Tests and UI tests start from what they ask for (`-unlocked`), never a run before theirs.
        unlocked = !Self.enabled || (!LaunchOptions.current.isQuiet && UserDefaults.standard.bool(forKey: Self.ownedKey))
        #if DEBUG
        if LaunchOptions.current.has("-unlocked") { unlocked = true }
        #endif
    }

    func start() async {
        guard Self.enabled else { return }
        // Entitlements are on the device: they answer before the product, which needs the network.
        await refresh()
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
        // What StoreKit said, before the DEBUG override: a run with `-unlocked` mustn't leave the
        // next one without it unlocked.
        UserDefaults.standard.set(owned, forKey: Self.ownedKey)
        #if DEBUG
        if LaunchOptions.current.has("-unlocked") { owned = true }
        #endif
        unlocked = owned
    }

    /// Buys the unlock through the view's purchase action (`@Environment(\.purchase)`), which shows
    /// the App Store's sheet over the right window or scene on every platform.
    func buy(with purchase: PurchaseAction) async {
        guard let product else { return }
        purchasing = true
        defer { purchasing = false }
        do {
            switch try await purchase(product) {
            case .success(.verified(let transaction)):
                await transaction.finish()
            case .success(.unverified(_, let failure)):
                self.error = "The App Store couldn't confirm the purchase: \(failure.localizedDescription)"
            case .pending:
                // Ask to Buy: it arrives through `Transaction.updates` once it's approved.
                self.error = "Waiting for approval. Mind Track unlocks as soon as it's given."
            case .userCancelled:
                break
            @unknown default:
                break
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

struct PaywallView: View {
    @Environment(Purchases.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @Environment(\.purchase) private var purchase

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "lock.open.fill").font(.system(size: 44)).foregroundStyle(.tint)
                Text("Mind Track, for good").font(.largeTitle.bold())
                VStack(alignment: .leading, spacing: 12) {
                    Label("Sessions that find your level and train it, in every subject", systemImage: "brain.head.profile")
                    Label("Spaced repetition that brings things back just before you forget", systemImage: "arrow.triangle.2.circlepath")
                    Label("One purchase. No subscription. Ever.", systemImage: "checkmark.seal")
                    Label("The assessment, your history, export and backup stay free", systemImage: "square.and.arrow.up")
                }
                Spacer()
                Button {
                    Task {
                        await purchases.buy(with: purchase)
                        if purchases.unlocked { dismiss() }
                    }
                } label: {
                    Text(purchases.product.map { "Unlock for \($0.displayPrice)" } ?? "Unlock").font(.headline).frame(maxWidth: .infinity)
                }
                .primaryAction()
                .accessibilityIdentifier("paywall.buy")
                .controlSize(.large)
                .disabled(purchases.product == nil || purchases.purchasing)
                Button("Restore purchase") { Task { await purchases.restore() } }.frame(maxWidth: .infinity)
                if let error = purchases.error { Text(error).font(.footnote).foregroundStyle(.secondary) }
                Text("Part of The System bundle on the App Store, with Lift Track and Macro Track.").font(.footnote).foregroundStyle(.secondary)
            }
            .padding(24)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() }.accessibilityIdentifier("paywall.notNow") } }
        }
        #if os(macOS)
        .frame(width: 460, height: 520)
        #endif
        // A purchase confirmed late (StoreKit answering at launch, Ask to Buy approved) closes it.
        .onChange(of: purchases.unlocked) { _, unlocked in if unlocked { dismiss() } }
    }
}
