// swift-tools-version: 6.2
import PackageDescription

/// The week's meals from prep-friendly whole-food building blocks, sized to the person's targets,
/// with the grocery list and a timed Sunday prep. Nutrients come from the catalog; Apple's model
/// only reads requests like "no fish this week".
let package = Package(
    name: "MealPlanner",
    platforms: [.iOS(.v26), .macOS(.v26), .visionOS(.v26)],
    products: [.library(name: "MealPlanner", targets: ["MealPlanner"])],
    dependencies: [.package(path: "../SystemCore"), .package(path: "../NutritionEngine"), .package(path: "../FoodDatabase")],
    targets: [
        .target(name: "MealPlanner", dependencies: ["SystemCore", "NutritionEngine", "FoodDatabase"]),
        .testTarget(name: "MealPlannerTests", dependencies: ["MealPlanner", "NutritionEngine", "FoodDatabase", "SystemCore"]),
    ],
    swiftLanguageModes: [.v6]
)
