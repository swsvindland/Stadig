// swift-tools-version: 6.2
import PackageDescription

/// The offline food catalog: USDA SR Legacy bundled here, and Open Food Facts when the app ships
/// it. Read-only SQLite with FTS5, the search ranker, portion units, barcodes and the nutrition
/// label parser. Pure Swift over the system's SQLite.
let package = Package(
    name: "FoodDatabase",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26)],
    products: [.library(name: "FoodDatabase", targets: ["FoodDatabase"])],
    dependencies: [.package(path: "../SystemCore")],
    targets: [
        .target(name: "FoodDatabase", dependencies: ["SystemCore"], resources: [.copy("Resources/usda.db"), .copy("Resources/ATTRIBUTION.md")],
                linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "FoodDatabaseTests", dependencies: ["FoodDatabase"]),
    ],
    swiftLanguageModes: [.v6]
)
