import Foundation
import Observation
import StoreKit
import SwiftUI
import SystemCore

/// The one-time unlock. No subscription. Logging (search, scan, photo, description), the
/// assessment, export and backup always work without it: your data is yours. Starting the plan
/// after the assessment needs it.
@MainActor @Observable
final class Purchases {
    /// Off while the app is in testing (it isn't in App Store Connect yet): everything is unlocked,
    /// StoreKit is never asked, and the Unlock rows are hidden. Turn on before release.
    static let enabled = false

    static let productID = "dev.svindland.stadig.macro.unlock"

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
        // Tests and UI tests never reach StoreKit.
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
    /// App Store's sheet over the right window or scene on every platform (Vision Pro has no bare
    /// `purchase()`).
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

struct PaywallView: View {
    @Environment(Purchases.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @Environment(\.purchase) private var purchase

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "lock.open.fill").font(.system(size: 44)).foregroundStyle(.tint)
                Text("Stadig Macro, for good").font(.largeTitle.bold())
                VStack(alignment: .leading, spacing: 12) {
                    Label("Your phase plan: cut, bulk or maintain, chosen from your data", systemImage: "map")
                    Label("Targets that adapt every week to your real maintenance", systemImage: "arrow.triangle.2.circlepath")
                    Label("One purchase. No subscription. Ever.", systemImage: "checkmark.seal")
                    Label("Logging, photo and description logging, export and backup stay free", systemImage: "square.and.arrow.up")
                }
                Spacer()
                Button {
                    Task {
                        await purchases.buy { try await purchase($0) }
                        if purchases.unlocked { dismiss() }
                    }
                } label: {
                    Text(purchases.product.map { "Unlock for \($0.displayPrice)" } ?? "Unlock").font(.headline).frame(maxWidth: .infinity)
                }
                .primaryAction()
                .controlSize(.large)
                .disabled(purchases.product == nil || purchases.purchasing)
                .accessibilityIdentifier("paywall.unlock")
                Button("Restore purchase") { Task { await purchases.restore() } }.frame(maxWidth: .infinity)
                    .accessibilityIdentifier("paywall.restore")
                if let error = purchases.error { Text(error).font(.footnote).foregroundStyle(.secondary) }
                Text("Part of the Stadig bundle on the App Store, with \(AppID.liftTrack.displayName) and \(AppID.knowledge.displayName).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() }.accessibilityIdentifier("paywall.notNow") }
            }
        }
    }
}
