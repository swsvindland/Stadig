import Foundation

/// What people most often mean to type, said as they'd say it. The catalogs know which foods
/// exist but not which are eaten: USDA's foods carry no count, and a label's scans say nothing of
/// a banana. Suggestions lean on this list for the plain foods, the most logged first, and on the
/// search's own rows for brands, products and everything it doesn't have.
enum EverydayPhrases {
    /// The foods logged most of all.
    static let top: [String] = [
        "eggs", "chicken breast", "chicken", "rice", "banana", "coffee", "milk", "bread", "oatmeal", "greek yogurt", "peanut butter", "apple",
        "cheese", "butter", "avocado", "salmon", "ground beef", "potato", "protein shake", "olive oil", "almonds", "pasta", "broccoli", "yogurt",
        "toast", "water",
    ]

    /// The foods nearly everyone logs.
    static let first: [String] = [
        "egg whites", "chicken thigh", "ground turkey", "tuna", "shrimp", "steak", "bacon", "turkey", "ham", "sausage", "beef", "white rice",
        "brown rice", "bagel", "tortilla", "cereal", "granola", "quinoa", "whole milk", "almond milk", "oat milk", "cheddar cheese",
        "cottage cheese", "cream cheese", "orange", "strawberries", "blueberries", "grapes", "spinach", "carrots", "tomato", "sweet potato",
        "onion", "cucumber", "lettuce", "bell pepper", "mushrooms", "green beans", "corn", "black beans", "beans", "walnuts", "mayonnaise",
        "ketchup", "honey", "sugar", "black coffee", "tea", "orange juice", "protein bar", "protein powder", "pizza", "burger", "french fries",
        "sandwich", "salad", "soup", "chips", "cookie", "chocolate", "ice cream",
    ]

    /// Foods and dishes most people log now and then.
    static let second: [String] = [
        // Meat, fish and eggs.
        "chicken wings", "chicken drumstick", "chicken tenders", "chicken nuggets", "grilled chicken", "rotisserie chicken", "fried chicken",
        "chicken salad", "chicken soup", "chicken sandwich", "turkey breast", "turkey bacon", "pork chop", "pork tenderloin", "pulled pork",
        "ribs", "ribeye", "sirloin", "hot dog", "meatballs", "pepperoni", "salami", "beef jerky", "tilapia", "cod", "tuna salad", "sardines",
        "crab", "lobster", "scallops", "tofu", "hard boiled egg", "scrambled eggs", "fried egg", "omelet", "pork", "fish",
        // Dairy.
        "skim milk", "2% milk", "chocolate milk", "soy milk", "coconut milk", "half and half", "heavy cream", "sour cream", "whipped cream",
        "mozzarella", "parmesan", "swiss cheese", "feta", "string cheese", "american cheese", "provolone", "goat cheese", "ricotta", "kefir",
        // Grains and bread.
        "spaghetti", "macaroni", "noodles", "ramen", "white bread", "wheat bread", "sourdough bread", "english muffin", "croissant", "pancakes",
        "waffles", "french toast", "pita", "naan", "flour tortilla", "corn tortilla", "crackers", "couscous", "grits", "cornbread", "biscuit",
        "muffin", "blueberry muffin", "donut",
        // Fruit.
        "banana bread", "raspberries", "blackberries", "pineapple", "mango", "watermelon", "peach", "pear", "cherries", "kiwi", "lemon", "lime",
        "grapefruit",
        "cantaloupe", "clementine", "raisins", "dates", "dried cranberries", "applesauce",
        // Vegetables.
        "cauliflower", "zucchini", "asparagus", "kale", "cabbage", "celery", "brussels sprouts", "eggplant", "peas", "garlic", "red onion",
        "baby carrots", "cherry tomatoes", "romaine lettuce", "arugula", "sweet corn", "edamame", "beets", "butternut squash", "jalapeno",
        "olives", "pickles", "coleslaw", "baked potato", "mashed potatoes", "hash browns", "tater tots", "sweet potato fries", "potato salad",
        // Beans, nuts and seeds.
        "pinto beans", "kidney beans", "chickpeas", "lentils", "refried beans", "baked beans", "hummus", "peanuts", "cashews", "pistachios",
        "pecans", "almond butter", "sunflower seeds", "chia seeds", "flax seeds", "pumpkin seeds", "trail mix", "nuts",
        // Oils, sauces and sweeteners.
        "canola oil", "coconut oil", "vegetable oil", "mustard", "soy sauce", "salsa", "ranch", "bbq sauce", "hot sauce", "vinegar",
        "maple syrup", "jam", "jelly", "guacamole", "marinara sauce", "tomato sauce", "alfredo sauce", "salad dressing", "italian dressing",
        "caesar dressing",
        // Drinks.
        "iced coffee", "latte", "cappuccino", "espresso", "green tea", "iced tea", "apple juice", "lemonade", "soda", "coke", "diet coke",
        "sparkling water", "coconut water", "sports drink", "energy drink", "beer", "wine", "red wine", "white wine", "vodka", "whiskey",
        "margarita", "smoothie", "milkshake", "hot chocolate", "juice",
        // Snacks and sweets.
        "potato chips", "tortilla chips", "popcorn", "pretzels", "granola bar", "dark chocolate", "brownie", "cake", "cheesecake", "cupcake",
        "apple pie", "candy",
        // Dishes.
        "cheeseburger", "hamburger", "burrito", "taco", "quesadilla", "nachos", "mac and cheese", "fried rice", "sushi", "pad thai", "lasagna",
        "chicken noodle soup", "tomato soup", "chili", "beef stew", "grilled cheese", "peanut butter and jelly", "caesar salad", "greek salad",
        "egg salad", "burrito bowl", "stir fry", "chicken curry", "dumplings", "egg roll", "orange chicken", "lo mein", "falafel", "enchiladas",
        "breakfast sandwich", "breakfast burrito",
    ]

    /// A phrase with its words, and how much it counts beside what the search's rows suggest: a
    /// row counts one at most, so the first foods outweigh a handful of rows and the rest a few.
    struct Phrase {
        let words: [String]
        let weight: Double
    }

    static let all: [Phrase] =
        top.map { Phrase(words: $0.split(separator: " ").map(String.init), weight: 14) }
        + first.map { Phrase(words: $0.split(separator: " ").map(String.init), weight: 11) }
        + second.map { Phrase(words: $0.split(separator: " ").map(String.init), weight: 7) }
}
