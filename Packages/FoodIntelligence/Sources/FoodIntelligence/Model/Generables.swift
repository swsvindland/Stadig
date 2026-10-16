import Foundation
import FoundationModels

// The shapes the model fills in, in the order it writes them: a photo's scene and verdict come
// before any food, so a person, pet or room reads as "no food" instead of the likeliest meal.

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "A food or drink in the meal")
struct FoodOutput {
    @Guide(description: "Restaurant chain or product brand if visible or stated, otherwise empty")
    var brand: String
    @Guide(description: "Common food name, e.g. Pepperoni pizza, Hamburger bun, Beef patty")
    var name: String
    @Guide(description: "How many units", .range(0.1...3000))
    var quantity: Double
    @Guide(description: "e.g. slice, piece, patty, cup, tbsp, serving")
    var unit: String
    @Guide(description: "Estimated total edible weight in grams", .range(1...3000))
    var grams: Double
}

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "The foods in a meal")
struct MealOutput {
    @Guide(.maximumCount(SeenFoods.maxFoods))
    var items: [FoodOutput]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "What a photo shows and the foods in it")
struct MealPhotoOutput {
    @Guide(description: "What the photo really shows in a few words, e.g. a plate of pasta, a person")
    var scene: String
    @Guide(description: "true only if food or drink is clearly visible and recognizable")
    var food: Bool
    @Guide(.maximumCount(SeenFoods.maxFoods))
    var items: [FoodOutput]
}

/// Entry numbers in food order, [2, 1, 3]: a few tokens, where a list of objects took about
/// thirty per food. (The on-device model rejects regex guides.)
@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "The chosen entry's number for each food, in order")
struct PicksOutput {
    @Guide(description: "One entry number per food, in order", .maximumCount(SeenFoods.maxFoods))
    var entries: [Int]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "A packaged food's name")
struct LabelNameOutput {
    @Guide(description: "The product in a few words, e.g. Rolled oats")
    var name: String
    @Guide(description: "The brand or maker if printed, otherwise empty")
    var brand: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "A packaged food's name and the values printed on its label for one serving")
struct LabelOutput {
    @Guide(description: "The product in a few words, e.g. Rolled oats")
    var name: String
    @Guide(description: "The brand or maker if printed, otherwise empty")
    var brand: String
    @Guide(description: "The serving size as printed, e.g. 2/3 cup (55g)")
    var servingSize: String?
    @Guide(description: "The serving's weight in grams, if printed")
    var servingGrams: Double?
    var calories: Double?
    @Guide(description: "Total fat in grams")
    var fat: Double?
    @Guide(description: "Saturated fat in grams")
    var saturatedFat: Double?
    @Guide(description: "Total carbohydrate in grams")
    var carbs: Double?
    @Guide(description: "Dietary fiber in grams")
    var fiber: Double?
    @Guide(description: "Total sugars in grams")
    var sugar: Double?
    @Guide(description: "Protein in grams")
    var protein: Double?
    @Guide(description: "Sodium in milligrams")
    var sodium: Double?
}

@available(iOS 26.0, macOS 26.0, *)
extension FoodOutput {
    var item: MealReply.Item { MealReply.Item(brand: brand, name: name, quantity: quantity, unit: unit, grams: grams) }
}
