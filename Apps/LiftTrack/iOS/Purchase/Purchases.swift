import SystemPurchases

extension PurchaseConfiguration {
    /// Stadig Lift is free and open source: nothing is sold, so `SystemPurchases` treats everything as
    /// owned and never shows its offer. The package stays linked until it's removed for good.
    static let lift = PurchaseConfiguration(
        appName: "Stadig Lift",
        enabled: false,
        slug: "lift",
        benefits: [
            .init("Every training block after the assessment, built from your data", symbol: "calendar"),
            .init("Deloads, vacations, crunch, injury and illness modes", symbol: "airplane"),
            .init("Your data is yours: logging, export and backup are always free", symbol: "square.and.arrow.up"),
        ])
}
