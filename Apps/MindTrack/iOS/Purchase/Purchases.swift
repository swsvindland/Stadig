import SystemPurchases

extension PurchaseConfiguration {
    /// What Stadig Mind sells and says about it. How it's paid for is `SystemPurchases`. The assessment,
    /// every session in it, your history, export and backup always work without paying: your data is
    /// yours. Sessions after the two-week assessment need it.
    static let mind = PurchaseConfiguration(
        appName: "Stadig Mind",
        enabled: true,
        slug: "mind",
        benefits: [
            .init("Sessions that find your level and train it, in every subject", symbol: "brain.head.profile"),
            .init("Spaced repetition that brings things back just before you forget", symbol: "arrow.triangle.2.circlepath"),
            .init("The assessment, your history, export and backup stay free", symbol: "square.and.arrow.up"),
        ])
}
