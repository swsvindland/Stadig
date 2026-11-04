import SystemPurchases

extension PurchaseConfiguration {
    /// What Stadig Lift sells and says about it. How it's paid for is `SystemPurchases`. The assessment,
    /// logging, export and backup always work without paying: your data is yours. Generating real
    /// training blocks after the assessment needs it.
    static let lift = PurchaseConfiguration(
        appName: "Stadig Lift",
        enabled: true,
        slug: "lift",
        benefits: [
            .init("Every training block after the assessment, built from your data", symbol: "calendar"),
            .init("Deloads, vacations, crunch, injury and illness modes", symbol: "airplane"),
            .init("Your data is yours: logging, export and backup are always free", symbol: "square.and.arrow.up"),
        ])
}
