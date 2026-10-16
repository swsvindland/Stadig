import Foundation
import Observation
import StoreKit
import SwiftUI

/// The one-time unlock. No subscription. Logging (search, scan, photo, description), the
/// assessment, export and backup always work without it: your data is yours. Starting the plan
/// after the assessment needs it.
@MainActor @Observable
final class Purchases {
    /// Off while the app is in testing (it isn't in App Store Connect yet): everything is unlocked,
    /// StoreKit is never asked, and the Unlock rows are hidden. Turn on before release.
    static let enabled = false

    static let productID = "dev.svindland.macrotrack.unlock"

    private(set) var product: Product?
    private(set) var unlocked = false
    private(set) var purchasing = false
    var error: String?

    @ObservationIgnored private var updates: Task<Void, Never>?

    init() {
        if !Self.enabled { unlocked = true }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-unlocked") { unlocked = true }
        #endif
    }

    func start() async {
        guard Self.enabled else { return }
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
        if ProcessInfo.processInfo.arguments.contains("-unlocked") { owned = true }
        #endif
        unlocked = owned
    }

    func buy() async {
        guard let product else { return }
        purchasing = true
        defer { purchasing = false }
        do {
            let result = try await product.purchase()
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

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "lock.open.fill").font(.system(size: 44)).foregroundStyle(.tint)
                Text("Macro Track, for good").font(.largeTitle.bold())
                VStack(alignment: .leading, spacing: 12) {
                    Label("Your phase plan: cut, bulk or maintain, chosen from your data", systemImage: "map")
                    Label("Targets that adapt every week to your real maintenance", systemImage: "arrow.triangle.2.circlepath")
                    Label("One purchase. No subscription. Ever.", systemImage: "checkmark.seal")
                    Label("Logging, photo and description logging, export and backup stay free", systemImage: "square.and.arrow.up")
                }
                Spacer()
                Button {
                    Task {
                        await purchases.buy()
                        if purchases.unlocked { dismiss() }
                    }
                } label: {
                    Text(purchases.product.map { "Unlock for \($0.displayPrice)" } ?? "Unlock").font(.headline).frame(maxWidth: .infinity)
                }
                .primaryAction()
                .controlSize(.large)
                .disabled(purchases.product == nil || purchases.purchasing)
                Button("Restore purchase") { Task { await purchases.restore() } }.frame(maxWidth: .infinity)
                if let error = purchases.error { Text(error).font(.footnote).foregroundStyle(.secondary) }
                Text("Part of The System bundle on the App Store, with Lift Track and the Knowledge app.").font(.footnote).foregroundStyle(.secondary)
            }
            .padding(24)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } } }
        }
    }
}
