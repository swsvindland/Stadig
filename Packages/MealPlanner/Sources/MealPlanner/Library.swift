import Foundation
import SystemCore

/// When a planned meal is eaten. Logging has no slots (a day is a timeline), but a plan needs
/// to know which container is lunch.
public enum MealSlot: String, Codable, Sendable, CaseIterable, Comparable, Identifiable {
    case breakfast, lunch, snack, dinner

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .snack: "Snack"
        case .dinner: "Dinner"
        }
    }

    /// The share of the day's targets it carries, planned or not.
    public var share: Double {
        switch self {
        case .breakfast: 0.25
        case .lunch, .dinner: 0.3
        case .snack: 0.15
        }
    }

    /// Hours after midnight it's usually eaten.
    public var hour: Double {
        switch self {
        case .breakfast: 8
        case .lunch: 12.5
        case .snack: 15.5
        case .dinner: 18.5
        }
    }

    public static func < (a: MealSlot, b: MealSlot) -> Bool { a.hour < b.hour }
}

/// Where in the shop.
public enum Aisle: String, Codable, Sendable, CaseIterable, Identifiable {
    case produce, meatAndFish, dairyAndEggs, pantry, frozen

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .produce: "Produce"
        case .meatAndFish: "Meat and fish"
        case .dairyAndEggs: "Dairy and eggs"
        case .pantry: "Pantry"
        case .frozen: "Frozen"
        }
    }
}

/// What a food is, for diets and for "no fish this week".
public struct FoodTags: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let meat = FoodTags(rawValue: 1 << 0)
    public static let poultry = FoodTags(rawValue: 1 << 1)
    public static let pork = FoodTags(rawValue: 1 << 2)
    public static let fish = FoodTags(rawValue: 1 << 3)
    public static let shellfish = FoodTags(rawValue: 1 << 4)
    public static let dairy = FoodTags(rawValue: 1 << 5)
    public static let eggs = FoodTags(rawValue: 1 << 6)
    public static let gluten = FoodTags(rawValue: 1 << 7)
    public static let nuts = FoodTags(rawValue: 1 << 8)
    public static let peanuts = FoodTags(rawValue: 1 << 9)
    public static let soy = FoodTags(rawValue: 1 << 10)

    /// Words people use for each, in requests and settings.
    public static let named: [(word: String, tags: FoodTags)] = [
        ("meat", [.meat, .poultry, .pork]), ("red meat", [.meat, .pork]), ("beef", .meat), ("poultry", .poultry), ("pork", .pork),
        ("fish", .fish), ("seafood", [.fish, .shellfish]), ("shellfish", .shellfish), ("dairy", .dairy), ("lactose", .dairy),
        ("milk", .dairy), ("cheese", .dairy), ("egg", .eggs), ("eggs", .eggs), ("gluten", .gluten), ("wheat", .gluten),
        ("nuts", .nuts), ("tree nuts", .nuts), ("peanut", .peanuts), ("peanuts", .peanuts), ("soy", .soy),
    ]
}

/// How a building block is batch-cooked on prep day.
public enum Cooking: Hashable, Sendable {
    /// On a tray in a hot oven.
    case roast(minutes: Int)
    /// Covered on the stove until the water's absorbed: `water` grams per gram dry.
    case simmer(minutes: Int, water: Double)
    /// In plenty of boiling water, then drained.
    case boil(minutes: Int)
    /// Browned in a large pan.
    case pan(minutes: Int)
    /// In a muffin tin at a lower heat.
    case bake(minutes: Int)
    /// Nothing to cook: opened, rinsed, sliced or spooned.
    case none
}

/// A purchase unit for the grocery list: "can" of 240 g drained, "head" of 350 g.
public struct BuyUnit: Hashable, Sendable {
    public var name: String
    public var plural: String
    /// Grams bought per unit, in the form the list counts (raw, dry or drained).
    public var grams: Double
    /// The size on the shelf, for packaged units: "500 g", "1 L".
    public var size: String?

    public init(_ name: String, _ plural: String? = nil, grams: Double, size: String? = nil) {
        self.name = name
        self.plural = plural ?? name + "s"
        self.grams = grams
        self.size = size
    }
}

