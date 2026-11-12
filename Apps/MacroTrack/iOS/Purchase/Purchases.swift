import SystemPurchases

extension PurchaseConfiguration {
    /// Stadig Macro is free and open source: purchases are off, so everything is unlocked and no screen
    /// offers to sell anything. `SystemPurchases` stays linked, with what it would say, should that
    /// ever change.
    static let macro = PurchaseConfiguration(
        appName: "Stadig Macro",
        enabled: false,
        slug: "macro",
        benefits: [
            .init("Your phase plan: cut, bulk or maintain, chosen from your data", symbol: "map"),
            .init("Targets that adapt every week to your real maintenance", symbol: "arrow.triangle.2.circlepath"),
            .init("Logging, photo and description logging, export and backup stay free", symbol: "square.and.arrow.up"),
        ])
}
