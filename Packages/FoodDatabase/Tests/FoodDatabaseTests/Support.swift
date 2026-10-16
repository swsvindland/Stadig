import Foundation
@testable import FoodDatabase

/// The catalogs tests read: USDA from this package, and Open Food Facts where the app installs it
/// (`Apps/MacroTrack/Catalogs/off.db`), or wherever `OFF_DB` says. Tests that need packaged foods
/// are skipped when it isn't there.
enum Catalogs {
    static let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let usdaURL = package.appending(path: "Sources/FoodDatabase/Resources/usda.db")

    static let offURL: URL? = {
        let path = ProcessInfo.processInfo.environment["OFF_DB"]
            ?? package.appending(path: "../../Apps/MacroTrack/Catalogs/off.db").standardizedFileURL.path
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }()

    static var hasOFF: Bool { offURL != nil }

    /// Both catalogs, as the app opens them on a US phone.
    static let both = FoodCatalog(usda: usdaURL, off: offURL, region: "us")
    /// USDA alone, as the app runs without the packaged-food catalog.
    static let usda = FoodCatalog(usda: usdaURL, off: nil, region: "us")
}

extension FoodCatalog {
    /// The first names a search lists.
    func top(_ query: String, _ count: Int = 3, personal: [PersonalFood] = []) -> [String] {
        search(query, personal: personal).prefix(count).map(\.food.name)
    }

    /// "Name [Brand]" for the first results.
    func names(_ query: String, _ count: Int = 5) -> [String] {
        search(query).prefix(count).map { "\($0.food.name) [\($0.food.brand ?? "")]" }
    }
}

/// A JavaScript-style pattern test; "(?i)" makes it ignore case.
func matches(_ pattern: String, _ text: String) -> Bool { Pattern(pattern).test(text) }