/// A prep-friendly whole food, tied to the catalog food whose numbers it uses: the form it's
/// eaten in (roast chicken, cooked rice).
public struct Ingredient: Hashable, Sendable, Identifiable {
    public enum Role: String, Sendable { case protein, carb, vegetable, fat, fruit, dairy, extra }

    public var id: String
    public var name: String
    /// A short word for dish names: "chicken", "rice".
    public var short: String
    public var foodID: String
    public var role: Role
    public var tags: FoodTags
    public var aisle: Aisle
    /// Grams eaten per gram bought: 0.73 for roast chicken breast (raw to cooked), 3 for rice
    /// (dry to cooked).
    public var yield: Double
    public var unit: BuyUnit?
    public var cooking: Cooking
    /// Grams per serving, as eaten.
    public var range: ClosedRange<Double>
    public var typical: Double
    /// 1 cheap (rice, lentils, eggs) to 3 dear (salmon, shrimp).
    public var cost: Int
    /// How often people eat it, 0–1: the everyday choices come first.
    public var everyday: Double
    /// Bought as a kitchen staple (oil, honey, soy sauce): "check you have" on the list.
    public var pantry: Bool
    /// Measured in millilitres (milk, kefir): a gram is about a millilitre.
    public var liquid: Bool

    init(_ id: String, _ name: String, short: String? = nil, food: Int, _ role: Role, tags: FoodTags = [], aisle: Aisle,
         yield: Double = 1, unit: BuyUnit? = nil, cooking: Cooking = .none, range: ClosedRange<Double>, typical: Double,
         cost: Int = 1, everyday: Double = 0.5, pantry: Bool = false, liquid: Bool = false) {
        self.id = id
        self.name = name
        self.short = short ?? name.lowercased()
        foodID = "usda:\(food)"
        self.role = role
        self.tags = tags
        self.aisle = aisle
        self.yield = yield
        self.unit = unit
        self.cooking = cooking
        self.range = range
        self.typical = typical
        self.cost = cost
        self.everyday = everyday
        self.pantry = pantry
        self.liquid = liquid
    }
}

