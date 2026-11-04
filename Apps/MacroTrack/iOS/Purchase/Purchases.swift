import SystemPurchases

extension PurchaseConfiguration {
    /// What Stadig Macro sells and says about it. How it's paid for is `SystemPurchases`. Logging (search,
    /// scan, photo, description), the assessment, export and backup always work without paying: your
    /// data is yours. Starting the plan after the assessment needs it.
    static let macro = PurchaseConfiguration(
        appName: "Stadig Macro",
        enabled: true,
        slug: "macro",
        benefits: [
            .init("Your phase plan: cut, bulk or maintain, chosen from your data", symbol: "map"),
            .init("Targets that adapt every week to your real maintenance", symbol: "arrow.triangle.2.circlepath"),
            .init("Logging, photo and description logging, export and backup stay free", symbol: "square.and.arrow.up"),
        ])
}