/// A flavour that turns protein, carb and a vegetable into a dish: its sauce, its spices, and
/// what it goes with.
public struct Profile: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// How the dish is seasoned, for the prep steps: "soy sauce, honey, ginger and garlic".
    public var seasoning: String
    /// Dried spices and fresh aromatics from the pantry.
    public var spices: [String]
    /// In every container, grams per serving.
    public var sauce: [(id: String, grams: Double)]
    /// Added when eating, kept apart (kimchi, a spoon of yogurt): grams per serving.
    public var topping: (id: String, grams: Double)?
    /// How the sauce comes together on prep day; nil when the seasoning goes on before roasting.
    public var sauceStep: String?
    public var proteins: Set<String>
    public var carbs: Set<String>
    public var vegetables: Set<String>
    /// Words a request might use for it: "asian", "spicy".
    public var words: Set<String>

    public static func == (a: Profile, b: Profile) -> Bool { a.id == b.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A breakfast or snack: fixed parts and parts sized to the targets.
public struct Template: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var slot: MealSlot
    /// The parts; a part whose range starts at zero can be left out for a diet.
    public var parts: [(id: String, grams: ClosedRange<Double>, typical: Double)]
    /// Fridge days once made; 0 for something put together on the day.
    public var keeps: Int
    public var freezes: Bool
    /// How it's made ahead, in a line, with the per-serving amounts filled in later.
    public var make: String
    public var cooking: Cooking

    public static func == (a: Template, b: Template) -> Bool { a.id == b.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Everything plans are built from. USDA's foods, so the numbers never change under a plan.
public enum Library {
    public static let ingredients: [Ingredient] = [
        // Proteins, as eaten.
        Ingredient("chicken-breast", "Chicken breast", short: "chicken", food: 171477, .protein, tags: .poultry, aisle: .meatAndFish,
                   yield: 0.73, cooking: .roast(minutes: 22), range: 90...320, typical: 160, cost: 2, everyday: 1),
        Ingredient("chicken-thigh", "Chicken thighs", short: "chicken thigh", food: 172388, .protein, tags: .poultry, aisle: .meatAndFish,
                   yield: 0.7, cooking: .roast(minutes: 28), range: 90...300, typical: 150, cost: 1, everyday: 0.8),
        Ingredient("turkey", "Lean ground turkey", short: "turkey", food: 172851, .protein, tags: .poultry, aisle: .meatAndFish,
                   yield: 0.75, cooking: .pan(minutes: 10), range: 90...300, typical: 150, cost: 2, everyday: 0.7),
        Ingredient("beef", "Lean ground beef", short: "beef", food: 174755, .protein, tags: .meat, aisle: .meatAndFish,
                   yield: 0.75, cooking: .pan(minutes: 10), range: 90...280, typical: 140, cost: 2, everyday: 0.75),
        Ingredient("pork", "Pork tenderloin", short: "pork", food: 168250, .protein, tags: .pork, aisle: .meatAndFish,
                   yield: 0.73, cooking: .roast(minutes: 25), range: 90...300, typical: 150, cost: 2, everyday: 0.5),
        Ingredient("salmon", "Salmon fillets", short: "salmon", food: 175168, .protein, tags: .fish, aisle: .meatAndFish,
                   yield: 0.8, cooking: .roast(minutes: 14), range: 90...250, typical: 140, cost: 3, everyday: 0.7),
        Ingredient("cod", "Cod fillets", short: "cod", food: 171956, .protein, tags: .fish, aisle: .meatAndFish,
                   yield: 0.8, cooking: .roast(minutes: 12), range: 100...320, typical: 170, cost: 3, everyday: 0.45),
        Ingredient("shrimp", "Peeled shrimp", short: "shrimp", food: 175180, .protein, tags: .shellfish, aisle: .frozen,
                   yield: 0.85, cooking: .pan(minutes: 4), range: 90...300, typical: 150, cost: 3, everyday: 0.5),
        Ingredient("tofu", "Firm tofu", short: "tofu", food: 172448, .protein, tags: .soy, aisle: .dairyAndEggs,
                   yield: 0.85, unit: BuyUnit("block", grams: 400, size: "400 g"), cooking: .roast(minutes: 25), range: 120...400, typical: 200,
                   cost: 1, everyday: 0.45),
        Ingredient("lentils", "Green or brown lentils", short: "lentils", food: 172421, .protein, aisle: .pantry,
                   yield: 2.8, cooking: .simmer(minutes: 25, water: 3), range: 100...350, typical: 180, cost: 1, everyday: 0.45),
        Ingredient("chickpeas", "Chickpeas", short: "chickpeas", food: 173757, .protein, aisle: .pantry,
                   unit: BuyUnit("can", grams: 240), cooking: .roast(minutes: 20), range: 100...320, typical: 160, cost: 1, everyday: 0.45),
        Ingredient("black-beans", "Black beans", short: "black beans", food: 173735, .carb, aisle: .pantry,
                   unit: BuyUnit("can", grams: 240), range: 0...250, typical: 120, cost: 1, everyday: 0.5),

        // Carbs, cooked.
        Ingredient("rice-white", "White rice", short: "rice", food: 168878, .carb, aisle: .pantry,
                   yield: 2.8, cooking: .simmer(minutes: 18, water: 1.9), range: 0...420, typical: 180, cost: 1, everyday: 1),
        Ingredient("rice-brown", "Brown rice", short: "brown rice", food: 169704, .carb, aisle: .pantry,
                   yield: 3, cooking: .simmer(minutes: 40, water: 2.8), range: 0...420, typical: 180, cost: 1, everyday: 0.65),
        Ingredient("quinoa", "Quinoa", short: "quinoa", food: 168917, .carb, aisle: .pantry,
                   yield: 3, cooking: .simmer(minutes: 15, water: 2.8), range: 0...400, typical: 170, cost: 2, everyday: 0.5),
        Ingredient("pasta", "Whole-wheat pasta", short: "pasta", food: 168910, .carb, tags: .gluten, aisle: .pantry,
                   yield: 2.4, cooking: .boil(minutes: 10), range: 0...380, typical: 170, cost: 1, everyday: 0.75),
        Ingredient("potato", "Potatoes", short: "potatoes", food: 170093, .carb, aisle: .produce,
                   yield: 0.83, unit: BuyUnit("potato", "potatoes", grams: 210), cooking: .roast(minutes: 35), range: 0...500,
                   typical: 220, cost: 1, everyday: 0.8),
        Ingredient("sweet-potato", "Sweet potatoes", short: "sweet potato", food: 168483, .carb, aisle: .produce,
                   yield: 0.95, unit: BuyUnit("sweet potato", "sweet potatoes", grams: 200), cooking: .roast(minutes: 30),
                   range: 0...500, typical: 220, cost: 1, everyday: 0.65),

        // Vegetables, cooked.
        Ingredient("broccoli", "Broccoli", food: 169967, .vegetable, aisle: .produce, yield: 0.9,
                   unit: BuyUnit("head", grams: 350), cooking: .roast(minutes: 18), range: 100...250, typical: 150, everyday: 1),
        Ingredient("green-beans", "Green beans", food: 169141, .vegetable, aisle: .produce, yield: 0.95,
                   cooking: .roast(minutes: 15), range: 100...250, typical: 150, everyday: 0.8),
        Ingredient("carrots", "Carrots", food: 170394, .vegetable, aisle: .produce, yield: 0.9,
                   unit: BuyUnit("carrot", grams: 70), cooking: .roast(minutes: 25), range: 100...250, typical: 140, everyday: 0.7),
        Ingredient("peppers", "Bell peppers", short: "peppers", food: 170110, .vegetable, aisle: .produce, yield: 0.85,
                   unit: BuyUnit("pepper", grams: 160), cooking: .roast(minutes: 20), range: 100...250, typical: 150, everyday: 0.8),
        Ingredient("zucchini", "Zucchini", food: 169292, .vegetable, aisle: .produce, yield: 0.85,
                   unit: BuyUnit("zucchini", "zucchini", grams: 200), cooking: .roast(minutes: 18), range: 100...250, typical: 150,
                   everyday: 0.65),
        Ingredient("cauliflower", "Cauliflower", food: 170397, .vegetable, aisle: .produce, yield: 0.9,
                   unit: BuyUnit("head", grams: 600), cooking: .roast(minutes: 22), range: 100...250, typical: 160, everyday: 0.6),
        Ingredient("brussels", "Brussels sprouts", food: 169971, .vegetable, aisle: .produce, yield: 0.9,
                   cooking: .roast(minutes: 25), range: 100...250, typical: 140, everyday: 0.5),
        Ingredient("spinach", "Baby spinach", short: "spinach", food: 168462, .vegetable, aisle: .produce,
                   unit: BuyUnit("bag", grams: 150, size: "150 g"), range: 30...150, typical: 60, everyday: 0.6),
        Ingredient("onion", "Onions", short: "onion", food: 170000, .vegetable, aisle: .produce,
                   unit: BuyUnit("onion", grams: 150), range: 0...80, typical: 30, everyday: 0.8),
        Ingredient("tomatoes", "Tomatoes", food: 170457, .vegetable, aisle: .produce,
                   unit: BuyUnit("tomato", grams: 120), range: 0...150, typical: 60, everyday: 0.8),

        // Fats, sauces and toppings.
        Ingredient("olive-oil", "Olive oil", food: 171413, .fat, aisle: .pantry, range: 0...20, typical: 8, pantry: true),
        Ingredient("soy-sauce", "Soy sauce", food: 174278, .extra, tags: [.soy, .gluten], aisle: .pantry, range: 0...20, typical: 12,
                   pantry: true),
        Ingredient("honey", "Honey", food: 169640, .extra, aisle: .pantry, range: 0...20, typical: 8, pantry: true),
        Ingredient("sesame", "Sesame seeds", food: 170150, .extra, aisle: .pantry, range: 0...10, typical: 3, pantry: true),
        Ingredient("peanut-butter", "Peanut butter", food: 172470, .fat, tags: .peanuts, aisle: .pantry, range: 0...30, typical: 15,
                   pantry: true),
        Ingredient("canned-tomatoes", "Canned tomatoes", food: 170051, .vegetable, aisle: .pantry,
                   unit: BuyUnit("can", grams: 400, size: "400 g"), range: 0...150, typical: 90),
        Ingredient("lime", "Limes", short: "lime", food: 168155, .extra, aisle: .produce, unit: BuyUnit("lime", grams: 45),
                   range: 0...20, typical: 8),
        Ingredient("lemon", "Lemons", short: "lemon", food: 167747, .extra, aisle: .produce, unit: BuyUnit("lemon", grams: 45),
                   range: 0...20, typical: 8),
        Ingredient("feta", "Feta", food: 173420, .dairy, tags: .dairy, aisle: .dairyAndEggs, unit: BuyUnit("block", grams: 200, size: "200 g"),
                   range: 0...40, typical: 25),
        Ingredient("parmesan", "Parmesan", food: 171247, .dairy, tags: .dairy, aisle: .dairyAndEggs, unit: BuyUnit("wedge", grams: 100, size: "100 g"),
                   range: 0...20, typical: 10),
        Ingredient("kimchi", "Kimchi", food: 170392, .vegetable, aisle: .produce, unit: BuyUnit("jar", grams: 400, size: "400 g"),
                   range: 0...80, typical: 50, everyday: 0.4),

        // Breakfast and snacks.
        Ingredient("greek-yogurt", "Plain Greek yogurt", short: "Greek yogurt", food: 170903, .dairy, tags: .dairy, aisle: .dairyAndEggs,
                   unit: BuyUnit("tub", grams: 500, size: "500 g"), range: 0...350, typical: 170, everyday: 0.9),
        Ingredient("yogurt", "Plain yogurt", short: "yogurt", food: 171284, .dairy, tags: .dairy, aisle: .dairyAndEggs,
                   unit: BuyUnit("tub", grams: 500, size: "500 g"), range: 0...100, typical: 50),
        Ingredient("kefir", "Plain kefir", short: "kefir", food: 170904, .dairy, tags: .dairy, aisle: .dairyAndEggs,
                   unit: BuyUnit("bottle", grams: 1000, size: "1 L"), range: 0...400, typical: 250, liquid: true),
        Ingredient("cottage-cheese", "Cottage cheese", food: 172182, .dairy, tags: .dairy, aisle: .dairyAndEggs,
                   unit: BuyUnit("tub", grams: 500, size: "500 g"), range: 0...300, typical: 150),
        Ingredient("milk", "Milk", food: 171267, .dairy, tags: .dairy, aisle: .dairyAndEggs, unit: BuyUnit("carton", grams: 1030, size: "1 L"),
                   range: 0...150, typical: 100, liquid: true),
        Ingredient("eggs", "Eggs", short: "eggs", food: 171287, .protein, tags: .eggs, aisle: .dairyAndEggs,
                   unit: BuyUnit("egg", grams: 50), cooking: .bake(minutes: 22), range: 0...250, typical: 150, everyday: 0.9),
        Ingredient("boiled-eggs", "Eggs", short: "eggs", food: 173424, .protein, tags: .eggs, aisle: .dairyAndEggs,
                   unit: BuyUnit("egg", grams: 50), cooking: .boil(minutes: 10), range: 0...150, typical: 100, everyday: 0.8),
        Ingredient("oats", "Rolled oats", short: "oats", food: 173904, .carb, tags: .gluten, aisle: .pantry, range: 0...110, typical: 60,
                   everyday: 0.9),
        Ingredient("chia", "Chia seeds", food: 170554, .extra, aisle: .pantry, range: 0...20, typical: 10, pantry: true),
        Ingredient("blueberries", "Frozen blueberries", short: "blueberries", food: 173950, .fruit, aisle: .frozen, range: 0...150,
                   typical: 75),
        Ingredient("banana", "Bananas", short: "banana", food: 173944, .fruit, aisle: .produce, unit: BuyUnit("banana", grams: 118),
                   range: 0...180, typical: 118, everyday: 0.9),
        Ingredient("apple", "Apples", short: "apple", food: 171688, .fruit, aisle: .produce, unit: BuyUnit("apple", grams: 182),
                   range: 0...200, typical: 182, everyday: 0.9),
        Ingredient("orange", "Oranges", short: "orange", food: 169097, .fruit, aisle: .produce, unit: BuyUnit("orange", grams: 140),
                   range: 0...160, typical: 140),
        Ingredient("pineapple", "Pineapple", food: 169124, .fruit, aisle: .produce, range: 0...160, typical: 100),
        Ingredient("almonds", "Almonds", food: 170567, .fat, tags: .nuts, aisle: .pantry, range: 0...40, typical: 20),
    ]

    public static let profiles: [Profile] = [
        Profile(id: "teriyaki", name: "Teriyaki", seasoning: "soy sauce, honey, ginger and garlic", spices: ["Fresh ginger", "Garlic"],
                sauce: [("soy-sauce", 12), ("honey", 8), ("sesame", 3)], topping: ("kimchi", 50),
                sauceStep: "Stir together the soy sauce, honey, a thumb of grated ginger and 3 cloves of garlic; toss with the {protein} as it comes out.",
                proteins: ["chicken-breast", "chicken-thigh", "salmon", "tofu", "shrimp", "pork"],
                carbs: ["rice-white", "rice-brown", "quinoa"], vegetables: ["broccoli", "green-beans", "carrots", "peppers"],
                words: ["teriyaki", "asian", "japanese", "soy", "sweet", "kimchi", "korean"]),
        Profile(id: "tex-mex", name: "Tex-Mex", seasoning: "chili powder, cumin, garlic and lime", spices: ["Chili powder", "Ground cumin", "Garlic powder"],
                sauce: [("tomatoes", 60), ("onion", 20), ("lime", 8)], topping: ("greek-yogurt", 50),
                sauceStep: "Dice the tomatoes and onion, mix with the lime juice and a pinch of salt for a fresh salsa.",
                proteins: ["chicken-breast", "chicken-thigh", "turkey", "beef"],
                carbs: ["rice-white", "rice-brown", "sweet-potato", "quinoa", "black-beans"], vegetables: ["peppers", "zucchini", "cauliflower"],
                words: ["tex-mex", "mexican", "taco", "burrito", "spicy", "chili", "southwest"]),
        Profile(id: "mediterranean", name: "Mediterranean", seasoning: "lemon, garlic and oregano", spices: ["Dried oregano", "Garlic powder"],
                sauce: [("lemon", 8), ("feta", 25)], topping: nil, sauceStep: nil,
                proteins: ["chicken-breast", "chicken-thigh", "salmon", "cod", "turkey", "chickpeas"],
                carbs: ["quinoa", "potato", "rice-brown"], vegetables: ["zucchini", "peppers", "green-beans", "broccoli"],
                words: ["mediterranean", "greek", "lemon", "feta", "light", "fresh"]),
        Profile(id: "curry", name: "Curry", seasoning: "curry powder, garlic and tomato", spices: ["Curry powder", "Garam masala", "Garlic"],
                sauce: [("canned-tomatoes", 90), ("onion", 30)], topping: ("yogurt", 50),
                sauceStep: "Soften the onion in a little oil, add the curry powder and garam masala for a minute, then the canned tomatoes; simmer 10 minutes and stir in the {protein}.",
                proteins: ["chicken-breast", "chicken-thigh", "chickpeas", "lentils", "tofu", "shrimp"],
                carbs: ["rice-white", "rice-brown"], vegetables: ["cauliflower", "spinach", "peppers", "green-beans"],
                words: ["curry", "indian", "spicy", "masala", "warm"]),
        Profile(id: "italian", name: "Italian", seasoning: "tomato, garlic and basil", spices: ["Dried basil", "Garlic"],
                sauce: [("canned-tomatoes", 100), ("parmesan", 10)], topping: nil,
                sauceStep: "Simmer the canned tomatoes with 3 cloves of garlic and the basil for 10 minutes; stir in the {protein}.",
                proteins: ["turkey", "beef", "chicken-breast", "lentils"],
                carbs: ["pasta", "potato"], vegetables: ["zucchini", "broccoli", "peppers", "spinach"],
                words: ["italian", "pasta", "tomato", "bolognese", "comfort"]),
        Profile(id: "peanut", name: "Peanut-lime", seasoning: "peanut butter, soy sauce and lime", spices: ["Garlic", "Chili flakes"],
                sauce: [("peanut-butter", 15), ("soy-sauce", 8), ("lime", 8)], topping: nil,
                sauceStep: "Whisk the peanut butter, soy sauce, lime juice and a splash of hot water into a sauce; toss with the {protein}.",
                proteins: ["chicken-breast", "tofu", "shrimp", "pork"],
                carbs: ["rice-white", "rice-brown", "quinoa"], vegetables: ["broccoli", "carrots", "peppers", "green-beans"],
                words: ["peanut", "thai", "satay", "asian", "nutty"]),
    ]

    public static let templates: [Template] = [
        Template(id: "overnight-oats", name: "Overnight oats", slot: .breakfast,
                 parts: [("oats", 40...100, 60), ("greek-yogurt", 50...200, 150), ("milk", 0...150, 100), ("chia", 0...15, 10),
                         ("blueberries", 50...100, 75)],
                 keeps: 4, freezes: true, make: "Fill {servings} jars, each with {parts}; lid and chill.", cooking: .none),
        Template(id: "egg-muffins", name: "Egg muffins and fruit", slot: .breakfast,
                 parts: [("eggs", 100...250, 150), ("spinach", 30...30, 30), ("peppers", 40...40, 40), ("feta", 0...30, 15),
                         ("banana", 0...180, 118)],
                 keeps: 4, freezes: true,
                 make: "Whisk {eggs} eggs with the spinach, peppers and feta; fill a greased muffin tin and bake at 180°C (350°F) for 22 minutes. {perDay} a day, with a banana.",
                 cooking: .bake(minutes: 22)),
        Template(id: "yogurt-bowl", name: "Greek yogurt bowl", slot: .breakfast,
                 parts: [("greek-yogurt", 150...350, 200), ("oats", 0...80, 40), ("blueberries", 50...100, 75), ("honey", 0...15, 8),
                         ("almonds", 0...25, 10)],
                 keeps: 0, freezes: false, make: "Nothing to prep: spoon it together in the morning.", cooking: .none),
        Template(id: "kefir-banana", name: "Kefir and a banana", slot: .snack,
                 parts: [("kefir", 150...400, 250), ("banana", 0...180, 118)], keeps: 0, freezes: false,
                 make: "Nothing to prep.", cooking: .none),
        Template(id: "yogurt-berries", name: "Greek yogurt and berries", slot: .snack,
                 parts: [("greek-yogurt", 100...300, 170), ("blueberries", 50...100, 75)], keeps: 0, freezes: false,
                 make: "Nothing to prep.", cooking: .none),
        Template(id: "cottage-pineapple", name: "Cottage cheese and pineapple", slot: .snack,
                 parts: [("cottage-cheese", 100...300, 150), ("pineapple", 50...150, 100)], keeps: 0, freezes: false,
                 make: "Nothing to prep.", cooking: .none),
        Template(id: "eggs-orange", name: "Boiled eggs and an orange", slot: .snack,
                 parts: [("boiled-eggs", 50...150, 100), ("orange", 140...140, 140)], keeps: 7, freezes: false,
                 make: "Boil {eggs} eggs for 10 minutes, cool them in cold water and keep them in their shells.", cooking: .boil(minutes: 10)),
        Template(id: "apple-almonds", name: "An apple and almonds", slot: .snack,
                 parts: [("apple", 182...182, 182), ("almonds", 10...40, 20)], keeps: 0, freezes: false,
                 make: "Nothing to prep.", cooking: .none),
    ]

    public static let byID: [String: Ingredient] = Dictionary(uniqueKeysWithValues: ingredients.map { ($0.id, $0) })

    public static func ingredient(_ id: String) -> Ingredient? { byID[id] }
    public static func profile(_ id: String) -> Profile? { profiles.first { $0.id == id } }
    public static func template(_ id: String) -> Template? { templates.first { $0.id == id } }
}
