import SystemCore
import Testing

@testable import FoodDatabase

/// Everyday foods as they're typed with no brand, a word or two, each with a pattern for the plain
/// food that should come first: the cooked chicken, the whole milk, the raw apple, and the food
/// itself where USDA files it under another word ("Pork, cured, bacon", "Salad dressing,
/// mayonnaise", "Frankfurter").
let staples: [(String, String)] = [
    // Meat, fish and eggs.
    ("chicken", "^Chicken, (broilers or fryers|roasting), .*cooked, roasted|^Chicken, cooked"),
    ("chicken breast", "^Chicken, broilers or fryers, breast, .*cooked, roasted|^Chicken breast, cooked"),
    ("chicken thigh", "^Chicken, broilers or fryers, thigh, .*cooked|^Chicken thigh, cooked"),
    ("chicken wings", "^Chicken, broilers or fryers, wing, .*cooked|^Chicken wing, cooked"),
    ("ground beef", "^Beef, ground, .*cooked"),
    ("steak", "^Beef, .*steak.*cooked|^Steak, cooked"),
    ("ribeye", "^Beef, rib ?eye|^Beef, steak, ribeye"),
    ("sirloin", "^Beef, .*sirloin"),
    ("pork chop", "^Pork, fresh, .*chops.*cooked|^Pork, chop"),
    ("bacon", "^Pork, cured, bacon, .*cooked|^Bacon, cooked"),
    ("ham", "^Ham, "),
    ("sausage", "^Sausage, "),
    ("hot dog", "^Frankfurter, (beef|meat|pork)|^Hot dog"),
    ("turkey", "^Turkey, .*cooked, roasted|^Turkey, cooked"),
    ("ground turkey", "^Turkey, [Gg]round, .*cooked"),
    ("turkey breast", "^Turkey, .*breast, .*(cooked|roasted)"),
    ("salmon", "^Fish, salmon, .*cooked|^Fish, salmon, (baked|grilled|steamed|cooked)"),
    ("tuna", "^Fish, tuna, "),
    ("shrimp", "^Crustaceans, shrimp, .*cooked|^Shrimp, cooked"),
    ("tilapia", "^Fish, tilapia, cooked|^Fish, tilapia, (baked|grilled|steamed|cooked)"),
    ("cod", "^Fish, cod, .*cooked|^Fish, cod, (baked|grilled|steamed|cooked)"),
    ("egg", "^Egg, whole, cooked"),
    ("egg white", "^Egg, white, "),
    ("tofu", "^Tofu, (raw|firm|extra firm|soft|hard)"),
    ("meatballs", "^Meatballs, frozen, Italian style"),
    ("pepperoni", "^Pepperoni"),
    ("salami", "^Salami"),
    ("beef jerky", "(?i)jerky"),
    // Dairy.
    ("milk", "^Milk, whole"),
    ("skim milk", "^Milk, nonfat, fluid"),
    ("whole milk", "^Milk, whole"),
    ("almond milk", "^Almond milk"),
    ("soy milk", "^Soy milk"),
    ("butter", "^Butter, (salted|without salt)"),
    ("cheese", "^Cheese, cheddar"),
    ("cheddar", "^Cheese, cheddar"),
    ("mozzarella", "^Cheese, mozzarella"),
    ("parmesan", "^Cheese, parmesan"),
    ("swiss cheese", "^Cheese, swiss$"),
    ("feta", "^Cheese, feta"),
    ("cream cheese", "^Cheese, cream$"),
    ("cottage cheese", "^Cheese, cottage, (creamed, large or small curd|lowfat, [12]% milkfat$)"),
    ("yogurt", "^Yogurt, plain"),
    ("greek yogurt", "^Yogurt, Greek, plain"),
    ("sour cream", "^Cream, sour, cultured"),
    ("heavy cream", "^Cream, fluid, heavy"),
    ("half and half", "^Cream, fluid, half and half"),
    ("ice cream", "^Ice creams, vanilla|^Ice cream$"),
    ("whipped cream", "^Cream, whipped"),
    // Grains and bread.
    ("rice", "^Rice, white, long-grain, .*cooked"),
    ("brown rice", "^Rice, brown, .*cooked"),
    ("pasta", "^Pasta, cooked"),
    ("spaghetti", "^Pasta, cooked"),
    ("macaroni", "^Pasta, cooked"),
    ("bread", "^Bread, (white|wheat)"),
    ("white bread", "^Bread, white, commercially prepared \\(includes"),
    ("wheat bread", "^Bread, (wheat|whole-wheat)"),
    ("toast", "^Bread, .*toasted"),
    ("bagel", "^Bagels, plain"),
    ("tortilla", "^Tortillas, ready-to-bake or -fry, (corn|flour)"),
    ("flour tortilla", "^Tortillas, ready-to-bake or -fry, flour"),
    ("corn tortilla", "^Tortillas, ready-to-bake or -fry, corn"),
    ("oatmeal", "^Cereals, oats, .*cooked"),
    ("granola", "^Cereals ready-to-eat, granola|^Cereal, granola"),
    ("quinoa", "^Quinoa, cooked"),
    ("couscous", "^Couscous, cooked"),
    ("pancake", "^Pancakes, plain|^Pancakes$"),
    ("waffle", "^Waffles?, plain|^Waffle$"),
    ("english muffin", "^Muffins, English, plain"),
    ("croissant", "^Croissants, butter|^Croissant$"),
    ("crackers", "^Crackers, "),
    ("pita", "^Bread, pita"),
    ("noodles", "^Noodles, egg, .*cooked"),
    // Fruit.
    ("apple", "^Apples, raw, with(out)? skin"),
    ("banana", "^Bananas, raw"),
    ("orange", "^Oranges, raw"),
    ("grapes", "^Grapes, red or green"),
    ("strawberries", "^Strawberries, raw"),
    ("blueberries", "^Blueberries, raw"),
    ("raspberries", "^Raspberries, raw"),
    ("pineapple", "^Pineapple, raw"),
    ("mango", "^Mangos, raw"),
    ("watermelon", "^Watermelon, raw"),
    ("peach", "^Peaches, yellow, raw"),
    ("pear", "^Pears, raw"),
    ("avocado", "^Avocados, raw"),
    ("lemon", "^Lemons, raw"),
    ("lime", "^Limes, raw"),
    ("cherries", "^Cherries, sweet, raw"),
    ("kiwi", "^Kiwifruit"),
    ("grapefruit", "^Grapefruit, raw"),
    ("cantaloupe", "^Melons, cantaloupe, raw"),
    ("raisins", "^Raisins"),
    ("dates", "^Dates"),
    // Vegetables.
    ("broccoli", "^Broccoli, (raw|cooked)"),
    ("spinach", "^Spinach, (raw|cooked)"),
    ("carrot", "^Carrots, (raw|cooked)"),
    ("tomato", "^Tomatoes, red, ripe, raw"),
    ("potato", "^Potatoes, (baked|boiled)"),
    ("sweet potato", "^Sweet potato, cooked, (baked|boiled)"),
    ("onion", "^Onions, raw"),
    ("garlic", "^Garlic, raw"),
    ("lettuce", "^Lettuce, (iceberg|cos or romaine|green leaf|red leaf)"),
    ("cucumber", "^Cucumber, "),
    ("bell pepper", "^Peppers, sweet, (red|green|yellow), raw"),
    ("mushrooms", "^Mushrooms, white"),
    ("corn", "^Corn, sweet, (yellow|white), (cooked|raw)"),
    ("peas", "^Peas, green"),
    ("green beans", "^Beans, snap, green"),
    ("cauliflower", "^Cauliflower, (raw|cooked)"),
    ("zucchini", "^Squash, summer, zucchini"),
    ("asparagus", "^Asparagus"),
    ("kale", "^Kale"),
    ("cabbage", "^Cabbage, (raw|cooked)"),
    ("celery", "^Celery"),
    ("brussels sprouts", "^Brussels sprouts"),
    ("eggplant", "^Eggplant"),
    // Beans, nuts and seeds.
    ("black beans", "^Beans, black, mature seeds, cooked"),
    ("pinto beans", "^Beans, pinto, mature seeds, cooked"),
    ("kidney beans", "^Beans, kidney, .*cooked"),
    ("chickpeas", "^Chickpeas .*cooked"),
    ("lentils", "^Lentils, .*cooked"),
    ("peanuts", "^Peanuts, all types"),
    ("almonds", "^Nuts, almonds"),
    ("walnuts", "^Nuts, walnuts, english"),
    ("cashews", "^Nuts, cashew nuts"),
    ("peanut butter", "^Peanut butter, (smooth|chunk)"),
    ("almond butter", "^Nuts, almond butter"),
    ("hummus", "^Hummus, commercial"),
    ("pistachios", "^Nuts, pistachio nuts"),
    ("sunflower seeds", "^Seeds, sunflower seed kernels"),
    ("chia seeds", "^Seeds, chia seeds"),
    // Oils, sauces and sweeteners.
    ("olive oil", "^Oil, olive"),
    ("canola oil", "^Oil, canola"),
    ("coconut oil", "^Oil, coconut$"),
    ("mayo", "^Salad dressing, mayonnaise, regular"),
    ("mayonnaise", "^Salad dressing, mayonnaise, regular"),
    ("ketchup", "^Catsup$|^Ketchup$"),
    ("mustard", "^Mustard, prepared, yellow"),
    ("soy sauce", "^Soy sauce made from soy"),
    ("salsa", "^Sauce, salsa, ready-to-serve|^Salsa$"),
    ("ranch", "^Salad dressing, ranch dressing, regular"),
    ("honey", "^Honey$"),
    ("maple syrup", "^Syrups, maple"),
    ("sugar", "^Sugars, granulated"),
    ("jam", "^Jams and preserves$"),
    ("jelly", "^Jellies$"),
    ("bbq sauce", "^Sauce, barbecue"),
    ("hot sauce", "^Sauce, (ready-to-serve, pepper or hot|hot chile)"),
    ("vinegar", "^Vinegar, "),
    // Drinks.
    ("coffee", "^Beverages, coffee, brewed, prepared with tap water$|^Coffee(, brewed)?$"),
    ("tea", "^Beverages, tea, black, brewed"),
    ("orange juice", "^Orange juice"),
    ("apple juice", "^Apple juice, canned or bottled"),
    ("soda", "^Beverages, carbonated, cola"),
    ("coke", "(?i)^(Beverages, carbonated, cola|coca.cola|coke)"),
    ("beer", "^Alcoholic beverage, beer, regular"),
    ("wine", "^Alcoholic beverage, wine, table"),
    ("red wine", "^Alcoholic beverage, wine, table, red|^Wine, red$"),
    ("white wine", "^Alcoholic beverage, wine, table, white|^Wine, white$"),
    ("vodka", "^Alcoholic beverage, distilled, vodka|^Vodka$"),
    ("whiskey", "^Alcoholic beverage, distilled, whiskey|^Whiskey$"),
    ("espresso", "^Beverages, coffee, brewed, espresso|^Coffee, espresso$"),
    ("milkshake", "^Milk shakes?, "),
    // Snacks and sweets.
    ("chips", "^(Snacks, potato chips, plain|Potato chips)"),
    ("potato chips", "^(Snacks, potato chips, plain, salted|Potato chips)"),
    ("tortilla chips", "^(Snacks, )?[Tt]ortilla chips"),
    ("popcorn", "^(Snacks, popcorn, (air-popped|oil-popped|home-prepared)|Popcorn$)"),
    ("pretzels", "^(Snacks, pretzels|Pretzels)"),
    ("cookie", "^Cookies?, |^Cookie$"),
    ("chocolate", "^(Chocolate|Candies, milk chocolate)"),
    ("dark chocolate", "^(Chocolate, dark|Dark chocolate candy)"),
    ("brownie", "^Cookies, brownies|^Cookie, brownie$"),
    ("donut", "^Doughnuts|^Doughnut$"),
    ("muffin", "^Muffin$"),
    ("granola bar", "(?i)granola bars?"),
    // Dishes.
    ("french fries", "[Ff]rench fries"),
    ("pizza", "^Pizza, cheese"),
    ("burger", "^(Hamburger|Cheeseburger)"),
    ("hamburger", "^Hamburger"),
    ("cheeseburger", "^Cheeseburger"),
    ("burrito", "^(Fast foods, burrito, with beans$|Burrito, beef and bean, microwaved)|^Burrito$"),
    ("mac and cheese", "^Macaroni and [Cc]heese|^Macaroni or noodles with cheese$"),
    ("fried rice", "(?i)fried rice|^Rice, fried$"),
]

/// Foods from the pantry, dishes and the forms foods come in, measured after the staples: what a
/// suggestion leads to when it's tapped.
let pantry: [(String, String)] = [
    ("beef", "^Beef, ground, .*cooked"),
    ("pork", "^Pork, fresh, .*cooked"),
    ("ribs", "^Pork, fresh, .*ribs.*cooked|^Ribs, cooked"),
    ("cereal", "^Cereals ready-to-eat|^Cereal, ready-to-eat"),
    ("nuts", "^Nuts, mixed nuts"),
    ("coconut milk", "^(Nuts|Beverages), coconut milk"),
    ("tomato sauce", "^Tomato (sauce|products), canned"),
    ("tomato paste", "^Tomato products, canned, paste"),
    ("taco", "(?i)^(TACO BELL, Original Taco|Fast foods, taco|Taco)"),
    ("nachos", "^Fast foods, nachos|^Nachos$"),
    ("chili", "^Chili"),
    ("egg roll", "^(Egg rolls|Restaurant, Chinese, egg rolls)"),
    ("enchiladas", "(?i)cheese enchilada|^Enchilada$"),
    ("beef stew", "^Beef stew|^Stew, beef$"),
    ("tomato soup", "^Soup, tomato, canned, prepared|^Soup, tomato$"),
    ("chicken noodle soup", "^Soup, chicken noodle, canned, prepared|^Soup, chicken noodle$"),
    ("pickles", "^Pickles, cucumber, dill"),
    ("sardines", "^Fish, sardine"),
    ("tuna", "^Fish, tuna, (light|white), canned|^Fish, tuna, canned"),
    ("canned tuna", "^Fish, tuna, (light|white), canned|^Fish, tuna, canned"),
    ("anchovies", "^Fish, anchovy, european, canned"),
    ("sourdough bread", "^Bread, french or vienna"),
    ("cornbread", "^Cornbread"),
    ("sports drink", "(?i)(gatorade|powerade|sports? drink)"),
    ("american cheese", "^Cheese, pasteurized process, American"),
    ("black coffee", "^Beverages, coffee, brewed|^Coffee, brewed$"),
    ("lasagna", "(?i)lasagna with meat"),
    ("spam", "(?i)spam"),
    ("canned corn", "^Corn, sweet, (yellow|white), canned, (whole kernel|vacuum pack|brine pack)"),
    ("pumpkin puree", "^Pumpkin, canned"),
    ("condensed milk", "^Milk, canned, condensed, sweetened|^Milk, condensed, sweetened"),
    ("evaporated milk", "^Milk, (canned, )?evaporated"),
    ("refried beans", "^(Refried beans|Beans, refried)"),
    ("olives", "^Olives, ripe, canned"),
    ("black olives", "^Olives, ripe"),
    ("applesauce", "^Applesauce, canned, unsweetened"),
    ("baked beans", "^Beans, baked"),
    ("chicken broth", "^Soup, chicken broth"),
    ("oat milk", "(?i)^oat.?milk"),
    ("eggs", "^Egg, whole, cooked"),
    ("water", "^Water, (bottled|tap)"),
    ("white rice", "^Rice, white, long-grain, .*cooked"),
    ("carrots", "^Carrots, raw"),
    ("beans", "^Beans, (black|pinto), mature seeds, cooked"),
    ("fried egg", "^Egg, whole, cooked, fried"),
    ("scrambled eggs", "^Egg, whole, cooked, scrambled"),
    ("hard boiled egg", "^Egg, whole, cooked, hard-boiled"),
    ("grilled chicken", "^Chicken, .*grilled"),
    ("fried chicken", "^Chicken, .*fried"),
    ("chicken nuggets", "^Chicken nuggets"),
    ("chicken tenders", "^Chicken tenders"),
    ("turkey bacon", "^Bacon, turkey|^Turkey bacon, cooked"),
    ("pulled pork", "^Pulled pork|^Barbecue pork"),
    ("pork tenderloin", "^Pork, fresh, loin, tenderloin, .*cooked|^Pork, tenderloin"),
    ("tuna salad", "^Fish, tuna salad|^Tuna salad$"),
    ("crab", "^Crustaceans, crab, .*cooked|^Crab, cooked"),
    ("lobster", "^Crustaceans, lobster, .*cooked|^Lobster, cooked"),
    ("2% milk", "^Milk, reduced fat, fluid, 2% milkfat"),
    ("chocolate milk", "^Milk, chocolate"),
    ("provolone", "^Cheese, provolone"),
    ("goat cheese", "^Cheese, goat"),
    ("ricotta", "^Cheese, ricotta"),
    ("pancakes", "^Pancakes, plain|^Pancakes$"),
    ("waffles", "^Waffles, plain|^Waffle$"),
    ("french toast", "^French toast"),
    ("naan", "^Bread, naan"),
    ("biscuit", "^Biscuit$"),
    ("blueberry muffin", "^Muffins, blueberry"),
    ("banana bread", "^Bread, banana"),
    ("blackberries", "^Blackberries, raw"),
    ("baby carrots", "^Carrots, baby, raw"),
    ("romaine lettuce", "^Lettuce, cos or romaine"),
    ("arugula", "^Arugula"),
    ("edamame", "^Edamame"),
    ("butternut squash", "^Squash, winter, butternut"),
    ("jalapeno", "^Peppers, jalapeno"),
    ("coleslaw", "^Coleslaw"),
    ("baked potato", "^Potatoes, baked"),
    ("mashed potatoes", "^Potatoes, mashed|^Potato, mashed$"),
    ("hash browns", "^Potatoes, hash brown|^Potato, hash brown$"),
    ("potato salad", "^Potato salad"),
    ("pecans", "^Nuts, pecans"),
    ("flax seeds", "^Seeds, flaxseed"),
    ("pumpkin seeds", "^Seeds, pumpkin"),
    ("trail mix", "^Snacks, trail mix"),
    ("vegetable oil", "^Oil, vegetable"),
    ("marinara sauce", "^Sauce, pasta, spaghetti/marinara"),
    ("italian dressing", "^Salad dressing, italian dressing"),
    ("caesar dressing", "^Salad dressing, caesar"),
    ("green tea", "^Beverages, tea, green, brewed"),
    ("iced tea", "^Tea, iced"),
    ("lemonade", "(?i)^(Beverages, )?lemonade"),
    ("coconut water", "^Nuts, coconut water|^Coconut water, unsweetened$"),
    ("hot chocolate", "(?i)(hot cocoa|hot chocolate)"),
    ("cheesecake", "^Cake, cheesecake"),
    ("apple pie", "^Pie, apple"),
    ("quesadilla", "(?i)quesadilla"),
    ("orange chicken", "(?i)orange chicken"),
    ("lo mein", "(?i)lo mein"),
    ("falafel", "^Falafel"),
    ("breakfast burrito", "(?i)breakfast burrito"),
]

/// The everyday form of a plain food: what a word or two typed with no brand most likely means.
/// Foods said with how they're cooked, cut or trimmed, and by the words people use for how lean,
/// salted or smooth they are, each with the plain food that should come first: USDA lists a
/// cooked food one or two ways, and mostly leaves a cut unsaid.
let forms: [(String, String)] = [
    // Fish and shellfish, by a way of cooking or a cut USDA doesn't list.
    ("baked salmon", "^Fish, salmon, .*cooked, dry heat|^Fish, salmon, (baked|grilled|steamed|cooked)"),
    ("grilled salmon", "^Fish, salmon, .*cooked, dry heat|^Fish, salmon, (baked|grilled|steamed|cooked)"),
    ("roasted salmon", "^Fish, salmon, .*cooked, dry heat|^Fish, salmon, (baked|grilled|steamed|cooked)"),
    ("salmon fillet", "^Fish, salmon, .*cooked|^Fish, salmon, (baked|grilled|steamed|cooked)"),
    ("grilled salmon fillet", "^Fish, salmon, .*cooked, dry heat|^Fish, salmon, (baked|grilled|steamed|cooked)"),
    ("poached salmon", "^Fish, salmon, .*cooked|^Fish, salmon, (baked|grilled|steamed|cooked)"),
    ("baked cod", "^Fish, cod, .*cooked|^Fish, cod, (baked|grilled|steamed|cooked)"),
    ("baked tilapia", "^Fish, tilapia, cooked|^Fish, tilapia, (baked|grilled|steamed|cooked)"),
    ("grilled tilapia", "^Fish, tilapia, cooked|^Fish, tilapia, (baked|grilled|steamed|cooked)"),
    ("cod fillet", "^Fish, cod, .*cooked|^Fish, cod, (baked|grilled|steamed|cooked)"),
    ("grilled shrimp", "^Crustaceans, shrimp, (mixed species, )?cooked(?!, breaded)|^Shrimp, grilled|^Shrimp, steamed or boiled"),
    ("steamed shrimp", "^Crustaceans, shrimp, (mixed species, )?cooked(?!, breaded)|^Shrimp, grilled|^Shrimp, steamed or boiled"),
    ("raw salmon", "^Fish, salmon, .*raw"),
    // Vegetables.
    ("steamed broccoli", "^Broccoli, cooked"),
    ("roasted broccoli", "^Broccoli, cooked"),
    ("broccoli florets", "^Broccoli, (raw|cooked)"),
    ("grilled asparagus", "^Asparagus, cooked"),
    ("roasted asparagus", "^Asparagus, cooked"),
    ("asparagus spears", "^Asparagus, (raw|cooked)"),
    ("sauteed spinach", "^Spinach, cooked"),
    ("steamed spinach", "^Spinach, cooked"),
    ("baby spinach", "^Spinach, raw"),
    ("sauteed mushrooms", "^Mushrooms, white, (stir-fried|cooked)"),
    ("sauteed onions", "^Onions, (yellow, sauteed|cooked)"),
    ("grilled onions", "^Onions, (yellow, sauteed|cooked)"),
    ("roasted cauliflower", "^Cauliflower, cooked"),
    ("steamed cauliflower", "^Cauliflower, cooked"),
    ("roasted carrots", "^Carrots, cooked"),
    ("steamed carrots", "^Carrots, cooked"),
    ("roasted brussels sprouts", "^Brussels sprouts, cooked"),
    ("steamed green beans", "^Beans, snap, green, (cooked|microwaved)"),
    ("sauteed kale", "^Kale, cooked"),
    ("grilled zucchini", "^Squash, summer, zucchini, .*cooked"),
    ("roasted zucchini", "^Squash, summer, zucchini, .*cooked"),
    ("grilled corn", "^Corn, sweet, .*cooked"),
    ("roasted sweet potato", "^Sweet potato, cooked, baked"),
    ("baked sweet potato", "^Sweet potato, cooked, baked"),
    ("roasted potatoes", "^Roasted potatoes"),
    ("raw spinach", "^Spinach, raw"),
    ("raw broccoli", "^Broccoli, raw"),
    ("raw carrots", "^Carrots, raw"),
    ("garlic clove", "^Garlic, raw"),
    ("celery stalk", "^Celery, raw"),
    ("corn kernels", "^Corn, "),
    ("garlic cloves", "^Garlic, raw"),
    ("baby carrots", "^Carrots, baby"),
    ("baby potatoes", "^Potatoes"),
    ("fresh spinach", "^Spinach, raw"),
    // Rice, meat and tofu.
    ("steamed rice", "^Rice, white, (steamed|.*cooked)"),
    ("boiled rice", "^Rice, white, .*cooked"),
    ("grilled chicken breast", "^Chicken, .*breast.*grilled|^Chicken breast, grilled"),
    ("baked chicken breast", "^Chicken.*breast.*(roasted|baked)"),
    ("roasted chicken breast", "^Chicken, .*breast.*roasted"),
    ("boiled chicken breast", "^Chicken, .*breast.*(stewed|cooked)"),
    ("grilled chicken thigh", "^Chicken, .*thigh.*(roasted|grilled|cooked)|^Chicken thigh, grilled"),
    ("baked chicken thigh", "^Chicken, .*thigh, meat.*roasted|^Chicken thigh, baked"),
    ("skinless chicken thigh", "^Chicken, .*thigh, meat only|^Chicken thigh, cooked"),
    ("boneless skinless chicken thigh", "^Chicken, .*thigh, meat only|^Chicken thigh, cooked"),
    ("boneless skinless chicken breast", "^Chicken, .*breast.*(skinless|meat only)"),
    ("chicken cutlet", "^Chicken, "),
    ("grilled pork chop", "^Pork, .*chops.*(broiled|grilled)|^Pork, chop"),
    ("baked pork chop", "^Pork, .*chops.*(broiled|roasted)|^Pork, chop"),
    ("grilled pork tenderloin", "^Pork, .*tenderloin.*(broiled|roasted)"),
    ("roasted turkey breast", "^Turkey, .*breast.*roasted"),
    ("grilled steak", "^Beef, .*steak.*(grilled|broiled)|^Steak, cooked"),
    ("grilled tofu", "^Tofu, (raw|firm|fried|extra firm)"),
    ("baked tofu", "(?i)tofu"),
    ("chicken pieces", "(?i)chicken"),
    // How lean, how fat, how salted, how smooth.
    ("lean ground beef", "^Beef, ground, 9[0-7]% lean.*cooked"),
    ("extra lean ground beef", "^Beef, ground, 9[5-7]% lean.*cooked"),
    ("lean ground turkey", "^Turkey, ground, 93% lean"),
    ("fat free milk", "^Milk, nonfat"),
    ("fat free yogurt", "^Yogurt, (.*(nonfat|fat free)|plain, skim milk)"),
    ("fat free greek yogurt", "^Yogurt, Greek, .*nonfat"),
    ("unsalted butter", "^Butter, without salt"),
    ("unsalted almonds", "^Nuts, almonds, .*without salt"),
    ("unsalted peanuts", "^Peanuts, .*without salt"),
    ("crunchy peanut butter", "^Peanut butter, chunk"),
    ("creamy peanut butter", "^Peanut butter, smooth"),
    // Raw, fresh and cut.
    ("raw almonds", "^Nuts, almonds$"),
    ("pecan halves", "^Nuts, pecans"),
    ("apple slices", "^Apples, raw"),
    ("cucumber slices", "^Cucumber, (with peel, raw|peeled, raw)"),
    ("pineapple chunks", "^Pineapple, (raw|canned|frozen)"),
    ("toasted almonds", "^Nuts, almonds, (dry|oil) roasted"),
    ("general tso chicken", "(?i)general tso"),
    ("pb&j", "(?i)peanut butter.*jelly"),
    ("pbj", "(?i)peanut butter.*jelly"),
    ("oj", "^Orange juice"),
    ("great northern beans", "^Beans, great northern"),
    ("little smokies", "(?i)smok"),
    ("egg salad", "(?i)^egg salad"),
    ("grape juice", "^Grape juice"),
    ("ham sandwich", "^Ham sandwich"),
    ("pea soup", "^Soup, pea"),
    ("fresh strawberries", "^Strawberries, raw"),
    ("simple syrup", "(?i)syrup"),
    ("mission figs", "(?i)fig"),
]

/// Foods as a vision model names what's on a plate: with an amount in brackets, what the food
/// comes with, how it was cooked and cut. Each with the plain food the meal AI's matching
/// should offer first.
let plates: [(String, String)] = [
    ("Grilled chicken breast (skinless)", "^Chicken, .*breast.*grilled|^Chicken breast, grilled"),
    ("Grilled chicken breast, sliced", "^Chicken, .*breast.*grilled|^Chicken breast, grilled"),
    ("White rice, cooked", "^Rice, white, .*cooked"),
    ("Brown rice (cooked)", "^Rice, brown, .*cooked"),
    ("Jasmine rice", "^Rice, white, .*cooked"),
    ("Basmati rice", "^Rice, white, .*cooked"),
    ("Mixed greens with vinaigrette", "(?i)^mixed greens"),
    ("Side salad with ranch dressing", "^Lettuce, salad"),
    ("Scrambled eggs (2 large)", "^Egg, whole, cooked, scrambled"),
    ("Fried egg, sunny side up", "^Egg, whole, cooked, fried"),
    ("Hard-boiled egg", "^Egg, whole, cooked, hard-boiled"),
    ("Whole wheat toast with butter", "^Bread, whole-wheat, .*toasted"),
    ("Buttered toast", "^Bread, .*toasted"),
    ("Sourdough toast", "^Bread, .*toasted.*sourdough"),
    ("Toast with jam", "^Bread, .*toasted"),
    ("Black coffee", "^Beverages, coffee, brewed|^Coffee, brewed$"),
    ("Coffee with milk", "^Beverages, coffee, brewed|^Coffee(, brewed)?$"),
    ("Iced coffee with cream", "^Beverages, coffee, brewed|^Iced Coffee, brewed$"),
    ("Orange juice (fresh squeezed)", "^Orange juice"),
    ("Glass of whole milk", "^Milk, whole"),
    ("French fries (medium serving)", "^Potato(es)?, french fri"),
    ("Cheeseburger with lettuce and tomato", "(?i)^cheeseburger"),
    ("Hamburger patty", "^Beef, ground, .*patty, cooked|^Beef, ground, patty"),
    ("Beef burger patty (grilled)", "^Beef, ground, .*patty, cooked|^Beef, ground, patty"),
    ("Pasta with marinara sauce", "^Pasta, cooked|^Pasta with tomato-based sauce, restaurant$"),
    ("Spaghetti with tomato sauce", "^(Pasta, cooked|Spaghetti)|^Pasta with tomato-based sauce, restaurant$"),
    ("Penne pasta", "^Pasta, cooked"),
    ("Roasted vegetables (broccoli, carrots)", "^Vegetables, mixed, .*cooked"),
    ("Roasted broccoli florets", "^Broccoli, cooked"),
    ("Steamed green beans", "^Beans, snap, green, (cooked|microwaved)"),
    ("Sauteed spinach with garlic", "^Spinach, cooked"),
    ("Avocado slices", "^Avocados, raw"),
    ("Half an avocado", "^Avocados, raw"),
    ("Cherry tomatoes", "^Tomatoes, red, ripe, raw"),
    ("Sliced cucumber", "^Cucumber, .*raw"),
    ("Sliced tomato", "^Tomatoes, red, ripe, raw"),
    ("Diced onion", "^Onions, raw"),
    ("Shredded lettuce", "^Lettuce, .*raw"),
    ("Shredded cheddar cheese", "^Cheese, cheddar"),
    ("Grated parmesan cheese", "^Cheese, parmesan"),
    ("Crumbled feta cheese", "^Cheese, feta"),
    ("Greek yogurt with berries", "^Yogurt, Greek, plain"),
    ("Plain Greek yogurt (nonfat)", "^Yogurt, Greek, plain, nonfat"),
    ("Almonds (raw)", "^Nuts, almonds$"),
    ("Tortilla chips with salsa", "^(Snacks, t|T)ortilla chips"),
    ("Black beans (canned)", "^Beans, black.*canned"),
    ("Chicken thigh, roasted, with skin", "^Chicken, .*thigh, meat and skin, cooked, roasted|^Chicken thigh, baked"),
    ("Chicken wings (buffalo)", "^Chicken, .*wing.*cooked|^Chicken .wings. with hot sauce|^Chicken wing, cooked"),
    ("Ground beef, cooked", "^Beef, ground, .*cooked"),
    ("Ground turkey (93% lean)", "^Turkey, ground, 93% lean"),
    ("Pan-seared salmon fillet", "^Fish, salmon, .*cooked, dry heat|^Fish, salmon, (baked|grilled|steamed|cooked)"),
    ("Salmon, baked", "^Fish, salmon, .*cooked, dry heat|^Fish, salmon, (baked|grilled|steamed|cooked)"),
    ("Tuna steak, seared", "^Fish, tuna, .*fresh.*cooked"),
    ("Shrimp, grilled", "^Crustaceans, shrimp, (mixed species, )?cooked(?!, breaded)|^Shrimp, grilled|^Shrimp, steamed or boiled"),
    ("Bacon strips (2)", "^Pork, cured, bacon, .*cooked|^Bacon, cooked"),
    ("Sausage patty", "^Pork sausage, .*cooked"),
    ("Pork chop, grilled", "^Pork, fresh, .*chops.*cooked|^Pork, chop"),
    ("Sirloin steak, grilled", "^Beef, .*sirloin.*cooked"),
    ("Baked potato with sour cream", "^Potatoes, baked"),
    ("Mashed potatoes with gravy", "^Potato(es)?, mashed.*gravy"),
    ("Roasted potatoes", "^Roasted potatoes"),
    ("Corn on the cob", "^Corn, sweet, .*cooked"),
    ("Steamed broccoli", "^Broccoli, cooked"),
    ("Asparagus spears, grilled", "^Asparagus, cooked"),
    ("Brussels sprouts, roasted", "^Brussels sprouts, cooked"),
    ("Baby carrots", "^Carrots, baby"),
    ("Red bell pepper", "^Peppers, sweet, red, raw"),
    ("Mushrooms, sauteed", "^Mushrooms, white, (stir-fried|cooked)"),
    ("Zucchini, grilled", "^Squash, summer, zucchini, .*cooked"),
    ("Butternut squash, roasted", "^Squash, winter, butternut, cooked"),
    ("Sweet potato, baked", "^Sweet potato, cooked, baked"),
    ("Apple slices", "^Apples, raw"),
    ("Banana (medium)", "^Bananas, raw"),
    ("Blueberries (fresh)", "^Blueberries, raw"),
    ("Strawberries, sliced", "^Strawberries, raw"),
    ("Grapes (red)", "^Grapes, red"),
    ("Orange segments", "^Oranges, raw"),
    ("Watermelon cubes", "^Watermelon, raw"),
    ("Pineapple chunks", "^Pineapple, raw"),
    ("Mango slices", "^Mangos, raw"),
    ("Peanut butter (2 tbsp)", "^Peanut butter, smooth"),
    ("Honey drizzle", "^Honey$"),
    ("Olive oil drizzle", "^Oil, olive"),
    ("Butter pat", "^Butter, salted"),
    ("Bagel with cream cheese", "^Bagels, plain"),
    ("Pancakes with syrup", "^Pancakes, plain|^Pancakes$"),
    ("French toast with syrup", "^French toast"),
    ("Oatmeal with banana", "^Cereals, oats, .*cooked"),
    ("Oatmeal (cooked)", "^Cereals, oats, .*cooked"),
    ("Cereal with milk", "^Cereals ready-to-eat|^Cereal, ready-to-eat"),
    ("Vanilla ice cream scoop", "^Ice creams, vanilla"),
    ("Slice of cheese pizza", "^Pizza, cheese"),
    ("Slice of pepperoni pizza", "^Pizza.*pepperoni"),
    ("Turkey sandwich on wheat bread", "^Turkey sandwich"),
    ("Hummus with pita", "^Hummus"),
    ("White bread slice", "^Bread, white"),
    ("Quinoa (cooked)", "^Quinoa, cooked"),
    ("Tofu, fried", "^Tofu, fried"),
]

/// Popular products and chains' items as people type them, a name and no more, each with a
/// pattern for the "Name [Brand]" that should come first: the brand's own, or the chain's item
/// as USDA lists it.
let products: [(String, String)] = [
    ("big mac", "^Big Mac"), ("whopper", "^Whopper"), ("quarter pounder", "^Quarter Pounder"), ("mcnuggets", "(?i)mcnuggets|chicken nuggets"),
    ("mcchicken", "(?i)mcchicken"), ("egg mcmuffin", "Egg McMUFFIN \\["), ("mcflurry", "McFLURRY"),
    ("chick fil a sandwich", "^CHICK-FIL-A, chicken sandwich"), ("chick fil a nuggets", "(?i)chick-fil-a.*(nugget|strips)|chicken nuggets"),
    ("chipotle chicken", "^Chipotle chicken"), ("starbucks latte", "(?i)latte.*Starbucks"),
    ("starbucks frappuccino", "(?i)frappuccino.*Starbucks"), ("pumpkin spice latte", "(?i)pumpkin spice latte|^Coffee, Latte, flavored"),
    ("subway footlong", "(?i)subway"),
    ("taco bell crunchwrap", "(?i)crunchwrap"), ("crunchy taco", "(?i)taco with beef.*hard shell|taco bell"),
    ("mcdonalds fries", "^McDONALD'S, french fries"), ("kfc chicken", "^KFC"),
    ("glazed donut", "(?i)^doughnuts?,.*glazed|glazed (donut|doughnut)|^Doughnut, yeast type"), ("dominos pizza", "^DOMINO'S"), ("oreos", "(?i)oreo"),
    ("cheerios", "(?i)cheerios"), ("honey nut cheerios", "(?i)honey nut cheerios"), ("frosted flakes", "(?i)frosted flakes"),
    ("doritos", "(?i)doritos"), ("pop tarts", "(?i)pop.tarts"), ("goldfish", "(?i)goldfish"), ("cheez its", "(?i)cheez.its"),
    ("ritz crackers", "(?i)ritz"), ("nutella", "^Nutella"), ("kind bar", "(?i)\\[kind"), ("clif bar", "(?i)\\[clif"),
    ("quest bar", "(?i)\\[quest"), ("rxbar", "(?i)rxbar"), ("fairlife", "(?i)\\[fairlife"), ("premier protein", "(?i)\\[premier protein"),
    ("muscle milk", "(?i)\\[muscle milk"), ("gatorade", "(?i)\\[gatorade"), ("red bull", "(?i)\\[red bull"), ("monster energy", "(?i)\\[monster"),
    ("celsius", "(?i)\\[celsius"), ("la croix", "(?i)\\[la ?croix"), ("coke zero", "(?i)coke zero|coca.cola zero"),
    ("diet coke", "(?i)^diet coke|^Soft drink, cola, diet"), ("sprite", "(?i)\\[sprite"), ("dr pepper", "(?i)dr.? pepper"),
    ("mountain dew", "(?i)mountain dew"),
    ("halo top", "(?i)\\[halo top"), ("ben and jerrys", "(?i)\\[ben & jerry"), ("haagen dazs", "(?i)\\[h.agen.dazs"),
    ("chobani", "(?i)\\[chobani"), ("oikos", "(?i)\\[oikos"), ("siggis", "(?i)\\[siggi"), ("yoplait", "(?i)\\[yoplait"),
    ("activia", "(?i)\\[activia"), ("kraft mac and cheese", "(?i)macaroni.*\\[kraft"), ("velveeta", "(?i)\\[velveeta"), ("spam", "(?i)spam"),
    ("ramen noodles", "(?i)ramen"), ("cup noodles", "(?i)cup noodle"), ("uncrustables", "(?i)uncrustable"), ("hot pockets", "(?i)\\[hot pockets"),
    ("lean cuisine", "(?i)\\[lean cuisine"), ("eggo waffles", "(?i)waffle.*\\[eggo"), ("pringles", "(?i)\\[pringles"), ("lays", "(?i)\\[lay.?s"),
    ("cheetos", "(?i)\\[cheetos"), ("takis", "(?i)\\[takis"), ("skittles", "(?i)skittles"), ("m&ms", "(?i)m&m"), ("snickers", "(?i)snickers"),
    ("reeses", "(?i)\\[reese"), ("kit kat", "(?i)kit ?kat"), ("twix", "(?i)twix"), ("hersheys", "(?i)\\[hershey"), ("pepsi", "(?i)pepsi"),
    ("fanta", "(?i)fanta"), ("7up", "(?i)7.?up"), ("arizona iced tea", "(?i)\\[arizona"), ("vitamin water", "(?i)vitamin ?water"),
    ("body armor", "(?i)body ?armor"), ("liquid iv", "(?i)liquid i\\.?v"), ("ensure", "(?i)\\[ensure"), ("boost", "(?i)^boost"),
    ("core power", "(?i)core power"), ("orgain", "(?i)\\[orgain"), ("ghost protein", "(?i)\\[ghost"),
    ("optimum nutrition whey", "(?i)optimum nutrition"), ("quaker oats", "(?i)\\[quaker"), ("special k", "(?i)special k"),
    ("lucky charms", "(?i)lucky charms"), ("cinnamon toast crunch", "(?i)cinnamon toast crunch"), ("froot loops", "(?i)froot loops"),
    ("raisin bran", "(?i)raisin bran"), ("cap n crunch", "(?i)cap.?n.? crunch"), ("nature valley", "(?i)\\[nature valley"),
    ("kashi", "(?i)\\[kashi"), ("daves killer bread", "(?i)\\[dave.?s killer"), ("wonder bread", "(?i)\\[wonder"),
    ("thomas english muffins", "(?i)english muffin.*\\[thomas"), ("philadelphia cream cheese", "(?i)\\[philadelphia"), ("babybel", "(?i)babybel"),
    ("laughing cow", "(?i)laughing cow"), ("sargento", "(?i)\\[sargento"), ("kerrygold butter", "(?i)\\[kerrygold"),
    ("jif peanut butter", "(?i)\\[jif"), ("skippy", "(?i)\\[skippy"), ("smuckers", "(?i)\\[smucker"), ("heinz ketchup", "(?i)\\[heinz"),
    ("hellmanns mayo", "(?i)\\[hellmann"), ("hidden valley ranch", "(?i)\\[hidden valley"), ("sriracha", "(?i)sriracha"),
    ("franks red hot", "(?i)frank.?s"), ("tabasco", "(?i)tabasco"), ("cholula", "(?i)cholula"), ("oscar mayer bacon", "(?i)bacon.*\\[oscar mayer"),
    ("jimmy dean sausage", "(?i)\\[jimmy dean"), ("hillshire farm", "(?i)\\[hillshire"), ("tyson chicken nuggets", "(?i)nugget.*\\[tyson"),
    ("perdue chicken", "(?i)\\[perdue"), ("beyond burger", "(?i)beyond"), ("impossible burger", "(?i)impossible"),
    ("morningstar", "(?i)morning ?star"), ("amys burrito", "(?i)burrito.*\\[amy"), ("digiorno pizza", "(?i)\\[digiorno"),
    ("totinos pizza rolls", "(?i)\\[totino"), ("stouffers lasagna", "(?i)lasagn.*\\[stouffer"), ("healthy choice", "(?i)\\[healthy choice"),
    ("campbells chicken noodle", "(?i)\\[campbell"), ("progresso", "(?i)\\[progresso"), ("chef boyardee", "(?i)boyardee"),
    ("barilla", "(?i)\\[barilla"), ("raos marinara", "(?i)\\[rao"), ("prego", "(?i)\\[prego"), ("uncle bens rice", "(?i)ben.?s"),
    ("kodiak cakes", "(?i)\\[kodiak"), ("bisquick", "(?i)bisquick"), ("nesquik", "(?i)nesquik"), ("swiss miss", "(?i)swiss miss"),
    ("coffee mate", "(?i)coffee.?mate"), ("international delight", "(?i)\\[international delight"), ("silk almond milk", "(?i)almond.*\\[silk"),
    ("oatly", "(?i)\\[oatly"), ("califia", "(?i)califia"), ("almond breeze", "(?i)almond breeze"), ("lactaid", "(?i)lactaid"),
    ("horizon organic milk", "(?i)milk.*\\[horizon"), ("naked juice", "(?i)\\[naked"), ("tropicana", "(?i)\\[tropicana"),
    ("simply orange", "(?i)\\[simply"), ("capri sun", "(?i)capri.?sun"), ("kool aid", "(?i)kool.?aid"), ("haribo", "(?i)\\[haribo"),
    ("sour patch kids", "(?i)sour patch"), ("swedish fish", "(?i)swedish fish"), ("starburst", "(?i)starburst"), ("milky way", "(?i)milky ?way"),
    ("butterfinger", "(?i)butterfinger"), ("ferrero rocher", "(?i)ferrero"), ("lindt", "(?i)\\[lindt"), ("ghirardelli", "(?i)\\[ghirardelli"),
    ("toblerone", "(?i)toblerone"), ("tic tac", "(?i)tic.?tac"), ("chips ahoy", "(?i)chips ahoy"), ("nutter butter", "(?i)nutter butter"),
    ("fig newtons", "(?i)newton"), ("teddy grahams", "(?i)teddy graham"), ("nilla wafers", "(?i)nilla"), ("triscuit", "(?i)triscuit"),
    ("wheat thins", "(?i)wheat thins"), ("tostitos", "(?i)\\[tostitos"), ("fritos", "(?i)frito"), ("ruffles", "(?i)\\[ruffles"),
    ("sun chips", "(?i)sun ?chips"), ("smartfood popcorn", "(?i)\\[smartfood"), ("skinny pop", "(?i)skinny ?pop"),
    ("pirates booty", "(?i)pirate.?s booty"), ("slim jim", "(?i)slim jim"), ("jack links", "(?i)\\[jack link"), ("chomps", "(?i)\\[chomps"),
    ("larabar", "(?i)l.rabar"), ("luna bar", "(?i)\\[luna"), ("pure protein bar", "(?i)\\[pure protein"), ("built bar", "(?i)\\[built"),
    ("think thin", "(?i)think.?thin"), ("danimals", "(?i)danimals"), ("fage", "(?i)\\[fage"), ("noosa", "(?i)\\[noosa"),
    ("two good", "(?i)\\[two good"), ("talenti", "(?i)\\[talenti"), ("magnum", "(?i)\\[magnum"), ("klondike", "(?i)\\[klondike"),
    ("drumstick", "(?i)drumstick"), ("popsicle", "(?i)popsicle|ice pop"),
]

/// Drinks, produce by its variety, condiments, baking ingredients, spices and foods from the
/// deli and the fish counter as they're typed, each with a pattern for the plain food that
/// should come first: a spirit USDA lists only among "distilled, all (gin, rum, vodka,
/// whiskey)", the scallions for a green onion, the semisweet chocolate for chocolate chips, the
/// squid for calamari.
let kitchen: [(String, String)] = [
    ("beer", "^Alcoholic beverage, beer, regular, all|^Beer$"), ("light beer", "^Alcoholic beverage, beer, light$|^Beer, light$"),
    ("ipa", "^Alcoholic beverages, beer, higher alcohol|^Beer, higher alcohol"), ("lager", "^Alcoholic beverage, beer, regular, all|^Beer$"),
    ("red wine", "^Alcoholic beverage, wine, table, red$|^Wine, red$"), ("white wine", "^Alcoholic beverage, wine, table, white$|^Wine, white$"),
    ("rose wine", "^Alcoholic beverages, wine, rose|^Wine, rose"), ("champagne", "^Wine, sparkling"),
    ("vodka", "^Alcoholic beverage, distilled, vodka|^Vodka$"), ("tequila", "^Tequila$"),
    ("rum", "^Alcoholic beverage, distilled, (rum|all .* 80 proof)|^Rum$"), ("gin", "^Gin$"),
    ("whiskey", "^Alcoholic beverage, distilled, whiskey|^Whiskey$"), ("bourbon", "^Whiskey$"),
    ("scotch", "^Scotch$"), ("brandy", "^Brandy$"),
    ("sake", "^Alcoholic beverage, rice \\(sake\\)|^Wine, rice"), ("pina colada", "^Alcoholic beverage, pina colada|^Pina Colada$"),
    ("hard cider", "hard cider|^Hard cider"),
    ("espresso", "^Beverages, coffee, brewed, espresso|^Coffee, espresso$"), ("hot chocolate", "(?i)hot cocoa|hot chocolate|^Hot chocolate"),
    ("green tea", "^Beverages, tea, green, brewed|^Tea, hot, leaf, green$"), ("herbal tea", "^Beverages, tea, herb|^Tea, hot, herbal"),
    ("chamomile tea", "^Beverages, tea, herb, brewed, chamomile|^Tea, hot, chamomile"), ("iced tea", "^Tea, iced, brewed, black, unsweetened"),
    ("sweet tea", "^Tea, iced, brewed, black, pre-sweetened"), ("lemonade", "^Lemonade|^Beverages, lemonade"), ("apple juice", "^Apple juice"),
    ("cranberry juice", "^Cranberry juice"), ("grapefruit juice", "^Grapefruit juice"), ("tomato juice", "^Tomato juice"),
    ("coconut water", "(?i)coconut water|^Coconut water, unsweetened$"), ("tonic water", "^Beverages, carbonated, tonic water|^Water, tonic$"),
    ("club soda", "^Beverages, carbonated, club soda"), ("ginger ale", "^Beverages, carbonated, ginger ale"),
    ("root beer", "^Beverages, carbonated, root beer"), ("almond milk", "^Almond milk"),
    ("granny smith apple", "^Apples, raw, granny smith"), ("gala apple", "^Apples, raw, gala"), ("fuji apple", "^Apples, raw, fuji"),
    ("roma tomato", "^Tomatoes, red, ripe, raw"), ("cherry tomatoes", "^Tomatoes, red, ripe, raw"), ("russet potato", "^Potatoes, [Rr]usset"),
    ("yukon gold potato", "^Potatoes, (white|flesh)"), ("red potato", "^Potatoes, red"), ("sweet onion", "^Onions, sweet, raw"),
    ("red onion", "^Onions, raw"), ("yellow onion", "^Onions, (raw|yellow)"), ("green onion", "^Onions, spring or scallions"),
    ("scallions", "^Onions, spring or scallions"), ("shallot", "^Shallots, raw"), ("jalapeno", "^Peppers, jalapeno, raw"),
    ("serrano pepper", "^Peppers, serrano, raw"), ("habanero", "^Peppers, hot chili"), ("romaine lettuce", "^Lettuce, cos or romaine"),
    ("arugula", "^Arugula, raw"), ("kale", "^Kale"), ("bok choy", "^Cabbage, chinese \\(pak-choi\\)"), ("napa cabbage", "^Cabbage, napa"),
    ("brussels sprouts", "^Brussels sprouts"), ("butternut squash", "^Squash, winter, butternut"), ("acorn squash", "^Squash, winter, acorn"),
    ("spaghetti squash", "^Squash, winter, spaghetti"), ("zucchini", "^Squash, summer, zucchini"), ("eggplant", "^Eggplant"),
    ("portobello mushroom", "^Mushrooms, portabella"), ("shiitake mushrooms", "^Mushrooms, shiitake"), ("navel orange", "^Oranges, raw, navels"),
    ("clementine", "^Clementines, raw"), ("mandarin", "^Tangerines"), ("pink grapefruit", "^Grapefruit, raw, pink"),
    ("medjool dates", "^Dates, medjool"), ("dried apricots", "^Apricots, dried"), ("raisins", "^Raisins"),
    ("dried cranberries", "^Cranberries, dried"), ("ketchup", "^Catsup|^Ketchup$"), ("mustard", "^Mustard, prepared, yellow"),
    ("yellow mustard", "^Mustard, prepared, yellow"), ("mayo", "^Salad dressing, mayonnaise, regular"),
    ("sriracha", "^Sauce, hot chile, sriracha"), ("hot sauce", "^Sauce, ready-to-serve, pepper or hot"),
    ("soy sauce", "^Soy sauce made from soy and wheat \\(shoyu\\)$"), ("teriyaki sauce", "^Sauce, teriyaki"),
    ("worcestershire sauce", "^Sauce, worcestershire"), ("fish sauce", "^Sauce, fish"), ("oyster sauce", "^Sauce, oyster"),
    ("hoisin sauce", "^Sauce, hoisin"), ("bbq sauce", "^Sauce, barbecue"), ("ranch dressing", "^Salad dressing, ranch dressing, regular"),
    ("caesar dressing", "^Salad dressing, caesar dressing, regular"), ("italian dressing", "^Salad dressing, italian dressing"),
    ("olive oil", "^Oil, olive"), ("avocado oil", "^Oil, avocado"), ("coconut oil", "^Oil, coconut"), ("sesame oil", "^Oil, sesame"),
    ("vegetable oil", "^Oil, (vegetable|soybean|canola)"), ("butter", "^Butter, salted"), ("ghee", "^Butter, Clarified butter \\(ghee\\)"),
    ("honey", "^Honey"), ("maple syrup", "^Syrups, maple"), ("agave", "^Sweetener, syrup, agave"), ("brown sugar", "^Sugars, brown"),
    ("powdered sugar", "^Sugars, powdered"), ("all purpose flour", "^Wheat flour, white, all-purpose"),
    ("whole wheat flour", "^Wheat flour, whole-grain"), ("cornstarch", "^Cornstarch"), ("baking soda", "^Leavening agents, baking soda"),
    ("baking powder", "(?i)baking powder"), ("vanilla extract", "^Vanilla extract"), ("cocoa powder", "^Cocoa, dry powder, unsweetened$"),
    ("chocolate chips", "^(Candies, semisweet chocolate|Chocolate chips)"), ("yeast", "^Leavening agents, yeast"),
    ("breadcrumbs", "^Bread, crumbs, dry, grated, plain"), ("bread crumbs", "^Bread, crumbs, dry, grated, plain"), ("salt", "^Salt, table"),
    ("black pepper", "^Spices, pepper, black"), ("garlic powder", "^Spices, garlic powder"), ("onion powder", "^Spices, onion powder"),
    ("paprika", "^Spices, paprika"), ("cumin", "^Spices, cumin seed"), ("cinnamon", "^Spices, cinnamon"), ("oregano", "^Spices, oregano"),
    ("basil", "^Basil, fresh"), ("cilantro", "^Coriander \\(cilantro\\) leaves"), ("parsley", "^Parsley, fresh"), ("ginger", "^Ginger root, raw"),
    ("ground ginger", "^Spices, ginger, ground"), ("garlic", "^Garlic, raw"), ("turmeric", "^Spices, turmeric"), ("chia seeds", "^Seeds, chia"),
    ("flax seeds", "^Seeds, flaxseed"), ("hemp seeds", "^Seeds, hemp"), ("pumpkin seeds", "^Seeds, pumpkin"),
    ("sunflower seeds", "^Seeds, sunflower"), ("whey protein", "(?i)whey protein"), ("protein powder", "(?i)protein powder"),
    ("fish oil", "^Fish oil"), ("prosecco", "^Wine, sparkling"), ("grape juice", "^Grape juice"),
    ("scallions", "^Onions, spring or scallions"), ("plantain", "^Plantains"), ("leeks", "^Leeks"), ("radishes", "^Radishes, raw"),
    ("artichoke", "^Artichokes"), ("okra", "^Okra"), ("collard greens", "^Collards"), ("swiss chard", "^Chard, swiss"),
    ("snap peas", "^Peas, edible-podded"), ("snow peas", "^Peas, edible-podded"), ("bean sprouts", "^Mung beans, mature seeds, sprouted"),
    ("pesto", "^Sauce, pesto"), ("relish", "^Pickle relish"), ("tartar sauce", "^Sauce, tartar"), ("honey mustard", "(?i)honey mustard"),
    ("enchilada sauce", "^Sauce, enchilada"), ("gravy", "^Gravy, (beef|HEINZ Home Style, savory beef)|^Gravy$"), ("lard", "^Lard"),
    ("margarine", "^Margarine"), ("shortening", "^Shortening,? (vegetable, )?household"), ("cooking spray", "(?i)cooking spray"),
    ("molasses", "^Molasses"), ("corn syrup", "^Syrups, corn, light"), ("cornmeal", "^Cornmeal"),
    ("gelatin", "^Gelatins, dry powder|^Gelatin dessert$"),
    ("frosting", "^Frostings, vanilla"), ("chili powder", "^Spices, chili powder"), ("nutmeg", "^Spices, nutmeg"),
    ("curry powder", "^Spices, curry powder"), ("red pepper flakes", "^Spices, pepper, red or cayenne"),
    ("cayenne pepper", "^Spices, pepper, red or cayenne"), ("taco seasoning", "^Seasoning mix, dry, taco"), ("sesame seeds", "^Seeds, sesame"),
    ("balsamic vinegar", "^Vinegar, balsamic"), ("tahini", "(?i)tahini"), ("kimchi", "^Cabbage, kimchi"), ("sauerkraut", "^Sauerkraut"),
    ("capers", "^Capers"), ("horseradish", "^Horseradish"), ("wasabi", "^Wasabi"), ("miso", "^Miso"), ("tempeh", "^Tempeh"),
    ("oat bran", "^Oat bran"), ("wheat germ", "^Wheat germ"), ("barley", "^Barley, pearled, cooked"), ("bulgur", "^Bulgur, cooked"),
    ("rice cakes", "^Snacks, rice cakes"), ("rice noodles", "^Rice noodles, cooked"), ("soba", "^Noodles, japanese, soba"),
    ("ravioli", "^Ravioli"), ("tortellini", "^Tortellini"), ("bratwurst", "^Bratwurst"), ("chorizo", "^Sausage, pork, chorizo|^Chorizo, cooked"),
    ("pastrami", "^Pastrami, beef|^Beef, cured, pastrami|^Pastrami$"), ("corned beef", "^Beef, cured, corned beef|^Beef, corned"),
    ("liver", "^Beef, variety meats and by-products, liver|^Liver, beef"), ("chicken liver", "^Chicken, liver|^Liver, chicken"), ("lamb", "^Lamb"),
    ("duck", "^Duck, domesticated|^Duck, cooked"), ("venison", "^Game meat, deer|^Venison, cooked"), ("bison", "^Game meat, bison|^Bison, cooked"),
    ("anchovies", "^Fish, anchovy"),
    ("mackerel", "^Fish, mackerel, Atlantic"), ("trout", "^Fish, trout"), ("halibut", "^Fish, halibut"), ("mahi mahi", "^Fish, mahimahi"),
    ("swordfish", "^Fish, swordfish"), ("catfish", "^Fish, catfish"), ("clams", "^Mollusks, clam|^Clams, cooked"),
    ("mussels", "^Mollusks, mussel|^Mussels, cooked"),
    ("oysters", "^Mollusks, oyster|^Oysters, raw"), ("calamari", "^Mollusks, squid|^Calamari, cooked"),
    ("octopus", "^Mollusks, octopus|^Octopus, cooked"), ("crawfish", "^Crustaceans, crayfish|^Crayfish, cooked"),
    ("egg noodles", "^Noodles, egg"), ("whipped topping", "(?i)whipped.*topping|topping"), ("evaporated milk", "^Milk, canned, evaporated"),
    ("buttermilk", "^Milk, buttermilk"), ("eggnog", "^Eggnog|^Eggnog"),
    ("custard", "^Desserts, egg custard|^Egg custards|^Pie, egg custard|^Custard$"),
    ("pudding", "^Puddings|^Pudding, (chocolate|vanilla)"), ("frozen yogurt", "^Frozen yogurts|^Frozen yogurt$"),
]

/// What's ordered at a coffee shop or a bar, each with a pattern for the drink that should come
/// first: FNDDS's latte, margarita or hard seltzer, by its own name or the one it's ordered by
/// ("flat white", "vodka cranberry", "oat milk latte").
let bar: [(String, String)] = [
    ("latte", "^Coffee, Latte$"), ("cappuccino", "^Coffee, Cappuccino$"), ("mocha", "^Coffee, Cafe Mocha$"),
    ("cafe mocha", "^Coffee, Cafe Mocha$"), ("macchiato", "^Coffee, macchiato$"),
    ("americano", "^Coffee, brewed$|^Beverages, coffee, brewed, prepared with tap water"), ("iced latte", "^Coffee, Iced Latte$"),
    ("iced coffee", "^Iced Coffee, brewed$"), ("cold brew", "^Iced Coffee, brewed$"), ("iced mocha", "^Coffee, Iced Cafe Mocha$"),
    ("flat white", "^Coffee, Latte$"), ("nonfat latte", "^Coffee, Latte, nonfat$"), ("oat milk latte", "^Coffee, Latte, with non-dairy milk$"),
    ("decaf latte", "^Coffee, Latte, decaffeinated$"), ("vanilla latte", "^Coffee, Latte, flavored$"),
    ("decaf coffee", "^Coffee, (brewed, )?decaffeinated|^Beverages, coffee, brewed, prepared with tap water, decaffeinated"),
    ("instant coffee", "^Coffee, instant, reconstituted|^Beverages, coffee, instant, regular, prepared with water"),
    ("frappuccino", "(?i)frappuccino|^Frozen coffee drink$"), ("frozen coffee", "^Frozen coffee drink$"),
    ("cafe con leche", "^Coffee, cafe con leche$"), ("turkish coffee", "^Coffee, Turkish"), ("bubble tea", "^Tea, bubble"),
    ("boba", "^Tea, bubble"), ("kombucha", "^Tea, kombucha"), ("ginger tea", "^Tea, ginger"),
    ("black tea", "^Tea, hot, leaf, black$|^Beverages, tea, black, brewed"),
    ("tea with milk", "^Tea, hot, with milk|^Beverages, tea, black, brewed"),
    ("hot chocolate", "^Hot chocolate / cocoa(, made with whole or reduced fat \\(2%\\) milk)?$|^Milk, chocolate beverage, hot cocoa"),
    ("hot cocoa", "^Hot chocolate / cocoa"), ("chocolate milk", "^Chocolate milk$|^Milk, chocolate"), ("strawberry milk", "^Strawberry milk"),
    ("milkshake", "^Milk shake"), ("chocolate milkshake", "^Milk shake.*chocolate$|^Milk shakes, thick chocolate"),
    ("vanilla milkshake", "^Milk shake|^Milk shakes, thick vanilla"), ("smoothie", "^Fruit smoothie"), ("fruit smoothie", "^Fruit smoothie"),
    ("green smoothie", "^Fruit and vegetable smoothie|^Vegetable smoothie"), ("horchata", "^Horchata"), ("eggnog", "^Eggnog"),
    ("margarita", "^Margarita$"), ("frozen margarita", "^Frozen margarita"), ("martini", "^Martini$"), ("mojito", "^Mojito"),
    ("old fashioned", "^Old fashioned"), ("manhattan", "^Manhattan"), ("gin and tonic", "^Gin and tonic"), ("rum and coke", "^Rum and cola"),
    ("whiskey and coke", "^Whiskey and cola"), ("jack and coke", "^Whiskey and cola"), ("vodka soda", "^Vodka and soda"),
    ("vodka tonic", "^Vodka and tonic"), ("vodka cranberry", "^Cape Cod"), ("screwdriver", "^Screwdriver"),
    ("whiskey sour", "^Whiskey sour|^Alcoholic beverage, whiskey sour"), ("bloody mary", "^Bloody Mary"), ("mimosa", "^Mimosa"),
    ("sangria", "^Sangria"), ("moscow mule", "^Moscow mule"), ("white russian", "^White Russian"),
    ("long island iced tea", "^Long Island iced tea"), ("daiquiri", "^Daiquiri|^Alcoholic beverage, daiquiri"), ("mai tai", "^Mai Tai"),
    ("tequila sunrise", "^Tequila Sunrise|^Alcoholic beverage, tequila sunrise"), ("pina colada", "^Pina Colada|^Alcoholic beverage, pina colada"),
    ("cocktail", "^Cocktail$"), ("champagne", "^Wine, sparkling"), ("prosecco", "^Wine, sparkling"), ("sparkling wine", "^Wine, sparkling"),
    ("red wine", "^Wine, red$|^Alcoholic beverage, wine, table, red$"), ("white wine", "^Wine, white$|^Alcoholic beverage, wine, table, white$"),
    ("rose", "^Wine, rose|^Alcoholic beverages, wine, rose"), ("wine", "^Wine, red$|^Alcoholic beverage, wine, table, (all|red)$"),
    ("wine cooler", "^Wine cooler"), ("wine spritzer", "^Wine spritzer"), ("dessert wine", "^Wine, dessert|^Alcoholic beverage, wine, dessert"),
    ("beer", "^Beer$|^Alcoholic beverage, beer, regular, all"), ("light beer", "^Beer, light$|^Alcoholic beverage, beer, light$"),
    ("ipa", "^Beer, higher alcohol|^Alcoholic beverages, beer, higher alcohol"),
    ("craft beer", "^Beer, higher alcohol|^Beer$|^Alcoholic beverage, beer, regular, all"), ("hard seltzer", "^Hard seltzer"),
    ("white claw", "(?i)hard seltzer"), ("hard cider", "^Hard cider"), ("michelada", "^Michelada"), ("vodka", "^Vodka$"), ("whiskey", "^Whiskey$"),
    ("bourbon", "^Whiskey$"), ("scotch", "^Scotch$"), ("gin", "^Gin$"), ("rum", "^Rum$"), ("tequila", "^Tequila$"), ("mezcal", "^Tequila$"),
    ("brandy", "^Brandy$"), ("cognac", "^Brandy$"), ("sake", "^Wine, rice|^Alcoholic beverage, rice \\(sake\\)"), ("liqueur", "^Liqueur$"),
    ("baileys", "^Liqueur, cream|(?i)baileys"), ("jello shot", "^Gelatin shot, alcoholic"), ("shot of tequila", "^Tequila$"),
    ("glass of red wine", "^Wine, red$|^Alcoholic beverage, wine, table, red$"),
    ("pint of beer", "^Beer$|^Alcoholic beverage, beer, regular, all"),
]

/// Dishes as they're cooked, ordered and logged: a sandwich, a burrito, a plate of pad thai, a
/// slice of pie. Each with a pattern for the dish that should come first: FNDDS's, by its own
/// name or the one the catalog keeps for it ("chicken parmesan", "fettuccine alfredo", "tater
/// tots"), or a label's where USDA lists none ("poke bowl").
let dishes: [(String, String)] = [
    ("turkey sandwich", "(?i)turkey.*sandwich|sandwich.*turkey"), ("ham sandwich", "(?i)ham.*sandwich|sandwich.*ham"),
    ("ham and cheese sandwich", "(?i)ham.*cheese.*sandwich|sandwich.*ham.*cheese|(?i)^ham sandwich.*with cheese"),
    ("blt", "(?i)bacon, lettuce|\\bBLT\\b"), ("grilled cheese", "(?i)grilled cheese|cheese sandwich.*grilled"),
    ("grilled cheese sandwich", "(?i)grilled cheese|cheese sandwich.*grilled"),
    ("peanut butter and jelly sandwich", "(?i)peanut butter and jelly sandwich"), ("pb&j", "(?i)peanut butter and jelly"),
    ("tuna sandwich", "(?i)tuna.*sandwich|sandwich.*tuna"), ("tuna melt", "(?i)tuna melt|^Tuna salad sandwich on white, with cheese$"),
    ("egg salad sandwich", "(?i)egg salad sandwich"), ("chicken salad sandwich", "(?i)chicken salad sandwich"),
    ("club sandwich", "(?i)club sandwich|sandwich.*club"), ("reuben", "(?i)reuben"),
    ("philly cheesesteak", "(?i)cheesesteak|cheese steak|steak and cheese"), ("cheesesteak", "(?i)cheesesteak|cheese steak|steak and cheese"),
    ("pulled pork sandwich", "(?i)pulled pork sandwich|pork.*barbecue.*sandwich|pork sandwich"), ("meatball sub", "(?i)meatball.*(sub|sandwich)"),
    ("italian sub", "(?i)(italian|cold cut).*(sub|sandwich)"), ("chicken sandwich", "(?i)chicken.*sandwich"),
    ("fried chicken sandwich", "(?i)chicken.*sandwich.*fried|fried chicken.*sandwich|chicken fillet.*sandwich|crispy chicken"),
    ("grilled chicken sandwich", "(?i)chicken.*sandwich.*grilled|grilled chicken.*sandwich"), ("fish sandwich", "(?i)fish sandwich"),
    ("breakfast sandwich", "(?i)(egg|breakfast).*sandwich|sandwich.*egg"),
    ("bacon egg and cheese", "(?i)bacon.*egg.*cheese|egg.*cheese.*bacon|^Egg sandwich on English muffin, with bacon$"),
    ("sausage egg and cheese", "(?i)sausage.*egg.*cheese|egg.*cheese.*sausage|^Egg sandwich on English muffin, with sausage$"),
    ("egg sandwich", "(?i)egg.*sandwich"), ("cheeseburger", "(?i)^cheeseburger|cheeseburger"), ("hamburger", "(?i)^hamburger"),
    ("double cheeseburger", "(?i)double.*cheeseburger|cheeseburger.*double|2 patties"),
    ("bacon cheeseburger", "(?i)bacon.*cheeseburger|cheeseburger.*bacon"),
    ("veggie burger", "(?i)veggie burger|vegetarian burger|vegetable burger|veggieburger"),
    ("turkey burger", "(?i)turkey burger|turkey.*patt|^Turkey or chicken burger"),
    ("chili dog", "(?i)chili dog|frankfurter.*chili|hot dog.*chili|^Chili hot dog sandwich"), ("corn dog", "(?i)corn ?dog"), ("gyro", "(?i)gyro"),
    ("french dip", "(?i)french dip|roast beef sandwich.*(dipped|au jus|gravy)"), ("sloppy joe", "(?i)sloppy joe"),
    ("quesadilla", "(?i)^quesadilla"), ("chicken quesadilla", "(?i)quesadilla.*chicken|chicken quesadilla"), ("burrito", "(?i)^burrito"),
    ("bean burrito", "(?i)burrito.*bean|bean burrito"), ("chicken burrito", "(?i)burrito.*chicken|chicken burrito"),
    ("breakfast burrito", "(?i)breakfast burrito|burrito.*egg"), ("burrito bowl", "(?i)burrito bowl"), ("taco", "(?i)^taco\\b"),
    ("fish taco", "(?i)taco.*fish|fish taco"), ("chicken taco", "(?i)taco.*chicken|chicken taco"), ("beef taco", "(?i)taco.*(beef|meat)|beef taco"),
    ("enchilada", "(?i)^enchilada"), ("chicken enchilada", "(?i)enchilada.*chicken|chicken enchilada"), ("tamale", "(?i)^tamale"),
    ("nachos", "(?i)^nachos"), ("fajitas", "(?i)^fajita"), ("chicken fajitas", "(?i)fajita.*chicken|chicken fajita"),
    ("chimichanga", "(?i)^chimichanga"), ("tostada", "(?i)^tostada"), ("taquitos", "(?i)^taquito|flauta"), ("lasagna", "(?i)^lasagna"),
    ("spaghetti and meatballs", "(?i)spaghetti.*meatballs|pasta.*meatballs"),
    ("fettuccine alfredo", "(?i)fettuccine.*alfredo|pasta.*(alfredo|cream sauce)"),
    ("chicken alfredo", "(?i)chicken.*alfredo|alfredo.*chicken|pasta.*cream sauce.*(chicken|poultry)"),
    ("mac and cheese", "(?i)^macaroni (and|or noodles with) cheese"), ("ravioli", "(?i)^ravioli"), ("pad thai", "(?i)pad thai"),
    ("lo mein", "(?i)lo mein"), ("chow mein", "(?i)chow mein"), ("fried rice", "(?i)^(rice, )?fried(, |\\s)?rice|^fried rice|rice, fried"),
    ("chicken fried rice", "(?i)fried rice.*chicken|chicken fried rice|rice, fried, with chicken"), ("general tso chicken", "(?i)general tso"),
    ("orange chicken", "(?i)orange chicken"), ("kung pao chicken", "(?i)kung pao"), ("sweet and sour chicken", "(?i)sweet and sour chicken"),
    ("beef and broccoli", "(?i)beef (and|with) broccoli|beef.*vegetables.*(soy|stir)"), ("sesame chicken", "(?i)sesame chicken"),
    ("spring roll", "(?i)spring roll|egg roll|^Roll with meat and/or shrimp, vegetables and rice paper"),
    ("dumplings", "(?i)^dumpling|^Wonton, dumpling or pot sticker"),
    ("potstickers", "(?i)potsticker|dumpling.*(fried|meat)|wonton.*fried|dumpling"), ("wonton soup", "(?i)wonton soup|soup, wonton"),
    ("sushi", "(?i)^sushi"), ("california roll", "(?i)california roll|sushi.*(crab|avocado|vegetable)|^Sushi roll, California$"),
    ("ramen", "(?i)ramen"), ("pho", "(?i)\\bpho\\b"), ("miso soup", "(?i)miso soup|soup, miso"),
    ("chicken noodle soup", "(?i)chicken noodle soup|soup, chicken noodle"), ("tomato soup", "(?i)tomato soup|soup, tomato"),
    ("clam chowder", "(?i)clam chowder|chowder, clam"), ("minestrone", "(?i)minestrone"),
    ("french onion soup", "(?i)onion soup|soup, onion|^Soup, French onion$"), ("chicken pot pie", "(?i)chicken pot ?pie|pot ?pie.*chicken"),
    ("shepherds pie", "(?i)shepherd'?s pie"), ("meatloaf", "(?i)meat ?loaf"), ("pot roast", "(?i)pot roast"),
    ("chicken parmesan", "(?i)chicken parm|^Chicken or turkey parmigiana$"), ("eggplant parmesan", "(?i)eggplant parm"),
    ("chicken tikka masala", "(?i)tikka masala|^Chicken curry$"),
    ("butter chicken", "(?i)butter chicken|chicken.*(makhani|tikka masala)|^Chicken curry$"), ("chicken curry", "(?i)chicken curry|curry.*chicken"),
    ("jambalaya", "(?i)jambalaya"), ("gumbo", "(?i)gumbo"), ("paella", "(?i)paella"), ("risotto", "(?i)risotto"),
    ("stuffed peppers", "(?i)stuffed pepper|pepper.*stuffed"), ("beef stroganoff", "(?i)stroganoff"),
    ("chicken and rice", "(?i)chicken (and|with) rice|rice (and|with) chicken|^Chicken or turkey and rice$"),
    ("rice and beans", "(?i)rice (and|with) beans|beans (and|with) (white )?rice"),
    ("red beans and rice", "(?i)red beans and rice|beans (and|with) rice|(?i)rice and red beans"), ("falafel", "(?i)^falafel"),
    ("caesar salad", "(?i)caesar salad"), ("greek salad", "(?i)greek salad"), ("cobb salad", "(?i)cobb salad"),
    ("chef salad", "(?i)chef'?s? salad"), ("garden salad", "(?i)garden salad|lettuce.*salad|salad.*lettuce|tossed"),
    ("chicken caesar salad", "(?i)caesar salad.*chicken|chicken caesar|^Chicken or turkey caesar garden salad"),
    ("taco salad", "(?i)taco( or tostada)? salad"), ("potato salad", "(?i)^potato salad"), ("macaroni salad", "(?i)macaroni.*salad"),
    ("pasta salad", "(?i)pasta salad|macaroni or pasta salad"), ("tuna salad", "(?i)^tuna salad|^salad.*tuna"), ("egg salad", "(?i)^egg salad"),
    ("chicken salad", "(?i)^chicken salad|^salad.*chicken|chicken.*salad"), ("omelet", "(?i)omelet"),
    ("cheese omelet", "(?i)omelet.*cheese|cheese omelet"),
    ("western omelet", "(?i)omelet.*(western|ham|pepper|vegetable)|western omelet|denver|^Egg omelet or scrambled egg"),
    ("eggs benedict", "(?i)benedict"), ("quiche", "(?i)quiche"), ("frittata", "(?i)frittata|omelet"), ("pancakes", "(?i)^pancake"),
    ("waffles", "(?i)^waffle"), ("french toast", "(?i)^french toast"), ("crepes", "(?i)^crepe"),
    ("biscuits and gravy", "(?i)biscuits? (and|with) gravy"), ("hash browns", "(?i)hash ?brown"), ("home fries", "(?i)home fries|potato.*home fri"),
    ("sweet potato fries", "(?i)sweet potato.*fries"), ("onion rings", "(?i)onion rings"), ("mashed potatoes", "(?i)potato.*mashed|mashed potato"),
    ("baked potato", "(?i)potato.*baked|baked potato"), ("scalloped potatoes", "(?i)scalloped"),
    ("tater tots", "(?i)tater tots|potato (puffs|tots)"), ("mozzarella sticks", "(?i)mozzarella sticks|cheese.*sticks.*fried|fried.*mozzarella"),
    ("buffalo wings", "(?i)wing"), ("chicken wings", "(?i)chicken.*wing"), ("chicken tenders", "(?i)chicken (tenders|strips|fingers)|tenders"),
    ("cheese pizza", "(?i)pizza.*cheese|cheese pizza"), ("calzone", "(?i)calzone"), ("stromboli", "(?i)stromboli|calzone"),
    ("garlic bread", "(?i)garlic bread|bread, garlic"), ("chocolate cake", "(?i)cake, chocolate|chocolate cake"), ("cheesecake", "(?i)cheesecake"),
    ("carrot cake", "(?i)carrot cake|cake.*carrot"), ("apple pie", "(?i)pie, apple|apple pie"), ("pumpkin pie", "(?i)pie, pumpkin|pumpkin pie"),
    ("pecan pie", "(?i)pie, pecan|pecan pie"), ("key lime pie", "(?i)key lime pie|pie.*lime"), ("brownie", "(?i)brownie"),
    ("chocolate chip cookie", "(?i)cookies?, chocolate chip|chocolate chip cookie"), ("oatmeal cookie", "(?i)cookies?, oatmeal|oatmeal cookie"),
    ("sugar cookie", "(?i)cookies?, sugar|sugar cookie"), ("peanut butter cookie", "(?i)cookies?, peanut butter|peanut butter cookie"),
    ("donut", "(?i)doughnut|donut"), ("glazed donut", "(?i)(doughnut|donut).*glazed|glazed (doughnut|donut)|^Doughnut, yeast type$"),
    ("chocolate donut", "(?i)(doughnut|donut).*chocolate|chocolate.*(doughnut|donut)"),
    ("cinnamon roll", "(?i)cinnamon (roll|bun)|sweet roll.*cinnamon"), ("blueberry muffin", "(?i)muffin.*blueberry|blueberry muffin"),
    ("banana bread", "(?i)banana bread|bread, banana"), ("croissant", "(?i)^croissant"), ("danish", "(?i)danish"),
    ("cupcake", "(?i)cupcake|cake.*cupcake"), ("tiramisu", "(?i)tiramisu"),
    ("vanilla ice cream", "(?i)ice creams?, vanilla|vanilla ice cream|^ice cream$"),
    ("chocolate ice cream", "(?i)ice creams?, chocolate|chocolate ice cream"), ("frozen yogurt", "(?i)frozen yogurt"),
    ("sorbet", "(?i)sorbet|sherbet"), ("chocolate pudding", "(?i)pudding.*chocolate|chocolate pudding"),
    ("rice pudding", "(?i)rice pudding|pudding.*rice"), ("jello", "(?i)gelatin|jell-?o"), ("ice cream sandwich", "(?i)ice cream sandwich"),
    ("milkshake", "(?i)milk ?shake|shake"), ("banana split", "(?i)banana split"), ("sundae", "(?i)sundae"), ("churro", "(?i)churro"),
    ("baklava", "(?i)baklava"), ("flan", "(?i)flan"), ("bread pudding", "(?i)bread pudding|pudding, bread"),
    ("apple crisp", "(?i)apple crisp|crisp, apple|apple.*cobbler"), ("peach cobbler", "(?i)cobbler.*peach|peach cobbler"),
    ("funnel cake", "(?i)funnel cake"), ("pound cake", "(?i)pound ?cake|^Cake, pound$"), ("angel food cake", "(?i)angel ?food"),
    ("coffee cake", "(?i)coffee ?cake"), ("chicken soup", "(?i)chicken.*soup|soup.*chicken"),
    ("vegetable soup", "(?i)vegetable soup|soup, vegetable"), ("lentil soup", "(?i)lentil soup|soup, lentil"),
    ("split pea soup", "(?i)pea soup|soup, pea|^Soup, split pea$"), ("black bean soup", "(?i)black bean soup|soup, black bean|soup, bean"),
    ("broccoli cheddar soup", "(?i)broccoli.*(cheese|cheddar).*soup|soup.*broccoli.*chees"), ("potato soup", "(?i)potato soup|soup, potato"),
    ("beef barley soup", "(?i)beef.*barley|barley.*beef"), ("tortilla soup", "(?i)tortilla soup|soup.*tortilla"), ("egg drop soup", "(?i)egg drop"),
    ("hot and sour soup", "(?i)hot and sour"), ("chicken teriyaki", "(?i)teriyaki"), ("teriyaki chicken", "(?i)teriyaki"),
    ("chicken stir fry", "(?i)chicken.*(stir|vegetables)|stir.*chicken"), ("beef stir fry", "(?i)beef.*(stir|vegetables)|stir.*beef"),
    ("vegetable stir fry", "(?i)vegetable.*stir|stir.*vegetable|^Tofu and vegetables, with soy-based sauce$"),
    ("chicken nuggets", "(?i)chicken nuggets"), ("fish and chips", "(?i)fish and chips|fish.*(battered|fried)|(?i)^fish (&|and) chips$"),
    ("fish sticks", "(?i)fish sticks?|^Fish, stick"), ("crab cake", "(?i)crab cake|^Crab, cake$"),
    ("shrimp scampi", "(?i)scampi|^Shrimp in garlic sauce"),
    ("fried shrimp", "(?i)shrimp.*(fried|breaded)"), ("shrimp cocktail", "(?i)shrimp cocktail"),
    ("lobster roll", "(?i)lobster.*(roll|sandwich|salad)"), ("poke bowl", "(?i)poke"),
    ("stuffed cabbage", "(?i)cabbage.*(stuffed|roll)|stuffed cabbage"), ("pierogi", "(?i)pierog"), ("samosa", "(?i)samosa"),
    ("empanada", "(?i)empanada"), ("pupusa", "(?i)pupusa"), ("arepa", "(?i)arepa"), ("hummus", "(?i)^hummus"), ("guacamole", "(?i)^guacamole"),
    ("spinach dip", "(?i)spinach.*dip"), ("queso", "(?i)queso|cheese dip|cheese sauce"), ("salsa", "(?i)^salsa|sauce, salsa"),
    ("bruschetta", "(?i)bruschetta"), ("deviled eggs", "(?i)devil"), ("creamed spinach", "(?i)spinach.*cream|creamed spinach"),
    ("green bean casserole", "(?i)green bean casserole|beans.*casserole"), ("sweet potato casserole", "(?i)sweet potato.*(casserole|candied)"),
    ("stuffing", "(?i)stuffing|dressing"), ("cornbread", "(?i)corn ?bread"), ("collard greens", "(?i)collard"),
    ("baked ziti", "(?i)ziti|baked.*pasta|pasta.*baked|^Pasta with tomato-based sauce and cheese$"),
    ("stuffed shells", "(?i)stuffed shells|shells.*stuffed|manicotti|pasta.*cheese.*filled"), ("manicotti", "(?i)manicotti"),
    ("gnocchi", "(?i)gnocchi"), ("carbonara", "(?i)carbonara|^Pasta with cream sauce and meat"),
    ("spaghetti bolognese", "(?i)spaghetti.*meat sauce|pasta.*meat sauce|bolognese|^Pasta with tomato-based sauce and meat"),
    ("penne vodka", "(?i)vodka sauce|penne.*vodka|pasta.*vodka"), ("tuna casserole", "(?i)tuna.*casserole|tuna noodle"),
    ("chicken casserole", "(?i)chicken.*casserole"), ("enchiladas", "(?i)^enchilada"), ("carnitas", "(?i)carnitas|pork.*(shredded|pulled)"),
    ("carne asada", "(?i)carne asada|beef.*steak"), ("al pastor", "(?i)pastor"), ("huevos rancheros", "(?i)huevos rancheros"),
    ("chilaquiles", "(?i)chilaquiles"), ("elote", "(?i)elote|corn.*(mexican|mayonnaise|cotija)"), ("pozole", "(?i)pozole"),
    ("menudo", "(?i)menudo"), ("chicken shawarma", "(?i)shawarma"), ("kebab", "(?i)kebab|kabob"), ("tabbouleh", "(?i)tabbouleh|tabouli"),
    ("biryani", "(?i)biryani"), ("dal", "(?i)\\bdal\\b|dahl|lentil"), ("naan", "(?i)^naan|bread, naan"), ("saag paneer", "(?i)paneer"),
    ("chana masala", "(?i)chana|chickpea.*(curry|sauce)"), ("bibimbap", "(?i)bibimbap"), ("bulgogi", "(?i)bulgogi"),
    ("kimchi fried rice", "(?i)kimchi.*rice|fried rice"), ("tonkatsu", "(?i)katsu|pork.*cutlet.*(breaded|fried)"), ("tempura", "(?i)tempura"),
    ("edamame", "(?i)edamame"), ("seaweed salad", "(?i)seaweed"),
]

/// Produce, herbs, fish and juice said to be fresh, which USDA calls raw: a tenth list.
let fresh: [(String, String)] = [
    ("fresh spinach", "^Spinach, raw"), ("fresh basil", "^Basil, fresh"), ("fresh cilantro", "^Coriander \\(cilantro\\) leaves, raw"),
    ("fresh ginger", "^Ginger root, raw"), ("fresh ginger root", "^Ginger root, raw"), ("fresh garlic", "^Garlic, raw"),
    ("fresh parsley", "^Parsley, fresh"), ("fresh mint", "^(Peppermint|Spearmint), fresh"), ("fresh dill", "^Dill weed, fresh"),
    ("fresh thyme", "^Thyme, fresh"), ("fresh rosemary", "^Rosemary, fresh"), ("fresh chives", "^Chives, raw"),
    ("fresh strawberries", "^Strawberries, raw"), ("fresh blueberries", "^Blueberries, raw"), ("fresh raspberries", "^Raspberries, raw"),
    ("fresh blackberries", "^Blackberries, raw"), ("fresh cranberries", "^Cranberries, raw"), ("fresh pineapple", "^Pineapple, raw"),
    ("fresh mango", "^Mangos, raw"), ("fresh peaches", "^Peaches, yellow, raw"), ("fresh cherries", "^Cherries, sweet, raw"),
    ("fresh figs", "^Figs, raw"), ("fresh apricots", "^Apricots, raw"), ("fresh plums", "^Plums, raw"), ("fresh apple", "^Apples, raw"),
    ("fresh pear", "^Pears, raw"), ("fresh banana", "^Bananas, raw"), ("fresh orange", "^Oranges, raw"), ("fresh lemon", "^Lemons, raw"),
    ("fresh lime", "^Limes, raw"), ("fresh grapefruit", "^Grapefruit, raw"), ("fresh grapes", "^Grapes, .*raw"),
    ("fresh watermelon", "^Watermelon, raw"), ("fresh cantaloupe", "^Melons, cantaloupe, raw"), ("fresh papaya", "^Papayas, raw"),
    ("fresh kiwi", "^Kiwifruit, green, raw"), ("fresh avocado", "^Avocados, raw"), ("fresh coconut", "^Nuts, coconut meat, raw"),
    ("fresh tomatoes", "^Tomatoes, red, ripe, raw"), ("fresh tomato", "^Tomatoes, red, ripe, raw"),
    ("fresh corn", "^Corn, sweet, (white|yellow), raw"), ("fresh green beans", "^Beans, snap, green, raw"), ("fresh peas", "^Peas, green, raw"),
    ("fresh broccoli", "^Broccoli, raw"), ("fresh cauliflower", "^Cauliflower, raw"), ("fresh carrots", "^Carrots, raw"),
    ("fresh mushrooms", "^Mushrooms, white, raw"), ("fresh jalapeno", "^Peppers, jalapeno, raw"),
    ("fresh zucchini", "^Squash, summer, zucchini, includes skin, raw"), ("fresh onion", "^Onions, raw"), ("fresh cabbage", "^Cabbage, raw"),
    ("fresh beets", "^Beets, raw"), ("fresh asparagus", "^Asparagus, raw"), ("fresh cucumber", "^Cucumber, (peeled|with peel), raw"),
    ("fresh bell pepper", "^Peppers, sweet, .*raw"), ("fresh kale", "^Kale, raw"), ("fresh lettuce", "^Lettuce, .*raw"),
    ("fresh celery", "^Celery, raw"), ("fresh eggplant", "^Eggplant, raw"), ("fresh okra", "^Okra, raw"), ("fresh radishes", "^Radishes, raw"),
    ("fresh arugula", "^Arugula, raw"), ("fresh shallots", "^Shallots, raw"), ("fresh leeks", "^Leeks, \\(bulb and lower leaf-portion\\), raw"),
    ("fresh fennel", "^Fennel, bulb, raw"), ("fresh brussels sprouts", "^Brussels sprouts, raw"), ("fresh pumpkin", "^Pumpkin, raw"),
    ("fresh potatoes", "^Potatoes, .*flesh and skin, raw"), ("fresh lemon juice", "^Lemon juice, raw"), ("fresh lime juice", "^Lime juice, raw"),
    ("fresh orange juice", "^Orange juice, raw"), ("fresh squeezed orange juice", "(?i)orange juice"), ("fresh salmon", "^Fish, salmon, .*raw"),
    ("fresh salmon fillet", "^Fish, salmon, .*raw"), ("fresh tuna", "^Fish, tuna, fresh|^Fish, tuna, raw"),
    ("fresh cod", "^Fish, cod, Atlantic, raw"),
    ("fresh shrimp", "^Crustaceans, shrimp, raw"), ("fresh scallops", "^Mollusks, scallop, .*raw"),
    ("fresh oysters", "^Mollusks, oyster, .*raw|^Oysters, raw"),
    ("fresh salsa", "^Salsa"), ("fresh mozzarella", "(?i)mozzarella"), ("fresh pasta", "^Pasta, fresh-refrigerated"),
    ("fresh eggs", "^Egg, whole, raw, fresh"), ("fresh bread", "^Bread, (white|wheat)"), ("fresh fruit salad", "(?i)fruit salad"),
    ("fresh milk", "^Milk, (whole|reduced fat|lowfat)"), ("fresh strawberry", "^Strawberries, raw"), ("fresh blueberry", "^Blueberries, raw"),
    ("fresh herbs", "(?i)herb"), ("fresh pineapple chunks", "^Pineapple, raw"), ("fresh sliced tomato", "^Tomatoes, red, ripe, raw"),
    ("fresh baby spinach", "^Spinach, (raw|baby)"), ("fresh chopped onion", "^Onions, raw"), ("fresh berries", "(?i)berries"),
]

/// Grains, vegetables, meat and fish said to be cooked: an eleventh list.
let cookedFoods: [(String, String)] = [
    ("cooked rice", "^Rice, white, long-grain, regular, enriched, cooked"),
    ("cooked white rice", "^Rice, white, long-grain, regular, enriched, cooked"), ("cooked brown rice", "^Rice, brown, .*cooked"),
    ("cooked jasmine rice", "^Rice, white, long-grain, regular, enriched, cooked"),
    ("cooked basmati rice", "^Rice, white, long-grain, regular, enriched, cooked"), ("cooked wild rice", "^Wild rice, cooked"),
    ("cooked chicken", "^Chicken, broilers or fryers, meat only, cooked, roasted|^Chicken, cooked"),
    ("cooked chicken breast", "^Chicken, broilers or fryers, breast, meat only, cooked, roasted|^Chicken breast, cooked"),
    ("cooked chicken thigh", "^Chicken, broilers or fryers, thigh, meat only, cooked, roasted|^Chicken thigh, cooked"),
    ("cooked ground chicken", "^Chicken, ground, .*cooked"), ("cooked chicken wings", "^Chicken, .*wing.*cooked|^Chicken wing, cooked"),
    ("cooked pasta", "^Pasta, cooked"), ("cooked spaghetti", "^Pasta, cooked"), ("cooked macaroni", "^Pasta, cooked"),
    ("cooked noodles", "^Noodles, egg, enriched, cooked"), ("cooked egg noodles", "^Noodles, egg, enriched, cooked"),
    ("cooked rice noodles", "^Rice noodles, cooked"), ("cooked quinoa", "^Quinoa, cooked"),
    ("cooked oatmeal", "^(Cereals, oats, .*cooked with water|Oatmeal, regular or quick, made with water)"),
    ("cooked oats", "^(Cereals, oats, .*cooked with water|Oatmeal, regular or quick, made with water)"), ("cooked couscous", "^Couscous, cooked"),
    ("cooked barley", "^Barley, pearled, cooked"), ("cooked bulgur", "^Bulgur, cooked"), ("cooked millet", "^Millet, cooked"),
    ("cooked grits", "^(Grits|Cereals, corn grits.*cooked)"), ("cooked spinach", "^Spinach, cooked, boiled"),
    ("cooked broccoli", "^Broccoli, cooked"), ("cooked carrots", "^Carrots, cooked"), ("cooked potato", "^Potatoes, (boiled|baked)"),
    ("cooked sweet potato", "^Sweet potato, cooked"), ("cooked green beans", "^Beans, snap, green, cooked, boiled"),
    ("cooked peas", "^Peas, green, cooked"), ("cooked corn", "^Corn, sweet, (yellow|white), cooked"), ("cooked cabbage", "^Cabbage, cooked"),
    ("cooked kale", "^Kale, cooked"), ("cooked mushrooms", "^Mushrooms, white, cooked"), ("cooked onions", "^Onions, cooked"),
    ("cooked zucchini", "^Squash, summer, zucchini, includes skin, cooked"), ("cooked cauliflower", "^Cauliflower, cooked"),
    ("cooked asparagus", "^Asparagus, cooked"), ("cooked brussels sprouts", "^Brussels sprouts, cooked"),
    ("cooked squash", "^Squash, (winter|summer), .*cooked"), ("cooked butternut squash", "^Squash, winter, butternut, cooked"),
    ("cooked collard greens", "^Collards, cooked"), ("cooked eggplant", "^Eggplant, cooked"), ("cooked beets", "^Beets, cooked"),
    ("cooked okra", "^Okra, cooked"), ("cooked lentils", "^Lentils, mature seeds, cooked"),
    ("cooked black beans", "^Beans, black, mature seeds, cooked"), ("cooked beans", "^Beans, (black|pinto), mature seeds, cooked"),
    ("cooked chickpeas", "^Chickpeas .*cooked"), ("cooked kidney beans", "^Beans, kidney, red, mature seeds, cooked"),
    ("cooked pinto beans", "^Beans, pinto, mature seeds, cooked"), ("cooked ground beef", "^Beef, ground, .*cooked"),
    ("cooked beef", "^Beef, .*cooked"), ("cooked steak", "^Beef, .*steak.*cooked|^Steak, cooked"),
    ("cooked pork", "^Pork, fresh, (composite|loin).*cooked|^Pork, cooked"),
    ("cooked pork chop", "^Pork, fresh, loin.*chops.*cooked|^Pork, chop"),
    ("cooked pork tenderloin", "^Pork, fresh, loin, tenderloin.*cooked|^Pork, tenderloin"),
    ("cooked ground pork", "^Pork, fresh, ground, cooked|^Pork, ground"), ("cooked bacon", "^Pork, cured, bacon, cooked|^Bacon, cooked"),
    ("cooked ham", "^(Ham|Pork, cured, ham)"), ("cooked sausage", "^(Sausage|Pork sausage).*cooked"), ("cooked lamb", "^Lamb, .*cooked"),
    ("cooked veal", "^Veal, .*cooked"), ("cooked turkey", "^Turkey, whole, meat only, cooked|^Turkey, cooked"),
    ("cooked turkey breast", "^Turkey, whole, breast, meat only, cooked"), ("cooked ground turkey", "^Turkey, [Gg]round, cooked"),
    ("cooked duck", "^Duck, .*cooked"), ("cooked egg", "^Egg, whole, cooked"), ("cooked eggs", "^Egg, whole, cooked"),
    ("cooked salmon", "^Fish, salmon, .*cooked|^Fish, salmon, (baked|grilled|steamed|cooked)"),
    ("cooked shrimp", "^Crustaceans, shrimp, cooked|^Shrimp, cooked"),
    ("cooked tilapia", "^Fish, tilapia, cooked|^Fish, tilapia, (baked|grilled|steamed|cooked)"),
    ("cooked cod", "^Fish, cod, (Pacific|Atlantic), cooked|^Fish, cod, cooked"), ("cooked tuna", "^Fish, tuna, .*cooked"),
    ("cooked trout", "^Fish, trout, .*cooked"),
    ("cooked halibut", "^Fish, halibut, .*cooked"), ("cooked catfish", "^Fish, catfish, .*cooked"),
    ("cooked crab", "^Crustaceans, crab, .*cooked|^Crab, cooked"),
    ("cooked lobster", "^Crustaceans, lobster, northern, cooked|^Lobster, cooked"), ("cooked scallops", "^Mollusks, scallop.*cooked"),
    ("cooked tofu", "^Tofu"),
    ("cooked edamame", "^Edamame"),
]

/// Dishes known by their own names, from other kitchens than the diner's, with a few plurals: a
/// twelfth list. The last patterns only ask for a food of that name, where the catalogs have
/// no plain one.
let world: [(String, String)] = [
    ("pho", "^Soup, pho"), ("bibimbap", "^Bibimbap"), ("tikka masala", "^Chicken curry"), ("chicken tikka masala", "^Chicken curry"),
    ("butter chicken", "^Chicken curry"), ("saag paneer", "^Palak Paneer"), ("palak paneer", "^Palak Paneer"), ("samosa", "^Samosa"),
    ("falafel", "^Falafel"), ("gyro", "^Gyro sandwich"), ("pierogi", "^Pierogi"), ("borscht", "^Soup, borscht"), ("ramen", "^Ramen bowl"),
    ("miso soup", "^Soup, miso"), ("empanada", "^Empanada"), ("arepa", "(?i)arepa"), ("pupusa", "^Pupusa"), ("tamale", "^Tamale"),
    ("churro", "^Churros"), ("flan", "^Flan"), ("tres leches", "^Cake, tres leche"), ("baklava", "^Baklava"), ("tiramisu", "^Tiramisu"),
    ("gelato", "^Gelato"), ("crepe", "^Crepe"), ("quiche", "^Quiche"), ("ratatouille", "^Ratatouille"), ("paella", "^Paella"),
    ("gazpacho", "^Soup, gazpacho"), ("plantains", "^Plantains"), ("fried plantains", "^Plantains, .*fried"), ("congee", "^Congee"),
    ("bao", "^Bao bun"), ("potstickers", "^Wonton, dumpling or pot sticker"), ("gyoza", "^Wonton, dumpling or pot sticker"),
    ("dumplings", "^Wonton, dumpling or pot sticker"), ("lo mein", "^Lo mein"), ("chow mein", "^Chow mein"),
    ("kung pao chicken", "^Kung pao chicken"), ("general tso chicken", "^General Tso chicken"), ("sweet and sour pork", "^Sweet and sour pork"),
    ("sweet and sour chicken", "^Sweet and sour chicken"), ("egg foo young", "^Egg foo yung"),
    ("teriyaki chicken", "^Chicken or turkey with teriyaki"), ("tteokbokki", "^Dukboki"), ("biryani", "^Biryani"),
    ("chicken biryani", "^Biryani with chicken"), ("naan", "^Bread, naan"), ("roti", "^Bread, chapati or roti"),
    ("chapati", "^Bread, chapati or roti"), ("dosa", "^Dosa"), ("idli", "^Idli"), ("pakora", "^Pakora"), ("chai", "^Tea, hot, with milk"),
    ("masala chai", "^Tea, hot, with milk"), ("hummus", "^Hummus"), ("tabbouleh", "^Tabbouleh"), ("kebab", "shish kabob"),
    ("shish kebab", "shish kabob"), ("spanakopita", "^Spanakopita"), ("dolmas", "rape leaves"), ("stuffed grape leaves", "rape leaves"),
    ("gnocchi", "^Gnocchi"), ("carbonara", "^Pasta with cream sauce and meat"), ("bruschetta", "^Bruschetta"), ("minestrone", "^Soup, minestrone"),
    ("ceviche", "^Ceviche"), ("cubano", "^Cuban sandwich"), ("pozole", "^Soup, pozole"), ("menudo", "^Menudo"), ("carnitas", "^Pork, carnitas"),
    ("chilaquiles", "^Chilaquiles"), ("huevos rancheros", "^Huevos rancheros"), ("enchiladas", "^Enchilada"), ("chile relleno", "^Chiles rellenos"),
    ("mole", "^Mole sauce"), ("horchata", "^Horchata"), ("pan dulce", "^Pan dulce"), ("arroz con gandules", "Arroz con grandules"),
    ("wonton soup", "^Soup, wonton"), ("egg drop soup", "^Soup, egg drop"), ("hot and sour soup", "^Soup, hot and sour"),
    ("salmon sashimi", "^Fish, salmon, .*raw"), ("tuna sashimi", "^Fish, tuna, .*raw"), ("raita", "(?i)raita"), ("mapo tofu", "(?i)ma.?po"),
    ("kimchi", "^(Kimchi|Cabbage, kimchi)"), ("edamame", "^Edamame"), ("udon", "(?i)udon"), ("sodas", "^(Soft drink|Beverages, carbonated)"),
    ("cokes", "^(Soft drink, cola|Beverages, carbonated, cola)"), ("lagers", "(?i)beer"), ("french fry", "^Potato(es)?, french fri"),
    ("sweet potato fry", "^Sweet potato fries"), ("tzatziki", "(?i)tzatziki"), ("shawarma", "(?i)shawarma"), ("bulgogi", "(?i)bulgogi"),
]

/// Foods as they're commonly misspelt, each with the right spelling: the search for one should
/// find what the search for the other does.
let misspellings: [(wrong: String, right: String)] = [
    ("quesedilla", "quesadilla"), ("burito", "burrito"), ("tikka massala", "tikka masala"), ("humus", "hummus"), ("hummas", "hummus"),
    ("fettucini alfredo", "fettuccine alfredo"), ("ceasar salad", "caesar salad"), ("cesar salad", "caesar salad"), ("sandwhich", "sandwich"),
    ("expresso", "espresso"), ("zuchini", "zucchini"), ("zuccini", "zucchini"), ("brocolli", "broccoli"), ("brocoli", "broccoli"),
    ("avacado", "avocado"), ("avocato", "avocado"), ("tomatoe", "tomato"), ("potatoe", "potato"), ("sweet potatoe", "sweet potato"),
    ("bannana", "banana"), ("bananna", "banana"), ("strawbery", "strawberry"), ("strawberrys", "strawberries"), ("rasberry", "raspberry"),
    ("rasberries", "raspberries"), ("blueberrys", "blueberries"), ("yoghurt", "yogurt"), ("yogert", "yogurt"), ("omlet", "omelet"),
    ("omlette", "omelette"), ("spagetti", "spaghetti"), ("spaghetti bolognaise", "spaghetti bolognese"), ("lasagne", "lasagna"),
    ("lasanga", "lasagna"), ("parmesean", "parmesan"), ("parmasean", "parmesan"), ("mozarella", "mozzarella"), ("mozzerella", "mozzarella"),
    ("guacamoli", "guacamole"), ("tortila", "tortilla"), ("jalepeno", "jalapeno"), ("chipolte", "chipotle"), ("siracha", "sriracha"),
    ("worchestershire sauce", "worcestershire sauce"), ("cappucino", "cappuccino"), ("capuccino", "cappuccino"), ("machiato", "macchiato"),
    ("frappachino", "frappuccino"), ("smoothy", "smoothie"), ("sherbert", "sherbet"), ("pistacio", "pistachio"), ("pistachos", "pistachios"),
    ("almound", "almond"), ("cashu", "cashew"), ("margerine", "margarine"), ("mayonaise", "mayonnaise"), ("mayonnase", "mayonnaise"),
    ("catsup", "ketchup"), ("ketsup", "ketchup"), ("vinagrette", "vinaigrette"), ("ceral", "cereal"), ("bagle", "bagel"),
    ("crossiant", "croissant"), ("croisant", "croissant"), ("biscut", "biscuit"), ("doughnut", "donut"), ("wafle", "waffle"),
    ("pankcake", "pancake"), ("pancaks", "pancakes"), ("sausauge", "sausage"), ("bolonga", "bologna"), ("baloney", "bologna"), ("salomi", "salami"),
    ("proscuitto", "prosciutto"), ("tilapa", "tilapia"), ("salman", "salmon"), ("shrip", "shrimp"), ("califlower", "cauliflower"),
    ("cauliflour", "cauliflower"), ("cucmber", "cucumber"), ("letuce", "lettuce"), ("lettus", "lettuce"), ("spinich", "spinach"),
    ("asparagas", "asparagus"), ("egplant", "eggplant"), ("brussel sprouts", "brussels sprouts"), ("edemame", "edamame"), ("quinua", "quinoa"),
    ("cous cous", "couscous"), ("barly", "barley"), ("lentles", "lentils"), ("chick peas", "chickpeas"), ("garbonzo beans", "garbanzo beans"),
    ("rasins", "raisins"), ("cranberrys", "cranberries"), ("pinapple", "pineapple"), ("watermellon", "watermelon"), ("cantalope", "cantaloupe"),
    ("cantelope", "cantaloupe"), ("grapefruite", "grapefruit"), ("tangarine", "tangerine"), ("blackberrys", "blackberries"),
    ("chicken brest", "chicken breast"), ("chiken breast", "chicken breast"), ("chicken thighs", "chicken thigh"), ("grond beef", "ground beef"),
    ("ground beaf", "ground beef"), ("turky", "turkey"), ("stake", "steak"), ("porkchop", "pork chop"), ("hamberger", "hamburger"),
    ("cheesburger", "cheeseburger"), ("hot dogs", "hot dog"), ("french frys", "french fries"), ("mash potatoes", "mashed potatoes"),
    ("mashed potatos", "mashed potatoes"), ("scrambeled eggs", "scrambled eggs"), ("hard boild egg", "hard boiled egg"),
    ("peanutbutter", "peanut butter"), ("peanut buter", "peanut butter"), ("cream chese", "cream cheese"), ("cottage chese", "cottage cheese"),
    ("chedder cheese", "cheddar cheese"), ("swis cheese", "swiss cheese"), ("greek yogert", "greek yogurt"), ("oatmeel", "oatmeal"),
    ("granola barr", "granola bar"), ("protien shake", "protein shake"), ("protien bar", "protein bar"), ("whey protien", "whey protein"),
    ("orange juce", "orange juice"), ("apple juce", "apple juice"), ("lemonaid", "lemonade"), ("ice tea", "iced tea"), ("coffe", "coffee"),
    ("expresso shot", "espresso shot"), ("choclate", "chocolate"), ("chocolat chip cookie", "chocolate chip cookie"), ("brownie", "brownie"),
    ("cheescake", "cheesecake"), ("tiramasu", "tiramisu"), ("macaroni and chese", "macaroni and cheese"), ("mac n chese", "mac n cheese"),
    ("chicken noodel soup", "chicken noodle soup"), ("tomatoe soup", "tomato soup"), ("clam chowda", "clam chowder"),
    ("ceasar dressing", "caesar dressing"), ("ranch dresing", "ranch dressing"), ("bbq sause", "bbq sauce"), ("soy sause", "soy sauce"),
    ("terriyaki chicken", "teriyaki chicken"), ("general tsos chicken", "general tso chicken"), ("kung pow chicken", "kung pao chicken"),
    ("pad tai", "pad thai"), ("sushi role", "sushi roll"), ("california role", "california roll"), ("gyro sandwhich", "gyro sandwich"),
    ("fallafel", "falafel"), ("tabouli", "tabbouleh"), ("baclava", "baklava"), ("canoli", "cannoli"),
    // Drinks and dishes by names few foods say: a word that is a plain food's whole name is one
    // a misspelling is read as.
    ("screwdrirer", "screwdriver"), ("screwdrivr", "screwdriver"), ("screwdiver", "screwdriver"), ("manhatten", "manhattan"),
    ("americno", "americano"), ("ameriacno", "americano"), ("mezcall", "mezcal"), ("prosseco", "prosecco"), ("fappuccino", "frappuccino"),
    ("negronni", "negroni"), ("cosmopolitian", "cosmopolitan"), ("liquorice", "licorice"), ("churos", "churros"), ("mortadela", "mortadella"),
    ("baklva", "baklava"), ("falafal", "falafel"), ("empanda", "empanada"), ("paela", "paella"), ("spanikopita", "spanakopita"),
    ("kilbasa", "kielbasa"), ("lolipop", "lollipop"), ("popcicle", "popsicle"), ("wasabe", "wasabi"), ("caviare", "caviar"),
    ("samossa", "samosa"), ("cornstach", "cornstarch"),
]

/// Sweets, snacks and what's bought at a bakery counter, by the names they're asked for: a
/// thirteenth list.
let sweets: [(String, String)] = [
    ("milk chocolate", "^(Candies, milk chocolate|Chocolate candy)$"), ("chocolate milk", "^(Chocolate milk|Milk, chocolate)"),
    ("white chocolate", "^(Candies, white chocolate|White chocolate candy)"), ("dark chocolate", "^(Chocolate, dark|Dark chocolate candy)"),
    ("chocolate bar", "^(Candies, milk chocolate|Chocolate candy)$"), ("candy bar", "^(Chocolate candy|Candies, )"),
    ("candy", "^(Candy$|Candies, )"), ("peanut butter cup", "(?i)peanut butter (filled|cups)"),
    ("peanut butter cups", "(?i)peanut butter (filled|cups)"), ("fudge", "^(Candies, fudge|Chocolate candy, fudge)"),
    ("truffles", "^Candies, truffles"), ("gummy bears", "^(Candy, gummy|Candies, gumdrops)"), ("gummies", "^(Candy, gummy|Candies, gumdrops)"),
    ("jelly beans", "^Candies, jellybeans"), ("licorice", "^Candy, licorice"), ("lollipop", "^(Candy, lollipop|Candies, hard)"),
    ("marshmallows", "^(Candies, marshmallows|Candy, marshmallow)"), ("caramels", "^(Candies, caramels|Candy, caramel)"),
    ("toffee", "^Candies, toffee"), ("cotton candy", "^Candy, cotton"), ("hard candy", "^(Candies, hard|Candy, hard)"),
    ("taffy", "^(Candies, taffy|Candy, taffy)"), ("mints", "^Candy, mint"), ("gum", "^Chewing gum"), ("chewing gum", "^Chewing gum"),
    ("chocolate covered almonds", "^Almonds, chocolate covered candy"), ("kettle corn", "^Popcorn, .*kettle|(?i)^kettle corn"),
    ("air popped popcorn", "^(Snacks, popcorn, air-popped|Popcorn, air-popped)"), ("microwave popcorn", "^Popcorn, microwave"),
    ("caramel corn", "^(Popcorn, caramel coated|Snacks, popcorn, caramel-coated)"), ("movie theater popcorn", "^Popcorn, movie theater"),
    ("tortilla chips", "^(Snacks, tortilla chips|Tortilla chips)"), ("corn chips", "^(Snacks, corn-based|Corn chips)"),
    ("cheese puffs", "^(Cheese flavored corn snacks|Snacks, corn-based, extruded, puffs or twists, cheese)"),
    ("veggie straws", "^Vegetable chips|(?i)veggie straws"), ("veggie chips", "^(Vegetable chips|Snacks, vegetable chips)"),
    ("pork rinds", "^Snacks, pork skins"), ("plantain chips", "^Plantain chips"), ("sweet potato chips", "^Sweet potato chips"),
    ("pita chips", "^Snacks, pita chips"), ("protein bar", "^Nutrition bar or meal replacement bar"),
    ("energy bar", "^Nutrition bar or meal replacement bar"), ("granola bar", "^(Snacks, granola bars|Cereal or Granola bar)"),
    ("cereal bar", "^(Cereal or Granola bar|Snacks, granola bar)"), ("fruit snacks", "^(Candy, fruit snacks|Snacks, fruit leather)"),
    ("fruit roll up", "^(Candy, fruit leather|Snacks, fruit leather)"), ("toaster pastry", "^Toaster pastries"),
    ("saltines", "^Crackers, saltines"), ("graham crackers", "^(Graham crackers|Crackers, graham)"),
    ("animal crackers", "^Cookies, animal crackers"), ("vanilla wafers", "^Cookie, vanilla wafer"), ("biscotti", "^Cookie, biscotti"),
    ("shortbread", "^Cookie, shortbread"), ("macaroon", "^Cookie, macaroon"), ("macaron", "(?i)macaron(s)?( |$)"),
    ("macarons", "(?i)macaron(s)?( |$)"), ("smores", "(?i)s.?mores?"), ("donut holes", "^Doughnut holes"), ("bran muffin", "^Muffins?, .*bran"),
    ("danish", "^Danish pastry"), ("chocolate croissant", "^Croissant, chocolate"), ("tapioca pudding", "^Puddings?, tapioca"),
    ("creme brulee", "^Creme brulee"), ("cobbler", "^Cobbler"), ("eclair", "^Cream puff, eclair"), ("cream puff", "^Cream puff, eclair"),
    ("funnel cake", "^Funnel cake"), ("snack mix", "^(Snack mix|Snacks, trail mix|Snacks, oriental mix)"), ("trail mix", "^Snacks, trail mix"),
    ("popsicle", "^Popsicle"), ("ice cream cone", "^Ice cream cone"), ("frozen yogurt", "^Frozen yogurt"), ("sorbet", "^Sorbet"),
    ("jello", "^Gelatin dessert"), ("cookie dough", "^Cookies, .*dough"), ("lemon bar", "^Cookie, lemon bar"), ("rice cake", "^Snacks, rice cakes"),
    ("peanut brittle", "^(Candies, peanut brittle|Candy, peanut brittle)"), ("gumdrops", "^Candies, gumdrops"),
    ("butterscotch", "^Candies, butterscotch"), ("nougat", "^(Candies, nougat|Candy, nougat)"), ("churros", "^Churros"), ("beignet", "^Beignet"),
    ("soft pretzel", "^Pretzels, soft"), ("nachos with cheese", "^(Nachos, cheese only|Fast foods, nachos, with cheese|Nachos$)"),
    ("mixed nuts", "^Nuts, mixed nuts"), ("dried mango", "^Mango, dried"), ("banana chips", "^Snacks, banana chips"),
    ("chocolate chip cookie", "^Cookie, chocolate chip"), ("brownie", "^Cookie, brownie"), ("cheesecake", "^(Cheesecake|Cake, cheesecake)"),
    ("cupcake", "^Cake or cupcake"), ("ice cream", "^Ice cream"), ("chocolate ice cream", "^Ice creams?, chocolate"), ("apple pie", "^Pie, apple"),
    ("donut", "^Doughnut"), ("muffin", "^Muffin"),
]

/// Breakfast, snacks, wraps and what's drunk from a can, as they're logged through a day: each
/// with a pattern for the plain food that should come first ("oatmeal with milk" FNDDS's oatmeal
/// made with milk, "pretzels" the hard ones, "shredded chicken" cooked chicken, "sparkling
/// water" its plain carbonated water).
/// Foods typed with what they come with: the food, and the entry that has it where one does.
let withSides: [(String, String)] = [
    ("coffee with cream", "^(Coffee$|Beverages, coffee, brewed|Coffee, .*cream)"),
    ("coffee with milk", "^(Coffee$|Beverages, coffee, brewed|Coffee, (Cafe con leche|.*with milk$))"),
    ("coffee with cream and sugar", "^(Coffee$|Beverages, coffee, brewed|Coffee, pre-lightened and pre-sweetened)"),
    ("coffee with sugar", "^(Coffee$|Beverages, coffee, brewed|Coffee, pre-sweetened with sugar)"), ("tea with milk", "^Tea, hot, with milk"),
    ("tea with honey", "^(Beverages, tea, black, brewed|Tea, hot)"), ("tea with lemon", "^(Beverages, tea, black, brewed|Tea, hot)"),
    ("cereal with milk", "^Cereal"), ("oatmeal with banana", "^(Cereals, oats|Oatmeal)"), ("oatmeal with berries", "^(Cereals, oats|Oatmeal)"),
    ("oatmeal with peanut butter", "^(Cereals, oats|Oatmeal)"), ("toast with butter", "^Bread, .*toasted"), ("toast with jam", "^Bread, .*toasted"),
    ("toast with peanut butter", "^Bread, .*toasted"), ("toast with avocado", "(?i)toast"), ("bagel with cream cheese", "^Bagel"),
    ("bagel with butter", "^Bagel"), ("eggs with cheese", "^(Egg omelet or scrambled egg, with cheese|Egg, whole)"),
    ("scrambled eggs with cheese", "^(Egg omelet or scrambled egg, with cheese|Egg, whole, cooked, scrambled)"),
    ("rice with chicken", "^(Chicken or turkey and rice|Rice, white)"), ("chicken with rice", "^Chicken or turkey(,| and) rice"),
    ("chicken with vegetables", "^Chicken or turkey.*vegetables"), ("salad with chicken", "^(Chicken or turkey (garden )?salad|Lettuce, salad)"),
    ("salad with dressing", "^Lettuce, salad"), ("salad with ranch", "^Lettuce, salad"), ("pasta with sauce", "^Pasta with sauce"),
    ("pasta with tomato sauce", "^Pasta with tomato"), ("pasta with meat sauce", "^Pasta with tomato-based sauce and meat"),
    ("pasta with chicken", "^Pasta"), ("pasta with cheese", "^Pasta"), ("spaghetti with sauce", "^Pasta with (sauce|tomato)"),
    ("noodles with vegetables", "(?i)noodles"), ("yogurt with granola", "^Yogurt"), ("yogurt with fruit", "^Yogurt, fruit"),
    ("yogurt with honey", "^Yogurt"), ("yogurt with berries", "^Yogurt"), ("apple with peanut butter", "^Apples, raw"),
    ("banana with peanut butter", "^Bananas, raw"), ("celery with peanut butter", "^Celery, raw"),
    ("tomato soup with grilled cheese", "^Soup, tomato"), ("mashed potatoes with gravy", "^Potato, mashed, .*with gravy"),
    ("rice with vegetables", "^Rice, white"), ("rice with butter", "^Rice, white"), ("rice with egg", "^Rice, white"),
    ("rice with soy sauce", "^Rice, white, with soy"), ("potato with butter", "^Potatoes, (baked|boiled)"),
    ("baked potato with sour cream", "^Potato(es)?, baked"), ("baked potato with cheese", "^Potato(es)?, baked"),
    ("broccoli with cheese", "^Broccoli"), ("vegetables with butter", "^Vegetables, mixed"), ("corn with butter", "^Corn"),
    ("pancakes with syrup", "^Pancakes"), ("pancakes with butter", "^Pancakes"), ("waffles with syrup", "^Waffle"),
    ("french toast with syrup", "^French toast"), ("ice cream with chocolate syrup", "^Ice cream"), ("bread with butter", "^Bread, (white|wheat)"),
    ("pita with hummus", "^Bread, pita"), ("tortilla with cheese", "^(Tortillas|Quesadilla)"), ("quesadilla with chicken", "^Quesadilla, chicken"),
    ("nachos with cheese", "^(Nachos, cheese only|Fast foods, nachos, with cheese)"), ("fries with ketchup", "^Potato(es)?, french fri"),
    ("fries with cheese", "^Potato, french fries, with cheese"), ("hot dog with bun", "^(Hot dog sandwich|Frankfurter)|^Hot dog"),
    ("hot dog with ketchup", "^(Hot dog|Frankfurter)"), ("hamburger with cheese", "^(Cheeseburger|Hamburger)"),
    ("burger with cheese", "^(Cheeseburger|Hamburger)"), ("sandwich with turkey", "^Turkey sandwich"), ("wrap with chicken", "(?i)chicken.*wrap"),
    ("steak with potatoes", "^Beef|^Steak, cooked"), ("chicken breast with rice", "^Chicken"), ("salmon with rice", "^Fish, salmon"),
    ("oatmeal with milk", "^Oatmeal, regular or quick, made with milk"), ("cereal with almond milk", "^Cereal"),
    ("toast with eggs", "^Bread, .*toasted"),
]

/// Two or three foods typed together: the dish where the catalog has one, else the first
/// food, with the second right after it where a pattern for it is given.
let together: [(typed: String, first: String, second: String)] = [
    ("rice and beans", "^(Beans and|Rice and beans|Black beans and)", ""), ("beans and rice", "^(Beans and|Rice and beans|Black beans and)", ""),
    ("chicken and rice", "^Chicken or turkey and rice", ""), ("rice and chicken", "^Chicken or turkey and rice", ""),
    ("mac and cheese", "^Macaroni or noodles with cheese", ""), ("macaroni and cheese", "^Macaroni or noodles with cheese", ""),
    ("peanut butter and jelly", "^Peanut butter and jelly sandwich", ""), ("biscuits and gravy", "^Biscuit with gravy", ""),
    ("pork and beans", "^Beans, baked, canned, with pork", ""), ("franks and beans", "^Beans, baked, canned, with franks", ""),
    ("beans and franks", "^Beans, baked, canned, with franks", ""), ("peas and carrots", "^Peas and carrots", ""),
    ("sausage and peppers", "^Sausage and peppers", ""), ("liver and onions", "^Liver, beef or calves, and onions", ""),
    ("spaghetti and meatballs", "(?i)spaghetti.*meatballs", ""), ("chicken and dumplings", "^Chicken or turkey with dumplings", ""),
    ("rum and coke", "^Rum and cola", ""), ("gin and tonic", "^Gin and tonic", ""), ("sweet and sour chicken", "^Sweet and sour chicken", ""),
    ("beef and broccoli", "^Beef and broccoli", ""), ("half and half", "^Cream, (fluid, )?half and half", ""),
    ("fish and chips", "^Fish, fried", "^Potato, french fries"), ("chicken and waffles", "^Chicken, fried, coated", "^Waffle"),
    ("oil and vinegar", "^Salad dressing, home recipe, vinegar and oil", ""), ("beef and rice", "^Beef and rice", ""),
    ("turkey and gravy", "^Turkey with gravy", ""), ("turkey and stuffing", "^Chicken or turkey with stuffing", ""),
    ("chicken and vegetables", "^Chicken or turkey and vegetables", ""), ("salt and vinegar chips", "(?i)salt (and|&) vinegar", ""),
    ("mike and ike", "(?i)mike and ike", ""), ("cookies and cream", "(?i)cookies? (and|&|'?n'?) cre(a|me)", ""),
    ("burger and fries", "^Hamburger", "^Potato, french fries"), ("burger & fries", "^Hamburger", "^Potato, french fries"),
    ("eggs and bacon", "^Egg, whole", "^Pork, cured, bacon|^Bacon, cooked"), ("bacon and eggs", "^Pork, cured, bacon|^Bacon, cooked", "^Egg, whole"),
    ("steak and potatoes", "^Beef, .*steak|^Steak, cooked", "^Potato"), ("steak and eggs", "^Beef, .*steak|^Steak, cooked", "^Egg, whole"),
    ("chips and salsa", "(?i)^(potato chips|tortilla chips|snacks, tortilla chips)", "^Salsa"),
    ("chips and guacamole", "(?i)^(potato chips|tortilla chips|snacks, tortilla chips)", "^Guacamole"),
    ("bread and butter", "^Bread, (wheat|white)", "^Butter, salted"), ("cheese and crackers", "^Cheese, cheddar", "^Crackers"),
    ("cereal and milk", "^Cereal", "^Milk, whole"), ("ham and cheese", "^Ham", "^Cheese, cheddar"), ("soup and salad", "^Soup", "(?i)salad"),
    ("coffee and donut", "^(Coffee|Beverages, coffee)", "^Doughnut"), ("hummus and pita", "^Hummus", "^Bread, pita"),
    ("yogurt and granola", "^Yogurt", "(?i)granola"), ("toast and eggs", "^Bread, .*toasted", "^Egg, whole"),
    ("eggs and toast", "^Egg, whole", "^Bread, .*toasted"), ("toast and jam", "^Bread, .*toasted", "^Jams"),
    ("pancakes and syrup", "^Pancakes", "^Syrup"), ("salt and pepper", "^Salt, table", "^Spices, pepper, black"),
    ("big mac and fries", "(?i)big mac", "^Potato, french fries"), ("peanut butter and banana", "^Peanut butter", "^Bananas, raw"),
    ("apple and peanut butter", "^Apples, raw", "^Peanut butter"), ("milk and cookies", "^Milk, whole", "^Cookie"),
    ("chicken and broccoli", "^Chicken", "^Broccoli"), ("salmon and rice", "(?i)salmon", "^Rice"),
    ("steak and salad", "^Beef, .*steak|^Steak, cooked", "(?i)salad"),
    ("bagel and cream cheese", "^Bagel", "^Cheese, cream"), ("tuna and crackers", "(?i)tuna", "^Crackers"), ("pizza and wings", "^Pizza", "(?i)wing"),
    ("burger and shake", "^Hamburger", "(?i)shake"), ("coffee and bagel", "^(Coffee|Beverages, coffee)", "^Bagel"),
    ("oatmeal and banana", "(?i)oat", "^Bananas, raw"), ("wine and cheese", "(?i)wine", "^Cheese, cheddar"), ("beer and pizza", "(?i)beer", "^Pizza"),
    ("lettuce and tomato", "^Lettuce", "^Tomato"), ("turkey and cheese", "^Turkey", "^Cheese, cheddar"), ("rice and broccoli", "^Rice", "^Broccoli"),
    ("chicken and potatoes", "^Chicken or turkey and potatoes", ""), ("eggs and sausage", "^Egg, whole", "(?i)sausage"),
    ("sausage and eggs", "(?i)sausage", "^Egg, whole"), ("waffles and syrup", "^Waffle", "^Syrup"), ("banana and yogurt", "^Bananas, raw", "^Yogurt"),
    ("eggs, bacon and toast", "^Egg, whole", "^Pork, cured, bacon|^Bacon, cooked"),
    ("burger, fries and a coke", "^Hamburger", "^Potato, french fries"),
]

/// Plain meats, poultry, fish and cereals by the names they're bought, cooked and ordered by:
/// the survey's entry as it's eaten ("Steak, cooked", "Chicken breast, cooked, without skin",
/// "Fish, salmon, grilled"), where SR Legacy has a cut, a grade and a trim.
let proteins: [(String, String)] = [
    ("steak", "^Steak, cooked"), ("sirloin steak", "^Beef, steak, sirloin"), ("ribeye steak", "^Beef, steak, ribeye"),
    ("t-bone steak", "^Beef, steak, T-bone"), ("filet mignon", "^Beef, steak, tenderloin"), ("new york strip", "^Beef, steak, strip"),
    ("strip steak", "^Beef, steak, strip"), ("flank steak", "^Beef, steak, flank"), ("skirt steak", "^Beef, plate, inside skirt steak"),
    ("roast beef", "^Beef, roast"), ("pot roast", "^Beef, pot roast"), ("brisket", "^Beef, brisket"), ("short ribs", "^Beef, shortribs"),
    ("prime rib", "^Beef, rib"), ("ground beef", "^Beef, ground, cooked"), ("hamburger patty", "^Beef, ground, patty"), ("beef jerky", "^Beef jerky"),
    ("corned beef", "^Beef, corned"), ("pork chop", "^Pork, chop, cooked"), ("pork loin", "^Pork, fresh, loin"),
    ("pork tenderloin", "^Pork, tenderloin"), ("pulled pork", "^(Barbecue pork|Pulled pork)"), ("pork ribs", "^Pork, ribs"),
    ("baby back ribs", "^Pork, (ribs|fresh, backribs)"), ("ribs", "^Ribs, cooked"), ("pork roast", "^Pork, roast"), ("carnitas", "^Pork, carnitas"),
    ("ham", "^Ham"), ("deli ham", "^Ham, prepackaged or deli"), ("bacon", "^Bacon, cooked"), ("turkey bacon", "^Turkey bacon"),
    ("canadian bacon", "^Canadian bacon"), ("sausage", "^Sausage, cooked"), ("breakfast sausage", "^Pork sausage"), ("sausage link", "^Pork sausage"),
    ("sausage patty", "^Pork sausage"), ("italian sausage", "^Italian sausage"), ("bratwurst", "^Bratwurst"),
    ("kielbasa", "^(Polish sausage|Kielbasa)"), ("chorizo", "^Chorizo"), ("hot dog", "^Hot dog"), ("salami", "^Salami"), ("pepperoni", "^Pepperoni"),
    ("bologna", "^Bologna"), ("pastrami", "^Pastrami"), ("prosciutto", "^Ham, prosciutto"), ("spam", "^Spam"),
    ("deli turkey", "^Turkey, prepackaged or deli"), ("turkey breast", "^Turkey, .*breast"), ("turkey", "^Turkey, cooked"),
    ("ground turkey", "^Turkey, [Gg]round"), ("chicken", "^Chicken, cooked$"), ("chicken breast", "^Chicken breast, cooked, without skin"),
    ("skinless chicken breast", "^Chicken breast, cooked, without skin|^Chicken, broiler or fryers, breast, skinless"),
    ("grilled chicken", "^Chicken, grilled"), ("grilled chicken breast", "^Chicken breast, grilled"), ("baked chicken", "^Chicken, baked"),
    ("baked chicken breast", "^Chicken breast, baked"), ("fried chicken", "^Chicken, fried"), ("rotisserie chicken", "^Chicken, rotisserie"),
    ("chicken thigh", "^Chicken thigh, cooked"), ("chicken wings", "^Chicken wing"), ("chicken drumstick", "^Chicken drumstick, cooked"),
    ("chicken tenders", "^Chicken tenders"), ("chicken nuggets", "^Chicken nuggets"), ("ground chicken", "^Chicken, ground"),
    ("lamb", "^Lamb, cooked"), ("lamb chop", "^Lamb, chop"), ("ground lamb", "^Lamb, ground"), ("duck", "^Duck, cooked"), ("venison", "^Venison"),
    ("liver", "^Liver, beef"), ("salmon", "^Fish, salmon, cooked"), ("baked salmon", "^Fish, salmon, baked"),
    ("grilled salmon", "^Fish, salmon, grilled"), ("smoked salmon", "^Fish, salmon, smoked"), ("tuna", "^Fish, tuna, canned"),
    ("cod", "^Fish, cod, cooked"), ("fried cod", "^Fish, cod, fried"), ("tilapia", "^Fish, tilapia, cooked"), ("halibut", "^Fish, halibut"),
    ("trout", "^Fish, trout"), ("catfish", "^Fish, catfish"), ("fried catfish", "^Fish, catfish, fried"), ("sardines", "^Fish, sardine"),
    ("fish", "^Fish, cooked"), ("fried fish", "^Fish, fried"), ("baked fish", "^Fish, baked"), ("shrimp", "^Shrimp, cooked"),
    ("grilled shrimp", "^Shrimp, grilled"), ("fried shrimp", "^Shrimp, fried"), ("crab", "^Crab, cooked"), ("lobster", "^Lobster, cooked"),
    ("scallops", "^Scallops"), ("clams", "^Clams, cooked"), ("oysters", "^Oysters"), ("mussels", "^Mussels, cooked"), ("calamari", "^Calamari"),
    ("fried calamari", "^Calamari, fried"), ("fish sticks", "^Fish sticks"), ("cereal", "^Cereal, ready-to-eat"),
    ("corn flakes", "^Cereal, corn flakes"), ("granola", "^Cereal, granola"), ("shredded wheat", "^Cereal, shredded wheat"),
    ("bran flakes", "^Cereal, bran flakes"), ("berries", "^Berries$"), ("mixed berries", "^Berries"), ("frozen berries", "^Berries, frozen"),
    ("fruit salad", "^Fruit salad"), ("frozen fruit", "^Fruit mixture, frozen"), ("fruit cocktail", "^Fruit cocktail"),
]

/// A cut or a kind of fish typed with nothing else, and the names fish and shellfish are sold
/// by: the cooked piece or fish ("wings" are cooked chicken wings, "mackerel" cooked mackerel),
/// where the first entry was the raw one.
let cuts: [(String, String)] = [
    ("wings", "^Chicken wing, cooked"), ("wing", "^Chicken wing, cooked"), ("chicken wings", "^Chicken wing, cooked"),
    ("chicken wing", "^Chicken wing, cooked"), ("thighs", "^Chicken thigh, cooked"), ("thigh", "^Chicken thigh, cooked"),
    ("chicken thighs", "^Chicken thigh, cooked"), ("chicken thigh", "^Chicken thigh, cooked"), ("drumsticks", "^Chicken drumstick, cooked"),
    ("drumstick", "^Chicken drumstick, cooked"), ("chicken drumsticks", "^Chicken drumstick, cooked"), ("breast", "^Chicken breast, cooked"),
    ("breasts", "^Chicken breast, cooked"), ("chicken breasts", "^Chicken breast, cooked"), ("legs", "^Chicken.*leg.*cooked"),
    ("chicken legs", "^Chicken(, broilers or fryers,)? leg.*cooked"), ("chicken leg", "^Chicken(, broilers or fryers,)? leg.*cooked"),
    ("leg quarters", "^Chicken leg, drumstick and thigh, cooked"), ("chops", "^Pork, chop, cooked"), ("pork chop", "^Pork, chop, cooked"),
    ("lamb chops", "^Lamb, chop, cooked"), ("lamb chop", "^Lamb, chop, cooked"), ("veal chop", "^Veal, chop, cooked"),
    ("tenders", "^Chicken tenders"), ("chicken tenders", "^Chicken tenders"), ("chicken strips", "^Chicken tenders"),
    ("chicken fingers", "^Chicken tenders"), ("nuggets", "^Chicken nuggets"), ("loin", "^Pork.*loin.*cooked"),
    ("pork loin", "^Pork.*loin.*cooked"), ("tenderloin", "tenderloin.*cooked|^Pork tenderloin"),
    ("turkey leg", "^Turkey.*(leg|drumstick).*cooked"), ("turkey wing", "^Turkey.*wing.*cooked"), ("turkey thigh", "^Turkey.*thigh.*cooked"),
    ("cutlet", "(cutlet|Chicken|Veal).*cooked"), ("chicken cutlet", "^Chicken(, cooked| breast, cooked| fillet)"),
    ("fillet", "^Fish, cooked|^Chicken fillet"), ("fish fillet", "^Fish, cooked"), ("salmon fillet", "^Fish, salmon, cooked"),
    ("cod fillet", "^Fish, cod, cooked"), ("tilapia fillets", "^Fish, tilapia, cooked"), ("sole", "flatfish.*cooked"),
    ("flounder", "^Fish, flounder, cooked"), ("snapper", "^Fish, snapper, cooked"), ("red snapper", "^Fish, snapper, cooked"),
    ("grouper", "^Fish, grouper.*cooked"), ("mackerel", "^Fish, mackerel,( Atlantic,)? cooked"), ("perch", "^Fish, perch, cooked"),
    ("pollock", "^Fish, pollock.*cooked"), ("swordfish", "^Fish, swordfish, cooked"), ("mahi mahi", "mahimahi, cooked"),
    ("mahi", "mahimahi, cooked"), ("sea bass", "^Fish, sea bass.*cooked"), ("bass", "^Fish, bass, cooked"), ("herring", "^Fish, herring, cooked"),
    ("whiting", "^Fish, whiting, cooked"), ("pike", "^Fish, pike, cooked"), ("carp", "^Fish, carp, cooked"), ("eel", "^Fish, eel, cooked"),
    ("mullet", "^Fish, mullet, cooked"), ("croaker", "^Fish, croaker, cooked"), ("catfish", "^Fish, catfish, cooked"),
    ("haddock", "^Fish, haddock, cooked"), ("halibut", "^Fish, halibut, cooked"), ("trout", "^Fish, trout, cooked"),
    ("rainbow trout", "^Fish, trout.*cooked"), ("shark", "^Fish, shark, cooked"), ("monkfish", "^Fish, monkfish, cooked"),
    ("walleye", "walleye.*cooked"), ("pompano", "^Fish, pompano, cooked"), ("prawns", "^Shrimp, cooked"), ("crawfish", "^Crayfish, cooked"),
    ("lobster tail", "^Lobster, cooked"), ("crab legs", "^Crab, cooked"), ("king crab", "alaska king, cooked"), ("snow crab", "queen, cooked"),
    ("scallops", "^Scallops, (grilled|baked or broiled|steamed or boiled)|scallop.*cooked"),
    ("calamari", "^(Calamari|Squid), cooked|squid.*cooked"), ("octopus", "^Octopus, cooked"), ("squid", "^(Calamari|Squid), cooked|squid.*cooked"),
    ("mussels", "^Mussels, cooked"), ("clams", "^Clams, cooked"), ("oysters", "^Oysters, (raw|cooked)"), ("liver", "^Liver, beef, cooked"),
    ("chicken liver", "^(Chicken liver|Liver, chicken).*cooked|liver.*cooked"), ("gizzards", "^Gizzard, cooked"), ("oxtail", "oxtail.*cooked"),
    ("tongue", "^Tongue, cooked"), ("tripe", "^Tripe"), ("ground turkey", "(?i)^(Ground turkey|Turkey, ground).*cooked"),
    ("ground chicken", "(?i)^(Ground chicken|Chicken, ground).*cooked"), ("ground pork", "(?i)^(Ground pork|Pork, ground).*cooked"),
    ("ground lamb", "(?i)^(Ground lamb|Lamb, ground).*cooked"), ("black eyed peas", "^Cowpeas.*cooked"), ("black-eyed peas", "^Cowpeas.*cooked"),
    ("blackeyed peas", "^Cowpeas.*cooked"), ("king crab legs", "alaska king, cooked"), ("snow crab legs", "queen, cooked"),
    ("crab meat", "^Crab, cooked|crab.*cooked"), ("chicken leg quarter", "^Chicken leg, drumstick and thigh, cooked"),
    ("mahi-mahi", "mahimahi, cooked"), ("ahi tuna", "yellowfin, fresh, cooked"),
    ("tuna steak", "(?i)^Fish, tuna.*fresh.*cooked|^Fish, tuna, cooked"), ("branzino", "sea bass.*cooked"),
    ("striped bass", "^Fish, bass, striped, cooked|^Fish, bass, cooked"), ("orange roughy", "roughy.*cooked"),
    ("arctic char", "^Fish, trout, cooked"), ("barramundi", "(?i)barramundi"), ("yellowtail", "yellowtail.*cooked"),
    ("swai", "(?i)swai|pangasius|^Fish, catfish.*cooked"), ("sockeye salmon", "sockeye.*cooked"),
    ("atlantic salmon", "^Fish, salmon, Atlantic.*cooked"), ("king salmon", "chinook, cooked"), ("canned salmon", "^Fish, salmon.*canned"),
    ("smoked salmon", "^Fish, salmon.*smoked"), ("lox", "lox|^Fish, salmon.*smoked"), ("albacore", "^Fish, tuna, white, canned in water"),
    ("anchovies", "^Fish, anchovy.*canned"), ("sardines", "^Fish, sardine.*canned|^Sardines"), ("smelt", "^Fish, smelt.*cooked"),
    ("turbot", "turbot.*cooked"), ("sturgeon", "sturgeon.*cooked"), ("rockfish", "rockfish.*cooked"), ("whitefish", "^Fish, white ?fish.*cooked"),
    ("white fish", "^Fish, white fish, cooked"), ("tilapia", "^Fish, tilapia, cooked"), ("cod", "^Fish, cod, cooked"),
    ("salmon", "^Fish, salmon, cooked"), ("tuna", "^Fish, tuna.*canned"), ("shrimp", "^Shrimp, cooked"), ("crab", "^Crab, cooked"),
    ("lobster", "^Lobster, cooked"), ("imitation crab", "^Imitation crab|imitation"), ("crab cakes", "(?i)crab,? cake"),
    ("shrimp cocktail", "(?i)shrimp cocktail"), ("fried shrimp", "^Fried shrimp|^Shrimp.*fried"), ("grilled shrimp", "^Shrimp, grilled"),
    ("baked salmon", "^Fish, salmon, baked"), ("grilled salmon", "^Fish, salmon, grilled"), ("fried catfish", "^Fish, catfish, fried"),
    ("blackened salmon", "^Fish, salmon"), ("black cod", "sablefish, cooked"), ("albacore tuna", "^Fish, tuna, white, canned in water"),
    ("ahi", "yellowfin, fresh, cooked"), ("blackened chicken", "^Chicken(, cooked| breast, cooked|, grilled)"),
    ("blackened fish", "^Fish, (cooked|grilled|baked or broiled)"), ("charred corn", "^Corn.*(cooked|grilled|roasted)"),
]

/// Foods by how they were cooked or come: a way of cooking said in two words ("pan seared
/// salmon", "air fried chicken"), where it was cooked ("slow cooker chicken"), smoked, bbq,
/// crispy and breaded, a way the catalog has no entry for ("roasted garlic"), and the single
/// ways and states the other lists don't have.
let ways: [(String, String)] = [
    ("pan seared salmon", "^Fish, salmon, grilled"), ("pan fried chicken", "^Chicken, fried, coated"), ("pan fried tofu", "^Tofu, fried"),
    ("pan fried pork chop", "^Pork.*chop.*(fried|cooked)"), ("pan seared steak", "^Steak, cooked"), ("pan seared scallops", "^Scallops, grilled"),
    ("oven roasted turkey", "^Turkey, whole, meat only, cooked, roasted"), ("oven roasted chicken", "^Chicken, baked, broiled, or roasted"),
    ("oven baked salmon", "^Fish, salmon, baked or broiled"), ("oven roasted vegetables", "^Vegetables, mixed.*cooked"),
    ("oven roasted potatoes", "^Roasted potatoes"),
    ("oven baked chicken breast", "^Chicken breast, baked, broiled, or roasted"), ("air fried chicken", "^Chicken, baked, broiled, or roasted"),
    ("air fryer chicken wings", "^Chicken wing, baked, broiled, or roasted"), ("air fried potatoes", "^Potatoes, baked, flesh, without salt"),
    ("deep fried shrimp", "^Shrimp, fried"), ("deep fried chicken", "^Chicken, fried, coated"), ("deep fried fish", "^Fish, fried"),
    ("stir fried vegetables", "^Tofu and vegetables, with soy\\-based sauce"),
    ("stir fried chicken", "^Chicken or turkey and vegetables, with soy\\-based sauce"),
    ("stir fry vegetables", "^Tofu and vegetables, with soy\\-based sauce"), ("slow cooked pork", "^Pork, cooked"),
    ("slow cooker chicken", "^Chicken, cooked"), ("slow roasted pork", "^Pork.*roasted"), ("pressure cooked chicken", "^Chicken, cooked"),
    ("instant pot chicken", "^Chicken, cooked"), ("char grilled chicken", "^Chicken, grilled"), ("chargrilled chicken", "^Chicken, grilled"),
    ("flame grilled burger", "^Hamburger"), ("charbroiled burger", "^Hamburger"), ("wood fired pizza", "^Pizza, cheese"),
    ("hard boiled egg", "^Egg, whole, cooked, hard\\-boiled"), ("hard boiled eggs", "^Egg, whole, cooked, hard\\-boiled"),
    ("soft boiled egg", "^Egg, whole, cooked, hard\\-boiled"), ("over easy eggs", "^Egg, whole, cooked, fried"),
    ("over medium eggs", "^Egg, whole, cooked, fried"), ("over hard egg", "^Egg, whole, cooked, fried"),
    ("sunny side up egg", "^Egg, whole, cooked, fried"), ("poached egg", "^Egg, whole, cooked, poached"),
    ("poached eggs", "^Egg, whole, cooked, poached"), ("boiled egg", "^Egg, whole, cooked, hard\\-boiled"),
    ("scrambled eggs", "^Egg, whole, cooked, scrambled"), ("fried egg", "^Egg, whole, cooked, fried"),
    ("smoked brisket", "^Beef, brisket, cooked"), ("smoked turkey", "^Turkey.*smoked"), ("smoked sausage", "^Sausage.*smoked"),
    ("smoked chicken", "^Chicken, grilled"), ("smoked ribs", "^Ribs, cooked"), ("smoked ham", "^(Ham|Pork, cured, ham)"),
    ("bbq chicken", "^Barbecue chicken"), ("barbecue chicken", "^Barbecue chicken"), ("barbecued chicken", "^Chicken, grilled"),
    ("bbq ribs", "^Ribs, cooked"), ("bbq pork", "^Barbecue pork"), ("bbq brisket", "^Beef, brisket, cooked"),
    ("rotisserie chicken", "^Chicken, rotisserie"), ("pulled chicken", "^Chicken, cooked"), ("pulled pork", "^Barbecue pork"),
    ("shredded beef", "^Beef, pot roast"), ("shredded pork", "^Pork"), ("crispy chicken", "^Chicken, fried, coated"),
    ("crispy tofu", "^Tofu, fried"), ("crispy bacon", "^Bacon, cooked"), ("breaded chicken", "^Chicken, fried, coated"),
    ("breaded fish", "^Fish, fried"), ("battered fish", "^Fish, fried"), ("breaded shrimp", "shrimp.*breaded and fried|^Shrimp, fried"),
    ("tempura shrimp", "^Shrimp, fried"), ("mashed sweet potatoes", "^Sweet potato"), ("mashed cauliflower", "(?i)cauliflower"),
    ("mashed potatoes", "^Potato, mashed"), ("stuffed peppers", "^Stuffed pepper, with meat"), ("stuffed mushrooms", "^Mushrooms, stuffed"),
    ("creamed spinach", "^Spinach, creamed"), ("creamed corn", "^Corn.*cream style"),
    ("candied yams", "^Sweet potato, cooked, candied, home\\-prepared"), ("caramelized onions", "^Onions, yellow, sauteed"),
    ("pickled onions", "(?i)onion"), ("pickled beets", "^Beets, pickled"), ("pickled ginger", "(?i)ginger"),
    ("stewed tomatoes", "^Tomatoes.*stewed"), ("stewed chicken", "^Chicken, stewed"), ("braised beef", "^Beef.*braised|^Beef, pot roast"),
    ("braised short ribs", "^Beef.*short ?ribs.*braised"), ("braised pork", "^Pork.*braised"), ("boiled potatoes", "^Potatoes, boiled"),
    ("boiled chicken", "^Chicken, stewed"), ("boiled shrimp", "^Shrimp, steamed or boiled"), ("boiled corn", "^Corn.*boiled"),
    ("boiled peanuts", "^Peanuts.*boiled"), ("steamed vegetables", "^Vegetables, mixed.*cooked"), ("steamed fish", "^Fish, steamed"),
    ("steamed dumplings", "^Wonton, dumpling or pot sticker, steamed"), ("roasted vegetables", "^Vegetables, mixed.*cooked"),
    ("roasted chicken", "^Chicken, baked, broiled, or roasted"), ("roasted turkey", "^Turkey, whole, meat only, cooked, roasted"),
    ("roasted garlic", "^Garlic, raw"), ("roasted peppers", "^Peppers, sweet.*(cooked|sauteed)"),
    ("roasted red peppers", "^Peppers, sweet, red.*(cooked|sauteed)"), ("roasted beets", "^Beets, cooked, boiled, drained"),
    ("roasted peanuts", "^Peanuts.*roasted"), ("dry roasted peanuts", "^Peanuts.*dry-roasted"),
    ("grilled vegetables", "^Vegetables, mixed.*cooked"), ("grilled fish", "^Fish.*grilled"), ("grilled chicken", "^Chicken, grilled"),
    ("grilled cheese", "^Grilled cheese sandwich"), ("grilled portobello", "^Mushrooms, portabella, grilled"),
    ("grilled eggplant", "^Eggplant, cooked"), ("grilled pineapple", "^Pineapple, raw, all varieties"),
    ("grilled peppers", "^Peppers, sweet.*(cooked|sauteed)"), ("fried chicken", "^Chicken, fried, coated"), ("fried fish", "^Fish, fried"),
    ("fried tofu", "^Tofu, fried"), ("fried plantains", "^Plantains, green, fried"), ("fried potatoes", "^Potato.*fried"),
    ("fried onions", "^Onions, yellow, sauteed"), ("fried okra", "^Fried okra"), ("fried zucchini", "^Fried summer squash, yellow or green"),
    ("fried mushrooms", "^Fried mushrooms"), ("seared tuna", "^Fish, tuna.*fresh.*cooked"), ("seared scallops", "^Scallops, grilled"),
    ("seared steak", "^Steak, cooked"), ("toasted bread", "^Bread.*toasted"), ("toasted bagel", "^Bagels.*toasted"),
    ("toasted sesame seeds", "^Seeds, sesame.*toasted"), ("microwaved potato", "^Potatoes, microwaved"),
    ("baked potato", "^Potatoes, baked, flesh, without salt"), ("baked beans", "^Beans, baked, home prepared"),
    ("baked chicken", "^Chicken, baked, broiled, or roasted"), ("baked fish", "^Fish, baked or broiled"), ("baked ham", "^(Ham|Pork, cured, ham)"),
    ("baked apple", "^Apples.*cooked"), ("sauteed shrimp", "^Shrimp, cooked"), ("sauteed vegetables", "^Vegetables, mixed.*cooked"),
    ("sauteed peppers", "^Peppers, sweet, red, sauteed"), ("sauteed zucchini", "zucchini.*cooked"), ("sauteed green beans", "^Beans, snap, green"),
    ("dried mango", "^Mango, dried"), ("dried apricots", "^Apricots, dried"), ("dried cranberries", "^Cranberries, dried"),
    ("canned tuna", "^Fish, tuna, canned"), ("canned chicken", "^Chicken, canned, meat only"), ("canned corn", "^Corn.*canned"),
    ("canned peaches", "^Peaches, canned"), ("canned green beans", "^Beans, snap, green, canned"), ("canned beans", "^Beans.*canned"),
    ("frozen peas", "^Peas, green, frozen"), ("frozen spinach", "^Spinach, frozen"), ("frozen broccoli", "^Broccoli, frozen"),
    ("frozen corn", "^Corn.*frozen"), ("air fryer salmon", "^Fish, salmon, baked or broiled"),
    ("sous vide chicken breast", "^Chicken breast, cooked, without skin"), ("crock pot chili", "^Chili"),
    ("instant pot rice", "^Rice, white.*cooked"), ("fire roasted tomatoes", "^Tomatoes, red, ripe, cooked"), ("barbecue ribs", "^Ribs, cooked"),
    ("pulled beef", "^Barbecue beef"), ("smoked gouda", "^Cheese, gouda"), ("smoked paprika", "^Spices, paprika"),
    ("smoked cheddar", "^Cheese, cheddar"), ("smoked almonds", "^Nuts, almonds.*roasted"), ("smoked mackerel", "^Fish, mackerel, grilled"),
    ("smoked pork chop", "^Pork, chop, cooked"), ("smoked turkey breast", "^Turkey, whole, breast, meat only, cooked, roasted"),
    ("smoked salmon", "^Fish, salmon, smoked"), ("roasted seaweed", "(?i)seaweed"), ("grilled peaches", "^Peaches, yellow, raw"),
    ("grilled avocado", "^Avocados, raw"), ("grilled watermelon", "^Watermelon, raw"), ("sauteed garlic", "^Garlic, raw"),
    ("boiled milk", "^Milk, (whole|reduced|lowfat)"), ("steamed milk", "^Milk, (whole|reduced|lowfat)"), ("steamed buns", "^Bao bun"),
    ("pork bun", "^Bao bun"), ("baked feta", "^Cheese, feta"), ("toasted sesame oil", "^Oil, sesame, salad or cooking"),
    ("over easy egg", "^Egg, whole, cooked, fried"), ("sunny side up eggs", "^Egg, whole, cooked, fried"),
    ("soft boiled eggs", "^Egg, whole, cooked, hard\\-boiled"), ("stir fried shrimp", "^Shrimp and vegetables, with soy\\-based sauce"),
    ("stir fried beef", "^Beef and vegetables, with soy\\-based sauce"), ("pan fried fish", "^Fish, fried"),
    ("pan fried potatoes", "^Potato.*fried"), ("oven baked fries", "^Potato, french fries, from (fresh|frozen), baked"),
    ("oven roasted broccoli", "^Broccoli, cooked"), ("air fried tofu", "^Tofu, (raw|firm|extra firm)"),
    ("air fryer fries", "^Potato, french fries, from (fresh|frozen), baked"), ("deep fried turkey", "^Turkey"),
    ("slow cooked beef", "^Beef, cooked"), ("slow cooker pulled pork", "^Barbecue pork"),
    ("crispy chicken sandwich", "^Chicken fillet sandwich, fried"), ("breaded chicken breast", "^Chicken breast, fried, coated$"),
    ("shrimp tempura", "^Shrimp, fried"), ("candied sweet potatoes", "^Sweet potato, cooked, candied, home\\-prepared"),
    ("fried squash", "^Fried summer squash, yellow or green"), ("bacon strips", "^Bacon, cooked"), ("blackened chicken", "^Chicken, grilled"),
    ("charred corn", "^Corn.*cooked"),
]

/// Foods typed together where one is said with how it was cooked: the grilled chicken and
/// the rice, not a mixed dish of the two. With the second food where there is one, and the
/// dishes that stay one however they're cooked.
let cookedPairs: [(typed: String, first: String, second: String)] = [
    ("grilled chicken and rice", "^Chicken, grilled", "^Rice, white.*cooked"),
    ("baked chicken and rice", "^Chicken, baked, broiled, or roasted", "^Rice, white.*cooked"),
    ("rice and grilled chicken", "^Rice, white.*cooked", "^Chicken, grilled"),
    ("grilled chicken and brown rice", "^Chicken, grilled", "^Rice, brown.*cooked"),
    ("grilled chicken breast and brown rice", "^Chicken breast, grilled", "^Rice, brown.*cooked"),
    ("grilled chicken and vegetables", "^Chicken, grilled", "^Vegetables, mixed"),
    ("roasted chicken and vegetables", "^Chicken, baked, broiled, or roasted", "^Vegetables, mixed"),
    ("baked chicken and roasted potatoes", "^Chicken, baked, broiled, or roasted", "^Roasted potatoes"),
    ("roasted chicken and potatoes", "^Chicken, baked, broiled, or roasted", "^Potatoes"),
    ("grilled shrimp and rice", "^Shrimp, grilled", "^Rice, white.*cooked"),
    ("grilled salmon and rice", "^Fish, salmon, grilled", "^Rice, white.*cooked"),
    ("grilled salmon and asparagus", "^Fish, salmon, grilled", "^Asparagus"),
    ("baked salmon and rice", "^Fish, salmon, baked", "^Rice, white.*cooked"), ("grilled steak and potatoes", "^Steak, cooked", "^Potatoes"),
    ("steak and baked potato", "^Steak, cooked", "^Potatoes, baked"), ("fried rice and beans", "^Rice, fried", "^Beans"),
    ("baked beans and rice", "^Beans, baked", "^Rice, white.*cooked"), ("fried eggs and toast", "^Egg, whole, cooked, fried", "^Bread.*toasted"),
    ("fried eggs and bacon", "^Egg, whole, cooked, fried", "^Bacon, cooked"),
    ("scrambled eggs and bacon", "^Egg, whole, cooked, scrambled", "^Bacon, cooked"),
    ("boiled eggs and toast", "^Egg, whole, cooked, hard-boiled", "^Bread.*toasted"),
    ("smoked salmon and cream cheese", "^Fish, salmon, smoked", "^Cheese, cream"),
    ("roasted turkey and stuffing", "^Turkey.*roasted", "(?i)stuffing"), ("grilled chicken and broccoli", "^Chicken, grilled", "^Broccoli"),
    ("baked potato and steamed broccoli", "^Potatoes, baked", "^Broccoli, cooked"),
    ("grilled cheese and tomato soup", "^Grilled cheese sandwich", "^Soup, tomato"),
    ("roasted vegetables and quinoa", "^Vegetables, mixed", "^Quinoa, cooked"),
    ("smoked sausage and rice", "^Sausage.*smoked", "^Rice, white.*cooked"),
    ("grilled chicken with rice", "^Chicken, grilled", "^Rice, white.*cooked"),
    ("baked chicken with rice", "^Chicken, baked, broiled, or roasted", "^Rice, white.*cooked"),
    ("grilled chicken with vegetables", "^Chicken, grilled", "^Vegetables, mixed"),
    ("grilled chicken with steamed broccoli", "^Chicken, grilled", "^Broccoli, cooked"),
    ("baked salmon with roasted vegetables", "^Fish, salmon, baked", "^Vegetables, mixed"),
    ("fish and chips", "^Fish, fried", "^Potato, french fries"), ("fried fish and chips", "^Fish, fried", "^Potato, french fries"),
    ("battered fish and chips", "^Fish, fried", "^Potato, french fries"), ("chicken and waffles", "^Chicken, fried, coated", "^Waffle"),
    ("fried chicken and waffles", "^Chicken, fried, coated", "^Waffle"), ("chicken and rice", "^Chicken or turkey and rice", ""),
    ("rice and beans", "^Beans and white rice", ""), ("beans and rice", "^Beans and white rice", ""),
    ("fried rice and chicken", "^Rice, fried, with chicken", ""), ("baked mac and cheese", "^Macaroni or noodles with cheese", ""),
    ("baked macaroni and cheese", "^Macaroni or noodles with cheese", ""), ("mac and cheese", "^Macaroni or noodles with cheese", ""),
    ("grilled ham and cheese sandwich", "^Ham sandwich.*cheese", ""),
    ("roast beef and cheddar sandwich", "(?i)^Roast beef & cheddar sandwich", ""), ("steamed beef and broccoli", "^Beef and broccoli", ""),
    ("baked spaghetti and meatballs", "(?i)spaghetti and meatballs", ""), ("biscuits and gravy", "^Biscuit with gravy", ""),
    ("chicken and brown rice", "^Chicken, cooked", "^Rice, brown.*cooked"),
]

/// A word that only describes, typed with nothing after it or not yet whole, and the everyday
/// food it most often starts: "skim" is skim milk, "fren" french fries begun. With the words
/// that are foods alone, which stay themselves, and a second word begun, which says which.
let describing: [(String, String)] = [
    ("skim", "^Milk, nonfat"), ("whole", "^Milk, whole"), ("french", "^Potato, french fries"), ("ground", "^Beef, ground, cooked"),
    ("whipped", "^Cream, whipped"), ("sour", "^Cream, sour"), ("swiss", "^Cheese, swiss"), ("american", "^Cheese, pasteurized process, American"),
    ("string", "^Cheese, mozzarella, low moisture, part-skim"), ("bell", "^Peppers, sweet"), ("dark", "^Dark chocolate"),
    ("sourdough", "^Bread, french or vienna"), ("refried", "^Refried beans"), ("kidney", "^Beans, kidney.*cooked"),
    ("pinto", "^Beans, pinto.*cooked"), ("green", "^Beans, snap, green"), ("black", "^Beans, black.*cooked"), ("hash", "^Potato, hash brown"),
    ("tater", "^Potato tots"), ("chia", "^Seeds, chia"), ("flax", "^Seeds, flaxseed"), ("hemp", "^Seeds, hemp"), ("alfredo", "^Alfredo sauce"),
    ("teriyaki", "^Sauce, teriyaki"), ("bbq", "^Sauce, barbecue"), ("sparkling", "^Water, carbonated"), ("root", "root beer"),
    ("iced", "^Iced Coffee"), ("herbal", "^Tea, hot, herbal|tea, herb"), ("bok", "pak-choi"), ("acorn", "^Squash, winter, acorn"),
    ("navel", "^Oranges, raw, navels"), ("snap", "^Peas, edible-podded"), ("snow", "^Peas, edible-podded"), ("yukon", "^Potatoes, white"),
    ("russet", "^Potatoes, [Rr]usset"), ("white", "^Rice, white.*cooked"), ("brown", "^Rice, brown.*cooked"),
    ("sweet", "^Sweet potato"), ("baked", "^Potatoes, baked"), ("fried", "^Chicken, fried"), ("grilled", "^Chicken, grilled"),
    ("scrambled", "^Egg, whole, cooked, scrambled"), ("pulled", "^Barbecue pork"), ("powdered", "^Sugars, powdered"),
    ("cocoa", "^Cocoa, dry powder"), ("cooking", "cooking spray"), ("veggie", "^Veggie burgers"), ("sloppy", "^Sloppy joe"),
    ("chow", "^Chow mein"), ("kung", "^Kung pao chicken"), ("cobb", "^Cobb salad"), ("buffalo", "^Chicken \"wings\" with hot sauce"),
    ("glazed", "^Doughnut"), ("tikka", "^Chicken curry"), ("saag", "^Palak Paneer"), ("filet", "^Beef, steak, tenderloin"),
    ("graham", "^Graham crackers"), ("animal", "animal crackers"), ("whey", "(?i)whey protein"), ("mac", "^Macaroni or noodles with cheese"),
    ("spring", "^Roll with meat"), ("home", "^Potato, home fries"), ("flour", "^Wheat flour, white, all-purpose"),
    ("sesame", "^Seeds, sesame seeds"), ("fren", "^Potato, french fries"), ("grou", "^Beef, ground, cooked"), ("whit", "^Rice, white.*cooked"),
    ("brow", "^Rice, brown.*cooked"), ("swee", "^Sweet potato"), ("whip", "^Cream, whipped"), ("toas", "^Bread, .*toasted"), ("mezca", "^Tequila"),
    ("cogna", "^Brandy"), ("mac and ch", "^Macaroni or noodles with cheese"), ("mac and chees", "^Macaroni or noodles with cheese"),
    ("white b", "^Bread, white"), ("french t", "^French toast"), ("ground t", "(?i)^Turkey, ground"), ("brown s", "^Sugars, brown"),
    ("cream", "^Cream, "), ("oat", "^Oats"), ("coconut", "^Nuts, coconut meat"), ("wheat", "^Wheat"), ("fruit", "^Fruit$"),
    ("pumpkin", "^Pumpkin"), ("vegetable", "^Vegetables"), ("ranch", "^Salad dressing, ranch"), ("protein", "(?i)protein powder"),
]

/// Foods by what they're called in Britain and Australia ("mince", "rocket", "icing sugar",
/// "tinned tomatoes") and by the short forms people type ("froyo", "veggies", "g&t"), with a
/// few that must stay what they are ("apple crisp", "tater tots").
let otherNames: [(String, String)] = [
    ("mince", "^Beef, ground, cooked"), ("minced beef", "^Beef, ground, cooked"), ("beef mince", "^Beef, ground, cooked"),
    ("turkey mince", "(?i)^Turkey, ground, cooked"), ("pork mince", "^Pork, ground, cooked"), ("lamb mince", "^Lamb, ground, cooked"),
    ("rocket", "^Arugula"), ("icing sugar", "^Sugars, powdered"), ("caster sugar", "^Sugars, granulated"),
    ("double cream", "^Cream, fluid, heavy"), ("single cream", "^Cream, fluid, light"), ("plain flour", "^Wheat flour, white, all-purpose"),
    ("self raising flour", "self-rising"), ("wholemeal bread", "^Bread, whole-wheat"), ("wholemeal flour", "^Wheat flour, whole-grain"),
    ("brown bread", "^Bread, (whole-)?wheat"), ("sultanas", "^Raisins, golden"), ("mangetout", "^Peas, edible-podded"),
    ("spring onions", "^Onions, spring or scallions"), ("capsicum", "^Peppers, sweet"), ("rockmelon", "^Melons, cantaloupe"),
    ("crisps", "^Potato chips|^Snacks, potato chips"), ("sweets", "^Candy"), ("fizzy drink", "^Soft drink"), ("porridge", "^Oatmeal"),
    ("jacket potato", "^Potatoes, baked"), ("butter beans", "^Lima beans"), ("broad beans", "^Broadbeans"), ("swede", "^Rutabagas"),
    ("gammon", "^Ham"), ("tinned tomatoes", "^Tomatoes.*canned"), ("tinned tuna", "^Fish, tuna, canned"), ("tinned peaches", "^Peaches, canned"),
    ("semi skimmed milk", "^Milk, reduced fat"), ("skimmed milk", "^Milk, nonfat"), ("full fat milk", "^Milk, whole"),
    ("full fat yogurt", "^Yogurt, plain, whole milk"), ("natural yoghurt", "^Yogurt, plain"), ("cornflour", "^Cornstarch"),
    ("bicarbonate of soda", "^Leavening agents, baking soda"), ("candy floss", "^Candy, cotton"), ("ice lolly", "(?i)ice.*pop"),
    ("bread roll", "^Rolls, dinner"), ("chicken goujons", "^Chicken tenders"), ("courgette", "zucchini"), ("aubergine", "^Eggplant"),
    ("beetroot", "^Beets"), ("prawns", "^Shrimp"), ("coriander", "^Coriander"), ("fish fingers", "(?i)fish (fingers|sticks)"),
    ("froyo", "^Frozen yogurt"), ("veggies", "^Vegetables, mixed"), ("roasted veggies", "^Vegetables, mixed"), ("spuds", "^Potatoes"),
    ("g&t", "^Gin and tonic"), ("cuke", "^Cucumber"), ("half n half", "^Cream, fluid, half and half"), ("slaw", "^Coleslaw"),
    ("tater salad", "^Potato salad"), ("mashed taters", "^Potato, mashed"), ("nugs", "^Chicken nuggets"),
    ("diet pop", "(?i)diet (soda|cola)|^Soft drink.*diet|carbonated.*(low calorie|diet)"), ("evoo", "^Oil, olive"),
    ("extra virgin olive oil", "^Oil, olive"), ("light cream", "^Cream, fluid, light"), ("raisins", "^Raisins, dark, seedless"),
    ("avo", "^Avocados"), ("guac", "^Guacamole"), ("parm", "^Cheese, parmesan"), ("mozz", "^Cheese, mozzarella"), ("tots", "^Potato tots"),
    ("marg", "^Margarita"), ("blt", "^Bacon, lettuce, tomato sandwich"), ("oj", "^Orange juice"), ("pb", "^Peanut butter"),
    ("pbj", "^Peanut butter and jelly sandwich"), ("apple crisp", "^Crisp, apple"), ("sweet potato", "^Sweet potato"),
    ("minced garlic", "(?i)garlic"), ("tater tots", "^Potato tots"), ("veggie burger", "^Veggie burgers"),
    // More of both, and what's asked for at a British or an Australian table.
    ("silverbeet", "^Chard"), ("kumara", "^Sweet potato"), ("snags", "^Sausage"), ("bangers", "^Sausage"), ("butty", "^Sandwich"),
    ("sarnie", "^Sandwich"), ("bacon butty", "(?i)^bacon.*sandwich"), ("bacon sarnie", "(?i)^bacon.*sandwich"),
    ("toastie", "^Grilled cheese sandwich"), ("cheese toastie", "^Grilled cheese sandwich"), ("cuppa", "(?i)tea"), ("rashers", "^Bacon"),
    ("bacon rashers", "^Bacon"), ("long black", "^Coffee, brewed"), ("short black", "^Coffee, espresso"), ("yorkshire pudding", "^Popover"),
    ("roast potatoes", "^Roasted potatoes"), ("dripping", "^Fat, beef tallow"), ("beef dripping", "^Fat, beef tallow"),
    ("rapeseed oil", "^Oil, canola"), ("groundnut oil", "^Oil, peanut"), ("granary bread", "^Bread, multi-grain"),
    ("fizzy pop", "^Soft drink"), ("chook", "^Chicken"), ("bikkies", "^Cookie"), ("stock", "^Soup, stock, chicken"),
    ("dried currants", "^Currants, zante"), ("apple cider", "^Apple cider"), ("chicken sando", "(?i)chicken.*sandwich"),
    // What only labels are named by: a plain food that happens to have the words comes after.
    ("brown sauce", "(?i)^brown sauce$"), ("salad cream", "(?i)^salad cream$"), ("sausage roll", "(?i)^sausage rolls?$"),
    ("baking soda", "^Leavening agents, baking soda"), ("taco seasoning", "^Seasoning mix, dry, taco"), ("bok choy", "^Cabbage, chinese"),
]

/// A restaurant chain typed with nothing after it, as it's written or most of the way typed,
/// with the food that comes first: what it's known for. And the names left as they were,
/// which are a food's word or a brand's in shops.
let chainsAlone: [(String, String)] = [
    ("mcdonalds", "^McDONALD'S, BIG MAC"), ("burger king", "^Whopper"), ("wendys", "^WENDY'S, CLASSIC SINGLE"),
    ("taco bell", "^TACO BELL, Original Taco"), ("subway", "^SUBWAY, turkey breast sub"), ("starbucks", "^Coffee, Latte"),
    ("dunkin donuts", "^Doughnut"), ("dunkin", "^Doughnut"), ("dominos", "^DOMINO'S 14\" Pepperoni"),
    ("papa johns", "^PAPA JOHN'S 14\" Pepperoni"), ("pizza hut", "^PIZZA HUT 14\" Pepperoni"), ("chick-fil-a", "^CHICK-FIL-A, chicken sandwich"),
    ("popeyes", "^POPEYES, Fried Chicken"), ("kfc", "^KFC, Fried Chicken"), ("arbys", "^ARBY'S, roast beef sandwich"),
    ("sonic", "^Cheeseburger, from fast food"), ("jack in the box", "^Cheeseburger, from fast food"), ("dairy queen", "^Soft serve, blended"),
    ("white castle", "^Cheeseburger slider"), ("hardees", "^Cheeseburger, from fast food"), ("carls jr", "^Cheeseburger, from fast food"),
    ("little caesars", "^LITTLE CAESARS 14\" Original Round Pepperoni"), ("krispy kreme", "^Doughnut"), ("panera", "^Sandwich"),
    ("panera bread", "^Sandwich"), ("in-n-out", "^Cheeseburger, from fast food"), ("five guys", "^Cheeseburger, from fast food"),
    ("shake shack", "^Cheeseburger, from fast food"), ("whataburger", "^Hamburger, from fast food"), ("culvers", "^Cheeseburger, from fast food"),
    ("panda express", "^Restaurant, Chinese, orange chicken"), ("olive garden", "^Breadsticks, soft"), ("ihop", "^Pancakes, plain, fast food"),
    ("red lobster", "^Shrimp, cooked"), ("outback", "^Steak, cooked"), ("texas roadhouse", "^Steak, cooked"),
    ("cheesecake factory", "^Cake, cheesecake"), ("buffalo wild wings", "^Chicken \"wings\", plain"), ("wingstop", "^Chicken \"wings\", plain"),
    ("raising canes", "^Chicken tenders or strips"), ("zaxbys", "^Chicken tenders or strips"), ("bojangles", "^Chicken, fried"),
    ("jimmy johns", "^Turkey sandwich or sub"), ("jersey mikes", "^Turkey sandwich or sub"), ("firehouse subs", "^Turkey sandwich or sub"),
    ("qdoba", "^Burrito"), ("moes", "^Burrito"), ("del taco", "^Taco"), ("el pollo loco", "^Chicken, grilled"), ("sweetgreen", "^Lettuce, salad"),
    ("tim hortons", "^Doughnut"), ("jamba", "^Fruit smoothie"), ("smoothie king", "^Fruit smoothie"), ("auntie annes", "^Pretzels, soft"),
    ("cinnabon", "^Roll, sweet, cinnamon bun"), ("baskin robbins", "^Ice cream"), ("cold stone", "^Ice cream"),
    ("waffle house", "^Waffle, plain"), ("steak n shake", "^Cheeseburger, from fast food"), ("red robin", "^Cheeseburger, from fast food"),
    ("pf changs", "^Rice, fried"), ("noodles and company", "^Macaroni or noodles with cheese"), ("portillos", "^Hot dog"),
    ("costco food court", "^Hot dog"), ("chickfila", "^Chicken fillet sandwich|^CHICK-FIL-A"), ("innout", "^Cheeseburger, from fast food"),
    ("steak and shake", "^Cheeseburger, from fast food"), ("mcdonald's", "^McDONALD'S, BIG MAC"), ("wendy's", "^WENDY'S, CLASSIC SINGLE"),
    ("in n out", "^Cheeseburger, from fast food"), ("chick fil a", "^CHICK-FIL-A, chicken sandwich"), ("papa john's", "^PAPA JOHN'S"),
    ("five guy", "^Cheeseburger, from fast food"), ("wingsto", "^Chicken"), ("jimmy jo", "^Turkey sandwich or sub"),
    ("five guys b", "^Cheeseburger, from fast food"), ("five guys fr", "^Potato, french fries"),
    ("five guys bu", "^Cheeseburger, from fast food"), ("five guys burger", "^Hamburger, from fast food"), ("chipotle", "^Chipotle dip"),
    ("chilis", "^Chili"), ("cracker barrel", "(?i)cheese"), ("out", "(?i)outshine"), ("five g", "(?i)five"), ("five cheese", "(?i)five cheese"),
    ("applebees", "^APPLEBEE'S"), ("dennys", "^DENNY'S"),
]

/// More chains, typed alone, as they're written, most of the way there and with a food: what
/// each is known for first, or the food as such a place serves it. A chain's own label still
/// comes first where it sells the food in shops, and a brand that only starts like a chain
/// isn't it.
let moreChains: [(String, String)] = [
    ("dutch bros", "^Coffee, Latte"), ("crumbl", "^Cookie$"), ("crumbl cookies", "^Cookie$"), ("insomnia cookies", "^Cookie$"),
    ("jollibee", "^Chicken, fried"), ("tropical smoothie cafe", "^Fruit smoothie"), ("jamba juice", "^Fruit smoothie"),
    ("boston market", "^Chicken, rotisserie"), ("churchs chicken", "^Chicken, fried"), ("checkers", "^Cheeseburger, from fast food"),
    ("rallys", "^Cheeseburger, from fast food"), ("freddys", "^Cheeseburger, from fast food"), ("smashburger", "^Cheeseburger, from fast food"),
    ("habit burger", "^Cheeseburger, from fast food"), ("cook out", "^Cheeseburger, from fast food"), ("krystal", "^Cheeseburger slider"),
    ("hungry jacks", "^Whopper"), ("blaze pizza", "^Pizza with pepperoni, from restaurant"),
    ("mod pizza", "^Pizza with pepperoni, from restaurant"), ("marcos pizza", "^Pizza with pepperoni, from restaurant"),
    ("papa murphys", "^Pizza with pepperoni, from restaurant"), ("sbarro", "^Pizza with pepperoni, from restaurant"),
    ("jets pizza", "^Pizza with pepperoni, from restaurant"), ("hungry howies", "^Pizza with pepperoni, from restaurant"),
    ("round table pizza", "^Pizza with pepperoni, from restaurant"), ("godfathers pizza", "^Pizza with pepperoni, from restaurant"),
    ("cicis", "^Pizza with pepperoni, from restaurant"), ("cicis pizza", "^Pizza with pepperoni, from restaurant"),
    ("chuck e cheese", "^Pizza with pepperoni, from restaurant"), ("potbelly", "^Turkey sandwich or sub"), ("quiznos", "^Turkey sandwich or sub"),
    ("blimpie", "^Turkey sandwich or sub"), ("penn station", "^Turkey sandwich or sub"), ("which wich", "^Turkey sandwich or sub"),
    ("schlotzskys", "^Turkey sandwich or sub"), ("mcalisters", "^Sandwich$"), ("jasons deli", "^Sandwich$"), ("charleys", "^Cheese steak sandwich"),
    ("einstein bros", "^Bagels, plain"), ("pret a manger", "^Sandwich$"), ("nandos", "^Chicken, grilled"), ("long john silvers", "^Fish, fried"),
    ("captain ds", "^Fish, fried"), ("slim chickens", "^Chicken tenders or strips, breaded, from fast food"),
    ("golden chick", "^Chicken tenders or strips, breaded, from fast food"), ("huey magoos", "^Chicken tenders or strips, breaded, from fast food"),
    ("taco cabana", "^Taco$"), ("taco johns", "^Taco$"), ("baja fresh", "^Taco$"), ("chuys", "^Taco$"), ("torchys tacos", "^Taco$"),
    ("guzman y gomez", "^Burrito$"), ("rubios", "^Taco, fish"), ("pei wei", "^(Restaurant, Chinese, orange chicken|Orange chicken)"),
    ("wagamama", "^Ramen"), ("chopt", "^Lettuce, salad with assorted vegetables"), ("honeygrow", "^Lettuce, salad with assorted vegetables"),
    ("yogurtland", "^Frozen yogurt"), ("menchies", "^Frozen yogurt"), ("pinkberry", "^Frozen yogurt"), ("wetzels pretzels", "^Pretzels, soft"),
    ("longhorn steakhouse", "^Steak, cooked"), ("golden corral", "^Chicken, fried"), ("tgi fridays", "^Chicken wing"),
    ("ruby tuesday", "^Lettuce, salad with assorted vegetables"), ("hooters", "^Chicken \"wings\""), ("benihana", "^Rice, fried"),
    ("carrabbas", "^Lasagna with meat"), ("maggianos", "^Lasagna with meat"), ("macaroni grill", "^Lasagna with meat"),
    ("buca di beppo", "^Lasagna with meat"), ("bonefish grill", "^Fish, cooked"), ("first watch", "^Pancakes, plain, fast food"),
    ("church's chicken", "^Chicken, fried"), ("freddy's", "^Cheeseburger, from fast food"), ("nando's", "^Chicken, grilled"),
    ("long john silver's", "^Fish, fried"), ("tgi friday's", "^Chicken wing"), ("mcalister's", "^Sandwich$"),
    ("papa murphy's", "^Pizza with pepperoni, from restaurant"), ("smashburge", "^Cheeseburger, from fast food"),
    ("longhorn steakhous", "^Steak, cooked"), ("golden corra", "^Chicken, fried"), ("dutch bro", "^Coffee, Latte"),
    ("dutch bros iced coffee", "^Iced Coffee"), ("crumbl sugar cookie", "^Cookies?, (butter or )?sugar"),
    ("crumbl chocolate chip cookie", "^Cookie, chocolate chip"), ("jollibee fried chicken", "^Chicken, fried"),
    ("jollibee spaghetti with meat sauce", "^Pasta with tomato-based sauce and meat, restaurant"), ("freddys burger", "^Hamburger, from fast food"),
    ("smashburger fries", "^Potato, french fries, fast food"), ("blaze pizza pepperoni pizza", "^Pizza with pepperoni, from restaurant"),
    ("potbelly italian sub", "^Italian sandwich or sub"), ("long john silvers hush puppies", "^Hush puppies"),
    ("slim chickens texas toast", "^Texas toast"), ("taco cabana quesadilla", "^Quesadilla"), ("pei wei fried rice", "^Rice, fried"),
    ("longhorn steakhouse baked potato", "^Potatoes, baked"), ("golden corral mashed potatoes", "^Potato, mashed, from restaurant"),
    ("hooters french fries", "^Potato, french fries, restaurant"), ("carrabbas chicken parmesan", "^Chicken or turkey parmigiana"),
    ("first watch omelet", "^Egg omelet or scrambled egg, from fast food"), ("benihana fried rice", "^Rice, fried"),
    ("chopt salad", "^Lettuce, salad"), ("menchies frozen yogurt", "^Frozen yogurt"), ("nandos chicken", "^Chicken"),
    ("churchs chicken biscuit", "^Biscuit, from fast food"), ("habit burger cheeseburger", "^Cheeseburger, from fast food"),
    ("krystal slider", "^Cheeseburger slider"), ("charleys cheesesteak", "^Cheese steak sandwich"),
    ("wetzels pretzels soft pretzel", "^Pretzels, soft"), ("rubios fish taco", "^Taco, fish"),
    ("sbarro cheese pizza", "^Pizza, cheese, from restaurant"), ("boston market mac and cheese", "\\[Boston Market\\]"),
    ("tgi fridays mozzarella sticks", "\\[TGI.?Friday"), ("einstein bros bagel", "\\[Einstein Bros"), ("hooters wings", "\\[Hooters\\]"),
    ("pret a manger sandwich", "\\[Pret A Manger\\]"), ("crumbl cookies cookie", "^Cookie$"), ("kfc macaroni", "^Pasta, cooked"),
    ("sbarro spaghetti", "^Pasta, cooked"),
]

/// A chain typed with two foods, or a food and what it comes with: the first food, and the
/// second where the search is two. The last few are one food all the same.
let chainPlates: [(typed: String, first: String, second: String)] = [
    ("five guys burger and fries", "^Hamburger, from fast food", "^Potato, french fries, fast food"),
    ("five guys cheeseburger and fries", "^Cheeseburger, from fast food", "^Potato, french fries, fast food"),
    ("burger and fries from five guys", "^Hamburger, from fast food", "^Potato, french fries, fast food"),
    ("mcdonalds big mac and fries", "^McDONALD'S, BIG MAC", "^McDONALD'S, french fries"),
    ("mcdonalds cheeseburger and fries", "^McDONALD'S, Cheeseburger", "^McDONALD'S, french fries"),
    ("mcdonalds cheeseburger, fries and a coke", "^McDONALD'S, Cheeseburger", "^McDONALD'S, french fries"),
    ("mcdonald's pancakes with syrup", "^(McDONALD'S, Hotcakes|Pancakes, plain, fast food)", "^Syrups"),
    ("mcdonalds nuggets and fries", "^(McDONALD'S, Chicken McNUGGETS|Chicken nuggets, from fast food)", "^McDONALD'S, french fries"),
    ("wendys burger and fries", "^(WENDY'S|Hamburger, from fast food)", "^(WENDY'S, french fries|Potato, french fries, fast food)"),
    ("wendys chili with cheese", "^Chili", "^Cheese"),
    ("burger king whopper and fries", "^(BURGER KING, WHOPPER|Whopper)", "^BURGER KING, french fries"),
    ("kfc mashed potatoes with gravy", "^Potato, mashed, from fast food, with gravy", ""), ("kfc chicken and biscuit", "^KFC", "^KFC, biscuit"),
    ("kfc fried chicken and coleslaw", "^KFC, Fried Chicken", "^KFC, Coleslaw"),
    ("popeyes chicken and biscuit", "^POPEYES", "^(POPEYES, biscuit|Biscuit, from fast food)"),
    ("chick-fil-a chicken sandwich and waffle fries", "^CHICK-FIL-A, chicken sandwich", "affle"),
    ("chick-fil-a nuggets and fries", "^(CHICK-FIL-A|Chicken nuggets)", "ries"),
    ("taco bell taco and burrito", "^TACO BELL, Original Taco", "^TACO BELL,.*(?i:burrito)"),
    ("taco bell burrito and nachos", "^TACO BELL,.*(?i:burrito)", "^TACO BELL, Nachos"),
    ("subway sandwich and chips", "^Sandwich", "^(Potato chips|Snacks, potato chips)"),
    ("starbucks latte and a croissant", "^Coffee, Latte", "^Croissant"), ("dunkin coffee and donut", "^Coffee", "^Doughnut"),
    ("ihop pancakes with syrup", "^Pancakes, plain, fast food", "^Syrups"),
    ("pancakes with syrup at ihop", "^Pancakes, plain, fast food", "^Syrups"),
    ("dennys pancakes with butter", "^(DENNY'S|Pancakes, plain, fast food)", "^Butter"),
    ("ihop omelet with cheese", "^Egg omelet or scrambled egg", "^Cheese"), ("waffle house steak and eggs", "^Steak", "^Egg"),
    ("waffle house waffle and bacon", "^Waffle", "^(Bacon|Pork, cured, bacon)"),
    ("whataburger burger with bacon", "^Hamburger, from fast food", "^(Bacon|Pork, cured, bacon)"),
    ("five guys burger with cheese", "^Cheeseburger, from fast food", ""),
    ("zaxbys wings with ranch", "^Chicken \"wings\"", "^Salad dressing, ranch"),
    ("wingstop wings and fries", "^Chicken \"wings\"", "^Potato, french fries, fast food"),
    ("raising canes chicken tenders and fries", "^Chicken tenders", "^Potato, french fries, fast food"),
    ("shake shack burger and shake", "^Hamburger, from fast food", "^(Milk shake|Shake, fast food)"),
    ("in-n-out burger and fries", "^Hamburger, from fast food", "^Potato, french fries, fast food"),
    ("culvers cheeseburger and fries", "^Cheeseburger, from fast food", "^Potato, french fries, fast food"),
    ("sonic cheeseburger and tots", "^Cheeseburger, from fast food", "^Potato tots"),
    (
        "panda express orange chicken and fried rice", "^(Restaurant, Chinese, orange chicken|Orange chicken)",
        "^(Restaurant, Chinese, fried rice|Rice, fried)"
    ),
    ("chipotle chips and guac", "^(Tortilla chips|Snacks, tortilla chips)", "^Guacamole"),
    ("olive garden salad and breadsticks", "^(OLIVE GARDEN|Lettuce, salad)", "^(OLIVE GARDEN|Breadsticks)"),
    ("texas roadhouse steak and baked potato", "^Steak", "^Potato(es)?, baked"),
    ("outback steak and fries", "^Steak", "^Potato, french fries, restaurant"),
    ("applebees burger and fries", "^(APPLEBEE'S|Hamburger)", "^(APPLEBEE'S, french fries|Potato, french fries, restaurant)"),
    ("jollibee fried chicken and rice", "^Chicken, fried", "^Rice"),
    ("freddys burger and fries", "^Hamburger, from fast food", "^Potato, french fries, fast food"),
    ("long john silvers fish and fries", "^Fish, fried", "^Potato, french fries, fast food"),
    ("longhorn steakhouse steak and salad", "^Steak", "^Lettuce, salad"),
    ("first watch pancakes and bacon", "Pancakes", "^(Bacon|Pork, cured, bacon)"),
    ("kfc mac and cheese", "^Macaroni or noodles with cheese, from restaurant", ""), ("popeyes red beans and rice", "(?i:red beans)", ""),
    ("cracker barrel biscuits and gravy", "^Biscuit with gravy", ""),
    ("cracker barrel chicken and dumplings", "^Chicken or turkey with dumplings", ""),
    ("olive garden spaghetti with meat sauce", "^OLIVE GARDEN, spaghetti with meat sauce", ""),
    ("burger king whopper with cheese", "^(BURGER KING, WHOPPER, with cheese|Whopper with cheese)", ""),
    ("mcdonalds sausage mcmuffin with egg", "^McDONALD'S, Sausage McMUFFIN with Egg", ""),
    ("mcdonalds bacon egg and cheese biscuit", "^McDONALD'S, Bacon,? Egg (&|and) Cheese Biscuit", ""),
    ("subway turkey sub with cheese", "^SUBWAY, turkey breast sub", ""),
]

/// A food typed without something ("whopper no cheese", "salad without dressing", "coffee with
/// no sugar"), with the food that comes first: the food, never the thing. Then the same said
/// the other way, and the searches left as they are: a label's own wording, a recipe's name.
let withoutTyped: [(String, String)] = [
    ("whopper no cheese", "^BURGER KING, WHOPPER, no cheese"), ("burger king whopper no cheese", "^BURGER KING, WHOPPER, no cheese"),
    ("burger no bun", "^Hamburger"), ("hamburger without bun", "^Hamburger"), ("burger, no bun", "^Hamburger"),
    ("cheeseburger no bun", "^Cheeseburger"), ("hot dog no bun", "^(Hot dog|Frankfurter)"),
    ("salad no dressing", "^Lettuce, salad with assorted vegetables, no dressing"),
    ("salad without dressing", "^Lettuce, salad with assorted vegetables, no dressing"),
    ("salad with no dressing", "^Lettuce, salad with assorted vegetables, no dressing"), ("caesar salad no dressing", "^Caesar salad"),
    ("salad no croutons", "^(Lettuce, salad|Salad)"), ("coffee no sugar", "^Coffee$"), ("coffee without sugar", "^Coffee$"),
    ("coffee with no sugar", "^Coffee$"), ("iced coffee no sugar", "^Iced Coffee"), ("latte no sugar", "^Coffee, Latte"),
    ("latte no foam", "^Coffee, Latte"), ("tea without milk", "^(Beverages, tea, black, brewed|Tea, hot, leaf, black)"),
    ("tea no milk", "^(Beverages, tea, black, brewed|Tea, hot, leaf, black)"),
    ("tea no sugar", "^(Beverages, tea, black, brewed|Tea, hot, leaf, black)|^Tea"),
    ("burrito bowl no rice", "^Burrito bowl($|, (chicken|beef or pork)$)"), ("burrito no cheese", "^Burrito"),
    ("chicken breast no skin", "^Chicken breast, cooked, without skin"), ("chicken breast without skin", "^Chicken breast, cooked, without skin"),
    ("chicken thigh no skin", "^Chicken thigh, cooked, without skin"), ("chicken no skin", "^Chicken.*(without skin|skinless|meat only)"),
    ("green beans no salt", "^Beans, snap, green, .*(without salt|no salt)"),
    ("peanut butter no salt", "^Peanut butter, smooth style, without salt"),
    ("peanut butter without salt", "^Peanut butter, smooth style, without salt"), ("almonds no salt", "^Nuts, almonds, .*without salt"),
    ("butter no salt", "^Butter, without salt"), ("butter without salt", "^Butter, without salt"),
    ("cashews no salt", "^Nuts, cashew nuts, .*without salt"), ("applesauce no sugar", "^Applesauce, canned, unsweetened"),
    ("applesauce no sugar added", "^Applesauce, canned, unsweetened"), ("oatmeal no sugar", "^(Cereals, oats|Oatmeal)"),
    ("yogurt no sugar", "^Yogurt"), ("almond milk no sugar", "(?i:unsweetened)"), ("popcorn no butter", "^Popcorn, air-popped, no butter added"),
    ("popcorn without butter", "^Popcorn, air-popped, no butter added"), ("baked potato no skin", "^Potatoes, baked, flesh"),
    ("baked potato without skin", "^Potatoes, baked, flesh"), ("tuna no mayo", "^Fish, tuna"), ("sandwich no mayo", "^Sandwich"),
    ("turkey sandwich no cheese", "^Turkey sandwich (or sub, restaurant|on)"),
    ("turkey sandwich without cheese", "^Turkey sandwich (or sub, restaurant|on)"), ("taco no cheese", "^Taco, meat, no cheese"),
    ("taco without cheese", "^Taco, meat, no cheese"), ("pizza no cheese", "^Pizza, no cheese"), ("fries no salt", "^Potato, french fries"),
    ("eggs no oil", "^Egg"), ("scrambled eggs no butter", "^Egg(, whole, cooked, scrambled| omelet or scrambled egg)"),
    ("rice no butter", "^Rice, white"), ("toast no butter", "^Bread.*toasted"), ("toast without butter", "^Bread.*toasted"),
    ("bagel no cream cheese", "^Bagel"), ("pancakes no syrup", "^Pancakes"), ("pancakes without butter", "^Pancakes"),
    ("cereal no milk", "^Cereal"), ("oatmeal without milk", "^(Cereals, oats|Oatmeal)"), ("milk no fat", "^Milk, nonfat"),
    ("orange juice no pulp", "^Orange juice"), ("water no ice", "(?i:water)"), ("burger hold the mayo", "^Hamburger"),
    ("burger minus the bun", "^Hamburger"), ("chili no beans", "^Chili, no beans|^Chili con carne"), ("pho no meat", "^Soup, pho, no meat"),
    ("gumbo no rice", "^Gumbo, no rice"), ("nachos no cheese", "^Nachos"), ("quesadilla no cheese", "^Quesadilla"),
    ("omelet no cheese", "^(Egg omelet|Egg, whole, cooked, omelet|Omelet)"), ("mashed potatoes no gravy", "^(Potato(es)?, mashed)"),
    ("mashed potatoes without butter", "^Potato(es)?, mashed"), ("steak no sauce", "^(Steak|Beef)"), ("wings no sauce", "^Chicken"),
    ("pasta no sauce", "^Pasta, cooked"), ("spaghetti without sauce", "^(Pasta|Spaghetti), cooked"),
    ("ice cream no sugar added", "^Ice creams?, .*(?i:no sugar added)"),
    ("burger king whopper with cheese", "^(BURGER KING, WHOPPER, with cheese|Whopper with cheese)"),
    ("whopper with cheese", "^Whopper with cheese"), ("chicken thigh with skin", "^Chicken thigh, cooked, with skin"),
    ("popcorn with butter", "^Popcorn, air-popped, with added butter"), ("salad with dressing", "^Lettuce, salad"),
    ("coffee with sugar", "^Coffee"), ("no sugar added applesauce", "(?i:no sugar added applesauce)"),
    ("coke no sugar", "(?i:(coca|coke).*(no sugar|zero)|cola, (diet|sugar free|low calorie))"), ("no bake cookies", "(?i:no.?bake)"),
    ("no salt added green beans", "^Beans, snap, green, canned, no salt added"),
]

/// The same as a model names them.
let withoutNamed: [(String, String)] = [
    ("Burger patty (no bun)", "^(Beef, ground, patty|Hamburger)"), ("Hamburger without bun", "^(Hamburger|Beef, ground, patty)"),
    ("Salad without dressing", "^Lettuce, salad with assorted vegetables, no dressing"),
    ("Garden salad (no dressing)", "^Lettuce, salad with assorted vegetables, no dressing"), ("Side salad, no dressing", "^Lettuce, salad"),
    ("Coffee without sugar", "^Coffee"), ("Black coffee, no sugar", "^Coffee"),
    ("Tea without milk", "^(Beverages, tea, black, brewed|Tea, hot, leaf, black)|^Tea, hot"),
    ("Turkey sandwich without cheese", "^Turkey sandwich (or sub, restaurant|on)"), ("Taco without cheese", "^Taco, meat, no cheese"),
    ("Popcorn without butter", "^Popcorn, air-popped, no butter added"), ("Chicken breast without skin", "^Chicken breast, cooked, without skin"),
    ("Baked potato without skin", "^Potatoes, baked, flesh"), ("Burrito bowl without rice", "^Burrito bowl($|, (chicken|beef or pork)$)"),
    ("Oatmeal without sugar", "^(Cereals, oats|Oatmeal)"), ("Tuna salad without mayo", "^Tuna salad"),
    ("Fries without salt", "^Potato, french fries"), ("Scrambled eggs (no butter)", "^Egg"), ("Latte, no sugar", "^Coffee, Latte"),
    ("Grilled chicken breast, no skin", "^Chicken breast, grilled, without skin"), ("Toast without butter", "^Bread.*toasted"),
    ("Pancakes without syrup", "^Pancakes"), ("Hot dog without bun", "^(Hot dog|Frankfurter)"), ("Cheeseburger without bun", "^Cheeseburger"),
    ("Green beans, no salt", "^Beans, snap, green"), ("Unsalted almonds", "^Nuts, almonds"), ("Pizza without cheese", "^Pizza, no cheese"),
    ("Rice without butter", "^Rice, white"), ("Steak, no sauce", "^(Steak|Beef)"), ("Pasta without sauce", "^Pasta, cooked"),
    ("Whopper without cheese", "^(BURGER KING, WHOPPER, no cheese|Whopper)"), ("Yogurt, no sugar added", "^Yogurt"),
]

/// A chain's item typed by its own name, without the chain: the chain's own where USDA has it,
/// else the nearest it has from there or the food as such a place serves it. Then a chain
/// typed with a food that isn't another chain's, the skin alone not being the food, and the
/// searches that stay as they were.
let menuNames: [(String, String)] = [
    ("frosty", "^WENDY'S, Frosty"), ("chocolate frosty", "^WENDY'S, Frosty"), ("baconator", "^WENDY'S, CLASSIC DOUBLE, with cheese"),
    ("dave's single", "^WENDY'S, DAVE'S"), ("daves single", "^WENDY'S, DAVE'S"), ("daves double", "^WENDY'S, CLASSIC DOUBLE, with cheese"),
    ("jr bacon cheeseburger", "^WENDY'S, Jr. Hamburger, with cheese"), ("junior bacon cheeseburger", "^WENDY'S, Jr. Hamburger, with cheese"),
    ("original recipe chicken", "^KFC, Fried Chicken, ORIGINAL RECIPE, .*meat and skin"),
    ("extra crispy chicken", "^KFC, Fried Chicken, EXTRA CRISPY, .*meat and skin"), ("nachos bellgrande", "^TACO BELL, Nachos Supreme"),
    ("doritos locos taco", "^TACO BELL, Original Taco"), ("doritos locos tacos", "^TACO BELL, Original Taco"),
    ("cheesy gordita crunch", "^Gordita, meat"), ("blizzard", "^Soft serve, blended with candy or cookies"),
    ("oreo blizzard", "^Soft serve, blended with candy or cookies"), ("double quarter pounder", "^McDONALD'S, DOUBLE QUARTER POUNDER"),
    ("hot and spicy mcchicken", "^McDONALD'S, McCHICKEN"), ("hot n spicy mcchicken", "^McDONALD'S, McCHICKEN"),
    ("shamrock shake", "^Milk shake, fast food"), ("croissanwich", "^BURGER KING, CROISSAN'WICH"),
    ("sausage croissanwich", "^BURGER KING, CROISSAN'WICH with Sausage"), ("beef n cheddar", "^Roast beef sandwich on white, with cheese"),
    ("beef and cheddar", "^Roast beef sandwich on white, with cheese"), ("butterburger", "^Cheeseburger, from fast food"),
    ("double double", "^Double cheeseburger, from fast food"), ("animal style fries", "^Potato, french fries, with cheese"),
    ("hot n ready", "^LITTLE CAESARS 14\" Original Round Pepperoni"), ("hot and ready", "^LITTLE CAESARS 14\" Original Round Pepperoni"),
    ("crazy bread", "^Breadsticks, soft, with parmesan"), ("footlong", "^(Turkey sandwich or sub|Fast foods, submarine sandwich)"),
    ("footlong sub", "^(Turkey sandwich or sub|Fast foods, submarine sandwich)"),
    ("footlong meatball marinara", "^Fast foods, submarine sandwich, meatball marinara"), ("steak and cheese", "^Cheese steak sandwich"),
    ("steak and cheese sub", "^Cheese steak sandwich"), ("bloomin onion", "^Fried onion rings"), ("blooming onion", "^Fried onion rings"),
    ("cake pop", "(?i:cake pop)"), ("slurpee", "^Slush frozen drink"), ("slushie", "^Slush frozen drink"), ("pot pie", "^Pot pie, chicken"),
    ("cheese curds", "^Cheese, cheddar"), ("fried cheese curds", "(?i:fried mozzarella sticks)"),
    ("potato skins", "^Potato skins, with cheese and bacon"), ("loaded potato skins", "^Potato skins, with cheese and bacon"),
    ("wendys jr cheeseburger", "^WENDY'S, Jr. Hamburger, with cheese"), ("wendys cheeseburger", "^WENDY'S, .*Hamburger, with cheese"),
    ("hungry jacks whopper", "^Whopper"), ("mcdonalds cheeseburger", "^McDONALD'S, Cheeseburger"),
    ("five guys cheeseburger", "^Cheeseburger, from fast food"), ("kfc original recipe", "^KFC, Fried Chicken, ORIGINAL RECIPE, .*meat and skin"),
    ("kfc extra crispy", "^KFC, Fried Chicken, EXTRA CRISPY, .*meat and skin"), ("baked potato with skin", "^Potatoes, .*flesh and skin"),
    ("raw potatoes", "^Potatoes, flesh and skin, raw"), ("subway footlong", "^SUBWAY, turkey breast sub"), ("mcchicken", "^McDONALD'S, McCHICKEN"),
    ("big mac", "^Big Mac|^McDONALD'S, BIG MAC"), ("egg mcmuffin", "^McDONALD'S, Egg McMUFFIN"), ("mcflurry", "^McDONALD'S, McFLURRY"),
    ("whopper", "^Whopper|^BURGER KING, WHOPPER"), ("mcrib", "^Barbecue rib sandwich"), ("pork rinds", "^(Snacks, pork skins|Pork skin rinds)"),
    ("zucchini", "^Squash, summer, zucchini"), ("frosting", "^Frosting"), ("frosted flakes", "(?i:frosted flakes)"), ("avocado toast", "^Avocados"),
    ("mac and cheese", "^Macaroni or noodles with cheese"), ("ham and cheese", "^Ham"), ("steak and eggs", "^Steak"),
]

/// A food that holds others, named with what's in it and an "and": one food, the plain one
/// or a chain's own with the words. The last few are two foods all the same.
let heldFoods: [(String, String)] = [

    (
        "bacon egg and cheese biscuit",
        "^(Fast foods, biscuit, with egg, cheese, and bacon|Egg sandwich on biscuit, with bacon and cheese|McDONALD'S, Bacon Egg & Cheese Biscuit)"
    ),
    (
        "bacon, egg and cheese biscuit",
        "^(Fast foods, biscuit, with egg, cheese, and bacon|Egg sandwich on biscuit, with bacon and cheese|McDONALD'S, Bacon Egg & Cheese Biscuit)"
    ),
    (
        "bacon egg & cheese biscuit",
        "^(Fast foods, biscuit, with egg, cheese, and bacon|Egg sandwich on biscuit, with bacon and cheese|McDONALD'S, Bacon Egg & Cheese Biscuit)"
    ),
    ("sausage egg and cheese biscuit", "^(Sausage, egg and cheese breakfast biscuit|Egg sandwich on biscuit, with sausage and cheese)"),
    ("egg and cheese biscuit", "^Egg sandwich on biscuit$"),
    ("egg and bacon biscuit", "^(Fast foods, biscuit, with egg and bacon|Egg sandwich on biscuit, with bacon)"),
    ("egg and sausage biscuit", "^(Fast Foods, biscuit, with egg and sausage|Egg sandwich on biscuit, with sausage)"),
    ("sausage egg and cheese mcmuffin", "^McDONALD'S, Sausage McMUFFIN with Egg"),
    ("sausage and egg mcmuffin", "^McDONALD'S, Sausage McMUFFIN with Egg"), ("sausage egg mcmuffin", "^McDONALD'S, Sausage McMUFFIN with Egg"),
    ("bacon egg and cheese mcgriddle", "^McDONALD'S, Bacon, Egg & Cheese McGRIDDLES"),
    ("sausage egg and cheese mcgriddle", "^McDONALD'S, Sausage, Egg & Cheese McGRIDDLES"),
    ("egg and cheese croissanwich", "^BURGER KING, CROISSAN'WICH with Egg and Cheese"),
    ("sausage egg and cheese croissanwich", "^BURGER KING, CROISSAN'WICH with Sausage, Egg and Cheese"),
    ("sausage and cheese croissanwich", "^BURGER KING, CROISSAN'WICH with Sausage and Cheese"),
    ("bacon egg and cheese bagel", "^Egg sandwich on bagel, with bacon"), ("egg and bacon bagel", "^Egg sandwich on bagel, with bacon"),
    ("sausage egg and cheese bagel", "^(Egg sandwich on bagel, with sausage|Fast foods, bagel, with egg, sausage patty, cheese)"),
    ("ham egg and cheese bagel", "^Egg sandwich on bagel, with ham"),
    ("ham egg and cheese croissant", "^Fast foods, croissant, with egg, cheese, and ham"),
    ("bacon egg and cheese croissant", "^Fast foods, croissant, with egg, cheese, and bacon"),
    ("sausage egg and cheese croissant", "^Fast foods, croissant, with egg, cheese, and sausage"),
    ("egg and cheese croissant", "^Egg sandwich on croissant$"), ("ham and egg muffin", "^Egg sandwich on English muffin, with ham"),
    ("bacon and egg english muffin", "^Egg sandwich on English muffin, with bacon"),
    (
        "sausage egg and cheese english muffin",
        "^(Fast foods, english muffin, with egg, cheese, and sausage|Egg sandwich on English muffin, with sausage)"
    ),
    ("egg and cheese sandwich", "^Egg sandwich on white bread, with cheese"), ("bacon egg and cheese sandwich", "^Egg sandwich on .*bacon"),
    ("ham and cheese sandwich", "^Ham sandwich"), ("turkey and cheese sandwich", "^Turkey sandwich .*with cheese"),
    ("peanut butter and jelly sandwich", "^Peanut butter and jelly sandwich"), ("peanut butter and banana sandwich", "^Peanut butter sandwich"),
    ("bean and cheese burrito", "^Burrito, with beans, cheese"), ("egg and cheese burrito", "^Egg burrito$"),
    ("bacon and egg burrito", "^Egg burrito, with bacon"), ("sausage and egg burrito", "^Egg burrito, with sausage"),
    ("chicken and cheese quesadilla", "^Quesadilla, chicken"), ("chicken and rice bowl", "^Rice bowl with chicken"),
    ("ham and cheese croissant", "^(Croissant|Fast foods, croissant|Ham)"), ("apple and peanut butter", "^Apples"),
    ("chicken and white rice", "^Chicken, cooked"), ("burger and cheese fries", "^Hamburger"), ("coffee and blueberry muffin", "^Coffee"),
    ("eggs and wheat toast", "^Egg, whole"), ("salmon and brown rice", "^Fish, salmon"), ("soup and grilled cheese sandwich", "^Soup"),
    ("chips and turkey sandwich", "^Potato chips"), ("fries and chicken sandwich", "^Potato, french fries"), ("coffee and egg sandwich", "^Coffee"),
    ("orange juice and bagel", "^Orange juice"), ("yogurt and granola", "^Yogurt"), ("salad and pepperoni pizza", "^(Lettuce, salad|Salad)"),
    ("banana and peanut butter sandwich", "^(Bananas|Peanut butter sandwich)"), ("burger and fries", "^Hamburger"),
    ("eggs and bacon", "^Egg, whole"), ("steak and eggs", "^Steak"),
]

/// The same as a model names them.
let heldNamed: [(String, String)] = [

    (
        "Bacon, egg and cheese biscuit",
        "^(Fast foods, biscuit, with egg, cheese, and bacon|Egg sandwich on biscuit, with bacon and cheese|McDONALD'S, Bacon Egg & Cheese Biscuit)"
    ),
    (
        "Bacon, Egg & Cheese Biscuit",
        "^(Fast foods, biscuit, with egg, cheese, and bacon|Egg sandwich on biscuit, with bacon and cheese|McDONALD'S, Bacon Egg & Cheese Biscuit)"
    ),
    ("Sausage and egg McMuffin", "^McDONALD'S, Sausage McMUFFIN with Egg"),
    ("Sausage, egg and cheese McMuffin", "^McDONALD'S, Sausage McMUFFIN with Egg"),
    ("Bacon, egg and cheese bagel", "^Egg sandwich on bagel, with bacon"), ("Egg and cheese biscuit", "^Egg sandwich on biscuit$"),
    ("Ham, egg and cheese croissant", "^Fast foods, croissant, with egg, cheese, and ham"),
    ("Egg and cheese breakfast burrito", "^(Egg burrito|Fast foods, breakfast burrito)"), ("Chicken and cheese quesadilla", "^Quesadilla, chicken"),
    ("Ham and cheese sandwich", "^Ham sandwich"), ("Turkey and cheese sandwich", "^Turkey sandwich .*with cheese"),
    ("Bean and cheese burrito", "^Burrito, with beans, cheese"), ("Eggs and bacon", "^Egg, whole"), ("Coffee and a blueberry muffin", "^Coffee"),
    ("Chicken and white rice", "^Chicken"), ("Burger and fries", "^Hamburger"),
]

/// Foods said by what they're light in or free of where the catalogs word it another way,
/// tuna by its packet, and an omelet by its meat; then the ones that stay as they were.
let wordedAnotherWay: [(String, String)] = [
    ("diet sprite", "^Sprite Zero"), ("light bread", "^Bread, reduced-calorie"), ("low calorie bread", "^Bread, reduced-calorie"),
    ("sugar free chocolate", "^Chocolate candy, sugar free"), ("unsweetened coconut", "^Nuts, coconut meat, dried \\(desiccated\\), not sweetened"),
    ("unsweetened shredded coconut", "^Nuts, coconut meat, dried \\(desiccated\\), not sweetened"),
    ("dried coconut", "^Nuts, coconut meat, dried \\(desiccated\\), not sweetened"),
    ("desiccated coconut", "^Nuts, coconut meat, dried \\(desiccated\\), not sweetened"),
    ("shredded coconut", "^Nuts, coconut meat, dried \\(desiccated\\), sweetened, shredded"),
    ("light ice cream", "^(Light ice cream, vanilla|Ice creams, vanilla, light)"),
    ("low fat ice cream", "^(Light ice cream, vanilla|Ice creams, vanilla, light)"), ("tuna packet", "^Fish, tuna, .*canned in water"),
    ("tuna pouch", "^Fish, tuna, .*canned in water"), ("nonfat yogurt", "^Yogurt, plain, skim milk"),
    ("fat free yogurt", "^Yogurt, plain, skim milk"), ("plain nonfat yogurt", "^Yogurt, plain, skim milk"),
    ("ham and cheese omelet", "^Egg omelet or scrambled egg, with cheese and meat"),
    ("bacon and cheese omelet", "^Egg omelet or scrambled egg, with cheese and meat"),
    ("sausage and cheese omelet", "^Egg omelet or scrambled egg, with cheese and meat"),
    ("ham and cheese omelette", "^Egg omelet or scrambled egg, with cheese and meat"), ("coconut", "(?i:coconut)"), ("ice cream", "^Ice cream"),
    ("bread", "^Bread"), ("sprite", "(?i:sprite)"), ("yogurt", "^Yogurt"), ("tuna", "^Fish, tuna"), ("nonfat milk", "^Milk, nonfat"),
    ("skim milk", "^Milk, nonfat"), ("nonfat greek yogurt", "^Yogurt, Greek, plain, nonfat"), ("nonfat latte", "^Coffee, Latte, nonfat"),
    ("cheese omelet", "^Egg omelet or scrambled egg, with cheese"), ("coconut water", "^Coconut water"), ("coconut milk", "(?i:coconut milk)"),
    ("light beer", "^Beer, light"), ("sugar free pudding", "^Pudding.*sugar free"), ("sprite zero", "^Sprite Zero"),
    ("unsweetened applesauce", "^Applesauce, canned, unsweetened"),
]

/// A plate typed as a list, some of it with nothing between the foods or with commas only:
/// the first food, and the second where the search is more than one. The last are one food
/// all the same, or two as they were.
let typedPlates: [(typed: String, first: String, second: String)] = [
    ("eggs bacon and toast", "^Egg, whole, cooked", "^Bacon, cooked"), ("eggs, bacon, toast", "^Egg, whole, cooked", "^Bacon, cooked"),
    ("eggs, bacon and toast", "^Egg, whole, cooked", "^Bacon, cooked"), ("burger fries and a shake", "^Hamburger", "^Potato, french fries"),
    ("burger, fries, coke", "^Hamburger", "^Potato, french fries"), ("chicken rice and broccoli", "^Chicken, cooked", "^Rice, white"),
    ("chicken, rice, broccoli", "^Chicken, cooked", "^Rice, white"), ("steak potatoes and green beans", "^Steak", "^Potatoes"),
    ("salmon rice and asparagus", "^Fish, salmon", "^Rice, white"), ("oatmeal banana and peanut butter", "^(Cereals, oats|Oatmeal)", "^Bananas"),
    ("turkey sandwich chips and an apple", "^Turkey sandwich", "^Potato chips"), ("pancakes eggs and sausage", "^Pancakes", "^Egg, whole, cooked"),
    ("coffee toast and eggs", "^Coffee", "^Bread"), ("yogurt granola and berries", "^Yogurt", "^Cereal, granola"),
    ("pork chop applesauce and green beans", "^Pork, chop", "^Applesauce"), ("pizza wings and soda", "^Pizza", "^Chicken wing"),
    ("chicken broccoli and rice", "^Chicken, cooked", "^Broccoli"), ("steak eggs and toast", "^Steak", "^Egg, whole, cooked"),
    ("bacon eggs and hash browns", "^Bacon, cooked", "^Egg, whole, cooked"),
    ("rice beans and chicken", "^Beans and white rice", "^Chicken, cooked"), ("toast eggs and coffee", "^Bread", "^Egg, whole, cooked"),
    ("banana yogurt and granola", "^Bananas", "^Yogurt"), ("tacos rice and beans", "^Taco", "^(Rice|Beans and)"),
    ("salad chicken and bread", "^(Lettuce, salad|Salad)", "^Chicken, cooked"), ("lentil soup and bread", "^(Lentil soup|Soup, lentil)", "^Bread"),
    ("chicken salad and crackers", "^Chicken or turkey salad", "^Crackers"), ("peanut butter and jelly", "^Peanut butter and jelly", ""),
    ("mac and cheese", "^Macaroni or noodles with cheese", ""), ("grilled chicken and rice", "^Chicken, grilled", "^Rice, white"),
    ("brown rice and chicken", "^Rice, brown", "^Chicken, cooked"), ("green beans and mashed potatoes", "^Beans, snap, green", "^Potato"),
    ("sweet potato fries and a burger", "^Sweet potato", "^Hamburger"),
    ("tomato soup and grilled cheese", "^(Tomato soup|Soup, tomato)", "^(Grilled cheese|Cheese)"),
    ("ice cream and apple pie", "^Ice cream", "^Pie, apple"), ("peanut butter and banana sandwich", "^Peanut butter sandwich", ""),
    ("bacon egg and cheese biscuit", "^(Fast foods, biscuit|Egg sandwich on biscuit)", ""),
    ("turkey sandwich and chips", "^Turkey sandwich", "^Potato chips"), ("chicken breast and rice", "^Chicken breast", "^Rice, white"),
    ("rice, brown", "^Rice, brown", ""), ("chicken breast, grilled, skinless", "^Chicken, broiler or fryers, breast", ""),
    ("burger and fries", "^Hamburger", "^Potato, french fries"), ("fish and chips", "^Fish, fried", "^Potato, french fries"),
]

/// A food said by another name after an amount or a size ("small frosty", "2 pbj"), a size
/// said in a food's name ("tallboy", "footlong hot dog"), and the sizes and servings that
/// already read right.
let sizesSaid: [(String, String)] = [
    ("small frosty", "^WENDY'S, Frosty"), ("large frosty", "^WENDY'S, Frosty"), ("2 frosty", "^WENDY'S, Frosty"), ("a frosty", "^WENDY'S, Frosty"),
    ("kids frosty", "^WENDY'S, Frosty"), ("jr frosty", "^WENDY'S, Frosty"), ("medium blizzard", "^Soft serve, blended with candy or cookies"),
    ("large blizzard", "^Soft serve, blended with candy or cookies"), ("small baconator", "^WENDY'S, CLASSIC DOUBLE, with cheese"),
    ("large oj", "^Orange juice"), ("glass of oj", "^Orange juice"), ("2 pbj", "^Peanut butter and jelly sandwich"),
    ("large double double", "^Double cheeseburger, from fast food"), ("small pot pie", "^Pot pie, chicken"),
    ("2 footlong", "^(Turkey sandwich or sub|Fast foods, submarine sandwich)"), ("tallboy", "^Beer$"),
    ("tall boy beer", "^Beer$"), ("foot long hot dog", "^Hot dog"), ("footlong hot dog", "^Hot dog"),
    ("half rack ribs", "^Ribs, cooked"), ("full rack ribs", "^Ribs, cooked"), ("sub", "^(Turkey sandwich or sub|Fast foods, submarine sandwich)"),
    ("6 inch sub", "^(Turkey sandwich or sub|Fast foods, submarine sandwich)"),
    ("six inch sub", "^(Turkey sandwich or sub|Fast foods, submarine sandwich)"), ("cup of joe", "^Coffee"), ("grande latte", "^Coffee, Latte"),
    ("venti iced coffee", "^Iced Coffee"), ("tall cappuccino", "^Coffee, Cappuccino"), ("large fries", "^Potato, french fries"),
    ("small fries", "^Potato, french fries"), ("medium coke", "^Beverages, carbonated, cola"), ("large coffee", "^Coffee"),
    ("fun size snickers", "(?i:snickers fun size)"), ("large pizza", "^Pizza, cheese"), ("medium banana", "^Bananas, raw"),
    ("large apple", "^Apples, raw"), ("half avocado", "^Avocados, raw"), ("8 oz chicken breast", "^Chicken breast"), ("12 oz steak", "^Steak"),
    ("16 oz latte", "^Coffee, Latte"), ("10 piece nuggets", "^Chicken nuggets"), ("20 piece mcnuggets", "^McDONALD'S, Chicken McNUGGETS"),
    ("2 slices pizza", "^Pizza"), ("3 tacos", "^Taco"), ("dozen eggs", "^Egg"), ("glass of wine", "^Alcoholic beverage, wine"),
    ("pint of ice cream", "^Ice cream"), ("shot of espresso", "^Coffee, espresso"), ("handful of nuts", "^Nuts, mixed nuts"),
    ("pat of butter", "^Butter"), ("scoop of ice cream", "^Ice cream"), ("two scoops ice cream", "^Ice cream"), ("splash of milk", "^Milk"),
    ("movie popcorn", "^Popcorn, movie theater"), ("large milkshake", "^Milk shake"), ("frosting", "^Frosting"),
    ("frosted flakes", "(?i:frosted flakes)"),
]

/// A food typed with how it was cut (chopped, diced, minced, sliced, cubed, crumbled,
/// grated): the food. Then the ones where a plain food lists the cut or the words name
/// what's sold in a can, and the ones that were right already.
let cutFoods: [(String, String)] = [
    ("chopped onion", "^Onions, raw"), ("chopped onions", "^Onions, raw"), ("diced onion", "^Onions, raw"), ("minced onion", "^Onions, raw"),
    ("sliced onion", "^Onions, raw"), ("diced red onion", "^Onions, raw"), ("chopped garlic", "^Garlic, raw"), ("minced garlic", "^Garlic, raw"),
    ("grated ginger", "^Ginger root"), ("chopped walnuts", "^Nuts, walnuts"), ("chopped pecans", "^Nuts, pecans"),
    ("chopped almonds", "^Nuts, almonds"), ("sliced almonds", "^Nuts, almonds"), ("chopped dates", "^Dates"), ("chopped carrots", "^Carrots, raw"),
    ("diced carrots", "^Carrots, raw"), ("sliced carrots", "^Carrots, raw"), ("chopped tomato", "^Tomatoes, red, ripe, raw"),
    ("sliced tomato", "^Tomatoes, red, ripe, raw"), ("chopped cilantro", "^Coriander"), ("chopped basil", "^Basil"),
    ("chopped spinach", "^Spinach, raw"), ("chopped kale", "^Kale, raw"), ("chopped cabbage", "^Cabbage, raw"),
    ("chopped broccoli", "^Broccoli, raw"), ("chopped romaine", "^Lettuce, cos or romaine"), ("torn lettuce", "^Lettuce"),
    ("chopped bell pepper", "^Peppers, sweet"), ("diced bell pepper", "^Peppers, sweet"), ("sliced bell pepper", "^Peppers, sweet"),
    ("diced green pepper", "^Peppers, sweet"), ("diced celery", "^Celery, raw"), ("diced avocado", "^Avocados"), ("diced potatoes", "^Potatoes"),
    ("cubed potatoes", "^Potatoes"), ("diced sweet potato", "^Sweet potato"), ("cubed sweet potato", "^Sweet potato"),
    ("diced jalapeno", "^Peppers, jalapeno"), ("sliced mushrooms", "^Mushrooms"), ("sliced zucchini", "^Squash, summer, zucchini"),
    ("grated zucchini", "^Squash, summer, zucchini"), ("sliced banana", "^Bananas, raw"), ("sliced strawberries", "^Strawberries, raw"),
    ("sliced apple", "^Apples, raw"), ("diced apple", "^Apples, raw"), ("sliced peaches", "^Peaches, yellow, raw"), ("diced mango", "^Mangos, raw"),
    ("diced pineapple", "^Pineapple, raw"), ("chopped chicken", "^Chicken, cooked"), ("diced chicken", "^Chicken, cooked"),
    ("cubed chicken", "^Chicken, cooked"), ("diced chicken breast", "^Chicken breast"), ("diced ham", "^Ham"), ("cubed ham", "^Ham"),
    ("sliced steak", "^Steak"), ("cubed pork", "^Pork"), ("cubed beef", "^Beef"), ("crumbled feta", "^Cheese, feta"),
    ("crumbled blue cheese", "^Cheese, blue"), ("crumbled bacon", "^Bacon"), ("cubed cheese", "^Cheese, cheddar"),
    ("grated cheddar", "^Cheese, cheddar"), ("grated mozzarella", "^Cheese, mozzarella"), ("grated coconut", "^Nuts, coconut meat"),
    ("chopped chocolate", "^Chocolate"), ("sliced ham", "^Ham, sliced"), ("sliced turkey", "^Turkey, prepackaged or deli"),
    ("sliced cheese", "^Cheese, cheddar, sharp, sliced"), ("shredded cheese", "^Cheese, .*shredded"),
    ("grated cheese", "^Cheese, parmesan, grated"), ("grated parmesan", "^Cheese, parmesan, grated"),
    ("crumbled beef", "^Beef, ground, .*crumbles"), ("shredded coconut", "^Nuts, coconut meat, dried .*shredded"),
    ("crushed tomatoes", "^Tomatoes, crushed, canned"), ("diced tomatoes", "^Tomatoes, red, ripe, canned"),
    ("sliced olives", "^Olives, ripe, canned"), ("sliced beets", "^Beets, canned"), ("sliced water chestnuts", "^Waterchestnuts, chinese, canned"),
    ("shredded chicken", "^Chicken, cooked"), ("shredded lettuce", "^Lettuce"), ("shredded wheat", "^Cereal, shredded wheat"),
    ("pulled pork", "^Barbecue pork"), ("cube steak", "^Beef, steak, cube"), ("cubed steak", "^Beef, steak, cube"),
    ("minced beef", "^Beef, ground"), ("chopped liver", "^Livers, chicken, chopped"), ("chopped salad", "^(Lettuce, salad|Salad)"),
    ("slice of pizza", "^Pizza"), ("cheese slice", "^Cheese"), ("ground beef", "^Beef, ground"),
]

/// A food typed with the shape it's cut or broken into (a lemon wedge, carrot sticks, feta
/// crumbles, spinach leaves), which is the food, and after them the foods named by a shape,
/// which are themselves: potato wedges, fish sticks, chicken strips, grape leaves.
let shapedFoods: [(String, String)] = [
    ("lemon wedge", "^Lemons, raw"), ("lime wedges", "^Limes, raw"), ("orange wedges", "^Oranges, raw"), ("apple wedges", "^Apples, raw"),
    ("watermelon wedge", "^Watermelon, raw"), ("tomato wedges", "^Tomatoes, red, ripe, raw"), ("cabbage wedge", "^Cabbage, raw"),
    ("lettuce wedge", "^Lettuce, iceberg"), ("cantaloupe wedge", "^Melons, cantaloupe"), ("carrot sticks", "^Carrots, raw"),
    ("celery sticks", "^Celery, raw"), ("cucumber sticks", "^Cucumber"), ("jicama sticks", "^Yambean"),
    ("zucchini sticks", "^Squash, summer, zucchini"), ("pretzel sticks", "^Snacks, pretzels"), ("cinnamon stick", "^Spices, cinnamon"),
    ("butter stick", "^Butter, salted"), ("pepper strips", "^Peppers, sweet"), ("bell pepper strips", "^Peppers, sweet"),
    ("bacon strips", "^Bacon, cooked"), ("cheese cubes", "^Cheese, cheddar"), ("melon cubes", "^Melons"), ("watermelon cubes", "^Watermelon, raw"),
    ("tofu cubes", "^Tofu"), ("mango cubes", "^Mangos, raw"), ("sugar cubes", "^Sugars, granulated"), ("blue cheese crumbles", "^Cheese, blue"),
    ("feta crumbles", "^Cheese, feta"), ("bacon crumbles", "^Bacon, cooked"), ("goat cheese crumbles", "^Cheese, goat"),
    ("orange segments", "^Oranges, raw"), ("grapefruit segments", "^Grapefruit, raw"), ("corn kernels", "^Corn, sweet"),
    ("spinach leaves", "^Spinach, raw"), ("spinach leaf", "^Spinach, raw"), ("basil leaves", "^Basil, fresh"), ("lettuce leaves", "^Lettuce"),
    ("mint leaves", "^(Peppermint|Spearmint), fresh"), ("cabbage leaves", "^Cabbage, raw"), ("kale leaves", "^Kale, raw"),
    ("romaine leaves", "^Lettuce, cos or romaine"), ("bay leaves", "^Spices, bay leaf"), ("parsley sprigs", "^Parsley, fresh"),
    ("cilantro sprigs", "^Coriander \\(cilantro\\) leaves, raw"), ("thyme sprigs", "^Thyme, fresh"), ("rosemary sprig", "^Rosemary, fresh"),
    ("mint sprig", "^(Peppermint|Spearmint), fresh"), ("dill sprigs", "^Dill weed, fresh"), ("romaine hearts", "^Lettuce, cos or romaine"),
    ("celery hearts", "^Celery, raw"), ("asparagus tips", "^Asparagus"), ("steak tips", "^Beef, steak, sirloin"),
    ("beef tips", "^Beef, steak, sirloin"), ("sirloin tips", "^Beef, steak, sirloin"), ("wing tips", "^Chicken wing"),
    ("broccoli crowns", "^Broccoli, raw"), ("almond slivers", "^Nuts, almonds"), ("chocolate shavings", "^Chocolate"),
    ("parmesan shavings", "^Cheese, parmesan"), ("carrot shreds", "^Carrots, raw"), ("cheese shreds", "^Cheese"),
    ("cabbage shreds", "^Cabbage, raw"), ("coconut shreds", "^Nuts, coconut meat"), ("coconut flakes", "^Nuts, coconut meat, dried"),
    ("pepper rings", "^Peppers"), ("squid rings", "^Mollusks, squid"), ("calamari rings", "^Calamari"), ("pineapple rings", "^Pineapple, canned"),
    ("carrot coins", "^Carrots, raw"), ("garlic bulb", "^Garlic, raw"), ("popcorn kernels", "^Popcorn"),
    ("cantaloupe chunks", "^Melons, cantaloupe"), ("pickle chips", "^Pickles"),
    ("butter pats", "^Butter, salted"), ("crab sticks", "^Imitation crab"), ("zoodles", "^Squash, summer, zucchini"),
    ("zucchini noodles", "^Squash, summer, zucchini"), ("potato wedges", "^Potato wedges"), ("fish sticks", "^Fish sticks"),
    ("bread sticks", "^Bread, sticks"), ("french toast sticks", "^French toast sticks"), ("mozzarella sticks", "(?i)mozzarella sticks"),
    ("cheese sticks", "^Cheese, mozzarella"), ("beef sticks", "^Snacks, beef sticks"), ("chicken strips", "^Chicken tenders or strips"),
    ("steak strips", "^Beef, steak, strip"), ("strip steak", "^Beef, steak, strip"), ("cube steak", "^Beef, steak, cube"),
    ("onion rings", "(?i)onion rings"), ("peach rings", "(?i)^peach rings"), ("apple rings", "(?i)^apple rings"), ("ice cubes", "(?i)^ice cube"),
    ("grape leaves", "^Grape leaves"), ("fennel bulb", "^Fennel, bulb"), ("chicken hearts", "^Chicken, heart"),
    ("beef heart", "^Beef, variety meats and by-products, heart"), ("leaf lettuce", "^Lettuce, (red|green) leaf"),
    ("sunflower kernels", "^Seeds, sunflower seed kernels"), ("hearts of palm", "^Hearts of palm"),
]

/// A food typed with what was done to it before it was eaten (slivered, pitted, peeled,
/// shelled, mashed, melted, leftover) or with "whole", and the foods those words name.
let preparedFoods: [(String, String)] = [
    ("slivered almonds", "^Nuts, almonds"), ("crushed garlic", "^Garlic, raw"), ("crushed peanuts", "^Peanuts"),
    ("crushed walnuts", "^Nuts, walnuts"), ("crushed pineapple", "^Pineapple, canned"), ("pineapple tidbits", "^Pineapple, canned"),
    ("crushed tomatoes", "^Tomatoes, crushed, canned"), ("crushed red pepper", "^Spices, pepper, red"), ("crushed ice", "(?i)^ice cube"),
    ("crushed crackers", "^Crackers"), ("crushed pretzels", "^Snacks, pretzels"), ("crushed oreos", "(?i)oreo"),
    ("mashed avocado", "^Avocados, raw"), ("smashed avocado", "^Avocados, raw"), ("mashed banana", "^Bananas, raw"),
    ("mashed potatoes", "^Potato, mashed"), ("mashed potato", "^Potato, mashed"), ("mashed sweet potato", "^Sweet potato"),
    ("mashed cauliflower", "^Cauliflower"), ("smashed burger", "^Hamburger"), ("pureed pumpkin", "^Pumpkin, canned"),
    ("pumpkin puree", "^Pumpkin, canned"), ("shaved parmesan", "^Cheese, parmesan"), ("shaved ham", "^Ham, sliced"),
    ("shaved turkey", "^Turkey, prepackaged or deli"), ("shaved steak", "^Steak, cooked|^Beef, steak"),
    ("shaved beef", "^Steak, cooked|^Beef, steak"), ("shaved ice", "^Snow cone"), ("shaved chocolate", "^Chocolate"),
    ("shaved brussels sprouts", "^Brussels sprouts"), ("shaved carrots", "^Carrots, raw"), ("julienned carrots", "^Carrots, raw"),
    ("matchstick carrots", "^Carrots, raw"), ("spiralized zucchini", "^Squash, summer, zucchini"), ("spiralized carrots", "^Carrots"),
    ("riced cauliflower", "^Cauliflower, raw"), ("cauliflower rice", "^Cauliflower, raw"), ("riced broccoli", "^Broccoli"),
    ("pitted olives", "^Olives, ripe"), ("pitted dates", "^Dates"), ("pitted cherries", "^Cherries"), ("pitted prunes", "^Prunes|^Plums, dried"),
    ("pitted green olives", "^Olives, pickled, canned or bottled, green"), ("peeled shrimp", "^Shrimp, cooked"),
    ("peeled deveined shrimp", "^Shrimp, cooked"), ("deveined shrimp", "^Shrimp, cooked"), ("peeled apple", "^Apples, raw, without skin"),
    ("peeled potatoes", "^Potatoes, .*flesh"), ("peeled potato", "^Potatoes, .*flesh"), ("peeled banana", "^Bananas, raw"),
    ("peeled orange", "^Oranges, raw, all"), ("peeled cucumber", "^Cucumber, peeled"), ("peeled carrots", "^Carrots, raw"),
    ("peeled garlic", "^Garlic, raw"), ("peeled lemon", "^Lemons, raw, without peel"), ("peeled kiwi", "^Kiwifruit"),
    ("peeled mango", "^Mangos, raw"), ("peeled zucchini", "^Squash, summer, zucchini"), ("peeled eggplant", "^Eggplant, raw"),
    ("peeled hard boiled egg", "^Egg, whole, cooked, hard-boiled"), ("peeled tomatoes", "^Tomatoes, red, ripe, canned"),
    ("shelled pistachios", "^Nuts, pistachio"), ("shelled edamame", "^Edamame"), ("shelled walnuts", "^Nuts, walnuts"),
    ("shelled peanuts", "^Peanuts"), ("shelled sunflower seeds", "^Seeds, sunflower seed kernels"),
    ("shelled pumpkin seeds", "^Seeds, pumpkin and squash seed kernels"), ("shelled peas", "^Peas, green"),
    ("seedless watermelon", "^Watermelon, raw"), ("seedless grapes", "^Grapes"), ("seedless raisins", "^Raisins"),
    ("seedless cucumber", "^Cucumber"), ("trimmed green beans", "^Beans, snap, green"), ("trimmed asparagus", "^Asparagus"),
    ("stemmed strawberries", "^Strawberries, raw"), ("stemmed kale", "^Kale, raw"), ("hulled strawberries", "^Strawberries, raw"),
    ("hulled hemp seeds", "^Seeds, hemp seed, hulled"), ("hulled barley", "^Barley, hulled"), ("cored apple", "^Apples, raw"),
    ("cored pineapple", "^Pineapple, raw"), ("deboned chicken", "^Chicken, cooked"), ("melted butter", "^Butter, salted"),
    ("melted cheese", "^Cheese"), ("melted chocolate", "^Chocolate"), ("softened butter", "^Butter, salted"), ("beaten egg", "^Egg, whole, raw"),
    ("beaten eggs", "^Egg, whole, raw"), ("whisked eggs", "^Egg, whole, raw"), ("leftover pizza", "^Pizza"),
    ("leftover chicken", "^Chicken, cooked"), ("leftover turkey", "^Turkey, cooked"), ("rinsed black beans", "^Beans, black"),
    ("washed spinach", "^Spinach, raw"), ("soaked almonds", "^Nuts, almonds"), ("thawed shrimp", "^Shrimp"),
    ("chilled watermelon", "^Watermelon, raw"), ("flaked almonds", "^Nuts, almonds"), ("flaked salmon", "^Fish, salmon"),
    ("flaked coconut", "^Nuts, coconut meat, dried"), ("green chiles", "^Peppers, chili, green"), ("diced green chiles", "^Peppers, chili, green"),
    ("canned green chiles", "^Peppers, chili, green"), ("stew meat", "^Beef, stew meat"), ("pepitas", "^Seeds, pumpkin and squash seed kernels"),
    ("peppercorns", "^Spices, pepper, black"), ("whole avocado", "^Avocados, raw"),
    ("a whole avocado", "^Avocados, raw"), ("whole banana", "^Bananas, raw"), ("whole apple", "^Apples, raw"), ("whole lemon", "^Lemons"),
    ("whole chicken", "^Chicken, cooked"), ("whole rotisserie chicken", "^Chicken, rotisserie"), ("whole strawberries", "^Strawberries, raw"),
    ("whole almonds", "^Nuts, almonds"), ("whole cashews", "^Nuts, cashew"), ("whole pecans", "^Nuts, pecans"), ("whole walnuts", "^Nuts, walnuts"),
    ("whole oats", "^Oats"), ("whole flaxseed", "^Seeds, flaxseed"), ("whole pizza", "^Pizza, cheese, from restaurant"),
    ("whole cloves", "^Spices, cloves"), ("whole carrot", "^Carrots, raw"), ("whole pickle", "^Pickles"), ("whole bagel", "^Bagels, plain"),
    ("whole sandwich", "^Sandwich"), ("whole milk", "^Milk, whole"), ("whole wheat bread", "^Bread, whole-wheat"),
    ("whole grain bread", "^Bread, multi-grain"), ("whole grain rice", "^Rice, brown"), ("whole egg", "^Egg, whole"),
    ("whole wheat pasta", "^Pasta, whole-wheat"), ("whole milk yogurt", "^Yogurt, plain, whole milk"),
    ("whole kernel corn", "^Corn, .*whole kernel"), ("whole wheat tortilla", "^Tortillas, .*whole wheat"),
    ("whole wheat pizza", "^Pizza, cheese, whole wheat"),
]

/// A food typed with the state it's in, how it was bought or how finely it was cut (ripe,
/// warm, cold, store bought, thick cut, medium rare, frozen), which is the food, with what
/// comes second where the search is two foods ("buttered toast"). The last are the foods
/// those words name: frozen yogurt, cold brew, a hot dog.
let stateFoods: [(typed: String, first: String, second: String)] = [
    ("ripe banana", "^Bananas, raw", ""), ("ripe avocado", "^Avocados, raw", ""), ("ripe mango", "^Mangos, raw", ""),
    ("ripe tomato", "^Tomatoes, red, ripe, raw", ""), ("ripe plantain", "^Plantains, yellow", ""), ("ripe pear", "^Pears, raw", ""),
    ("ripe peach", "^Peaches", ""), ("ripe strawberries", "^Strawberries, raw", ""), ("very ripe banana", "^Bananas, raw", ""),
    ("overripe banana", "^Bananas, raw", ""), ("unripe banana", "^Bananas, raw", ""), ("green banana", "^Bananas, raw", ""),
    ("warm milk", "^Milk, whole", ""), ("warm bread", "^Bread", ""), ("warm water", "^Water", ""), ("warm cookie", "^Cookie", ""),
    ("hot coffee", "^Coffee", ""), ("hot water", "^Water", ""), ("hot milk", "^Milk, whole", ""), ("hot oatmeal", "^Cereals, oats|^Oatmeal", ""),
    ("hot soup", "^Soup", ""), ("hot latte", "^Coffee, Latte", ""), ("cold water", "^Water", ""), ("cold milk", "^Milk, whole", ""),
    ("cold chicken", "^Chicken, cooked", ""), ("cold pasta", "^Pasta, cooked", ""), ("cold rice", "^Rice, white", ""), ("cold pizza", "^Pizza", ""),
    ("cold coffee", "^Coffee", ""), ("cold beer", "^Alcoholic beverage, beer|^Beer", ""), ("cold turkey sandwich", "^Turkey sandwich", ""),
    ("room temperature water", "^Water", ""), ("stale bread", "^Bread", ""), ("stale chips", "^Potato chips", ""),
    ("day old rice", "^Rice, white", ""), ("day old bread", "^Bread", ""), ("classic burger", "^Hamburger", ""), ("classic hummus", "^Hummus", ""),
    ("classic cheesecake", "(?i)cheesecake", ""), ("traditional hummus", "^Hummus", ""), ("traditional lasagna", "^Lasagna", ""),
    ("normal milk", "^Milk, whole", ""), ("normal yogurt", "^Yogurt, plain", ""), ("generic cola", "^Beverages, carbonated, cola", ""),
    ("store brand cola", "^Beverages, carbonated, cola", ""), ("store bought cookies", "^Cookie", ""), ("store bought hummus", "^Hummus", ""),
    ("store bought bread", "^Bread", ""), ("store bought rotisserie chicken", "^Chicken, rotisserie", ""), ("takeout pizza", "^Pizza", ""),
    ("takeout burger", "^Hamburger", ""), ("delivery pizza", "^Pizza", ""), ("carryout pizza", "^Pizza", ""),
    ("takeaway curry", "^Chicken curry", ""), ("gourmet burger", "^Hamburger", ""), ("gourmet popcorn", "^Popcorn", ""),
    ("artisan bread", "^Bread", ""), ("premium ice cream", "^Ice cream", ""), ("freshly squeezed orange juice", "^Orange juice, raw", ""),
    ("fresh squeezed orange juice", "^Orange juice, raw", ""), ("freshly squeezed lemon juice", "^Lemon juice, raw", ""),
    ("squeezed lemon", "^Lemons, raw", ""), ("freshly ground pepper", "^Spices, pepper, black", ""),
    ("fresh ground pepper", "^Spices, pepper, black", ""), ("freshly ground black pepper", "^Spices, pepper, black", ""),
    ("coarsely ground pepper", "^Spices, pepper, black", ""), ("freshly grated parmesan", "^Cheese, parmesan, grated", ""),
    ("freshly brewed coffee", "^Coffee, brewed|^Beverages, coffee, brewed", ""),
    ("fresh brewed coffee", "^Coffee, brewed|^Beverages, coffee, brewed", ""), ("freshly baked bread", "^Bread", ""),
    ("fresh baked cookies", "^Cookie", ""), ("freshly made guacamole", "^Guacamole", ""), ("finely chopped onion", "^Onions, raw", ""),
    ("roughly chopped cilantro", "^Coriander \\(cilantro\\) leaves, raw", ""), ("thinly sliced turkey", "^Turkey, prepackaged or deli", ""),
    ("thin sliced turkey", "^Turkey, prepackaged or deli", ""), ("thinly sliced ham", "^Ham, sliced", ""),
    ("thinly sliced onion", "^Onions, raw", ""), ("thick cut bacon", "^Bacon, cooked", ""), ("thick sliced bacon", "^Bacon, cooked", ""),
    ("thick sliced bread", "^Bread", ""), ("thick cut fries", "^Potato, french fries", ""), ("thin cut pork chop", "^Pork, chop", ""),
    ("well done steak", "^Steak, cooked|^Beef, steak", ""), ("medium rare steak", "^Steak, cooked|^Beef, steak", ""),
    ("medium well steak", "^Steak, cooked|^Beef, steak", ""), ("rare steak", "^Steak, cooked|^Beef, steak", ""),
    ("rare roast beef", "^Beef, roast", ""), ("buttered toast", "^Bread, wheat, toasted", "^Butter"), ("buttered noodles", "^Noodles", "^Butter"),
    ("buttered corn", "^Corn", "^Butter"), ("buttered bread", "^Bread", "^Butter"), ("buttered roll", "^Rolls", "^Butter"),
    ("lightly buttered toast", "^Bread, wheat, toasted", "^Butter"), ("buttered popcorn", "^Popcorn.*butter", ""),
    ("assorted nuts", "^Nuts, mixed nuts", ""), ("assorted fruit", "^Fruit", ""),
    ("spring mix", "^Lettuce, green leaf", ""), ("salad greens", "^Lettuce, green leaf", ""), ("frozen banana", "^Bananas, raw", ""),
    ("frozen bananas", "^Bananas, raw", ""), ("frozen grapes", "^Grapes", ""), ("frozen mango", "^Mangos, raw", ""),
    ("frozen avocado", "^Avocados, raw", ""), ("frozen chicken breast", "^Chicken breast, cooked", ""), ("frozen salmon", "^Fish, salmon", ""),
    ("frozen tilapia", "^Fish, tilapia", ""), ("frozen cod", "^Fish, cod", ""), ("frozen yogurt", "^Frozen yogurt", ""),
    ("frozen pizza", "^Pizza, .*frozen", ""), ("frozen peas", "^Peas, green, frozen", ""), ("frozen strawberries", "^Strawberries, frozen", ""),
    ("frozen blueberries", "^Blueberries, frozen", ""), ("frozen spinach", "^Spinach, frozen", ""),
    ("frozen waffles", "^Waffle, plain, frozen", ""), ("frozen fruit", "^Fruit mixture, frozen", ""),
    ("frozen vegetables", "^Vegetables, mixed, frozen", ""), ("frozen berries", "^Berries, frozen", ""),
    ("frozen custard", "(?i)^frozen custard", ""), ("frozen lemonade", "^Lemonade, frozen", ""),
    ("frozen fries", "^Potato, french fries, from frozen", ""), ("cold brew", "(?i)^iced coffee|cold brew", ""),
    ("cold cuts", "(?i)^turkey, prepackaged or deli|cold cuts", ""), ("cold cut sandwich", "(?i)cold cut", ""),
    ("cold pressed juice", "(?i)cold.pressed", ""), ("hot dog", "^Hot dog", ""), ("hot chocolate", "^Hot chocolate", ""),
    ("hot sauce", "^Sauce, .*hot", ""), ("hot tea", "^Tea, hot", ""), ("hot cereal", "^Cereals, .*hot", ""), ("hot wings", "(?i)wings", ""),
    ("hot peppers", "^Peppers, hot", ""), ("hot and sour soup", "^Soup, hot and sour", ""), ("hot fudge sundae", "(?i)hot fudge", ""),
    ("original glazed donut", "(?i)original glazed", ""), ("original recipe chicken", "ORIGINAL RECIPE", ""),
    ("simple syrup", "(?i)^simple syrup", ""), ("ripe olives", "^Olives, ripe", ""), ("whole milk", "^Milk, whole", ""),
]

/// A food typed with how it was raised, caught or sold (free range, cage free, wild caught,
/// local, halal), which is the food, and what's made without meat by the name of what it
/// stands in for, which is the catalog's meatless one. The last are the foods those words do
/// name: grass-fed beef, wild salmon, wild rice, and the brands.
let raisedFoods: [(String, String)] = [
    ("free range eggs", "^Egg, whole"), ("cage free eggs", "^Egg, whole"), ("pasture raised eggs", "^Egg, whole"), ("pastured eggs", "^Egg, whole"),
    ("farm fresh eggs", "^Egg, whole"), ("brown eggs", "^Egg, whole"), ("large brown eggs", "^Egg, whole"), ("extra large eggs", "^Egg, whole"),
    ("extra large egg", "^Egg, whole"), ("free range chicken", "^Chicken, cooked"), ("free range chicken breast", "^Chicken breast, cooked"),
    ("halal chicken", "^Chicken, cooked"), ("antibiotic free chicken", "^Chicken, cooked"), ("wild caught salmon", "^Fish, salmon"),
    ("farm raised salmon", "^Fish, salmon"), ("wild caught shrimp", "^Shrimp, cooked"), ("wild caught tuna", "^Fish, tuna"),
    ("line caught tuna", "^Fish, tuna"), ("local honey", "^Honey"), ("local milk", "^Milk, whole"), ("hormone free milk", "^Milk, whole"),
    ("grass fed milk", "^Milk, whole"), ("grass fed butter", "^Butter, salted"), ("non gmo tofu", "^Tofu"),
    ("homegrown tomatoes", "^Tomatoes, red, ripe, raw"), ("vegan burger", "^Veggie burger"), ("vegetarian burger", "^Veggie burger"),
    ("plant based burger", "^Veggie burger"), ("meatless burger", "^Veggie burger"), ("soy burger", "^Veggie burger"),
    ("vegan sausage", "^Sausage, meatless"), ("vegetarian sausage", "^Sausage, meatless"), ("veggie sausage", "^Sausage, meatless"),
    ("veggie dog", "^Frankfurter, meatless"), ("vegan hot dog", "^Frankfurter, meatless"), ("vegan bacon", "^Bacon, meatless"),
    ("veggie bacon", "^Bacon, meatless"), ("vegan meatballs", "^Meatballs, meatless"), ("vegan chicken", "^Chicken, meatless"),
    ("plant based chicken", "^Chicken, meatless"), ("vegan nuggets", "^Chicken, meatless, breaded"),
    ("vegan chicken nuggets", "^Chicken, meatless, breaded"), ("shrooms", "^Mushrooms"), ("sammy", "^Sandwich"),
    ("grass fed beef", "^Beef, grass-fed"), ("grass fed steak", "^Beef, grass-fed"), ("wild salmon", "^Fish, salmon, .*wild"),
    ("farmed salmon", "^Fish, salmon, .*farmed"), ("wild rice", "^Wild rice"), ("veggie burger", "^Veggie burger"),
    ("meatless meatballs", "^Meatballs, meatless"), ("impossible burger", "(?i)impossible"), ("beyond burger", "(?i)beyond"),
    ("vegan cheese", "(?i)vegan cheese"), ("vegan butter", "(?i)vegan butter"), ("organic milk", "^Milk, whole"), ("jumbo eggs", "^Egg, whole"),
    ("extra large pizza", "^Pizza"),
]

/// First results that an earlier list's pattern accepted and a person wouldn't: SR Legacy's
/// composite of pork cuts for "pork", microwaved green beans, 45% dark chocolate for
/// "chocolate", a label for "tahini". The last are searches that say more and stay as they were.
let plainFirsts: [(String, String)] = [
    ("pork", "^Pork, cooked$"), ("green beans", "^Beans, snap, green, cooked, boiled"), ("chocolate", "^Chocolate candy$"),
    ("stir fry", "^Chicken or turkey and vegetables, with soy-based sauce"), ("tahini", "^Tahini$"), ("tzatziki", "^Tzatziki dip"),
    ("gnocchi", "^Gnocchi, potato"), ("arepa", "^Restaurant, Latino, arepa"), ("cookie dough", "^Cookie dough, raw"),
    ("coffee cake", "^Coffee cake, crumb"), ("snack mix", "^Snack mix$"), ("caramel sauce", "^Topping, butterscotch or caramel"),
    ("yellow onion", "^Onions, raw"), ("oatmeal", "^Oatmeal$"), ("ham", "^Ham$"), ("beer", "^Beer$"), ("grits", "^Grits$"),
    ("chocolate milk", "^Chocolate milk$"), ("oatmeal cookie", "^Cookie, oatmeal"), ("bran", "^Wheat bran"), ("brand", "^Brandy"),
    // As they were.
    ("microwaved green beans", "^Beans, snap, green, microwaved"), ("sauteed yellow onion", "^Onions, yellow, sauteed"),
    ("dark chocolate", "^Dark chocolate candy"), ("chocolate chip cookie dough", "^Cookies, chocolate chip, refrigerated dough"),
    ("grilled chicken breast", "^Chicken breast, grilled, without skin"), ("peanut butter cup", "^Chocolate candy, peanut butter filled"),
    ("trail mix", "^Snacks, trail mix"), ("pulled pork", "^Barbecue pork"), ("veggie stir fry", "^Tofu and vegetables"),
    ("light beer", "^Beer, light"), ("instant oatmeal", "(?i)oatmeal, instant|oats, instant"), ("honey ham", "(?i)ham, honey|honey ham"),
]

/// Everyday foods the survey has and SR Legacy doesn't, or not by the name they're asked for,
/// and the other names a few are asked by. The last are foods that were right and stay so.
let surveyFoods: [(String, String)] = [
    ("oat milk", "^Oat milk$"), ("oatmilk", "^Oat milk$"), ("almond milk", "^Almond milk"),
    ("unsweetened almond milk", "^Almond milk, unsweetened"), ("chocolate almond milk", "^Almond milk, chocolate"), ("rice milk", "^Rice milk"),
    ("soy milk", "^Soy milk"), ("coconut milk beverage", "^Coconut milk beverage"), ("plant milk", "^Non-dairy milk"),
    ("soy yogurt", "^Soy yogurt"), ("coconut yogurt", "^Coconut milk yogurt"), ("almond milk yogurt", "^Almond milk yogurt"),
    ("scone", "^Scone$"), ("scones", "^Scone$"), ("blueberry scone", "^Scone, with fruit"), ("muffin", "^Muffin$"),
    ("chocolate chip muffin", "^Muffin, chocolate chip"), ("pumpkin muffin", "^Muffin, pumpkin"), ("banana nut muffin", "^Muffin, fruit"),
    ("zucchini bread", "^Bread, zucchini"), ("pumpkin bread", "^Bread, pumpkin"), ("banana nut bread", "^Bread, nut"),
    ("hush puppies", "^Hush pupp"), ("biscuit", "^Biscuit$"), ("coffee creamer", "^Coffee creamer"), ("creamer", "^Coffee creamer"),
    ("beet juice", "^Beet juice"), ("beetroot juice", "^Beet juice"), ("celery juice", "^Celery juice"),
    ("watermelon juice", "^Watermelon juice"), ("dried mango", "^Mango, dried"), ("dried pineapple", "^Pineapple, dried"),
    ("dried papaya", "^Papaya, dried"), ("pickled okra", "^Pickled okra"), ("pickled vegetables", "^Pickled vegetables"),
    ("chutney", "^Chutney"), ("mango chutney", "^Chutney"), ("buffalo sauce", "^Buffalo sauce"), ("wing sauce", "^Buffalo sauce"),
    ("fry sauce", "^Fry sauce"), ("simple syrup", "^Simple syrup"), ("caramel dip", "^Caramel dip"), ("honey butter", "^Honey butter"),
    ("cheese ball", "^Cheese ball"), ("paneer", "^Cheese, paneer"), ("colby jack", "^Cheese, Colby Jack"),
    ("caramel apple", "^Apple, candied"), ("candy apple", "^Apple, candied"), ("tapenade", "^Olive tapenade"),
    ("stuffed olives", "^Stuffed olives"), ("vodka sauce", "^Vodka sauce"), ("poppy seed dressing", "^Poppy seed dressing"),
    ("catalina dressing", "^French or Catalina dressing"), ("italian dressing", "^Salad dressing, italian dressing"),
    ("soy nuts", "^Soy nuts"), ("cinnamon sugar", "^Sugar, cinnamon"), ("tvp", "^Textured vegetable protein"),
    ("honey roasted peanuts", "^Honey roasted peanuts"), ("honey roasted cashews", "^Honey roasted cashews"),
    // Other names for foods the catalog had.
    ("turkey gravy", "^Gravy, poultry"), ("chicken gravy", "^Gravy, poultry"), ("latke", "^Potato pancake"),
    ("latkes", "^Potato pancake"), ("seven layer dip", "^Layer dip"), ("bear claw", "^Danish pastry"),
    ("flax seeds", "^Seeds, flaxseed"), ("flax", "^Seeds, flaxseed"), ("water chestnuts", "^Waterchestnuts"),
    ("multigrain bread", "^Bread, multi-grain"), ("salted almonds", "^Nuts, almonds, dry roasted, with salt"),
    ("salted cashews", "^Nuts, cashew nuts, dry roasted, with salt"), ("salted peanuts", "^Peanuts, all types, dry-roasted, with salt"),
    ("salted pecans", "^Nuts, pecans, dry roasted, with salt"), ("salted nuts", "^Nuts, mixed nuts, dry roasted"),
    // As they were.
    ("yogurt", "^Yogurt, plain"), ("coconut milk", "^Nuts, coconut milk"), ("blueberry muffin", "^Muffins, blueberry"),
    ("english muffin", "^Muffins, English"), ("corn muffin", "^Muffins, corn"), ("banana bread", "^Bread, banana"),
    ("beef gravy", "^Gravy, beef"), ("unsalted almonds", "^Nuts, almonds, dry roasted, without salt"), ("almonds", "^Nuts, almonds"),
    ("dumplings", "^Wonton, dumpling"), ("hot chocolate", "^Hot chocolate"), ("half and half", "^Cream, fluid, half and half"),
    ("milk", "^Milk, whole"), ("honey mustard", "^Salad dressing, honey mustard"), ("wasabi", "^Wasabi"),
    ("biscuits and gravy", "^Biscuit with gravy"), ("cashews", "^Nuts, cashew nuts, raw"), ("peanuts", "^Peanuts, all types, raw"),
    ("olives", "^Olives, ripe"), ("relish", "^Pickle relish"), ("zucchini", "^Squash, summer, zucchini"),
    ("fresh zucchini", "^Squash, summer, zucchini"), ("okra", "^Okra, raw"), ("fresh relish", "^Pickle relish"),
]

/// Drinks as they're ordered: a coffee drink with its milk said after it, a smoothie by its
/// fruit, a tea by its kind, and a few said short. The last are the drinks that were right.
let drinkOrders: [(String, String)] = [
    ("latte with oat milk", "^Coffee, Latte, with non-dairy milk"), ("latte with almond milk", "^Coffee, Latte, with non-dairy milk"),
    ("latte with soy milk", "^Coffee, Latte, with non-dairy milk"), ("latte with whole milk", "^Coffee, Latte$"),
    ("latte with milk", "^Coffee, Latte$"), ("latte with skim milk", "^Coffee, Latte, nonfat"),
    ("cappuccino with oat milk", "^Coffee, Cappuccino, with non-dairy milk"),
    ("mocha with almond milk", "^Coffee, Cafe Mocha, with non-dairy milk"),
    ("iced latte with oat milk", "^Coffee, Iced Latte, with non-dairy milk"), ("flat white with oat milk", "^Coffee, Latte, with non-dairy milk"),
    ("oat milk flat white", "^Coffee, Latte, with non-dairy milk"), ("oat milk latte", "^Coffee, Latte, with non-dairy milk"),
    ("flat white", "^Coffee, Latte$"), ("strawberry banana smoothie", "^Fruit smoothie"), ("banana smoothie", "^Fruit smoothie"),
    ("berry smoothie", "^Fruit smoothie"), ("mango smoothie", "^Fruit smoothie"), ("kale smoothie", "^Fruit and vegetable smoothie"),
    ("protein smoothie", "^Fruit smoothie, .*added protein"), ("green smoothie", "^Vegetable smoothie"), ("smoothie", "^Fruit smoothie"),
    ("mint tea", "^Beverages, tea, herb|^Tea, hot, herbal"), ("peppermint tea", "^Beverages, tea, herb|^Tea, hot, herbal"),
    ("rooibos tea", "^Beverages, tea, herb|^Tea, hot, herbal"), ("jasmine tea", "^Beverages, tea, green"), ("white tea", "^Beverages, tea, green"),
    ("earl grey", "^Beverages, tea, black"), ("english breakfast tea", "^Beverages, tea, black"), ("pink lemonade", "^Lemonade, fruit juice drink"),
    ("unsweet tea", "^Tea, iced, brewed, black, unsweetened"), ("psl", "^Coffee, Latte, flavored"), ("espresso shot", "^Coffee, espresso"),
    ("double espresso", "^Coffee, espresso"), ("decaf americano", "^Coffee, decaffeinated"), ("cortado", "^Coffee, macchiato"),
    ("breve", "^Coffee, Latte"), ("cafe au lait", "^Coffee, cafe con leche"), ("taro milk tea", "^Tea, bubble"),
    ("brown sugar boba", "^Tea, bubble"), ("latte", "^Coffee, Latte$"), ("iced latte", "^Coffee, Iced Latte"),
    ("cappuccino", "^Coffee, Cappuccino"), ("mocha", "^Coffee, Cafe Mocha"), ("americano", "^Coffee, brewed"), ("cold brew", "^Iced Coffee"),
    ("chamomile tea", "^Tea, hot, chamomile"), ("green tea", "^Beverages, tea, green"), ("bubble tea", "^Tea, bubble"), ("lemonade", "^Lemonade"),
    ("iced tea", "^Tea, iced, brewed, black, unsweetened"), ("sweet tea", "^Tea, iced, brewed, black, pre-sweetened"),
    ("hot chocolate", "^Hot chocolate"), ("milkshake", "^Milk shake"), ("kombucha", "^Tea, kombucha"), ("sparkling water", "^Water, carbonated"),
]

/// A food typed with what it's bought, served or counted by ("bag of chips", "head of lettuce",
/// "12 pack coke") or with its number as a word ("two eggs", "three slices of pizza"), each
/// with the food alone: the same food comes first for both.
let amountsSaid: [(typed: String, food: String)] = [
    ("bag of chips", "chips"), ("bag of popcorn", "popcorn"), ("box of cereal", "cereal"), ("jar of peanut butter", "peanut butter"),
    ("tub of yogurt", "yogurt"), ("carton of milk", "milk"), ("carton of eggs", "eggs"), ("packet of oatmeal", "oatmeal"),
    ("pouch of tuna", "tuna"), ("head of lettuce", "lettuce"), ("head of garlic", "garlic"), ("ear of corn", "corn on the cob"),
    ("bunch of grapes", "grapes"), ("bunch of bananas", "bananas"), ("stick of butter", "butter"), ("loaf of bread", "bread"),
    ("block of cheese", "cheese"), ("block of tofu", "tofu"), ("sleeve of crackers", "crackers"), ("pack of gum", "gum"),
    ("package of ramen", "ramen"), ("container of yogurt", "yogurt"), ("tin of sardines", "sardines"), ("sprig of parsley", "parsley"),
    ("basket of fries", "fries"), ("portion of rice", "rice"), ("helping of mashed potatoes", "mashed potatoes"), ("tray of sushi", "sushi"),
    ("platter of nachos", "nachos"), ("pitcher of beer", "beer"), ("jug of milk", "milk"), ("clove of garlic", "garlic"),
    ("stalk of celery", "celery"), ("2 bags of chips", "chips"), ("12 pack coke", "coke"), ("6 pack beer", "beer"), ("2 ears corn", "corn"),
    ("1 stick butter", "butter"), ("3 bunches kale", "kale"), ("small bag of chips", "chips"), ("two eggs", "eggs"), ("three eggs", "eggs"),
    ("one egg", "egg"), ("one banana", "banana"), ("one apple", "apple"), ("two slices of pizza", "pizza"), ("three pancakes", "pancakes"),
    ("four tacos", "tacos"), ("six nuggets", "nuggets"), ("two cups of rice", "rice"), ("three tablespoons peanut butter", "peanut butter"),
    ("two scoops ice cream", "ice cream"), ("one slice of bread", "bread"), ("two pieces of toast", "toast"), ("five almonds", "almonds"),
    ("ten grapes", "grapes"), ("twelve wings", "wings"), ("two beers", "beer"), ("three cookies", "cookies"),
    ("two scrambled eggs", "scrambled eggs"), ("two fried eggs", "fried eggs"), ("two large eggs", "eggs"), ("four fish tacos", "fish tacos"),
    ("two chicken breasts", "chicken breasts"), ("three chicken wings", "chicken wings"), ("two hard boiled eggs", "hard boiled eggs"),
    ("bowl of cereal", "cereal"), ("glass of milk", "milk"), ("can of tuna", "tuna"), ("slice of pizza", "pizza"), ("piece of cake", "cake"),
    ("scoop of ice cream", "ice cream"), ("handful of almonds", "almonds"), ("cup of coffee", "coffee"), ("bottle of water", "water"),
    ("side of fries", "fries"),
]

/// Foods typed in Spanish, and by their Hindi or Indian-English names, each with the English
/// search it's read as: the same food comes first for both.
let otherLanguages: [(typed: String, english: String)] = [
    ("pollo", "chicken"), ("arroz", "rice"), ("frijoles", "beans"), ("huevos", "eggs"), ("huevo", "egg"), ("leche", "milk"), ("carne", "meat"),
    ("cerdo", "pork"), ("puerco", "pork"), ("pescado", "fish"), ("camarones", "shrimp"), ("atun", "tuna"), ("jamon", "ham"), ("tocino", "bacon"),
    ("salchicha", "sausage"), ("pavo", "turkey"), ("papas", "potato"), ("papas fritas", "french fries"), ("cebolla", "onion"), ("ajo", "garlic"),
    ("aguacate", "avocado"), ("lechuga", "lettuce"), ("zanahoria", "carrot"), ("maiz", "corn"),
    ("manzana", "apple"), ("naranja", "orange"), ("fresas", "strawberries"), ("uvas", "grapes"), ("sandia", "watermelon"),
    ("mantequilla", "butter"), ("azucar", "sugar"), ("aceite", "oil"), ("harina", "flour"), ("avena", "oatmeal"), ("jugo", "juice"),
    ("jugo de naranja", "orange juice"), ("jugo de manzana", "apple juice"), ("agua", "water"), ("cerveza", "beer"), ("vino", "wine"),
    ("refresco", "soda"), ("frijoles negros", "black beans"), ("frijoles refritos", "refried beans"), ("frijoles pintos", "pinto beans"),
    ("arroz con leche", "rice pudding"), ("sopa", "soup"), ("ensalada", "salad"), ("pechuga de pollo", "chicken breast"),
    ("pechuga", "chicken breast"), ("carne molida", "ground beef"), ("carne de res", "beef"), ("bistec", "steak"), ("chuleta", "pork chop"),
    ("costillas", "ribs"), ("calabaza", "squash"), ("calabacita", "zucchini"), ("ejotes", "green beans"), ("espinacas", "spinach"),
    ("coliflor", "cauliflower"), ("repollo", "cabbage"), ("pepino", "cucumber"), ("champinones", "mushrooms"), ("hongos", "mushrooms"),
    ("nueces", "walnuts"), ("cacahuates", "peanuts"), ("almendras", "almonds"), ("miel", "honey"), ("mermelada", "jam"), ("galletas", "cookies"),
    ("pastel", "cake"), ("helado", "ice cream"), ("palomitas", "popcorn"), ("tortilla de maiz", "corn tortilla"),
    ("tortillas de harina", "flour tortillas"), ("arroz blanco", "white rice"), ("arroz integral", "brown rice"),
    ("pollo frito", "fried chicken"), ("pollo a la plancha", "grilled chicken"), ("pechuga de pollo asada", "grilled chicken breast"),
    ("pan blanco", "white bread"), ("pan integral", "whole wheat bread"), ("pan tostado", "toast"), ("te verde", "green tea"),
    ("cafe negro", "black coffee"), ("leche entera", "whole milk"), ("leche descremada", "skim milk"), ("leche de almendra", "almond milk"),
    ("leche de coco", "coconut milk"), ("agua de coco", "coconut water"), ("agua mineral", "sparkling water"),
    ("huevos revueltos", "scrambled eggs"), ("huevo duro", "hard boiled egg"), ("claras de huevo", "egg whites"), ("queso crema", "cream cheese"),
    ("crema de cacahuate", "peanut butter"), ("aceite de oliva", "olive oil"), ("ensalada de pollo", "chicken salad"),
    ("ensalada de atun", "tuna salad"), ("sopa de verduras", "vegetable soup"), ("carne de res molida", "ground beef"),
    ("bolillo", "french roll"), ("lengua", "beef tongue"), ("caldo", "broth"), ("2 huevos", "2 eggs"), ("pure de papa", "mashed potatoes"),
    ("chuleta de puerco", "pork chop"), ("alitas de pollo", "chicken wings"), ("berenjena", "eggplant"), ("apio", "celery"),
    ("toronja", "grapefruit"), ("durazno", "peach"), ("camote", "sweet potato"), ("langosta", "lobster"), ("tomate", "tomato"),
    ("verduras", "vegetables"), ("fruta", "fruit"), ("yogur", "yogurt"), ("lentejas", "lentils"), ("brinjal", "eggplant"), ("bhindi", "okra"),
    ("maida", "all purpose flour"), ("atta", "whole wheat flour"), ("dal", "lentil curry"), ("daal", "lentil curry"), ("chana", "chickpeas"),
    ("chole", "chickpeas"), ("rajma", "kidney beans"), ("aloo", "potato"), ("gobi", "cauliflower"), ("palak", "spinach"), ("dahi", "yogurt"),
    ("doodh", "milk"), ("anda", "egg"), ("murgh", "chicken"), ("keema", "ground meat"), ("methi", "fenugreek"), ("jeera", "cumin"),
    ("haldi", "turmeric"), ("dhania", "coriander"), ("adrak", "ginger"), ("lehsun", "garlic"), ("pyaz", "onion"), ("tamatar", "tomato"),
    ("kela", "banana"), ("aam", "mango"), ("seb", "apple"), ("nimbu", "lemon"), ("chawal", "rice"), ("sooji", "semolina"), ("rava", "semolina"),
    ("sabudana", "tapioca"), ("makhan", "butter"), ("pulao", "rice pilaf"), ("kheer", "rice pudding"), ("moong dal", "mung beans"),
    ("masoor dal", "red lentils"), ("toor dal", "pigeon peas"), ("matar", "peas"), ("gajar", "carrot"), ("kaju", "cashews"), ("badam", "almonds"),
]

/// Names in those languages that the catalogs have as typed, and English searches made of words
/// that are also Spanish ("pan pizza", "pina colada"), each with the food that comes first.
let keptAsTyped: [(String, String)] = [
    ("huevos rancheros", "^Huevos rancheros"), ("carne asada", "(?i)^carne asada"), ("pollo asado", "^Pollo asado"),
    ("caldo de pollo", "^Soup, sopa or caldo de pollo"), ("sopa de pollo", "^Soup, sopa or caldo de pollo"),
    ("arroz con pollo", "(?i)arroz con pollo"), ("pan dulce", "^Pan dulce"), ("queso fresco", "^Cheese, fresh, queso fresco"),
    ("queso", "^Cheese dip"), ("pozole", "^Soup, pozole"), ("tamales", "^Tamale"), ("horchata", "^Horchata"),
    ("dulce de leche", "(?i)dulce de leche"), ("salsa verde", "^Salsa verde"), ("pan pizza", "(?i)^pan pizza"), ("masa harina", "^Masa harina"),
    ("pina colada", "^Pina Colada"), ("pina", "^Pina Colada"), ("pan", "^Pancakes"), ("sal", "^Fish, salmon"),
    ("dal makhani", "(?i)^dal makhani"), ("chana masala", "(?i)^chana masala"), ("palak paneer", "(?i)^palak paneer"),
    ("aloo gobi", "(?i)^aloo gobi"), ("taco salad", "^Taco or tostada salad"), ("mango salsa", "(?i)mango salsa"), ("pinto", "^Beans, pinto"),
    ("chili con carne", "(?i)chili"), ("jamon serrano", "(?i)jam[oó]n serrano"), ("paneer", "(?i)paneer"), ("roti", "^Bread, chapati or roti"),
    ("ghee", "^Butter, Clarified butter"),
]

/// Words that mean one food in Britain, Ireland, Australia or New Zealand and another in the
/// United States, by the region of the phone, with the food that comes first there; and the
/// names around them that mean the same everywhere.
let regionalWords: [(region: String, typed: String, first: String)] = [
    ("gb", "chips", "^Potato, french fries"), ("ie", "chips", "^Potato, french fries"), ("us", "chips", "^Potato chips"),
    ("au", "chips", "^Potato chips"), ("fr", "chips", "^Potato chips"), ("gb", "hot chips", "^Potato, french fries"),
    ("au", "hot chips", "^Potato, french fries"), ("gb", "cheesy chips", "^Potato, french fries, with cheese"),
    ("gb", "oven chips", "^Potato, french fries, from frozen, baked"), ("gb", "portion of chips", "^Potato, french fries"),
    ("gb", "biscuits", "^Cookie"), ("ie", "biscuit", "^Cookie"), ("au", "biscuits", "^Cookie"), ("nz", "biscuits", "^Cookie"),
    ("us", "biscuits", "^Biscuit"), ("fr", "biscuits", "^Biscuit"), ("gb", "2 biscuits", "^Cookie"), ("us", "2 biscuits", "^Biscuit"),
    ("gb", "chocolate biscuits", "^Cookie, chocolate"), ("gb", "jelly", "^Gelatin dessert"), ("au", "jelly", "^Gelatin dessert"),
    ("us", "jelly", "^Jellies"), ("gb", "sugar free jelly", "^Gelatin dessert, sugar free"), ("gb", "cider", "^Hard cider"),
    ("au", "cider", "^Hard cider"), ("fr", "cider", "^Hard cider"), ("ca", "cider", "^Hard cider"), ("us", "cider", "^Apple cider"),
    ("us", "ciders", "^Apple cider"), ("gb", "glass of cider", "^Hard cider"), ("us", "hard cider", "^Hard cider"),
    ("gb", "currants", "^Currants, zante"), ("us", "currants", "^Currants, (red|european)"), ("au", "lollies", "^Candy$"),
    ("nz", "tomato sauce", "^Ketchup|^Catsup"), ("au", "tomato sauce", "^Ketchup|^Catsup"), ("us", "tomato sauce", "^Tomato sauce"),
    ("gb", "tomato sauce", "^Tomato sauce"), ("us", "flapjack", "^Pancakes"), ("ca", "flapjacks", "^Pancakes"),
    ("gb", "flapjack", "(?i)flapjack"), ("in", "biscuits", "^Cookie"), ("sg", "jelly", "^Gelatin dessert"),
    // The same everywhere.
    ("gb", "tortilla chips", "^Tortilla chips"), ("gb", "chocolate chips", "^Chocolate chips"), ("gb", "potato chips", "^Potato chips"),
    ("gb", "crisps", "^Potato chips"), ("gb", "biscuits and gravy", "^Biscuit with gravy"),
    ("gb", "peanut butter and jelly", "^Peanut butter and jelly"), ("gb", "jelly beans", "(?i)jelly ?beans"),
    ("gb", "cider vinegar", "^Vinegar, cider"), ("gb", "chips ahoy", "(?i)chips ahoy"),
]

/// The same for foods typed together, with the food that comes second.
let regionalPairs: [(region: String, typed: String, first: String, second: String)] = [
    ("gb", "steak and chips", "^Steak, cooked", "^Potato, french fries"), ("us", "steak and chips", "^Steak, cooked", "^Potato chips"),
    ("gb", "egg and chips", "^Egg, whole, cooked, fried", "^Potato, french fries"), ("gb", "chips and gravy", "^Potato, french fries", "^Gravy"),
    ("gb", "sausage and chips", "^Sausage", "^Potato, french fries"), ("gb", "burger and chips", "^Hamburger", "^Potato, french fries"),
    ("gb", "fish and chips", "^Fish, fried", "^Potato, french fries"), ("us", "fish and chips", "^Fish, fried", "^Potato, french fries"),
    // With salsa, guacamole or queso, chips are tortilla chips wherever they're eaten.
    ("gb", "chips and salsa", "^Tortilla chips", "^Salsa"), ("us", "chips and salsa", "^Tortilla chips", "^Salsa"),
    ("us", "chips and guac", "^Tortilla chips", "^Guacamole"), ("us", "chips and dip", "^Potato chips", "^Dip"),
    ("gb", "jelly and ice cream", "^Gelatin dessert", "^Ice cream"), ("gb", "tea and biscuits", "(?i)tea", "^Cookie"),
    ("gb", "cheese and biscuits", "^Cheese, cheddar", "^Crackers"), ("us", "cheese and biscuits", "^Cheese, cheddar", "^Biscuit"),
]

/// A food typed with what it's put on or over, which is the food and then what it's on; the
/// short names of such pairs; and the names with an "on" or an "over" that are one food.
let servedOnPairs: [(typed: String, first: String, second: String)] = [
    ("eggs on toast", "^Egg, whole, cooked", "^Bread.*toasted"), ("egg on toast", "^Egg, whole, cooked", "^Bread.*toasted"),
    ("scrambled eggs on toast", "^Egg, whole, cooked, scrambled", "^Bread.*toasted"),
    ("poached egg on toast", "^Egg, whole, cooked, poached", "^Bread.*toasted"), ("beans on toast", "^Beans, baked", "^Bread.*toasted"),
    ("cheese on toast", "^Cheese, cheddar", "^Bread.*toasted"), ("jam on toast", "^Jams", "^Bread.*toasted"),
    ("peanut butter on toast", "^Peanut butter", "^Bread.*toasted"), ("butter on toast", "^Butter", "^Bread.*toasted"),
    ("honey on toast", "^Honey", "^Bread.*toasted"), ("sardines on toast", "^Fish, sardine", "^Bread.*toasted"),
    ("avocado toast", "^Avocados", "^Bread.*toasted"), ("avocado on toast", "^Avocados", "^Bread.*toasted"),
    ("cream cheese on a bagel", "^Cheese, cream", "^Bagels"), ("peanut butter on a bagel", "^Peanut butter", "^Bagels"),
    ("lox on a bagel", "(?i)lox", "^Bagels"), ("tuna on crackers", "^Fish, tuna", "^Crackers"),
    ("cheese on crackers", "^Cheese, cheddar", "^Crackers"), ("butter on bread", "^Butter", "^Bread"),
    ("eggs over rice", "^Egg, whole, cooked", "^Rice, white.*cooked"), ("salmon on rice", "^Fish, salmon", "^Rice, white.*cooked"),
    ("chili over rice", "^Chili", "^Rice, white.*cooked"), ("pulled pork on a bun", "^Barbecue pork", "^Rolls, hamburger"),
    ("hot dog on a bun", "^Hot dog", "^Rolls, hamburger"), ("steak on a salad", "^Steak, cooked", "^Lettuce, salad"),
    ("chip butty", "^Potato, french fries", "^Bread"), ("bangers and mash", "^Sausage", "^Potato, mashed"),
    // One food, whatever it's on or over.
    ("eggs over easy", "^Egg, whole, cooked, fried", ""), ("corn on the cob", "^Corn, sweet.*cooked", ""),
    ("egg sandwich on english muffin", "^Egg sandwich on English muffin", ""), ("turkey sandwich on wheat", "^Turkey sandwich on wheat", ""),
    ("burger on a bun", "^Hamburger, on white bun", ""), ("pigs in a blanket", "^Pig in a blanket", ""),
    ("fruit on the bottom yogurt", "(?i)yogurt", ""),
]

let snacks: [(String, String)] = [
    ("oatmeal with milk", "^Oatmeal, regular or quick, made with milk$"), ("protein shake", "^Nutritional drink or shake, high protein"),
    ("yogurt parfait", "^Yogurt parfait"), ("egg and cheese sandwich", "^Egg sandwich on .*with cheese"),
    ("blueberry pancakes", "^Pancakes, blueberry"), ("turkey bacon", "^Bacon, turkey|^Turkey bacon, cooked"), ("turkey sausage", "^Sausage, turkey"),
    ("sausage patty", "^Pork sausage, link/patty|^Pork sausage, cooked"), ("hash brown patty", "hash browns, round pieces or patty"),
    ("english muffin", "^Muffins, English"), ("granola", "granola"), ("granola bar", "^(Snacks, granola bars|Cereal or Granola bar)"),
    ("trail mix", "^Snacks, trail mix"),
    ("beef jerky", "beef jerky|^Beef jerky"), ("rice cakes", "^Snacks, rice cakes"), ("pretzels", "^Snacks, pretzels, hard, plain"),
    ("popcorn", "^(Snacks, popcorn|Popcorn$)"), ("microwave popcorn", "^Popcorn, microwave"), ("crackers", "^Crackers"),
    ("pita chips", "^Snacks, pita chips"),
    ("tortilla chips", "^Tortilla chips|^Snacks, tortilla chips"), ("applesauce", "^Applesauce"), ("fruit salad", "^Fruit salad"),
    ("mixed nuts", "^Nuts, mixed nuts"), ("dried mango", "^Mango, dried"), ("banana chips", "^Snacks, banana chips"),
    ("dark chocolate", "^(Chocolate, dark|Dark chocolate candy)"), ("turkey wrap", "^Turkey sandwich wrap"),
    ("tuna wrap", "^Tuna salad sandwich wrap"),
    ("burrito bowl", "^Burrito bowl"), ("spaghetti squash", "^Squash, winter, spaghetti"), ("sweet potato", "^Sweet potato, cooked"),
    ("mixed vegetables", "^Vegetables, mixed"), ("side salad", "^Lettuce, salad with assorted vegetables"), ("rotisserie chicken", "rotisserie"),
    ("grilled chicken", "^Chicken, .*grilled"), ("shredded chicken", "^Chicken, broilers or fryers, .*cooked|^Chicken, cooked"),
    ("boneless wings", "^Chicken .wings., boneless"), ("chicken drumstick", "drumstick"), ("ground turkey", "^Turkey, [Gg]round"),
    ("turkey chili", "^Chili with chicken and beans$"), ("chicken chili", "^Chili with chicken"), ("beef chili", "^Chili with meat and beans$"),
    ("vegetarian chili", "^Chili, vegetarian"), ("chicken and dumplings", "^Chicken or turkey with dumplings"),
    ("chicken pot pie", "^Pot pie, chicken"), ("peanut butter sandwich", "^Peanut butter sandwich"),
    ("roast beef sandwich", "^Roast beef sandwich"), ("pasta with meat sauce", "^Pasta with tomato-based sauce and meat"),
    ("spaghetti with meatballs", "(?i)spaghetti and meatballs"), ("rice pilaf", "^Rice pilaf"), ("spanish rice", "^Spanish rice"),
    ("mexican rice", "(?i)spanish rice"), ("coconut rice", "^Rice, cooked with coconut milk"), ("sticky rice", "^Rice, white, glutinous, .*cooked"),
    ("refried beans", "^Refried beans"), ("baked beans", "^Beans, baked"), ("lentils", "^Lentils, .*cooked"), ("chickpeas", "^Chickpeas"),
    ("edamame", "^Edamame"), ("tofu", "^Tofu"), ("tempeh", "^Tempeh"), ("cottage cheese", "^Cheese, cottage"), ("rice pudding", "^Pudding, rice"),
    ("ice cream bar", "^Ice cream bar"), ("popsicle", "^Popsicle"), ("milkshake", "^Milk shake"),
    ("energy drink", "^Energy Drink$|^Beverages, Energy drink"), ("sports drink", "^Sports drink$"),
    ("sparkling water", "^Water, carbonated, plain$"), ("lemonade", "^Lemonade"), ("sweet tea", "^Tea, iced, .*sweetened"),
    ("hot chocolate", "^Hot chocolate|^Milk, chocolate beverage, hot cocoa"),
]

/// These rank foods made here, so they run without either catalog.
@Suite("Everyday forms")
struct EverydayFormTests {
    func first(_ query: String, _ names: [String], hints: RankHints = RankHints()) -> String {
        rankSearch(query, names.map { OwnWordsTests.food($0) }, hints: hints).first?.food.name ?? ""
    }

    @Test("the word USDA files a food under isn't held against it")
    func filedUnder() {
        // Most salsas are under "Sauce", so that's where salsa is: the plain one comes before a
        // kind that happens to lead with the word.
        let salsas = ["Sauce, salsa", "Sauce, salsa, verde", "Sauce, salsa, chipotle", "Salsa, mango", "Tortilla chips with salsa"]
        #expect(first("salsa", salsas) == "Sauce, salsa")
        // A food or two don't say where a food is filed.
        #expect(first("salsa", ["Sauce, salsa", "Salsa, mango", "Bread, wheat"]) == "Salsa, mango")
    }

    @Test("the word naming the food isn't one a name only includes")
    func includes() {
        let foods = ["Bagels, plain (includes onion, poppy, sesame)", "Snacks, popcorn, air-popped", "Spices, poppy seed"]
        #expect(first("pop", foods) == "Snacks, popcorn, air-popped")
        #expect(first("poppy", foods) == "Spices, poppy seed")
        // A word describing the food may be one of those it includes.
        #expect(first("poppy bagel", foods) == "Bagels, plain (includes onion, poppy, sesame)")
    }

    @Test("a people's traditional food is a kind of its own unless it's asked for")
    func tradition() {
        let corn = ["Corn, white, steamed (Navajo)", "Corn, white, steamed, kernels on cob"]
        #expect(first("corn", corn) == "Corn, white, steamed, kernels on cob")
        #expect(first("navajo corn", corn) == "Corn, white, steamed (Navajo)")
    }

    @Test("a food made of something else comes after a form of the food")
    func instead() {
        #expect(first("meatballs", ["Meatballs, meatless", "Meatballs, frozen, Italian style"]) == "Meatballs, frozen, Italian style")
        #expect(first("meatless meatballs", ["Meatballs, meatless", "Meatballs, frozen, Italian style"]) == "Meatballs, meatless")
    }

    @Test("the usual kind of a food is the one filed under what it's made of")
    func usual() {
        let bacon = ["Bacon, turkey, low sodium", "Pork, cured, bacon, cooked, pan-fried", "Bacon bits, meatless"]
        #expect(first("bacon", bacon) == "Pork, cured, bacon, cooked, pan-fried")
        #expect(first("turkey bacon", bacon) == "Bacon, turkey, low sodium")
        // Looked up by the stem a word is searched by.
        let whiskey = ["Whiskey sour mix, bottled", "Alcoholic beverage, distilled, whiskey, 86 proof"]
        #expect(first("whiskey", whiskey) == "Alcoholic beverage, distilled, whiskey, 86 proof")
    }

    @Test("with or without its skin, a food is still the food")
    func skin() {
        let first = { (name: String, foods: [String]) in
            scoreFoods(Named(name: name, brand: ""), foods.map { OwnWordsTests.food($0) }).first?.food.name ?? ""
        }
        #expect(first("apple", ["Rose-apples, raw", "Apples, raw, with skin"]) == "Apples, raw, with skin")
        #expect(
            first("sweet potato", ["Sweet potato leaves, cooked", "Sweet potato, cooked, boiled, without skin"])
                == "Sweet potato, cooked, boiled, without skin")
        // The skin alone is still a part of its own.
        let chicken = ["Chicken, broilers or fryers, skin only, cooked, roasted", "Chicken, broilers or fryers, meat only, cooked, roasted"]
        #expect(first("chicken", chicken) == "Chicken, broilers or fryers, meat only, cooked, roasted")
    }

    @Test("a brand that is an everyday word of foods isn't a brand the search names")
    func plainBrand() {
        let listed = OwnWordsTests.food("Goji Berries Dried", brand: "Goji")
        let plain = OwnWordsTests.food("Goji berries, dried")
        let score = { (foods: [Food]) in rankSearch("goji berries", foods).first { $0.food.id == listed.id }?.score ?? 0 }
        // Beside a plain food with every word, the one listed under "Goji" is no brand's; with
        // no plain food by those words, it is the food asked for.
        #expect(score([listed]) > score([listed, plain]) + 1.5)
        // An everyday food's own word is no brand whatever else is listed: the oat milk a label
        // lists under "milk" is no more the one asked for than Oatly's.
        let milk = OwnWordsTests.food("Oat Milk Original", brand: "Milk")
        let oatly = OwnWordsTests.food("Oat Milk Original", brand: "Oatly")
        let ranked = rankSearch("oat milk", [milk, oatly])
        #expect(ranked.count == 2 && ranked[0].score == ranked[1].score)
        // A brand people scan keeps its foods whatever plain food has the word.
        let crackers = OwnWordsTests.food("Baked Snack Crackers", brand: "Goldfish")
        let fish = OwnWordsTests.food("Goldfish snack crackers, baked")
        let theirs = { (foods: [Food]) in rankSearch("goldfish crackers", foods).first { $0.food.id == crackers.id }?.score ?? 0 }
        #expect(theirs([crackers]) == theirs([crackers, fish]))
    }

    func first(seen name: String, _ names: [String]) -> String {
        scoreFoods(Named(name: name, brand: ""), names.map { OwnWordsTests.food($0) }).first?.food.name ?? ""
    }

    @Test("a food that lacks a word said is another food where some food has them all")
    func everyWord() {
        // Typed or seen: oat milk isn't sheep's milk, and a packaged food's whole name isn't the plain food.
        let milks = [OwnWordsTests.food("Milk, sheep, fluid"), OwnWordsTests.food("Oat Milk", brand: "Oatly")]
        #expect(scoreFoods(Named(name: "oat milk", brand: ""), milks).first?.food.brand == "Oatly")
        let rice = [
            OwnWordsTests.food("Rice, white, long-grain, regular, cooked"),
            OwnWordsTests.food("Dolmas Vine Leaves stuffed with rice", brand: "Trader Joe's"),
        ]
        #expect(rankSearch("dolmas vine leaves rice", rice).first?.food.brand == "Trader Joe's")
        // A word that only says how a food comes isn't one it lacks, and with no food that has
        // every word the nearest still answers.
        let berries = [OwnWordsTests.food("Strawberries, raw"), OwnWordsTests.food("Fresh Organic Strawberries", brand: "Driscoll's")]
        #expect(scoreFoods(Named(name: "fresh strawberries", brand: ""), berries).first?.food.name == "Strawberries, raw")
        #expect(rankSearch("zesty banana", [OwnWordsTests.food("Bananas, raw")]).first?.food.name == "Bananas, raw")
    }

    @Test("a food is the kind it usually comes in")
    func usualForms() {
        // Canned, for the fish that are: not counted against them, nor what they're packed in.
        let sardines = ["Fish oil, sardine", "Fish, sardine, Atlantic, canned in oil, drained solids with bone"]
        #expect(first("sardines", sardines) == "Fish, sardine, Atlantic, canned in oil, drained solids with bone")
        // A two-word food's own usual kind comes before either word's.
        #expect(
            first("tomato sauce", ["Sauce, tomato chili sauce, bottled", "Tomato sauce, canned, no salt added"])
                == "Tomato sauce, canned, no salt added")
        #expect(first("egg roll", ["Rolls, dinner, egg", "Egg rolls, pork, refrigerated, heated"]) == "Egg rolls, pork, refrigerated, heated")
        #expect(first("beef stew", ["Beef, chuck for stew, cooked, braised", "Beef stew, canned entree"]) == "Beef stew, canned entree")
        // A meat alone is the cut most logged, and the kind the list says ribs are stays ahead
        // of the kind most of USDA's entries are.
        #expect(
            first("beef", ["Beef, cured, corned beef, brisket, cooked", "Beef, ground, 85% lean meat / 15% fat, patty, cooked, broiled"]).hasPrefix(
                "Beef, ground"))
        let ribs = (1...5).map { "Beef, rib, cut \($0), cooked, braised" } + ["Pork, fresh, backribs, separable lean and fat, cooked, roasted"]
        #expect(first("ribs", ribs).hasPrefix("Pork, fresh, backribs"))
    }

    @Test("a way of cooking the plain foods don't list is the nearest way they do")
    func cooking() {
        let broccoli = ["Broccoli, raw", "Broccoli, chinese, cooked", "Broccoli, cooked, boiled, drained, without salt"]
        #expect(first("steamed broccoli", broccoli) == "Broccoli, cooked, boiled, drained, without salt")
        #expect(first(seen: "roasted broccoli", broccoli) == "Broccoli, cooked, boiled, drained, without salt")
        // Before a label that says it: the plain cooked food is the one whose numbers are known.
        let labelled = [OwnWordsTests.food("Steamed Broccoli", brand: "Birds Eye")] + broccoli.map { OwnWordsTests.food($0) }
        #expect(rankSearch("steamed broccoli", labelled).first?.food.name == "Broccoli, cooked, boiled, drained, without salt")
        // The same kind of heat first: USDA's "dry heat" is baked and grilled, its "moist heat" poached.
        let salmon = [
            "Fish, salmon, Atlantic, farmed, raw", "Fish, salmon, coho, wild, cooked, moist heat", "Fish, salmon, Atlantic, farmed, cooked, dry heat",
        ]
        #expect(first("baked salmon", salmon) == "Fish, salmon, Atlantic, farmed, cooked, dry heat")
        #expect(first(seen: "grilled salmon fillet", salmon) == "Fish, salmon, Atlantic, farmed, cooked, dry heat")
        #expect(first("poached salmon", salmon) == "Fish, salmon, coho, wild, cooked, moist heat")
        // A way some plain food lists says which food is meant.
        let rice = ["Rice, white, long-grain, regular, enriched, cooked", "Restaurant, Chinese, fried rice, without meat"]
        #expect(first("fried rice", rice) == "Restaurant, Chinese, fried rice, without meat")
        // Unless only a less common form lists it.
        let potatoes = [
            "Potatoes, roasted, salt added in processing, frozen, unprepared", "Potatoes, microwaved, cooked in skin, flesh, without salt",
            "Potatoes, baked, flesh, without salt",
        ]
        #expect(first("roasted potatoes", potatoes) == "Potatoes, baked, flesh, without salt")
        // Fried is only ever fried: boiled zucchini isn't fried zucchini.
        let zucchini = [
            OwnWordsTests.food("Squash, summer, zucchini, includes skin, cooked, boiled, drained, without salt"),
            OwnWordsTests.food("Fried Zucchini", brand: "Farm Rich"),
        ]
        #expect(rankSearch("fried zucchini", zucchini).first?.food.brand == "Farm Rich")
        // And what's eaten cooked is still the raw food where no cooked one is listed.
        #expect(first("egg whites", ["Egg, white, dried", "Egg, white, raw, fresh"]) == "Egg, white, raw, fresh")
    }

    @Test("how a food is cut or trimmed, or that it's raw, is left unsaid")
    func cuts() {
        let salmon = [
            OwnWordsTests.food("Salmon Fillets", brand: "Morrisons"), OwnWordsTests.food("Fish, salmon, Atlantic, farmed, cooked, dry heat"),
        ]
        #expect(rankSearch("salmon fillet", salmon).first?.food.name == "Fish, salmon, Atlantic, farmed, cooked, dry heat")
        #expect(first("garlic clove", ["Spices, garlic powder", "Garlic, raw"]) == "Garlic, raw")
        #expect(first("raw almonds", ["Nuts, almonds, dry roasted, with salt added", "Nuts, almonds"]) == "Nuts, almonds")
        // "Baby" is how young it was picked, not baby food; a food that says it is still the one.
        #expect(first("baby spinach", ["Babyfood, vegetables, spinach, creamed, strained", "Spinach, raw"]) == "Spinach, raw")
        #expect(first("baby carrots", ["Carrots, raw", "Carrots, baby, raw"]) == "Carrots, baby, raw")
        // Skinless is USDA's "meat only".
        let thighs = [
            "Chicken, broilers or fryers, thigh, meat and skin, cooked, roasted", "Chicken, broilers or fryers, thigh, meat only, cooked, roasted",
        ]
        #expect(first("skinless chicken thigh", thighs) == "Chicken, broilers or fryers, thigh, meat only, cooked, roasted")
        // A cut only a less common form of the food lists isn't that form.
        #expect(first("apple slices", ["Apples, canned, sweetened, sliced, drained, heated", "Apples, raw, with skin"]) == "Apples, raw, with skin")
    }

    @Test("an everyday word with another typed after it is that word, and the last names the food")
    func finishedWords() {
        #expect(
            first("grape juice", ["Grapefruit juice, white, raw", "Grape juice, canned or bottled, unsweetened"])
                == "Grape juice, canned or bottled, unsweetened")
        #expect(first("ham sandwich", ["Hamburger, sandwich, plain", "Ham sandwich or sub, restaurant"]) == "Ham sandwich or sub, restaurant")
        // The word still being typed may be the start of a longer one.
        #expect(rankSearch("grape", [OwnWordsTests.food("Grapefruit juice, white, raw")]).count == 1)
        // A food that only has some of what was asked added to it is another dish.
        let salads = [OwnWordsTests.food("Potato salad with egg"), OwnWordsTests.food("Egg Salad", brand: "Market")]
        #expect(rankSearch("egg salad", salads).first?.food.brand == "Market")
        // Nor is a chain's pizza with pepperoni topping another dish for the parts before it.
        let pizza = [
            OwnWordsTests.food("Fast foods, pizza chain, 14\" pizza, pepperoni topping, regular crust"), OwnWordsTests.food("Pizza, cheese"),
        ]
        #expect(rankSearch("pepperoni pizza", pizza).first?.food.name.hasPrefix("Fast foods, pizza chain") == true)
        // USDA puts the word naming the food first: "Milk, chocolate" is chocolate milk.
        let milk = [OwnWordsTests.food("Milk, chocolate, fluid, commercial, whole")]
        #expect((rankSearch("chocolate milk", milk).first?.score ?? 0) > (rankSearch("milk chocolate", milk).first?.score ?? 0))
    }

    @Test("lean ground meat is the lean kind, and a brand's flavour isn't the food it's named after")
    func leanAndFlavours() {
        let beef = [
            "Beef, ground, 70% lean meat / 30% fat, patty, cooked, broiled", "Beef, ground, 93% lean meat / 7% fat, patty, cooked, broiled",
        ]
        #expect(first("lean ground beef", beef) == "Beef, ground, 93% lean meat / 7% fat, patty, cooked, broiled")
        #expect(first("ground beef", beef) == "Beef, ground, 70% lean meat / 30% fat, patty, cooked, broiled")
        let berries = [OwnWordsTests.food("Beverages, POWERADE, Zero, Mixed Berry"), OwnWordsTests.food("Mixed Berries", brand: "Publix")]
        #expect(rankSearch("mixed berries", berries).first?.food.brand == "Publix")
        // The brand's own name for the food is the food: Reese's are peanut butter cups.
        let cups = [OwnWordsTests.food("Candies, REESE'S Peanut Butter Cups"), OwnWordsTests.food("Peanut Butter Cups", brand: "Quest")]
        #expect(rankSearch("peanut butter cups", cups).first?.food.name == "Candies, REESE'S Peanut Butter Cups")
    }

    @Test("a dish is the dish, not a food with its words in it")
    func dishes() {
        // One made of something else is as far off as a label's: the real thing by any brand first.
        let loaves = [OwnWordsTests.food("Vegetarian meatloaf or patties"), OwnWordsTests.food("Meatloaf", brand: "Stouffer's")]
        #expect(rankSearch("meatloaf", loaves).first?.food.brand == "Stouffer's")
        // One word names a kind of food, which a brand's flavour of it is only one of.
        let smoothies = [OwnWordsTests.food("Beverages, V8 SPLASH Smoothies, Peach Mango"), OwnWordsTests.food("Smoothie", brand: "Naked")]
        #expect(rankSearch("smoothie", smoothies).first?.food.brand == "Naked")
        // A group USDA files foods under says what the food is when it's said.
        let chips = [OwnWordsTests.food("Snacks, potato chips, plain, salted"), OwnWordsTests.food("Fish & Chips", brand: "Smart Ones")]
        #expect(scoreFoods(Named(name: "fish and chips", brand: ""), chips).first?.food.brand == "Smart Ones")
        // A label that lists a dish under its own name as a brand is no brand's.
        let noodles = [OwnWordsTests.food("Chow Mein Chicken", brand: "Chow Mein"), OwnWordsTests.food("Noodles, chinese, chow mein")]
        #expect(rankSearch("chow mein", noodles).first?.food.name == "Noodles, chinese, chow mein")
        // USDA's own entry before a brand's "original" that it names in capitals.
        #expect(first("barbecue sauce", ["Sauce, barbecue, KRAFT, original", "Sauce, barbecue"]) == "Sauce, barbecue")
        #expect(first("goat cheese", ["Cheese, goat, hard type", "Cheese, goat, soft type"]) == "Cheese, goat, soft type")
        // A bowl named last is a dish; a bowl of something is how much of it.
        #expect(nameWords("Poke bowl") == ["poke", "bowl"])
        #expect(nameWords("Bowl of rice") == ["rice"])
    }

    @Test("a dish made with a food comes after the food, and one named by all that was said before its kinds")
    func madeWith() {
        func top(_ query: String, plain: [String], dishes: [String]) -> String {
            let entries = plain.map { Entry(OwnWordsTests.food($0)) } + dishes.map { Entry(OwnWordsTests.food($0), dish: true) }
            return rankSearch(query, entries).first?.food.name ?? ""
        }
        // A dish that doesn't lead with what was said is made with it or named after it.
        #expect(
            top("parmesan", plain: ["Cheese, parmesan, shredded"], dishes: ["Eggplant parmesan casserole, regular"]) == "Cheese, parmesan, shredded")
        #expect(
            top("flour tortilla", plain: ["Tortillas, ready-to-bake or -fry, flour"], dishes: ["Taco, flour tortilla, beef, cheese"])
                == "Tortillas, ready-to-bake or -fry, flour")
        // One that leads with it and adds another food is the food with more, where the
        // words name a food more than a dish.
        let livers = ["Liver, beef, cooked", "Liver, chicken, cooked"]
        #expect(top("liver", plain: livers, dishes: ["Liver, beef or calves, and onions"]) == livers[0])
        // Where they name a dish, what it comes with is part of it: chow mein has noodles.
        let mein = ["Chow mein or chop suey, with noodles", "Beef chow mein or chop suey with noodles", "Chow mein or chop suey, no noodles"]
        #expect(top("chow mein", plain: ["Noodles, chinese, chow mein"], dishes: mein) == "Chow mein or chop suey, with noodles")
        // And where a plain food leads with the words, so is a dish that says more of any kind.
        #expect(
            top("green beans", plain: ["Beans, snap, green, cooked, boiled"], dishes: ["Green beans, cooked, Szechuan-style"])
                == "Beans, snap, green, cooked, boiled")
        // A dish that is a kind of what was said is no dish made with it, whatever else has
        // the word: a turkey sandwich for "sandwich", where sandwich cookies are cookies.
        #expect(
            top("sandwich", plain: ["Cookies, peanut butter sandwich, regular"], dishes: ["Turkey sandwich on white", "Chicken or turkey sandwich"])
                != "Cookies, peanut butter sandwich, regular")
        // With no plain food by those words, the dishes are ranked as they were: the sauce a
        // pizza is made with isn't one.
        #expect(
            top("pizza", plain: ["Sauce, pizza, canned, ready-to-serve"], dishes: ["Pizza, cheese, from restaurant or fast food", "Pizza rolls"])
                == "Pizza, cheese, from restaurant or fast food")
        // Where a dish is from says nothing more of what it is; a plain food from a
        // restaurant is cooked their way.
        #expect(top("burrito", plain: [], dishes: ["Burrito, with beans, cheese", "Burrito, from fast food"]) == "Burrito, from fast food")
        #expect(
            first("green beans", ["Green beans, cooked, from restaurant", "Beans, snap, green, cooked, boiled"])
                == "Beans, snap, green, cooked, boiled")
        // The food named by nothing but what was said is the usual one, before the kind
        // that usually stands for it; by whole words, so a typo's start doesn't name a longer one.
        #expect(first("tomato soup", ["Soup, tomato, canned", "Soup, tomato"]) == "Soup, tomato")
        #expect(first("pizza", ["Pizza, cheese, stuffed crust", "Pizza, no cheese, thin crust", "Pizza, cheese"]) == "Pizza, cheese")
        // A dish without what it usually has is the less common one, and so is one made with
        // egg whites.
        #expect(first("chili dog", ["Chili hot dog, no bun", "Chili hot dog, on white bun"]) == "Chili hot dog, on white bun")
        #expect(first("egg sandwich", ["Egg white sandwich", "Egg sandwich on bagel"]) == "Egg sandwich on bagel")
        // Another name on the other side of an "or" is no word the food wasn't asked by, as
        // far as the first name is long: the parmigiana isn't chicken.
        #expect(first("chicken salad", ["Chicken salad with egg", "Chicken or turkey salad"]) == "Chicken or turkey salad")
        #expect(first("turkey salad", ["Turkey salad with egg", "Chicken or turkey salad"]) == "Chicken or turkey salad")
        #expect(
            first("macaroni and cheese", ["Macaroni and cheese, canned entree", "Macaroni or noodles with cheese"])
                == "Macaroni or noodles with cheese")
        #expect(
            top("chicken", plain: ["Chicken, broilers or fryers, breast, cooked, roasted"], dishes: ["Chicken or turkey parmigiana"]).hasPrefix(
                "Chicken, broilers"))
        // Another name the catalog keeps for a food, when it's all that was said in the order
        // said, stands for the food as its own name would.
        let shells = [
            Entry(OwnWordsTests.food("Manicotti, cheese-filled, with meat sauce"), dish: true),
            Entry(OwnWordsTests.food("Manicotti, cheese-filled, with tomato sauce, meatless"), also: "Manicotti", dish: true),
        ]
        #expect(rankSearch("manicotti", shells).first?.food.name == "Manicotti, cheese-filled, with tomato sauce, meatless")
        // What comes before the first name is said of both: a rice dessert or salad with
        // fruit is no fruit salad.
        #expect(
            top("fruit salad", plain: ["Fruit salad, canned, juice pack"], dishes: ["Rice dessert or salad with fruit"])
                == "Fruit salad, canned, juice pack")
        // Pretzels from a bag are the hard ones, and water is still water.
        #expect(first("pretzels", ["Pretzels, soft", "Pretzels, hard, plain, salted"]) == "Pretzels, hard, plain, salted")
        #expect(first("water", ["Water, tonic", "Water, bottled, generic"]) == "Water, bottled, generic")
        // How a label says a food was grown or made is no kind of the food: the plain food
        // before the label that says it, and a plain food that says it a little ahead.
        let breasts = [
            OwnWordsTests.food("Organic Chicken Breast", brand: "Kirkland"),
            OwnWordsTests.food("Chicken, broilers or fryers, breast, meat only, cooked, roasted"),
        ]
        #expect(rankSearch("organic chicken breast", breasts).first?.food.brand == nil)
        #expect(first("homemade granola", ["Granola, with nuts", "Granola, homemade"]) == "Granola, homemade")
        // Shredded meat is the cooked meat, where no plain food lists it shredded.
        #expect(first("shredded chicken", ["Chicken, feet, boiled", "Chicken, broilers or fryers, meat only, cooked, roasted"]).hasSuffix("roasted"))
        #expect(first("shredded cheese", ["Cheese, cheddar", "Cheese, mozzarella, shredded"]) == "Cheese, mozzarella, shredded")
        let teas = [Entry(OwnWordsTests.food("Tea, bubble"), also: "Milk tea"), Entry(OwnWordsTests.food("Tea, hot, with milk"))]
        #expect(rankSearch("tea with milk", teas).first?.food.name == "Tea, hot, with milk")
        #expect(rankSearch("milk tea", teas).first?.food.name == "Tea, bubble")
    }

    @Test("a model's name is read apart from its amount and what the food comes with")
    func seenNames() {
        #expect(seenName("Whole wheat toast with butter") == ("Whole wheat toast", ["butter"], ["butter"]))
        #expect(seenName("Turkey sandwich on wheat bread").main == "Turkey sandwich")
        // What's in brackets is said about the food; only another food is served beside it.
        #expect(seenName("Chicken wings (buffalo)") == ("Chicken wings", ["buffalo"], []))
        // A word for the form the food comes in is part of its name, before it.
        #expect(seenName("Plain Greek yogurt (nonfat)") == ("nonfat Plain Greek yogurt", [], []))
        #expect(seenName("Chicken thigh, roasted, with skin") == ("skin Chicken thigh, roasted", [], []))
        #expect(seenName("Ground turkey (93% lean)").main == "93 lean Ground turkey")
        // An amount is neither.
        #expect(seenName("Scrambled eggs (2 large)") == ("Scrambled eggs", [], []))
        // "On" and "in" after one short word name a dish.
        #expect(seenName("Corn on the cob").main == "Corn on the cob")
        #expect(seenName("Pigs in a blanket").main == "Pigs in a blanket")
        #expect(nameWords("Scrambled eggs (2 large)") == ["scrambled", "eggs"])
        #expect(nameWords("Glass of whole milk") == ["whole", "milk"])
        #expect(nameWords("Pan-seared salmon fillet") == ["seared", "salmon", "fillet"])
        #expect(nameWords("Buttered toast") == ["toast"])
        // A shape after the food is left for the ranking, which knows the foods named by one.
        #expect(nameWords("Watermelon cubes") == ["watermelon", "cubes"] && nameWords("2 slices of pizza") == ["pizza"])
        #expect(catalogDish("Fried egg, sunny side up") == "fried egg")
        // The food a name is for, as a caller can ask it.
        #expect(FoodCatalog.food(in: "Whole wheat toast with butter") == "Whole wheat toast")
        #expect(FoodCatalog.food(in: "Cereal with milk") == "Cereal")
        #expect(FoodCatalog.food(in: "oj") == "orange juice")
    }

    @Test("what comes with a food tells two foods apart, and is never the food")
    func sides() {
        let seen = { (name: String, foods: [String], sides: [String], beside: [String]) in
            scoreFoods(Named(name: name, brand: ""), foods.map { OwnWordsTests.food($0) }, hints: RankHints(sides: sides, beside: beside)).first?.food
                .name ?? ""
        }
        // The food with what was said beside it, where one entry is both.
        let mashed = ["Potatoes, mashed, ready-to-eat", "Potato, mashed, from restaurant, with gravy"]
        #expect(seen("Mashed potatoes", mashed, ["gravy"], ["gravy"]) == "Potato, mashed, from restaurant, with gravy")
        #expect(seen("Mashed potatoes", mashed, [], []) == "Potatoes, mashed, ready-to-eat")
        // Not the thing beside it: pasta with marinara sauce is pasta.
        let pasta = ["Sauce, pasta, spaghetti/marinara, ready-to-serve", "Pasta, cooked, enriched, without added salt"]
        #expect(seen("Pasta", pasta, ["marinara", "sauce"], ["marinara", "sauce"]) == "Pasta, cooked, enriched, without added salt")
        // Nor a food that says it comes without it.
        let sauced = ["Pasta with vegetables, no sauce or dressing", "Pasta with sauce"]
        #expect(seen("Pasta", sauced, ["sauce"], ["sauce"]) == "Pasta with sauce")
        // The food named with it before the food is that food with it, and so is one that
        // joins the two: a turkey sandwich, rice and beans. What it's with named last is
        // still the other food.
        #expect(seen("Sandwich", ["Sandwich spread, meatless", "Turkey sandwich on white"], ["turkey"], ["turkey"]) == "Turkey sandwich on white")
        #expect(seen("Rice", ["Beans, black, mature seeds, cooked", "Rice and beans"], ["beans"], ["beans"]) == "Rice and beans")
        #expect(seen("Salad", ["Salad dressing, ranch", "Salad, garden"], ["dressing"], ["dressing"]) == "Salad, garden")
        // Two words of one everyday food count only together: toast with butter isn't toast
        // with peanut butter.
        let toast = ["Bread, wheat, toasted, with butter", "Bread, wheat, toasted"]
        #expect(seen("Toast", toast, ["butter"], ["butter"]) == "Bread, wheat, toasted, with butter")
        let buttered = FoodText(OwnWordsTests.food(toast[0]))
        let has = { (sides: [String]) in
            CoverageQuery(seen: Named(name: "Toast", brand: ""), target: ["toast"], sides: sides, beside: sides).cover(buttered).sides
        }
        #expect(has(["butter"]) == 1 && has(["peanut", "butter"]) == 0 && has(["butter", "jam"]) == 1)
        // The entry that says it comes with all of it, and little else, before the usual one.
        let teas = ["Beverages, tea, black, brewed, prepared with tap water", "Tea, hot, with milk"]
        #expect(seen("Tea", teas, ["milk"], ["milk"]) == "Tea, hot, with milk")
        let rice = ["Rice, white, long-grain, regular, enriched, cooked", "Rice, fried, with chicken"]
        #expect(seen("Rice", rice, ["chicken"], ["chicken"]) == "Rice, white, long-grain, regular, enriched, cooked")
        // How a model saw the food cut is no kind of it; a food that says it is a little ahead.
        #expect(first(seen: "Strawberries, sliced", ["Strawberries, frozen, sweetened, sliced", "Strawberries, raw"]) == "Strawberries, raw")
        #expect(first(seen: "Grated parmesan cheese", ["Cheese, parmesan, shredded", "Cheese, parmesan, grated"]) == "Cheese, parmesan, grated")
        // A word only a note of what's in the food has doesn't name it; a note that is the
        // whole of what was said is another name for it.
        let greens = [
            OwnWordsTests.food("Vegetables, mixed (corn, lima beans, peas, green beans, carrots) canned, no salt added"),
            OwnWordsTests.food("Mixed Greens", brand: "Simply Nature"),
        ]
        #expect(scoreFoods(Named(name: "Mixed greens", brand: ""), greens).first?.food.brand == "Simply Nature")
        let chickpeas = [OwnWordsTests.food("Chickpeas (garbanzo beans, bengal gram), mature seeds, cooked, boiled, without salt")]
        #expect(scoreFoods(Named(name: "Garbanzo beans", brand: ""), chickpeas).first?.name == 1)
    }

    @Test("a food is named as two foods together by how its name joins them")
    func namedTogether() {
        let joint = { (name: String, foods: [[String]]) in isJoint(FoodText(OwnWordsTests.food(name)), foods) }
        // One opens the name and the other ends a run after "and" or "with".
        #expect(joint("Beans and white rice", [["rice"], ["beans"]]))
        #expect(joint("Biscuit with gravy", [["biscuits"], ["gravy"]]))
        #expect(joint("Beans, baked, canned, with pork", [["pork"], ["beans"]]))
        #expect(joint("Chicken or turkey with stuffing", [["turkey"], ["stuffing"]]))
        #expect(joint("Peas and carrots, canned, regular pack, solids and liquids", [["peas"], ["carrots"]]))
        #expect(joint("Rum and cola", [["rum"], ["coke"]]))
        // Or its last two runs are just the two.
        #expect(joint("Salad dressing, home recipe, vinegar and oil", [["oil"], ["vinegar"]]))
        // A food only named after them isn't the two, nor one of more foods than those.
        #expect(!joint("Crackers, cheese, regular", [["cheese"], ["crackers"]]))
        #expect(!joint("Milk and cereal bar", [["cereal"], ["milk"]]))
        #expect(!joint("Egg burrito, with bacon", [["eggs"], ["bacon"]]))
        #expect(!joint("Fast foods, biscuit, with egg and bacon", [["eggs"], ["bacon"]]))
        #expect(!joint("Chicken or turkey, rice, corn, and cheese, with gravy", [["turkey"], ["cheese"]]))
        #expect(!joint("Fast foods, submarine sandwich, bacon, lettuce, and tomato on white bread", [["lettuce"], ["tomato"]]))
        // Salt isn't joined to a food USDA lists "with salt".
        #expect(!joint("Peppers, sweet, green, cooked, boiled, drained, with salt", [["salt"], ["pepper"]]))
        // The last word may still be on its way.
        #expect(joint("Chicken or turkey and rice", [["chicken"], ["ri"]]))
        // A note that is just the foods names them together.
        #expect(joint("Restaurant, Latino, Arroz con habichuelas colorados (Rice And Red Beans)", [["red", "beans"], ["rice"]]))
        // An everyday name with its last word still being typed is on its way to that name.
        #expect(EverydayPhrases.isBegun(["mac", "and", "che"]) && EverydayPhrases.isBegun(["fish", "and", "chips"]))
        #expect(!EverydayPhrases.isBegun(["burger", "and", "che"]) && !EverydayPhrases.isBegun(["che"]))
        // What a name says the food comes without, up to the next comma or "with".
        #expect(wordsWithout(FoodText(OwnWordsTests.food("Lettuce, salad with assorted vegetables, no dressing"))) == ["dressing"])
        #expect(wordsWithout(FoodText(OwnWordsTests.food("Pasta with vegetables, no sauce or dressing"))) == ["sauce", "dressing"])
        #expect(wordsWithout(FoodText(OwnWordsTests.food("Potatoes, mashed, without milk, with gravy"))) == ["milk"])
        // A name has a word of each, however it joins them.
        #expect(hasEach(FoodText(OwnWordsTests.food("Crackers, cheese, regular")), [["cheese"], ["crackers"]]))
        #expect(!hasEach(FoodText(OwnWordsTests.food("Crackers, saltines")), [["cheese"], ["crackers"]]))
    }

    @Test("a kind of food typed alone is the one of its kind most logged")
    func kinds() {
        #expect(first("juice", ["Lemon juice, raw", "Orange juice, raw"]) == "Orange juice, raw")
        #expect(first("oil", ["Oil, palm", "Oil, olive, salad or cooking"]) == "Oil, olive, salad or cooking")
        #expect(first("cream", ["Cream, sour, cultured", "Cream, fluid, heavy whipping"]) == "Cream, fluid, heavy whipping")
        // Not once another word says which.
        #expect(first("lemon juice", ["Orange juice, raw", "Lemon juice, raw"]) == "Lemon juice, raw")
        #expect(first("sour cream", ["Cream, fluid, heavy whipping", "Cream, sour, cultured"]) == "Cream, sour, cultured")
        // A whole word typed alone isn't the start of a longer one; after other words the
        // last may still be half typed.
        #expect(first("curry", ["Currants, red and white, raw", "Spices, curry powder"]) == "Spices, curry powder")
        #expect(rankSearch("creamy oat", [OwnWordsTests.food("Extra Creamy Oatmilk", brand: "Chobani")]).count == 1)
    }

    @Test("another spelling of a food, or its British name, is the food")
    func spellings() {
        #expect(first("omelette", ["Eggplant, raw", "Egg, whole, cooked, omelet"]) == "Egg, whole, cooked, omelet")
        // With the usual kind and the cooked form of the word it's a spelling of.
        #expect(
            first("yoghurt", ["Yogurt, fruit, low fat", "Yogurt, plain, whole milk"])
                == first("yogurt", ["Yogurt, fruit, low fat", "Yogurt, plain, whole milk"]))
        #expect(first("prawns", ["Crustaceans, shrimp, raw", "Crustaceans, shrimp, cooked"]) == "Crustaceans, shrimp, cooked")
        #expect(first("aubergine", ["Eggplant, raw"]) == "Eggplant, raw")
    }

    @Test("a correction is a long shot where foods people look for have the word as typed")
    func longShots() {
        #expect(isLongShot("biscuit", for: "triscuit"))
        #expect(isLongShot("skinle", for: "skittles"))
        #expect(isLongShot("chicken", for: "mcchicken"))
        #expect(isLongShot("spa", for: "spam"))
        #expect(!isLongShot("protein", for: "protien"))
        #expect(!isLongShot("chicken", for: "chiken"))
        #expect(!isLongShot("strawberri", for: "strawberies"))
        // The brand of a food people scan is a name of its own.
        var sauce = OwnWordsTests.food("Original Hot Sauce", brand: "Cholula")
        sauce.popularity = 3
        let chocolate = OwnWordsTests.food("Chocolate sauce, ready-to-serve")
        let hot = RankHints(fixes: ["cholula": ["chocola"]], popularity: true, doubted: ["cholula"])
        #expect(rankSearch("cholula sauce", [chocolate, sauce], hints: hot).first?.food.id == sauce.id)
        // A label spells a word as it likes: its name doesn't make a word two typos from a
        // far commoner one a name.
        var label = OwnWordsTests.food("Mozerella Light", brand: "Casale")
        label.popularity = 3
        let cheese = OwnWordsTests.food("Cheese, mozzarella, whole milk")
        let typo = RankHints(fixes: ["mozerella": ["mozzarella"]], popularity: true, doubted: ["mozerella"])
        #expect(rankSearch("mozerella", [label, cheese], hints: typo).first?.food.id == cheese.id)
        // A chain's item USDA lists by the chain's name for it is that food, wherever its
        // other words put it.
        let chicken = ["Chicken, broilers or fryers, meat only, cooked, roasted", "McDONALD'S, McCHICKEN Sandwich"]
        #expect(
            first("mcchicken", chicken, hints: RankHints(fixes: ["mcchicken": ["chicken"]], doubted: ["mcchicken"]))
                == "McDONALD'S, McCHICKEN Sandwich")
        // Another wording of a word is the word, not a correction of it.
        let buns = ["Rolls, hamburger or hot dog, plain", "Burger relish"]
        let wording = RankHints(fixes: ["burgger": ["burger", "hamburger"]], doubted: ["burgger"], respelt: ["hamburger"])
        let ranked = rankSearch("burgger", buns.map { OwnWordsTests.food($0) }, hints: wording)
        #expect(ranked.count == 2 && ranked.allSatisfy { $0.score > 0 })
    }

    @Test("two letters with a word after them are a word, and a letter after a word is part of a name")
    func shortWords() {
        var soda = OwnWordsTests.food("Dr Pepper", brand: "Dr Pepper")
        soda.popularity = 3
        let dried = OwnWordsTests.food("Peppers, ancho, dried")
        #expect(rankSearch("dr pepper", [dried, soda], hints: RankHints(popularity: true)).first?.food.id == soda.id)
        // The last word may still be the start of one.
        #expect(first("pepper dr", ["Peppers, ancho, dried"]) == "Peppers, ancho, dried")
        #expect(readQuery("special k").letter == ["special", "k"])
        #expect(readQuery("special").letter.isEmpty && readQuery("2 k").letter.isEmpty)
        let cereal = OwnWordsTests.food("Special K Original", brand: "Kellogg's")
        let cookies = OwnWordsTests.food("Cookies, oatmeal, commercially prepared, special dietary")
        #expect(rankSearch("special k", [cookies, cereal]).first?.food.id == cereal.id)
        #expect(rankSearch("special", [cookies, cereal]).first?.food.id == cookies.id)
        // A dozen of a food is an amount of it.
        #expect(readQuery("dozen eggs").words == ["eggs"])
        #expect(readQuery("bakers dozen").words == ["bakers", "dozen"])
    }

    @Test("what follows the food after \"or\" is said of both, and nuggets are chicken")
    func alternatives() {
        let tacos = ["Taco or tostada salad with meat", "Fast foods, taco with beef, cheese and lettuce, soft"]
        #expect(first("taco", tacos) == "Fast foods, taco with beef, cheese and lettuce, soft")
        #expect(first("taco salad", tacos) == "Taco or tostada salad with meat")
        #expect(first("bagel", ["Bagel chips, plain", "Bagel or roll, plain"]) == "Bagel or roll, plain")
        let nuggets = ["Salmon nuggets, breaded, frozen, heated", "Chicken nuggets, from fast food"]
        #expect(first("nuggets", nuggets) == "Chicken nuggets, from fast food")
        #expect(first("salmon nuggets", nuggets) == "Salmon nuggets, breaded, frozen, heated")
    }

    @Test("what a food is packed in or only includes isn't the food, and a word typed alone can mean a food of its own")
    func packedAndAlone() {
        let juice = ["Tomatoes, red, ripe, canned, packed in tomato juice", "Tomato juice, canned, with salt added"]
        #expect(first("tomato juice", juice) == "Tomato juice, canned, with salt added")
        #expect(first(seen: "tomato juice", juice) == "Tomato juice, canned, with salt added")
        // The packing still tells two of a food apart.
        let tuna = ["Fish, tuna, light, canned in oil, drained solids", "Fish, tuna, light, canned in water, drained solids"]
        #expect(first("tuna in water", tuna) == "Fish, tuna, light, canned in water, drained solids")
        let crumbs = ["Bread, white, commercially prepared (includes soft bread crumbs)", "Bread, crumbs, dry, grated, plain"]
        #expect(first("bread crumbs", crumbs) == "Bread, crumbs, dry, grated, plain")
        #expect(first(seen: "bread crumbs", crumbs) == "Bread, crumbs, dry, grated, plain")
        // How a food is made says no other food, whatever it's made from.
        let soy = ["Soy sauce made from soy (tamari)", "Soy sauce made from soy and wheat (shoyu)"]
        #expect(first("soy sauce", soy) == "Soy sauce made from soy and wheat (shoyu)")
        // Chocolate chips are the chocolate, cocoa powder isn't a cocoa mix, and ginger is the root.
        let chips = ["Cookie, chocolate chip", "Cookies, chocolate chip, commercially prepared", "Candies, semisweet chocolate"]
        #expect(
            first("chocolate chips", chips, hints: RankHints(fixes: ["chips": ["semisweet"]], respelt: ["semisweet"]))
                == "Candies, semisweet chocolate")
        #expect(first("chocolate chip cookies", chips) != "Candies, semisweet chocolate")
        #expect(first("cocoa powder", ["Beverages, Cocoa mix, powder", "Cocoa, dry powder, unsweetened"]) == "Cocoa, dry powder, unsweetened")
        #expect(first("ginger", ["Spices, ginger, ground", "Ginger root, raw"]) == "Ginger root, raw")
        #expect(first("ground ginger", ["Ginger root, raw", "Spices, ginger, ground"]) == "Spices, ginger, ground")
        // A word typed alone, by the word itself and not any that shares its stem.
        #expect(aloneName("bourbon") == "whiskey" && aloneName("salads") == "lettuce salad" && aloneName("yeast") != nil)
        #expect(aloneName("yeasty") == nil && aloneName("ginger") == nil)
        // Spirits are 80 proof unless a number says otherwise.
        let spirits = [
            "Alcoholic beverage, distilled, all (gin, rum, vodka, whiskey) 86 proof",
            "Alcoholic beverage, distilled, all (gin, rum, vodka, whiskey) 80 proof",
        ]
        #expect(first(seen: "distilled gin", spirits) == "Alcoholic beverage, distilled, all (gin, rum, vodka, whiskey) 80 proof")
    }

    @Test("a word joined to the food's by a hyphen names another food, and a rarer food is read from four letters")
    func joinedAndRarer() {
        let custards = ["Custard-apple, (bullock's-heart), raw", "Desserts, egg custard, baked, prepared-from-recipe"]
        #expect(first("custard", custards) == "Desserts, egg custard, baked, prepared-from-recipe")
        let tacos = ["Snacks, tortilla chips, taco-flavor", "Fast foods, taco with beef, cheese and lettuce, soft"]
        #expect(first("taco", tacos) == "Fast foods, taco with beef, cheese and lettuce, soft")
        // Asked for by both its words, it's the food.
        #expect(first("custard apple", custards) == "Custard-apple, (bullock's-heart), raw")
        // The foods logged less often are read as begun from their fourth letter, and are whole
        // words of their own once typed.
        #expect(EverydayPhrases.likely(["tequ"]) == "tequila" && EverydayPhrases.likely(["teq"]) == nil)
        #expect(EverydayPhrases.likely(["cham"]) == "champagne" && EverydayPhrases.likely(["cha"]) != "champagne")
        #expect(EverydayPhrases.likely(["chee"]) == "cheese")
        #expect(EverydayPhrases.isWritten("gin") && EverydayPhrases.likely(["gin"]) == nil)
        // A word of a rarer food of two words isn't a food alone: the "roma" of a roma tomato
        // may be romaine begun, and "grape" a grapefruit.
        #expect(!EverydayPhrases.isWritten("roma") && EverydayPhrases.likely(["roma"]) == "romaine")
    }

    @Test("a group typed alone by its name leads its foods, and a raw food's cooked form is a kind of its own")
    func groups() {
        let nuts = ["Spices, nutmeg, ground", "Nuts, cashew nuts, raw", "Nuts, mixed nuts, dry roasted, with peanuts, with salt added"]
        #expect(first("nuts", nuts) == "Nuts, mixed nuts, dry roasted, with peanuts, with salt added")
        #expect(first("walnuts", ["Nuts, walnuts, dry roasted, with salt added", "Nuts, walnuts, english"]) == "Nuts, walnuts, english")
        #expect(
            first("roasted walnuts", ["Nuts, walnuts, dry roasted, with salt added", "Nuts, walnuts, english"])
                == "Nuts, walnuts, dry roasted, with salt added")
    }
}

/// Everyday searches over the catalogs the app ships.
@Suite("Everyday staples", .enabled(if: Catalogs.hasOFF, "needs Apps/MacroTrack/Catalogs/off.db or OFF_DB"))
struct StaplesTests {
    let catalog = Catalogs.both

    @Test("an everyday food typed plainly comes first")
    func basket() {
        var first = 0
        var three = 0
        var missed: [String] = []
        for (query, pattern) in staples {
            let names = catalog.top(query)
            if names.first.map({ matches(pattern, $0) }) == true { first += 1 } else { missed.append("\(query): \(names.first ?? "nothing")") }
            if names.contains(where: { matches(pattern, $0) }) { three += 1 }
        }
        print("Staples: \(first) of \(staples.count) first, \(three) in the first three")
        // A few points under what the ranking does on this catalog (every one first), so a change
        // can cost a staple or two for something worth more, and no more than that.
        #expect(Double(first) >= 0.97 * Double(staples.count), "\(missed.joined(separator: " | "))")
        #expect(Double(three) >= 0.99 * Double(staples.count), "\(missed.joined(separator: " | "))")
    }

    @Test("an everyday food a model names is matched to the same food")
    func seenBasket() {
        var first = 0
        var three = 0
        var missed: [String] = []
        for (name, pattern) in staples {
            let names = catalog.candidates(name: name, brand: nil).prefix(3).map(\.food.name)
            if names.first.map({ matches(pattern, $0) }) == true { first += 1 } else { missed.append("\(name): \(names.first ?? "nothing")") }
            if names.contains(where: { matches(pattern, $0) }) { three += 1 }
        }
        print("Staples as a model names them: \(first) of \(staples.count) first, \(three) in the first three")
        #expect(Double(first) >= 0.97 * Double(staples.count), "\(missed.joined(separator: " | "))")
        #expect(Double(three) >= 0.99 * Double(staples.count), "\(missed.joined(separator: " | "))")
    }

    @Test("an everyday food is first before its name is typed out")
    func letterByLetter() {
        // Every third staple, typed a letter at a time: the share of its letters it takes to come first.
        var shares: [Double] = []
        var slow: [String] = []
        for (query, pattern) in staples.enumerated().filter({ $0.offset % 3 == 0 }).map(\.element) {
            let letters = Array(query)
            let needed = (2...letters.count).first { count in
                letters[count - 1] != " " && catalog.top(String(letters[..<count]), 1).first.map { matches(pattern, $0) } == true
            }
            shares.append(Double(needed ?? letters.count) / Double(letters.count))
            if needed == nil || needed == letters.count { slow.append(query) }
        }
        let share = shares.reduce(0, +) / Double(shares.count)
        print(String(format: "Staples typed a letter at a time: first after %.0f%% of their letters", 100 * share))
        // Half the letters on this catalog; it was 63% while only whole words were read as foods.
        #expect(share <= 0.56, "only once typed whole: \(slow.joined(separator: ", "))")
    }

    @Test("an everyday food typed with a typo is still first")
    func typos() {
        // One typo in a word of five letters or more of every other staple and pantry food, never
        // its first letter.
        var random = SearchQualityTests.Seeded(state: 11)
        var first = 0
        var asked = 0
        var missed: [String] = []
        for (query, pattern) in (staples + pantry).enumerated().filter({ $0.offset % 2 == 0 }).map(\.element) {
            var words = query.split(separator: " ").map(String.init)
            guard let at = words.indices.filter({ words[$0].count >= 5 && words[$0].allSatisfy(\.isLetter) }).randomElement(using: &random) else {
                continue
            }
            let wrong = SearchQualityTests.typo(words[at], &random)
            guard wrong != words[at] else { continue }
            words[at] = wrong
            asked += 1
            let typed = words.joined(separator: " ")
            if catalog.top(typed, 1).first.map({ matches(pattern, $0) }) == true { first += 1 } else { missed.append(typed) }
        }
        print("Everyday foods with a typo: \(first) of \(asked) first")
        // 85% before a typo's word was read by the names and usual kind of the word it meant,
        // 92% before a search one typo from an everyday food was read as that food.
        #expect(Double(first) >= 0.93 * Double(asked), "\(missed.joined(separator: ", "))")
        // One typo from an everyday food, in a word USDA doesn't have and no scanned brand is
        // called: read as the food, whatever labels spell it that way.
        #expect(catalog.searchCatalog("french fires", known: [:]).text == "french fries")
        #expect(catalog.top("baked bans", 1).first?.hasPrefix("Beans, baked") == true)
        #expect(catalog.top("hot saue", 1).first?.hasPrefix("Sauce, ") == true)
        #expect(catalog.top("ice crem", 1).first == "Ice cream")
        // Not a word the catalogs know, a brand people scan, or a word still on its way to a
        // food: a jam sandwich is no ham sandwich, and "black bea" is black beans begun.
        #expect(catalog.searchCatalog("jam sandwich", known: [:]).text == "jam sandwich")
        #expect(catalog.searchCatalog("skittles", known: [:]).text == "skittles")
        #expect(catalog.searchCatalog("cooke", known: [:]).text == "cooke", "cooked begun, as much as a cookie misspelt")
        #expect(catalog.top("black bea", 1).first?.hasPrefix("Beans, black") == true)
        #expect(catalog.top("green bea", 1).first?.hasPrefix("Beans, snap, green") == true)
    }

    @Test("a search one typo from an everyday food names the word that was meant")
    func everydayTypos() {
        let fix = { (typed: [String]) in EverydayPhrases.misspelt(typed).map { "\($0.at) \($0.word)" } }
        #expect(fix(["french", "fires"]) == "1 fries")
        #expect(fix(["baked", "bans"]) == "1 beans")
        #expect(fix(["white", "bead"]) == "1 bread")
        #expect(fix(["hot", "saue"]) == "1 sauce")
        #expect(fix(["chese", "pizza"]) == "0 cheese")
        #expect(fix(["mac", "cheee"]) == "1 cheese", "a phrase's small words aren't counted")
        #expect(fix(["appel"]) == "0 apple")
        #expect(fix(["brocoli"]) == "0 broccoli")
        // Not a word that is an everyday food's ("jam"), a search typed right, a word still on
        // its way to the food some phrase has there, a last word under four letters, or two
        // typos.
        for typed in [
            ["jam", "sandwich"], ["french", "fries"], ["black", "bea"], ["french", "fri"], ["baked", "ban"], ["frnch", "fires"], ["peanutb"],
        ] {
            #expect(fix(typed) == nil, "\(typed)")
        }
    }

    @Test("an everyday name finds the food the catalogs file under another")
    func everydayNames() {
        // Typed apart or as one word, hot dogs are USDA's frankfurters and a bell pepper its sweet pepper.
        #expect(catalog.respell("hot dog").also["dog"]?.contains("frankfurter") == true)
        #expect(catalog.respell("hotdogs").also["dogs"]?.contains("frankfurter") == true)
        #expect(catalog.respell("bell peppers").also["bell"] == ["sweet"])
        // Alone, ranch is the dressing and spaghetti is also "Pasta"; with another word they're themselves.
        #expect(catalog.respell("ranch").text == "ranch salad dressing")
        #expect(catalog.respell("ranch chicken").text == "ranch chicken")
        #expect(catalog.respell("spaghetti").also["spaghetti"] == ["pasta"])
        #expect(catalog.respell("spaghetti squash").also["spaghetti"] == nil)
        #expect(catalog.top("spaghetti squash", 1).first.map { matches("^Squash, winter, spaghetti", $0) } == true)
    }

    @Test("the person's own food is found by the name as typed")
    func ownFood() {
        // "ranch" alone is searched as "ranch salad dressing"; their Ranch Dip has only the word typed.
        let own = Food(id: "custom:dip", name: "Ranch Dip", basis: .g, nutrients: .zero, source: .custom)
        let found = catalog.search("ranch", personal: [PersonalFood(food: own, score: 1)])
        #expect(found.first?.food.id == own.id && found.first?.personal == true)
        #expect(found.dropFirst().first.map { matches("^Salad dressing, ranch dressing", $0.food.name) } == true)
    }

    @Test("a food a label lists under its own name as a brand is still the plain food")
    func plainWords() {
        #expect(catalog.top("chia seeds", 1).first.map { matches("^Seeds, chia", $0) } == true)
        #expect(catalog.top("american cheese", 1).first.map { matches("^Cheese, pasteurized process, American", $0) } == true)
        // A brand that makes the food keeps it.
        #expect(catalog.search("kraft cheese").first?.food.brand?.lowercased() == "kraft")
        #expect(catalog.search("goldfish cheddar crackers").first.map { matches("(?i)goldfish", "\($0.food.name) \($0.food.brand ?? "")") } == true)
    }

    @Test("a food said with how it's cooked or cut comes first typed and named as a model would")
    func formsBasket() {
        for seen in [false, true] {
            var first = 0
            var missed: [String] = []
            for (query, pattern) in forms {
                let names = seen ? catalog.candidates(name: query, brand: nil).prefix(3).map(\.food.name) : catalog.top(query)
                if names.first.map({ matches(pattern, $0) }) == true { first += 1 } else { missed.append("\(query): \(names.first ?? "nothing")") }
            }
            print("Cooked and cut foods \(seen ? "as a model names them" : "typed"): \(first) of \(forms.count) first")
            #expect(Double(first) >= 0.95 * Double(forms.count), "\(seen ? "seen" : "typed"): \(missed.joined(separator: " | "))")
        }
    }

    @Test("a food as a vision model names it is matched to the plain food")
    func plateBasket() {
        var first = 0
        var missed: [String] = []
        for (name, pattern) in plates {
            let names = catalog.candidates(name: name, brand: nil).prefix(3).map(\.food.name)
            if names.first.map({ matches(pattern, $0) }) == true { first += 1 } else { missed.append("\(name): \(names.first ?? "nothing")") }
        }
        print("Foods as a model names them: \(first) of \(plates.count) first")
        #expect(Double(first) >= 0.95 * Double(plates.count), "\(missed.joined(separator: " | "))")
        // A match says when it names the food as the catalog read it, which the words of the two
        // names alone don't show: a frankfurter for a hot dog, toast for toast with butter.
        #expect(catalog.candidates(name: "hot dog", brand: nil).first?.named == true)
        #expect(catalog.candidates(name: "Whole wheat toast with butter", brand: nil).first?.named == true)
        #expect(catalog.candidates(name: "lobster roll", brand: nil).first?.named == false)
    }

    @Test("a word that starts a brand's name isn't the brand where the words together name a food")
    func namesNotBrands() {
        for query in ["great northern beans", "general tso chicken", "garlic clove", "little smokies"] {
            #expect(catalog.searchCatalog(query, known: [:]).brand.isEmpty, "\(query)")
        }
        #expect(catalog.searchCatalog("mission tortillas", known: [:]).brand == ["mission"])
        #expect(catalog.searchCatalog("great value milk", known: [:]).brand == ["great", "value"])
    }

    @Test("short names, other wordings and words USDA writes as one are read")
    func wordings() {
        #expect(catalog.respell("pb&j").text == "peanut butter and jelly")
        #expect(catalog.respell("fat free milk").also["fat"]?.contains("nonfat") == true)
        #expect(catalog.respell("crunchy peanut butter").also["crunchy"]?.contains("chunk") == true)
        #expect(catalog.respell("water chestnuts").also["water"]?.contains("waterchestnut") == true)
        // Of a typo's two readings, the one that makes one word with the word before it.
        #expect(catalog.typos(in: "flax sends")["sends"] == "seed")
        // A percentage in words is the number labels write.
        #expect(catalog.respell("2 percent milk").text == "2% milk")
        #expect(catalog.respell("one percent milk").text == "1% milk")
        #expect(catalog.top("monterey jack", 1).first == "Cheese, monterey")
        // A kind of food typed alone, where the usual one is far down the foods with the word,
        // and the words that mean a food of their own alone.
        #expect(catalog.top("juice", 1).first.map { matches("^Orange juice", $0) } == true)
        #expect(catalog.top("meat", 1).first.map { matches("^(Beef|Meat), ground", $0) } == true)
        #expect(catalog.top("protein", 1).first.map { matches("(?i)protein powder", $0) } == true)
        #expect(catalog.top("salad", 1).first.map { matches("^Lettuce, salad", $0) } == true)
        // A few letters aren't the start of a brand that isn't sold here: dal is the lentil
        // curry it is, then the labels called dal.
        #expect(catalog.top("dal", 1) == ["Lentil curry"] && catalog.top("dal", 5).contains { matches("(?i)^dal\\b", $0) })
    }

    @Test("a popular product or a chain's item typed by its name comes first")
    func productsBasket() {
        var first = 0
        var missed: [String] = []
        for (query, pattern) in products {
            let names = catalog.names(query, 1)
            if names.first.map({ matches(pattern, $0) }) == true { first += 1 } else { missed.append("\(query): \(names.first ?? "nothing")") }
        }
        print("Products: \(first) of \(products.count) first")
        #expect(Double(first) >= 0.97 * Double(products.count), "\(missed.joined(separator: " | "))")
        // A name the catalogs know isn't the commoner word a letter or two away, and a chain's
        // own word for its item isn't the food it's made of.
        #expect(catalog.names("skittles", 1).first.map { matches("(?i)skittles", $0) } == true)
        #expect(catalog.names("mcchicken", 1).first.map { matches("McCHICKEN", $0) } == true)
        #expect(catalog.names("egg mcmuffin", 1).first.map { matches("Egg McMUFFIN", $0) } == true)
        // A typo is still read: no food people look for is spelt that way.
        #expect(catalog.top("chiken brest", 1).first.map { matches("^Chicken.*breast", $0) } == true)
        #expect(catalog.top("crunchy taco", 1).first.map { matches("taco with beef.*hard shell", $0) } == true)
        // "Mc" typed apart is the start of the one word.
        #expect(catalog.respell("mc flurry").text == "mcflurry")
        #expect(catalog.top("mc flurry", 1).first.map { matches("McFLURRY", $0) } == true)
        #expect(catalog.searchCatalog("mc donalds fries", known: [:]).brand == ["mcdonalds"])
    }

    @Test("drinks, produce, condiments and baking ingredients come first typed and named as a model would")
    func kitchenBasket() {
        for seen in [false, true] {
            var first = 0
            var missed: [String] = []
            for (query, pattern) in kitchen {
                let names = seen ? catalog.candidates(name: query, brand: nil).prefix(1).map(\.food.name) : catalog.top(query, 1)
                if names.first.map({ matches(pattern, $0) }) == true { first += 1 } else { missed.append("\(query): \(names.first ?? "nothing")") }
            }
            print("Kitchen foods \(seen ? "as a model names them" : "typed"): \(first) of \(kitchen.count) first")
            #expect(Double(first) >= 0.95 * Double(kitchen.count), "\(seen ? "seen" : "typed"): \(missed.joined(separator: " | "))")
        }
        // A word some plain food has whole is that food, not a brand that starts with it.
        #expect(catalog.top("rum", 1).first == "Rum")
        // And a word USDA wrote is no typo of a commoner one.
        #expect(catalog.searchCatalog("ghee", known: [:]).fixes.isEmpty)
        // What a food is packed in isn't what it is.
        #expect(catalog.top("tomato juice", 1).first.map { matches("^Tomato juice", $0) } == true)
        #expect(catalog.top("tuna in water", 1).first.map { matches("(?i)tuna.*canned in water", $0) } == true)
        // A food logged less often is read as begun from its fourth letter.
        #expect(catalog.top("tequ", 1).first == "Tequila")
        #expect(catalog.top("bour", 1).first == "Whiskey")
    }

    @Test("what's ordered at a coffee shop or a bar comes first typed and named as a model would")
    func barBasket() {
        for seen in [false, true] {
            var first = 0
            var missed: [String] = []
            for (query, pattern) in bar {
                let names = seen ? catalog.candidates(name: query, brand: nil).prefix(1).map(\.food.name) : catalog.top(query, 1)
                if names.first.map({ matches(pattern, $0) }) == true { first += 1 } else { missed.append("\(query): \(names.first ?? "nothing")") }
            }
            print("Drinks \(seen ? "as a model names them" : "typed"): \(first) of \(bar.count) first")
            #expect(Double(first) >= 0.95 * Double(bar.count), "\(seen ? "seen" : "typed"): \(missed.joined(separator: " | "))")
        }
        // By the name it's ordered by, which the catalog keeps beside its own.
        #expect(catalog.top("vodka cranberry", 1).first == "Cape Cod")
        #expect(catalog.top("chai latte", 1).first == "Tea, hot, with milk")
        #expect(catalog.candidates(name: "Oat milk latte", brand: nil).first?.food.name == "Coffee, Latte, with non-dairy milk")
        // The whole of a search is no brand where USDA names a food by exactly those words.
        #expect(catalog.searchCatalog("mai tai", known: [:]).brand.isEmpty)
        #expect(catalog.top("mai tai", 1).first == "Mai Tai")
        // A word with a meaning of its own isn't read as the typo it could be.
        #expect(catalog.top("mezcal", 1).first == "Tequila")
    }

    @Test("a dish comes first typed and named as a model would, and mostly as USDA lists it")
    func dishesBasket() {
        for seen in [false, true] {
            var first = 0
            var plain = 0
            var missed: [String] = []
            for (query, pattern) in dishes {
                let found = seen ? catalog.candidates(name: query, brand: nil).first?.food : catalog.search(query).first?.food
                if found.map({ matches(pattern, $0.name) }) == true { first += 1 } else { missed.append("\(query): \(found?.name ?? "nothing")") }
                if found?.source == .usda { plain += 1 }
            }
            print("Dishes \(seen ? "as a model names them" : "typed"): \(first) of \(dishes.count) first, \(plain) as USDA lists them")
            #expect(Double(first) >= 0.95 * Double(dishes.count), "\(seen ? "seen" : "typed"): \(missed.joined(separator: " | "))")
            #expect(Double(plain) >= 0.85 * Double(dishes.count))
        }
        // By the name it's cooked or ordered by, which the catalog keeps beside its own.
        #expect(catalog.top("chicken parmesan", 1).first == "Chicken or turkey parmigiana")
        #expect(catalog.top("fettuccine alfredo", 1).first == "Pasta with cream sauce, restaurant")
        #expect(catalog.top("tater tots", 1).first == "Potato tots")
        #expect(catalog.candidates(name: "Grilled cheese", brand: nil).first?.called == true)
        // A dish made with a food isn't the food: the cheese, the tortilla and the liver first.
        #expect(catalog.top("parmesan", 1).first?.hasPrefix("Cheese, parmesan") == true)
        #expect(catalog.top("flour tortilla", 1).first?.hasPrefix("Tortillas") == true)
        #expect(catalog.top("american cheese", 1).first?.hasPrefix("Cheese") == true)
        #expect(catalog.top("liver", 1).first?.hasPrefix("Liver, beef") == true)
        // The dish named by nothing but what was said, before its kinds.
        #expect(catalog.top("burrito", 1).first == "Burrito")
        #expect(catalog.top("tomato soup", 1).first == "Soup, tomato")
        #expect(catalog.top("pizza", 1).first == "Pizza, cheese, from restaurant or fast food")
        // The whole of a search is no brand where the catalog names a dish by those words.
        #expect(catalog.searchCatalog("eggs benedict", known: [:]).brand.isEmpty)
        #expect(catalog.top("eggs benedict", 1).first == "Egg, Benedict")
    }

    @Test("a chain typed or named with a food it has none of in the catalogs is that food from a restaurant")
    func chains() {
        // The chain's words at either end of the search, with something else typed.
        #expect(Chains.chain(in: ["five", "guys", "fries"])?.span == 0..<2)
        #expect(Chains.chain(in: ["fries", "five", "guys"])?.span == 1..<3)
        #expect(Chains.chain(in: ["chick", "fil", "nuggets"])?.span == 0..<2)
        #expect(Chains.chain(in: ["five", "guys"]) == nil)
        #expect(Chains.chain(in: ["fries"]) == nil)
        // Fast food, or a restaurant with tables: the catalog files each food by which.
        #expect(Chains.chain(in: ["kfc", "biscuit"])?.place == "fast")
        #expect(Chains.chain(in: ["olive", "garden", "breadsticks"])?.place == "restaurant")
        // A word foods have for themselves is the chain as a possessive or with what it sells.
        #expect(Chains.chain(in: ["chili", "fajitas"], typed: "chili fajitas") == nil)
        #expect(Chains.chain(in: ["chilis", "fajitas"], typed: "chilis fajitas") == nil)
        #expect(Chains.chain(in: ["chili", "fajitas"], typed: "Chili's fajitas")?.span == 0..<1)
        #expect(Chains.chain(in: ["chipotle", "mayo"], typed: "chipotle mayo") == nil)
        #expect(Chains.chain(in: ["chipotle", "burrito", "bowl"], typed: "chipotle burrito bowl")?.span == 0..<1)
        #expect(Chains.chain(in: ["moe", "burrito"], typed: "moe's burrito")?.span == 0..<1)
        #expect(Chains.chain(in: ["mo", "burrito"], typed: "mo burrito") == nil)
        for (query, pattern) in [
            // Fries from fast food, breadsticks from a restaurant: each by the kind of place it is.
            ("five guys fries", "^Potato, french fries, fast food$"), ("kfc mashed potatoes", "^Potato, mashed, from fast food$"),
            ("olive garden breadsticks", "^Breadsticks, soft, fast food / restaurant$"), ("chick fil a nuggets", "^Chicken nuggets, from fast food$"),
            ("popeyes chicken sandwich", "^Chicken fillet sandwich, from fast food$"),
            ("waffle house waffle", "^Waffle, plain, fast food / restaurant$"),
            // The middle size of the ones a burger comes in.
            ("five guys burger", "^Hamburger, from fast food, 1 medium patty$"), ("fries five guys", "^Potato, french fries, fast food$"),
            // Its own item where a catalog has it, by its name or by the chain's name for it.
            ("mcdonalds fries", "^McDONALD'S, french fries"), ("dairy queen blizzard", "^Soft serve, blended"),
            ("mcdonald's big mac", "^McDONALD'S, BIG MAC$"),
            // The chain is the brand and no more of the search: the second "taco" is the food.
            ("taco bell taco", "^TACO BELL, .*Taco"),
            // A word that is also a flavour stays one, unless what's typed with it is on the chain's menu.
            ("chipotle mayo", "(?i)chipotle"), ("green chilis", "(?i)chil"), ("chipotle burrito bowl", "^Burrito bowl$"),
        ] {
            let names = catalog.top(query, 1)
            #expect(names.first.map { matches(pattern, $0) } == true, "\(query): \(names.first ?? "nothing")")
        }
        // The foods all the words found follow, none scored above the restaurant's.
        let listed = catalog.search("five guys fries")
        #expect(listed.count > 5 && zip(listed, listed.dropFirst()).allSatisfy { $0.score >= $1.score })
        // A word left that no plain food has as typed isn't read as another: a footlong isn't oolong.
        #expect(catalog.top("subway footlong", 1).first.map { matches("(?i)subway|footlong", $0) } == true)
        // A model names the chain as the food's brand: the same reading, and no score above
        // the one before it, so the meal pipeline keeps the order.
        #expect(Chains.place(of: "Chick-fil-A") == "fast" && Chains.place(of: "Chili's") == "restaurant")
        #expect(Chains.place(of: "Panera Bread") == "fast" && Chains.place(of: "Chipotle") == "fast")
        #expect(Chains.place(of: "Chili") == nil && Chains.place(of: "Kraft") == nil && Chains.place(of: "") == nil)
        for (name, brand, pattern) in [
            ("French fries", "Five Guys", "^Potato, french fries, fast food$"),
            ("Chicken nuggets", "Chick-fil-A", "^Chicken nuggets, from fast food$"),
            ("Breadsticks", "Olive Garden", "^Breadsticks, soft, fast food / restaurant$"), ("Burrito bowl", "Chipotle", "^Burrito bowl$"),
            ("Wings", "Wingstop", "^Chicken \"wings\", plain, from fast food / restaurant$"),
        ] {
            let found = catalog.candidates(name: name, brand: brand)
            #expect(found.first.map { matches(pattern, $0.food.name) } == true, "\(name) from \(brand): \(found.first?.food.name ?? "nothing")")
            #expect(zip(found, found.dropFirst()).allSatisfy { $0.score >= $1.score })
        }
        // The chain's own item where the catalog has it.
        #expect(catalog.candidates(name: "French fries", brand: "McDonald's").first?.food.name == "McDONALD'S, french fries")
        #expect(
            catalog.candidates(name: "Pepperoni pizza", brand: "Domino's").first.map { matches("^DOMINO'S 14\" Pepperoni Pizza", $0.food.name) }
                == true)
        // The person's own food is found by everything typed, and comes before the restaurant's.
        let own = Food(id: "custom:fries", name: "Five Guys Little Fries", basis: .g, nutrients: .zero, source: .custom)
        let found = catalog.search("five guys fries", personal: [PersonalFood(food: own, score: 1)])
        #expect(found.first?.food.id == own.id && found.dropFirst().first?.food.name == "Potato, french fries, fast food")
        // From a chain, the food as a restaurant serves it before the plain one.
        let fries = [OwnWordsTests.food("Potato, french fries"), OwnWordsTests.food("Potato, french fries, from fast food")]
        #expect(rankSearch("french fries", fries, hints: RankHints(out: "fast")).first?.food.name == "Potato, french fries, from fast food")
        #expect(rankSearch("french fries", fries).first?.food.name == "Potato, french fries")
        // And of the two places, the kind the chain is.
        let mashed = [OwnWordsTests.food("Potato, mashed, from restaurant"), OwnWordsTests.food("Potato, mashed, from fast food")]
        #expect(rankSearch("mashed potato", mashed, hints: RankHints(out: "fast")).first?.food.name == "Potato, mashed, from fast food")
        #expect(rankSearch("mashed potato", mashed, hints: RankHints(out: "restaurant")).first?.food.name == "Potato, mashed, from restaurant")
        // Of sizes no one asked for, the middle one.
        let burgers = ["small", "medium", "large"].map { OwnWordsTests.food("Hamburger, 1 \($0) patty") }
        #expect(rankSearch("hamburger", burgers).first?.food.name == "Hamburger, 1 medium patty")
        #expect(rankSearch("small hamburger", burgers).first?.food.name == "Hamburger, 1 small patty")
    }

    @Test("a staple is still first when it's typed in capitals, with an amount, or as organic, homemade or plain")
    func reworded() {
        let ways: [(String, (String) -> String)] = [
            ("in capitals", { $0.capitalized }), ("with an amount", { "1 cup \($0)" }), ("as half of one", { "half \($0)" }),
            ("organic", { "organic \($0)" }), ("homemade", { "homemade \($0)" }), ("plain", { "plain \($0)" }),
        ]
        for (way, reword) in ways {
            var first = 0
            var missed: [String] = []
            for (query, pattern) in staples {
                let names = catalog.top(reword(query), 1)
                if names.first.map({ matches(pattern, $0) }) == true {
                    first += 1
                } else {
                    missed.append("\(reword(query)): \(names.first ?? "nothing")")
                }
            }
            print("Staples \(way): \(first) of \(staples.count) first")
            #expect(Double(first) >= 0.95 * Double(staples.count), "\(way): \(missed.joined(separator: " | "))")
        }
        // An amount said without a number is an amount, and "half and half" still the cream.
        #expect(searchedWords(readQuery("half a sandwich").words) == ["sandwich"])
        #expect(searchedWords(readQuery("a few crackers").words) == ["crackers"])
        #expect(searchedWords(readQuery("2x eggs").words) == ["eggs"])
        #expect(catalog.top("half and half", 1).first == "Cream, fluid, half and half")
        #expect(catalog.top("plain hamburger", 1).first == "Hamburger")
        #expect(catalog.top("plain yogurt", 1).first == "Yogurt, plain, whole milk")
        // A label's word typed first is read past: the rules for a word typed alone, a short
        // name and a dish's other name still apply.
        #expect(catalog.top("organic ranch", 1).first?.hasPrefix("Salad dressing, ranch") == true)
        #expect(catalog.top("homemade mac and cheese", 1).first == "Macaroni or noodles with cheese")
        #expect(catalog.top("organic eggs benedict", 1).first == "Egg, Benedict")
        // Typed alone it's a search like any other.
        #expect(catalog.searchCatalog("organic", known: [:]).text == "organic")
    }

    @Test("what's eaten through a day comes first typed and named as a model would")
    func snacksBasket() {
        for seen in [false, true] {
            var first = 0
            var missed: [String] = []
            for (query, pattern) in snacks {
                let names = seen ? catalog.candidates(name: query, brand: nil).prefix(1).map(\.food.name) : catalog.top(query, 1)
                if names.first.map({ matches(pattern, $0) }) == true { first += 1 } else { missed.append("\(query): \(names.first ?? "nothing")") }
            }
            print("Breakfast and snacks \(seen ? "as a model names them" : "typed"): \(first) of \(snacks.count) first")
            #expect(Double(first) >= 0.95 * Double(snacks.count), "\(seen ? "seen" : "typed"): \(missed.joined(separator: " | "))")
        }
        // What the catalog names by exactly the words seen is that food, whatever it's said
        // to come with; otherwise the food, and a dish that has what it comes with.
        #expect(
            catalog.candidates(name: "Pasta with meat sauce", brand: nil).first?.food.name == "Pasta with tomato-based sauce and meat, restaurant")
        #expect(
            catalog.candidates(name: "Spaghetti with meatballs", brand: nil).first?.food.name == "Restaurant, family style, spaghetti and meatballs")
        #expect(catalog.candidates(name: "Toast with butter", brand: nil).first?.food.name.hasPrefix("Bread") == true)
        // A plain food reached past the dishes made with it, however many there are.
        #expect(
            catalog.candidates(name: "Shredded chicken", brand: nil).first?.food.name == "Chicken, cooked")
    }

    @Test("a food said to be fresh is the raw one, typed and named as a model would")
    func freshBasket() {
        for seen in [false, true] {
            var first = 0
            var missed: [String] = []
            for (query, pattern) in fresh {
                let names = seen ? catalog.candidates(name: query, brand: nil).prefix(1).map(\.food.name) : catalog.top(query, 1)
                if names.first.map({ matches(pattern, $0) }) == true { first += 1 } else { missed.append("\(query): \(names.first ?? "nothing")") }
            }
            print("Fresh foods \(seen ? "as a model names them" : "typed"): \(first) of \(fresh.count) first")
            #expect(Double(first) >= 0.95 * Double(fresh.count), "\(seen ? "seen" : "typed"): \(missed.joined(separator: " | "))")
        }
        // Fresh is USDA's raw, wherever the food is filed, and still the word of a food that says it.
        let zucchini = [OwnWordsTests.food("Squash, summer, zucchini, includes skin, raw"), OwnWordsTests.food("Fresh Zucchini", brand: "Farm")]
        #expect(rankSearch("fresh zucchini", zucchini).first?.food.name == "Squash, summer, zucchini, includes skin, raw")
        let basil = [OwnWordsTests.food("Spices, basil, dried"), OwnWordsTests.food("Basil, fresh")]
        #expect(rankSearch("fresh basil", basil).first?.food.name == "Basil, fresh")
        // It isn't cooked or smoked, though the food usually is when no more is said.
        let salmon = ["Fish, salmon, chinook, smoked", "Fish, salmon, Atlantic, wild, raw", "Fish, salmon, Atlantic, wild, cooked, dry heat"]
            .map { OwnWordsTests.food($0) }
        #expect(rankSearch("fresh salmon", salmon).first?.food.name == "Fish, salmon, Atlantic, wild, raw")
        #expect(rankSearch("salmon", salmon).first?.food.name == "Fish, salmon, Atlantic, wild, cooked, dry heat")
        // A word after only how the food comes is whole: the corn of "fresh corn" isn't cornsalad begun.
        let corn = [OwnWordsTests.food("Cornsalad, raw"), OwnWordsTests.food("Corn, sweet, white, raw")]
        #expect(rankSearch("fresh corn", corn).first?.food.name == "Corn, sweet, white, raw")
        #expect(rankSearch("raw corn", corn).first?.food.name == "Corn, sweet, white, raw")
        // USDA's name in another order is still its name, not a brand's: "Thyme, fresh".
        #expect(catalog.top("fresh thyme", 1).first == "Thyme, fresh")
        // The herb, typed alone or said to be fresh.
        #expect(catalog.top("mint", 1).first.map { matches("^(Peppermint|Spearmint), fresh$", $0) } == true)
        // Mashed potatoes made from fresh ones still say so.
        #expect(catalog.top("fresh mashed potatoes", 1).first == "Potato, mashed, from fresh")
    }

    @Test("a food said to be cooked is the plain cooked one, typed and named as a model would")
    func cookedBasket() {
        for seen in [false, true] {
            var first = 0
            var missed: [String] = []
            for (query, pattern) in cookedFoods {
                let names = seen ? catalog.candidates(name: query, brand: nil).prefix(1).map(\.food.name) : catalog.top(query, 1)
                if names.first.map({ matches(pattern, $0) }) == true { first += 1 } else { missed.append("\(query): \(names.first ?? "nothing")") }
            }
            print("Cooked foods \(seen ? "as a model names them" : "typed"): \(first) of \(cookedFoods.count) first")
            #expect(Double(first) >= 0.95 * Double(cookedFoods.count), "\(seen ? "seen" : "typed"): \(missed.joined(separator: " | "))")
        }
        // The fat trimmed off a cut isn't the meat, and the cuts together are the meat typed alone.
        let pork = [
            "Pork, fresh, separable fat, cooked", "Pork, fresh, backribs, separable lean and fat, cooked, roasted",
            "Pork, fresh, composite of trimmed retail cuts (leg, loin, and shoulder), separable lean only, cooked",
        ].map { OwnWordsTests.food($0) }
        #expect(
            rankSearch("pork", pork).first?.food.name
                == "Pork, fresh, composite of trimmed retail cuts (leg, loin, and shoulder), separable lean only, cooked")
        #expect(rankSearch("pork", pork).last?.food.name == "Pork, fresh, separable fat, cooked")
        // Typed alone, pork is the survey's "Pork, cooked", which the catalog keeps "Pork" for.
        #expect(catalog.top("pork", 1) == ["Pork, cooked"])
        // A plain food from a restaurant is cooked their way, which wasn't asked for.
        let beans = [
            OwnWordsTests.food("Green beans, cooked, from restaurant"),
            OwnWordsTests.food("Beans, snap, green, cooked, boiled, drained, without salt"),
        ]
        #expect(rankSearch("cooked green beans", beans).first?.food.name == "Beans, snap, green, cooked, boiled, drained, without salt")
        #expect(rankSearch("green beans restaurant", beans).first?.food.name == "Green beans, cooked, from restaurant")
        // With only how it comes said of it, a word is as good as typed alone.
        let lamb = [OwnWordsTests.food("Lambsquarters, cooked, boiled, drained, with salt"), OwnWordsTests.food("Lamb, ground, cooked, broiled")]
        #expect(rankSearch("cooked lamb", lamb).first?.food.name == "Lamb, ground, cooked, broiled")
        #expect(catalog.top("cooked spaghetti", 1).first.map { matches("^Pasta, cooked", $0) } == true)
        #expect(catalog.top("spaghetti squash", 1).first.map { matches("(?i)spaghetti", $0) } == true)
    }

    @Test("a dish known by its own name comes first typed and named as a model would")
    func worldBasket() {
        for seen in [false, true] {
            var first = 0
            var missed: [String] = []
            for (query, pattern) in world {
                let names = seen ? catalog.candidates(name: query, brand: nil).prefix(1).map(\.food.name) : catalog.top(query, 1)
                if names.first.map({ matches(pattern, $0) }) == true { first += 1 } else { missed.append("\(query): \(names.first ?? "nothing")") }
            }
            print("Dishes by their own names \(seen ? "as a model names them" : "typed"): \(first) of \(world.count) first")
            #expect(
                Double(first) >= 0.95 * Double(world.count),
                "\(seen ? "seen" : "typed"): \(missed.joined(separator: " | "))")
        }
        // An everyday food's whole name has no typo in it, however few foods have the word.
        #expect(EverydayPhrases.isName(["raita"]) && EverydayPhrases.isName(["mapo", "tofu"]) && !EverydayPhrases.isName(["mapo"]))
        #expect(catalog.top("raita", 1).first.map { matches("(?i)ratatouille", $0) } != true)
        #expect(catalog.top("mapo tofu", 1).first.map { matches("(?i)mayo", $0) } != true)
        // A word that is a food's whole name isn't another's begun: roti isn't rotisserie chicken.
        #expect(catalog.top("roti", 1).first.map { matches("^Bread, chapati or roti", $0) } == true)
        // The plural of a word the catalogs word their own way is read as the word is.
        #expect(searchForms("sodas").contains("carbonated") && searchForms("cokes").contains("cola") && searchForms("lagers").contains("beer"))
        #expect(!searchForms("mints").contains("spearmint"))
        // One french fry is french fries, and sashimi the fish raw.
        #expect(catalog.top("french fry", 1).first.map { matches("^Potato(es)?, french fri", $0) } == true)
        #expect(catalog.top("salmon sashimi", 1).first.map { matches("^Fish, salmon, .*raw", $0) } == true)
        // As a model spells them, where USDA spells them its own way.
        #expect(catalog.candidates(name: "Egg foo young", brand: nil).first?.food.name.hasPrefix("Egg foo yung") == true)
        #expect(catalog.candidates(name: "Dolmas", brand: nil).first.map { matches("rape leaves", $0.food.name) } == true)
    }

    @Test("a common misspelling finds what the right spelling does")
    func commonMisspellings() {
        var same = 0
        var missed: [String] = []
        for (wrong, right) in misspellings {
            let (found, meant) = (catalog.top(wrong, 1).first, catalog.top(right, 1).first)
            if found == meant { same += 1 } else { missed.append("\(wrong): \(found ?? "nothing"), not \(meant ?? "nothing")") }
        }
        print("Common misspellings: \(same) of \(misspellings.count) find what the right spelling does")
        #expect(Double(same) >= 0.95 * Double(misspellings.count), "\(missed.joined(separator: " | "))")
        // No misspelling is the start of the word meant, which a word still being typed could be.
        for (wrong, right) in Misspellings.meant { #expect(!right.hasPrefix(wrong), "\(wrong)") }
        // Wherever it's typed, and with the catalogs' own words for the food still read.
        #expect(catalog.searchCatalog("grilled porkchop", known: [:]).text == "grilled pork chop")
        #expect(catalog.searchCatalog("whey protien", known: [:]).text == "whey protein")
        #expect(catalog.top("mac n chese", 1) == catalog.top("mac n cheese", 1))
        // A word USDA writes is no misspelling, though another spelling of it is searched too.
        #expect(Misspellings.meant["lasagne"] == nil && searchForms("lasagne").contains("lasagna") && searchForms("catsup").contains("ketchup"))
        // A word that is the whole of a plain food's name is one a misspelling is read as,
        // however few foods say it: with USDA's foods alone, where no label helps.
        #expect(Catalogs.usda.top("screwdrirer", 1) == ["Screwdriver"] && Catalogs.usda.top("baklva", 1) == ["Baklava"])
        // And a name the catalog keeps for a food is as exact misspelt as typed right.
        #expect(catalog.top("americno", 1) == ["Coffee, brewed"] && catalog.top("manhatten", 1) == ["Manhattan"])
        // The person's own food is found by the word meant.
        let own = Food(id: "custom:broccoli", name: "Roasted Broccoli", basis: .g, nutrients: .zero, source: .custom)
        #expect(catalog.search("brocolli", personal: [PersonalFood(food: own, score: 1)]).first?.food.id == own.id)
    }

    @Test("sweets and snacks come first by the names they're asked for, typed and named as a model would")
    func sweetsBasket() {
        for seen in [false, true] {
            var first = 0
            var missed: [String] = []
            for (query, pattern) in sweets {
                let names = seen ? catalog.candidates(name: query, brand: nil).prefix(1).map(\.food.name) : catalog.top(query, 1)
                if names.first.map({ matches(pattern, $0) }) == true { first += 1 } else { missed.append("\(query): \(names.first ?? "nothing")") }
            }
            print("Sweets and snacks \(seen ? "as a model names them" : "typed"): \(first) of \(sweets.count) first")
            #expect(
                Double(first) >= 0.95 * Double(sweets.count),
                "\(seen ? "seen" : "typed"): \(missed.joined(separator: " | "))")
        }
        // A name with the words said back to front is another food, where a plain food is named
        // by them as said. Typed category first with no such food, the food is still the food.
        let chocolate = [
            Entry(OwnWordsTests.food("Chocolate milk")), Entry(OwnWordsTests.food("Chocolate candy"), also: "Milk chocolate\nChocolate bar"),
        ]
        #expect(rankSearch("milk chocolate", chocolate).first?.food.name == "Chocolate candy")
        #expect(rankSearch("chocolate milk", chocolate).first?.food.name == "Chocolate milk")
        let juice = [OwnWordsTests.food("Juice, apple and grape blend"), OwnWordsTests.food("Apple juice, canned or bottled")]
        #expect(rankSearch("juice apple", juice).first?.food.name == "Apple juice, canned or bottled")
        // Another name is what was said only when its words are joined as said: nachos with
        // cheese aren't the dip also called "Nacho cheese".
        let nachos = [
            Entry(OwnWordsTests.food("Cheese dip"), also: "Queso\nNacho cheese"), Entry(OwnWordsTests.food("Nachos, cheese only"), dish: true),
        ]
        #expect(rankSearch("nachos with cheese", nachos).first?.food.name == "Nachos, cheese only")
        #expect(rankSearch("nacho cheese", nachos).first?.food.name == "Cheese dip")
        // The name the catalog keeps, exactly as said, before a food's own name read into it.
        #expect(catalog.top("peanut butter cup", 1).first == "Chocolate candy, peanut butter filled")
        #expect(catalog.candidates(name: "Peanut butter cups", brand: nil).first?.food.name == "Chocolate candy, peanut butter filled")
        // A label listed under a food's own word isn't the maker of the food by that name.
        #expect(catalog.top("cereal bar", 1).first == "Cereal or Granola bar")
        // Nor does a plain food's other form of a word make it no brand's: Ruffles, typed as
        // written, aren't the "ruffled" of the survey's potato chips.
        #expect(catalog.search("ruffles").first?.food.brand?.lowercased() == "ruffles")
        // A word that starts a plain food's is still on its way to it, though a brand is
        // written just so: "sam" is a samosa before Sam's cola. And the name the catalog keeps
        // for a plain food is that food before the brand it was once.
        #expect(catalog.top("sam", 1).first == "Samosa")
        #expect(catalog.top("ok", 1).first?.hasPrefix("Okra") == true)
        #expect(catalog.top("jello", 1).first == "Gelatin dessert")
        // Mint is the herb and mints the sweet; a protein bar is the survey's nutrition bar.
        #expect(catalog.top("mints", 1).first == "Candy, mint")
        #expect(catalog.top("protein bar", 1).first == "Nutrition bar or meal replacement bar")
        // Sweets and snacks from the survey are read as snacks are, not as a restaurant's dish.
        for name in ["chocolate candy", "potato chips", "air popped popcorn", "gummy bears"] {
            #expect(catalog.search(name).first?.food.processing == .ultraProcessed, "\(name)")
        }
    }

    @Test("a food typed or named with what it comes with is the food, the one that has it first")
    func foodsWithSides() {
        for seen in [false, true] {
            var first = 0
            var missed: [String] = []
            for (query, pattern) in withSides {
                let names = seen ? catalog.candidates(name: query, brand: nil).prefix(1).map(\.food.name) : catalog.top(query, 1)
                if names.first.map({ matches(pattern, $0) }) == true { first += 1 } else { missed.append("\(query): \(names.first ?? "nothing")") }
            }
            print("Foods with what they come with \(seen ? "as a model names them" : "typed"): \(first) of \(withSides.count) first")
            #expect(
                Double(first) >= 0.95 * Double(withSides.count),
                "\(seen ? "seen" : "typed"): \(missed.joined(separator: " | "))")
        }
        // The food, not a label with both words nor what it comes with.
        #expect(catalog.top("toast with butter", 1).first?.hasPrefix("Bread") == true)
        #expect(catalog.top("salad with dressing", 1).first?.hasPrefix("Lettuce, salad") == true)
        // The entry that says it comes with it, where it says little else.
        #expect(catalog.top("tea with milk", 1).first == "Tea, hot, with milk")
        #expect(catalog.top("rice with chicken", 1).first != "Rice, fried, with chicken")
        // The food named with it before the food: a turkey sandwich is a sandwich with turkey.
        #expect(catalog.top("sandwich with turkey", 1).first?.hasPrefix("Turkey sandwich") == true)
        // Not the one that says it comes without it.
        #expect(catalog.top("spaghetti with sauce", 1).first != "Pasta with vegetables, no sauce or dressing")
        // A food the catalog names by all of it is found as before.
        #expect(catalog.top("biscuit with gravy", 1).first == "Biscuit with gravy")
        // What it comes with is a food to log too: right after the food, where the food found
        // doesn't have it, as foods typed together are.
        let beside = [
            ("toast with butter", "^Butter, salted"), ("toast with jam", "^Jams"), ("toast with peanut butter", "^Peanut butter"),
            ("toast with avocado", "^Avocados"), ("bagel with cream cheese", "^Cheese, cream"), ("coffee with sugar", "^Sugars, granulated"),
            ("tea with honey", "^Honey"), ("cereal with milk", "^Milk, whole"), ("oatmeal with banana", "^Bananas, raw"),
            ("yogurt with honey", "^Honey"), ("apple with peanut butter", "^Peanut butter"), ("celery with peanut butter", "^Peanut butter"),
            ("salad with dressing", "^Salad dressing"), ("salad with ranch", "^Salad dressing, ranch"), ("pancakes with syrup", "^Syrups"),
            ("waffles with syrup", "^Syrups"), ("bread with butter", "^Butter, salted"), ("pita with hummus", "^Hummus"),
            ("fries with ketchup", "^Ketchup"), ("hot dog with bun", "^Rolls, hamburger or hotdog"), ("rice with butter", "^Butter, salted"),
            ("baked potato with sour cream", "^Cream, sour"), ("steak with potatoes", "^Potato"), ("salmon with rice", "^Rice"),
            ("toast with eggs", "^Egg, whole"), ("tomato soup with grilled cheese", "^Grilled cheese sandwich"),
        ]
        let second = beside.filter { typed, pattern in catalog.top(typed, 2).dropFirst().first.map { matches(pattern, $0) } == true }
        print("Foods with what they come with: that food is second for \(second.count) of \(beside.count)")
        #expect(Double(second.count) >= 0.95 * Double(beside.count))
        #expect(catalog.top("coffee with cream and sugar", 3).dropFirst().allSatisfy { $0.hasPrefix("Cream") || $0.hasPrefix("Sugars") })
        // Not after the food that has it.
        #expect(catalog.top("tea with milk", 2).last?.hasPrefix("Milk") == false)
        #expect(catalog.top("mashed potatoes with gravy", 2).allSatisfy { $0.hasPrefix("Potato") })
        // Two words of one food count together: chocolate ice cream isn't ice cream with
        // chocolate syrup.
        #expect(catalog.top("ice cream with chocolate syrup", 2) == ["Ice cream", "Syrups, chocolate, fudge-type"])
        // A hamburger with cheese is a cheeseburger, and a bun the roll it comes in.
        #expect(catalog.top("burger with cheese", 1).first == "Cheeseburger")
        #expect(catalog.top("bun", 1).first == "Rolls, hamburger or hotdog, plain")
        // Fries a model names are french fries, whatever else is cut like them.
        #expect(catalog.candidates(name: "Fries", brand: nil).first?.food.name == "Potato, french fries")
        #expect(catalog.candidates(name: "Sweet potato fries", brand: nil).first?.food.name == "Sweet potato fries")
    }

    @Test("a food is found by its British or Australian name and by its short form, typed and named as a model would")
    func britishAndShort() {
        for seen in [false, true] {
            var first = 0
            var missed: [String] = []
            for (query, pattern) in otherNames {
                let names = seen ? catalog.candidates(name: query, brand: nil).prefix(1).map(\.food.name) : catalog.top(query, 1)
                if names.first.map({ matches(pattern, $0) }) == true { first += 1 } else { missed.append("\(query): \(names.first ?? "nothing")") }
            }
            print("British names and short forms \(seen ? "as a model names them" : "typed"): \(first) of \(otherNames.count) first")
            #expect(Double(first) >= 0.95 * Double(otherNames.count), "\(seen ? "seen" : "typed"): \(missed.joined(separator: " | "))")
        }
        // A word for the same food finds the labels that say it too: Tayto's crisps.
        #expect(catalog.top("cheese and onion crisps", 1).first.map { matches("(?i)crisps", $0) } == true)
        // Typed alone, a short name isn't the word a letter away: a cuke isn't a Coke.
        #expect(catalog.respell("cuke").text == "cucumber" && catalog.respell("nugs").text == "chicken nuggets")
        #expect(catalog.respell("mince").text == "ground beef" && catalog.respell("minced garlic").text == "minced garlic")
        // Two words that are one food there: the sugar, not a cookie with icing.
        #expect(catalog.respell("icing sugar").also["icing"] == ["powdered"])
        #expect(catalog.top("apple crisp", 1).first == "Crisp, apple")
    }

    @Test("a word that names another food in Britain or Australia is read by the phone's region, typed and named as a model would")
    func byRegion() {
        var opened: [String: FoodCatalog] = [:]
        func catalog(_ region: String) -> FoodCatalog {
            if let catalog = opened[region] { return catalog }
            let catalog = FoodCatalog(usda: Catalogs.usdaURL, off: Catalogs.offURL, region: region)
            opened[region] = catalog
            return catalog
        }
        for seen in [false, true] {
            var missed: [String] = []
            for (region, query, pattern) in regionalWords {
                let found = catalog(region)
                let names = seen ? found.candidates(name: query, brand: nil).prefix(1).map(\.food.name) : found.top(query, 1)
                if names.first.map({ matches(pattern, $0) }) != true { missed.append("\(region) \(query): \(names.first ?? "nothing")") }
            }
            print(
                "Words by region \(seen ? "as a model names them" : "typed"): \(regionalWords.count - missed.count) of \(regionalWords.count) first")
            #expect(Double(missed.count) <= 0.05 * Double(regionalWords.count), "\(seen ? "seen" : "typed"): \(missed.joined(separator: " | "))")
        }
        var first = 0
        var second = 0
        for pair in regionalPairs {
            let names = catalog(pair.region).top(pair.typed, 2)
            if names.first.map({ matches(pair.first, $0) }) == true { first += 1 }
            if names.dropFirst().first.map({ matches(pair.second, $0) }) == true { second += 1 }
        }
        print("Foods typed together by region: \(first) of \(regionalPairs.count) first, the second food second for \(second)")
        #expect(first == regionalPairs.count && second == regionalPairs.count)
        // A word on its way to one is read the same: "cide" is the cider of the place.
        #expect(catalog("us").top("cide", 1) == ["Apple cider"] && catalog("gb").top("cide", 1) == ["Hard cider"])
        #expect(catalog("gb").top("biscu", 1) == ["Cookie"])
        // What a model names so is logged as surely as the food by its American name.
        let fries = catalog("gb").candidates(name: "Chips", brand: nil).first
        #expect(fries?.food.name == "Potato, french fries" && fries?.named == true)
        // The words alone, with no region to read them by.
        #expect(regionalName(["chips"], in: "gb") == "french fries" && regionalName(["chips"], in: "us") == nil)
        #expect(regionalName(["chips"], in: "au") == nil && regionalName(["hot", "chips"], in: "au") == "french fries")
        #expect(regionalName(["chips"], in: nil) == nil && regionalName(["cider"], in: "us") == "apple cider")
    }

    @Test("a chain typed with nothing after it leads with what it's known for")
    func chainsTypedAlone() {
        var missed: [String] = []
        for (query, pattern) in chainsAlone where catalog.top(query, 1).first.map({ matches(pattern, $0) }) != true {
            missed.append("\(query): \(catalog.top(query, 1).first ?? "nothing")")
        }
        print("Chains typed alone: \(chainsAlone.count - missed.count) of \(chainsAlone.count) first")
        #expect(Double(missed.count) <= 0.05 * Double(chainsAlone.count), "\(missed.joined(separator: " | "))")
        // Its own item where USDA has it, else the food as such a place serves it, in the
        // order it's known for them; then what shops sell under its name.
        #expect(catalog.top("mcdonalds", 2) == ["McDONALD'S, BIG MAC", "McDONALD'S, Cheeseburger"])
        #expect(catalog.top("five guys", 2) == ["Cheeseburger, from fast food, 1 medium patty", "Potato, french fries, fast food"])
        #expect(catalog.top("wendys", 4).last == "WENDY'S, Frosty Dairy Dessert")
        #expect(catalog.names("taco bell", 8).contains { $0.hasSuffix("[Taco Bell]") })
        // A few letters after it are a food begun: what it's known for that starts so.
        #expect(catalog.top("five guys fr", 1) == ["Potato, french fries, fast food"])
        // A food it isn't known for is that food from such a place, as before.
        #expect(catalog.top("five guys grilled cheese", 1).first.map { matches("(?i)grilled cheese", $0) } == true)
        // The words alone: however it's written, most of the way there, and not a food's word.
        #expect(Chains.alone("in n out")?.name == "in-n-out" && Chains.alone("Wendy's")?.name == "wendys")
        #expect(Chains.alone("five guy")?.name == "five guys" && Chains.alone("five g") == nil && Chains.alone("out") == nil)
        #expect(Chains.alone("chipotle") == nil && Chains.alone("five guys b")?.name == "five guys")
        #expect(Chains.begun("fr", of: ["cheeseburger", "french fries"]) == ["french fries"])
        #expect(Chains.begun("bu", of: ["cheeseburger", "french fries"]) == ["cheeseburger"])
        // The suggestions go on to the same foods, and from most of a name to the chain.
        #expect(FoodCompletions.suggest("five guys", from: []).first == "five guys cheeseburger")
        #expect(FoodCompletions.suggest("five guys f", from: []).first == "five guys french fries")
        #expect(FoodCompletions.suggest("five gu", from: []).first == "five guys")
    }

    @Test("more chains are known, and a chain's label has its name word for word")
    func moreChainsKnown() {
        var missed: [String] = []
        for (query, pattern) in moreChains {
            // With its brand, where it's a label: a chain's own is told by it.
            let first = catalog.search(query).first.map { found in found.food.brand.map { "\(found.food.name) [\($0)]" } ?? found.food.name }
            if first.map({ matches(pattern, $0) }) != true { missed.append("\(query): \(first ?? "nothing")") }
        }
        print("More chains: \(moreChains.count - missed.count) of \(moreChains.count) first")
        #expect(Double(missed.count) <= 0.05 * Double(moreChains.count), "\(missed.joined(separator: " | "))")
        // The brand on a label is the chain's however it's written, and not one that only
        // starts like it, which is all a half-typed brand needs.
        #expect(Chains.isBrand("TGI-Fridays", of: "tgi fridays") && Chains.isBrand("Tgi Friday's", of: "tgi fridays"))
        #expect(Chains.isBrand("Panera Bread", of: "panera") && Chains.isBrand("Pret A Manger", of: "pret manger"))
        #expect(Chains.isBrand("Carl's Jr.", of: "carls jr") && Chains.isBrand(nil, of: "five guys"))
        #expect(!Chains.isBrand("Uncle crumbles granola", of: "crumbl") && !Chains.isBrand("Crumble Cookie", of: "crumbl cookies"))
        #expect(catalog.top("crumbl sugar cookie", 1).first.map { matches("^Cookies?, (butter or )?sugar", $0) } == true)
        // "Food" in a USDA footnote isn't "from fast food": a chain's macaroni is the plain
        // pasta, not the whole-wheat one "(Includes foods for USDA's Food Distribution Program)".
        #expect(catalog.top("kfc macaroni", 1).first.map { matches("^Pasta, cooked", $0) } == true)
        // Nor is a Chinese restaurant's wonton soup a sandwich shop's soup.
        #expect(catalog.top("panera soup and sandwich", 2) == ["Soup", "Sandwich"])
        #expect(catalog.top("panda express orange chicken", 1) == ["Restaurant, Chinese, orange chicken"])
    }

    @Test("a chain typed with two foods, or a food and a side, is each from that chain")
    func chainPlatesTyped() {
        var missed: [String] = []
        for (query, pattern, _) in chainPlates where catalog.top(query, 1).first.map({ matches(pattern, $0) }) != true {
            missed.append("\(query): \(catalog.top(query, 1).first ?? "nothing")")
        }
        print("Chain plates: \(chainPlates.count - missed.count) of \(chainPlates.count) first")
        #expect(Double(missed.count) <= 0.05 * Double(chainPlates.count), "\(missed.joined(separator: " | "))")
        let pairs = chainPlates.filter { !$0.second.isEmpty }
        let second = pairs.filter { pair in catalog.top(pair.typed, 2).dropFirst().first.map { matches(pair.second, $0) } == true }
        print("Chain plates: the second food is second for \(second.count) of \(pairs.count)")
        #expect(Double(second.count) >= 0.95 * Double(pairs.count))
        // Its own items where USDA has them, in the order typed, then the rest of each.
        #expect(catalog.top("mcdonalds big mac and fries", 2) == ["McDONALD'S, BIG MAC", "McDONALD'S, french fries"])
        #expect(catalog.top("five guys burger and fries", 2) == ["Hamburger, from fast food, 1 medium patty", "Potato, french fries, fast food"])
        // The chain's words apart from the rest, at either end and however it's written.
        #expect(Chains.apart("five guys burger and fries")?.rest == "burger and fries")
        #expect(Chains.apart("pancakes with syrup from McDonald's").map { [$0.name, $0.rest] } == ["mcdonalds", "pancakes with syrup"])
        #expect(Chains.apart("burger and fries") == nil && Chains.apart("five guys") == nil)
        // A way of cooking is the food's it was said with: fried chicken and rice aren't
        // fried rice with chicken, which chicken and fried rice are.
        #expect(catalog.top("fried chicken and rice", 2).first.map { matches("^Chicken, fried", $0) } == true)
        #expect(catalog.top("chicken and fried rice", 1) == ["Rice, fried, with chicken"])
    }

    @Test("a food said to be without something is the food, and never the thing")
    func saidWithout() {
        var missed: [String] = []
        for (query, pattern) in withoutTyped {
            let first = catalog.search(query).first.map { found in found.food.brand.map { "\(found.food.name) [\($0)]" } ?? found.food.name }
            if first.map({ matches(pattern, $0) }) != true { missed.append("\(query): \(first ?? "nothing")") }
        }
        print("Without something, typed: \(withoutTyped.count - missed.count) of \(withoutTyped.count) first")
        #expect(Double(missed.count) <= 0.05 * Double(withoutTyped.count), "\(missed.joined(separator: " | "))")
        missed = []
        for (name, pattern) in withoutNamed {
            let first = catalog.candidates(name: name, brand: nil).first?.food.name
            if first.map({ matches(pattern, $0) }) != true { missed.append("\(name): \(first ?? "nothing")") }
        }
        print("Without something, as a model names it: \(withoutNamed.count - missed.count) of \(withoutNamed.count) first")
        #expect(Double(missed.count) <= 0.05 * Double(withoutNamed.count), "\(missed.joined(separator: " | "))")
        // The words: after the food, however it's joined on, and not where "no" starts a
        // label's own wording or a number follows.
        #expect(withoutSaid("whopper no cheese").map { [$0.main] + $0.lacked } == ["whopper", "cheese"])
        #expect(withoutSaid("coffee with no sugar")?.main == "coffee" && withoutSaid("burger, hold the mayo")?.lacked == ["mayo"])
        #expect(withoutSaid("Burger patty (no bun)").map { [$0.main] + $0.lacked } == ["Burger patty", "bun"])
        #expect(withoutSaid("applesauce no sugar added")?.lacked == ["sugar"] && withoutSaid("salad w/o dressing")?.lacked == ["dressing"])
        #expect(withoutSaid("no sugar added applesauce") == nil && withoutSaid("pho no 1") == nil && withoutSaid("coffee") == nil)
        // A catalog name's words apart: what it's without, up to the next comma.
        let pasta = wordsApart("Pasta with vegetables, no sauce or dressing")
        #expect(pasta.without.contains(stem("dressing")) && pasta.with.contains("pasta") && !pasta.with.contains(stem("sauce")))
        #expect(wordsApart("Chicken breast, cooked, without skin").without == ["skin"])
        // The food a model's name is for leaves out what it's without.
        #expect(FoodCatalog.food(in: "Salad without dressing") == "Salad")
        // The thing itself is never first, nor the food with it.
        #expect(catalog.top("burger no bun", 3).allSatisfy { !$0.hasPrefix("Rolls") })
        #expect(catalog.top("tea without milk", 3).allSatisfy { !$0.contains("with milk") && !$0.hasPrefix("Milk") })
        // The plain food is already without it, or has a word for being so.
        #expect(catalog.top("tea no sugar", 1) == catalog.top("tea", 1) && catalog.top("milk no fat", 1).first?.hasPrefix("Milk, nonfat") == true)
        #expect(catalog.top("coke no sugar", 1) == ["Soft drink, cola, diet"])
        // Said the other way, the food that says it's without it isn't the one.
        #expect(catalog.top("burger king whopper with cheese", 1) == ["BURGER KING, WHOPPER, with cheese"])
        // A drink or dish of two foods isn't the second of them: diet cola isn't whiskey and
        // diet cola. Asked for by both, or by its first, it still is.
        #expect(catalog.top("diet coke", 1) == ["Soft drink, cola, diet"] && catalog.top("diet cola", 1) == ["Soft drink, cola, diet"])
        #expect(catalog.top("tonic", 1) == ["Water, tonic"] && catalog.top("rum and coke", 1) == ["Rum and cola"])
        #expect(catalog.top("gin and tonic", 1) == ["Gin and tonic"] && catalog.top("pb and j", 1) == ["Peanut butter and jelly sandwich"])
    }

    @Test("a chain's item typed by its own name is the chain's")
    func menuItemsByName() {
        var missed: [String] = []
        for (query, pattern) in menuNames {
            let first = catalog.search(query).first.map { found in found.food.brand.map { "\(found.food.name) [\($0)]" } ?? found.food.name }
            if first.map({ matches(pattern, $0) }) != true { missed.append("\(query): \(first ?? "nothing")") }
        }
        print("Menu items by name: \(menuNames.count - missed.count) of \(menuNames.count) first")
        #expect(Double(missed.count) <= 0.05 * Double(menuNames.count), "\(missed.joined(separator: " | "))")
        // A Frosty is Wendy's, where "frosty" found frosting; frosting is still frosting.
        #expect(catalog.top("frosty", 1) == ["WENDY'S, Frosty Dairy Dessert"])
        #expect(catalog.top("frosting", 1).first?.hasPrefix("Frosting") == true)
        // A double double is In-N-Out's burger, and at Tim Hortons a coffee.
        #expect(
            regionalName(["double", "double"], in: "ca") == "coffee with cream and sugar" && regionalName(["double", "double"], in: "us") == nil)
        // A chain typed with a food isn't answered by another chain's: Burger King's Whopper
        // Jr for Wendy's jr cheeseburger. Two names for one menu are one chain.
        #expect(Chains.isAnothers("Whopper Jr with cheese (Burger King)", than: "wendys"))
        #expect(Chains.isAnothers("BURGER KING, WHOPPER, no cheese", than: "five guys"))
        #expect(
            !Chains.isAnothers("Whopper (Burger King)", than: "hungry jacks") && !Chains.isAnothers("Cheeseburger, from fast food", than: "wendys"))
        #expect(catalog.top("wendys jr cheeseburger", 1) == ["WENDY'S, Jr. Hamburger, with cheese"])
        // The skin alone isn't the food, where skin wasn't asked for.
        #expect(FoodText(name: "KFC, Fried Chicken, ORIGINAL RECIPE, Skin and Breading", brand: "", source: .usda).skinAlone)
        #expect(FoodText(name: "Potatoes, baked, skin, without salt", brand: "", source: .usda).skinAlone)
        #expect(!FoodText(name: "Squash, summer, zucchini, includes skin, raw", brand: "", source: .usda).skinAlone)
        #expect(!FoodText(name: "Chicken breast, fried, coated, skin and coating removed", brand: "", source: .usda).skinAlone)
        #expect(!FoodText(name: "Chicken thigh, cooked, with skin", brand: "", source: .usda).skinAlone)
        #expect(catalog.top("baked potato with skin", 1).first.map { matches("flesh and skin", $0) } == true)
        // A potato's "flesh and skin" is the whole potato, not a part of it: raw potatoes are
        // that, where the skin alone had led and then a scalloped potato.
        #expect(catalog.top("raw potatoes", 1) == ["Potatoes, flesh and skin, raw"])
        // What's said for one food isn't then read as two: a steak and cheese is the sandwich.
        #expect(catalog.top("steak and cheese", 1).first?.hasPrefix("Cheese steak sandwich") == true)
        #expect(catalog.top("steak and eggs", 2).first?.hasPrefix("Steak") == true)
    }

    @Test("a sandwich named with what's in it and an \"and\" is one food")
    func foodsThatHoldOthers() {
        var missed: [String] = []
        for (query, pattern) in heldFoods where catalog.top(query, 1).first.map({ matches(pattern, $0) }) != true {
            missed.append("\(query): \(catalog.top(query, 1).first ?? "nothing")")
        }
        print("Foods that hold others, typed: \(heldFoods.count - missed.count) of \(heldFoods.count) first")
        #expect(Double(missed.count) <= 0.05 * Double(heldFoods.count), "\(missed.joined(separator: " | "))")
        missed = []
        for (name, pattern) in heldNamed {
            let first = catalog.candidates(name: name, brand: nil).first?.food.name
            if first.map({ matches(pattern, $0) }) != true { missed.append("\(name): \(first ?? "nothing")") }
        }
        print("Foods that hold others, as a model names them: \(heldNamed.count - missed.count) of \(heldNamed.count) first")
        #expect(Double(missed.count) <= 0.1 * Double(heldNamed.count), "\(missed.joined(separator: " | "))")
        // The one with the least in it that wasn't asked for, cheese or no: an egg and cheese
        // biscuit is the egg sandwich on a biscuit, not the one with bacon too.
        #expect(catalog.top("egg and cheese biscuit", 1) == ["Egg sandwich on biscuit"])
        #expect(catalog.top("egg and cheese burrito", 1) == ["Egg burrito"])
        // A chain's own item is one food too.
        #expect(catalog.top("sausage and egg mcmuffin", 1) == ["McDONALD'S, Sausage McMUFFIN with Egg"])
        // Two foods stay two: fries aren't the "fried" of a chicken sandwich, nor is apple
        // butter an apple and peanut butter.
        #expect(catalog.top("fries and chicken sandwich", 2).first?.hasPrefix("Potato, french fries") == true)
        #expect(catalog.top("apple and peanut butter", 2).last?.hasPrefix("Peanut butter") == true)
        // The words that say a food's kind leave out what it comes with.
        let bagel = FoodText(name: "Egg sandwich on bagel, with bacon", brand: "", source: .usda)
        #expect(bagel.kindWords.contains("bagel") && bagel.kindWords.contains("sandwich") && !bagel.kindWords.contains("bacon"))
    }

    @Test("more small things: light bread, unsweetened coconut, a tuna packet, an omelet with ham")
    func moreOddsAndEnds() {
        var missed: [String] = []
        for (query, pattern) in wordedAnotherWay {
            let first = catalog.search(query).first.map { found in found.food.brand.map { "\(found.food.name) [\($0)]" } ?? found.food.name }
            if first.map({ matches(pattern, $0) }) != true { missed.append("\(query): \(first ?? "nothing")") }
        }
        print("Worded another way: \(wordedAnotherWay.count - missed.count) of \(wordedAnotherWay.count) first")
        #expect(Double(missed.count) <= 0.05 * Double(wordedAnotherWay.count), "\(missed.joined(separator: " | "))")
        // "Nonfat" is skim as much as skim is nonfat, and plain before the fruit one.
        #expect(catalog.top("nonfat yogurt", 1) == ["Yogurt, plain, skim milk"])
        // The survey's omelets are "with meat", whichever meat it was.
        #expect(catalog.top("ham and cheese omelet", 1) == ["Egg omelet or scrambled egg, with cheese and meat"])
        #expect(catalog.top("cheese omelet", 1).first?.hasSuffix("with cheese") == true)
    }

    @Test("a plate typed as a list is its foods")
    func platesTypedAsLists() {
        var missed: [String] = []
        for (query, pattern, _) in typedPlates where catalog.top(query, 1).first.map({ matches(pattern, $0) }) != true {
            missed.append("\(query): \(catalog.top(query, 1).first ?? "nothing")")
        }
        print("Plates typed as lists: \(typedPlates.count - missed.count) of \(typedPlates.count) first")
        #expect(Double(missed.count) <= 0.05 * Double(typedPlates.count), "\(missed.joined(separator: " | "))")
        let pairs = typedPlates.filter { !$0.second.isEmpty }
        let second = pairs.filter { pair in catalog.top(pair.typed, 2).dropFirst().first.map { matches(pair.second, $0) } == true }
        print("Plates typed as lists: the second food is second for \(second.count) of \(pairs.count)")
        #expect(Double(second.count) >= 0.95 * Double(pairs.count))
        // Three foods, in the order typed.
        let plate = catalog.top("eggs bacon and toast", 3)
        #expect(plate.count == 3 && plate[0].hasPrefix("Egg, whole") && plate[1].hasPrefix("Bacon") && plate[2].hasPrefix("Bread"))
        #expect(catalog.top("eggs, bacon, toast", 3) == plate)
        // One comma isn't a list, nor are the parts of a catalog's name.
        #expect(catalog.top("rice, brown", 1).first?.hasPrefix("Rice, brown") == true)
        #expect(catalog.top("chicken breast, grilled, skinless", 1).first?.contains("breast") == true)
        // What an everyday name ends on is a food by itself; what one starts with isn't.
        #expect(EverydayPhrases.isHead(stem("fries")) && EverydayPhrases.isHead(stem("wings")) && !EverydayPhrases.isHead(stem("grilled")))
        // A name the catalog has stays one food: lentil soup, and a banana sandwich.
        #expect(catalog.top("lentil soup and bread", 2).last?.hasPrefix("Bread") == true)
        #expect(catalog.top("peanut butter and banana sandwich", 1) == ["Peanut butter sandwich"])
    }

    @Test("a food said by another name is read the same after an amount or a size")
    func sizesBeforeOtherNames() {
        var missed: [String] = []
        for (query, pattern) in sizesSaid {
            let first = catalog.search(query).first.map { found in found.food.brand.map { "\(found.food.name) [\($0)]" } ?? found.food.name }
            if first.map({ matches(pattern, $0) }) != true { missed.append("\(query): \(first ?? "nothing")") }
        }
        print("Sizes and other names: \(sizesSaid.count - missed.count) of \(sizesSaid.count) first")
        #expect(Double(missed.count) <= 0.05 * Double(sizesSaid.count), "\(missed.joined(separator: " | "))")
        // The amount or the size stays as typed, in front of what the name means.
        #expect(catalog.respell("small frosty").text == "small wendys frosty" && catalog.respell("2 oj").text == "2 orange juice")
        #expect(catalog.respell("frosty").text == "wendys frosty" && catalog.respell("small frosting").text == "small frosting")
    }

    @Test("how a food was cut says nothing of which food it is, typed as it does named")
    func foodsTypedWithHowTheyAreCut() {
        var missed: [String] = []
        for (query, pattern) in cutFoods where catalog.top(query, 1).first.map({ matches(pattern, $0) }) != true {
            missed.append("\(query): \(catalog.top(query, 1).first ?? "nothing")")
        }
        print("Foods typed with how they're cut: \(cutFoods.count - missed.count) of \(cutFoods.count) first")
        #expect(Double(missed.count) <= 0.05 * Double(cutFoods.count), "\(missed.joined(separator: " | "))")
        // The words used to find whatever had them: ground beef with onion, chopped livers,
        // canned sweetened apple slices, a broth cube.
        #expect(catalog.top("minced onion", 1) == ["Onions, raw"] && catalog.top("chopped chicken", 1) == ["Chicken, cooked"])
        #expect(catalog.top("sliced apple", 1).first?.hasPrefix("Apples, raw") == true)
        // The labels named so come after the food and its kinds.
        #expect(catalog.names("chopped walnuts", 8).contains { $0.hasPrefix("Chopped Walnuts [") })
        // A plain food that lists the cut and nothing else is still the one meant.
        #expect(catalog.top("sliced ham", 1).first?.hasPrefix("Ham, sliced") == true)
        #expect(catalog.top("grated cheese", 1) == ["Cheese, parmesan, grated"])
        // And what's sold in a can by that name is the canned food.
        #expect(catalog.top("diced tomatoes", 1).first?.contains("canned") == true)
    }

    @Test("a food typed with the shape it's cut into is the food, and a food named by a shape is itself")
    func foodsTypedWithTheirShape() {
        var missed: [String] = []
        for (query, pattern) in shapedFoods where catalog.top(query, 1).first.map({ matches(pattern, $0) }) != true {
            missed.append("\(query): \(catalog.top(query, 1).first ?? "nothing")")
        }
        print("Foods typed with their shape: \(shapedFoods.count - missed.count) of \(shapedFoods.count) first")
        #expect(Double(missed.count) <= 0.05 * Double(shapedFoods.count), "\(missed.joined(separator: " | "))")
        // The shape after the food says nothing of which food.
        #expect(catalog.top("lemon wedge", 1).first?.hasPrefix("Lemons, raw") == true && catalog.top("carrot sticks", 1) == ["Carrots, raw"])
        #expect(catalog.top("feta crumbles", 1) == ["Cheese, feta"] && catalog.top("spinach leaves", 1) == ["Spinach, raw"])
        // A food a plain food names by the shape is its own.
        #expect(catalog.top("potato wedges", 1).first?.hasPrefix("Potato wedges") == true && catalog.top("fish sticks", 1) == ["Fish sticks"])
        #expect(catalog.top("chicken strips", 1) == ["Chicken tenders or strips"] && catalog.top("grape leaves", 1) == ["Grape leaves, raw"])
        #expect(catalog.top("chicken hearts", 1).first?.hasPrefix("Chicken, heart") == true)
        // Said first, the word is a kind: leaf lettuce, a strip steak.
        #expect(howWords(["lettuce", "leaves"]) == [1] && howWords(["leaf", "lettuce"]).isEmpty && howWords(["2", "strips"]).isEmpty)
        #expect(catalog.top("strip steak", 1) == ["Beef, steak, strip, cooked"])
        // Nor is it a brand's word: broccoli crowns aren't King's Crown's. Maple Leaf still is one.
        #expect(catalog.top("broccoli crowns", 1) == ["Broccoli, raw"])
        #expect(catalog.names("maple leaf", 1).first?.hasSuffix("[Maple Leaf]") == true)
        // A model's name is read the same way, where the shape used to be dropped as an amount.
        let seen = { (name: String) in self.catalog.candidates(name: name, brand: nil).first?.food.name ?? "" }
        #expect(seen("Lemon wedge").hasPrefix("Lemons, raw") && seen("Grape leaves") == "Grape leaves, raw")
        #expect(matches("(?i)wedge", seen("Potato wedges")) && seen("Bacon strips") == "Bacon, cooked")
        #expect(seen("Watermelon cubes") == "Watermelon, raw")
        // The ice in a glass is water; typed, the word is ice cream begun.
        #expect(seen("Ice cubes").hasPrefix("Water") && seen("Ice").hasPrefix("Water") && FoodCatalog.food(in: "Ice cubes") == "water")
        #expect(catalog.top("ice", 1) == ["Ice cream"])
    }

    @Test("a food typed with how it was prepared, or as whole, is the food")
    func foodsTypedWithHowTheyArePrepared() {
        var missed: [String] = []
        for (query, pattern) in preparedFoods where catalog.top(query, 1).first.map({ matches(pattern, $0) }) != true {
            missed.append("\(query): \(catalog.top(query, 1).first ?? "nothing")")
        }
        print("Foods typed with how they're prepared: \(preparedFoods.count - missed.count) of \(preparedFoods.count) first")
        #expect(Double(missed.count) <= 0.05 * Double(preparedFoods.count), "\(missed.joined(separator: " | "))")
        // A plain food that lists the word and nothing else is the one meant, typed or seen.
        #expect(catalog.top("mashed potatoes", 1) == ["Potato, mashed"] && catalog.top("hulled barley", 1) == ["Barley, hulled"])
        #expect(catalog.candidates(name: "Mashed potatoes", brand: nil).first?.food.name == "Potato, mashed")
        #expect(catalog.candidates(name: "Slivered almonds", brand: nil).first?.food.name == "Nuts, almonds")
        // Peeled is the food without its skin or peel, where the catalog has it both ways.
        #expect(catalog.top("peeled apple", 1) == ["Apples, raw, without skin"] && catalog.top("peeled lemon", 1) == ["Lemons, raw, without peel"])
        #expect(catalog.top("peeled zucchini", 1).first?.hasPrefix("Squash, summer, zucchini") == true)
        // Whole is part of some names and says nothing in the rest.
        #expect(howWords(["whole", "avocado"]) == [0] && howWords(["whole", "milk"]).isEmpty && howWords(["whole", "wheat", "bread"]).isEmpty)
        #expect(catalog.top("whole bagel", 1).first?.hasPrefix("Bagels, plain") == true)
        #expect(catalog.top("whole pizza", 1).first.map { matches("whole", $0) } == false)
        #expect(catalog.names("whole foods almond milk", 1).first.map { matches("(?i)whole foods", $0) } == true)
        // A word for how a food was prepared isn't a brand misspelt.
        #expect(catalog.searchCatalog("leftover pizza", known: [:]).fixes.isEmpty)
    }

    @Test("a food typed with the state it's in, or how it was bought, is the food")
    func foodsTypedWithTheirState() {
        var missed: [String] = []
        for (query, pattern, _) in stateFoods where catalog.top(query, 1).first.map({ matches(pattern, $0) }) != true {
            missed.append("\(query): \(catalog.top(query, 1).first ?? "nothing")")
        }
        print("Foods typed with their state: \(stateFoods.count - missed.count) of \(stateFoods.count) first")
        #expect(Double(missed.count) <= 0.05 * Double(stateFoods.count), "\(missed.joined(separator: " | "))")
        // What's buttered is the food and then butter.
        let pairs = stateFoods.filter { !$0.second.isEmpty }
        #expect(pairs.allSatisfy { pair in catalog.top(pair.typed, 2).dropFirst().first.map { matches(pair.second, $0) } == true })
        #expect(FoodCatalog.buttered("buttered toast") == "toast with butter" && FoodCatalog.buttered("buttered toast with jam") == nil)
        // The words are left out as a two-word way of cooking is, and the labels named so follow.
        #expect(catalog.plainlyCooked("ripe banana") == "banana" && catalog.plainlyCooked("store bought cookies") == "cookies")
        #expect(catalog.plainlyCooked("medium rare steak") == "steak" && catalog.plainlyCooked("thinly sliced turkey") == "sliced turkey")
        #expect(catalog.names("ripe banana", 8).contains { matches("(?i)ripe banana", $0) })
        // Cold and hot by the word after them, which may be one still being typed.
        #expect(
            catalog.plainlyCooked("cold pizza") == "pizza" && catalog.plainlyCooked("cold brew") == nil && catalog.plainlyCooked("cold br") == nil)
        #expect(catalog.plainlyCooked("hot coffee") == "coffee" && catalog.plainlyCooked("hot dog") == nil && catalog.plainlyCooked("hot co") == nil)
        // A brand's word stays one, and a search that is another name for a food is left alone.
        #expect(catalog.top("original glazed donut", 1).first.map { matches("(?i)original glazed", $0) } == true)
        #expect(catalog.top("store bought cookies", 1).first?.hasPrefix("Cookie") == true)
        // Frozen is a kind of the food where the catalog has one, and the food where it doesn't.
        #expect(howWords(["frozen", "banana"]) == [0] && howWords(["banana", "frozen"]).isEmpty)
        #expect(catalog.top("frozen yogurt", 1) == ["Frozen yogurt"] && catalog.top("frozen banana", 1) == ["Bananas, raw"])
        // A model's name is read the same way.
        let seen = { (name: String) in self.catalog.candidates(name: name, brand: nil).first?.food.name ?? "" }
        #expect(seen("Warm milk").hasPrefix("Milk, whole") && seen("Ripe banana") == "Bananas, raw" && seen("Hot coffee") == "Coffee")
        #expect(seen("Ground black pepper") == "Spices, pepper, black" && seen("Frozen banana") == "Bananas, raw")
    }

    @Test("a small word typed last, with nothing after it, may be the next word begun")
    func smallWordsBegun() {
        // After a food's word, "on", "to" and "or" start onion, toast and orange; a space after
        // one says it's the small word.
        #expect(readQuery("red on").words == ["red", "on"] && readQuery("red on ").words == ["red"])
        #expect(readQuery("french to").words == ["french", "to"] && readQuery("blood or").words == ["blood", "or"])
        // "Of" after the few foods named with it, not after an amount.
        #expect(readQuery("cream of").words == ["cream", "of"] && !readQuery("cup of").words.contains("of"))
        // Not after a food that goes on another, nor the words every other name has.
        #expect(readQuery("eggs on").words == ["eggs"] && readQuery("ham and").words == ["ham"] && readQuery("toast with").words == ["toast"])
        #expect(catalog.top("french to", 1) == ["French toast"] && catalog.top("corn to", 1).first?.hasPrefix("Tortillas") == true)
        #expect(catalog.top("chopped on", 1) == ["Onions, raw"] && catalog.top("sweet on", 1) == ["Onions, sweet, raw"])
        #expect(
            catalog.top("cream of", 1).first?.hasPrefix("Cream of") == true && catalog.top("hearts of", 1).first?.hasPrefix("Hearts of palm") == true)
        #expect(catalog.top("eggs on", 1).first?.hasPrefix("Egg, whole") == true)
    }

    @Test("a food typed with how it was raised or sold is the food, and a meatless one the catalog's")
    func foodsTypedWithHowTheyWereRaised() {
        var missed: [String] = []
        for (query, pattern) in raisedFoods where catalog.names(query, 1).first.map({ matches(pattern, $0) }) != true {
            missed.append("\(query): \(catalog.top(query, 1).first ?? "nothing")")
        }
        print("Foods typed with how they were raised: \(raisedFoods.count - missed.count) of \(raisedFoods.count) first")
        #expect(Double(missed.count) <= 0.05 * Double(raisedFoods.count), "\(missed.joined(separator: " | "))")
        // The words are left out as the state a food is in is, and a brand read from them is none.
        #expect(catalog.plainlyCooked("free range eggs") == "eggs" && catalog.plainlyCooked("wild caught salmon") == "salmon")
        #expect(catalog.plainlyCooked("extra large eggs") == "large eggs" && catalog.top("farm fresh eggs", 1).first?.hasPrefix("Egg, whole") == true)
        // Where the catalog has the food so raised, that's the one: grass-fed beef, wild salmon.
        #expect(catalog.top("grass fed beef", 1).first?.hasPrefix("Beef, grass-fed") == true)
        #expect(
            catalog.top("wild salmon", 1).first.map { matches("wild", $0) } == true
                && catalog.top("wild rice", 1).first?.hasPrefix("Wild rice") == true)
        // A meatless food by the name of what it stands in for.
        #expect(catalog.top("vegan burger", 1).first?.hasPrefix("Veggie burger") == true && catalog.top("veggie dog", 1) == ["Frankfurter, meatless"])
        #expect(catalog.candidates(name: "Vegan sausage", brand: nil).first?.food.name == "Sausage, meatless")
        #expect(catalog.candidates(name: "Free-range eggs", brand: nil).first?.food.name.hasPrefix("Egg, whole") == true)
    }

    @Test("a drink ordered another way is the catalog's drink")
    func drinksAsOrdered() {
        var missed: [String] = []
        for (query, pattern) in drinkOrders where catalog.top(query, 1).first.map({ matches(pattern, $0) }) != true {
            missed.append("\(query): \(catalog.top(query, 1).first ?? "nothing")")
        }
        print("Drinks as ordered: \(drinkOrders.count - missed.count) of \(drinkOrders.count) first")
        #expect(Double(missed.count) <= 0.05 * Double(drinkOrders.count), "\(missed.joined(separator: " | "))")
        // The milk said after the drink is the drink the catalog names by it; the milk it's
        // made with anyway is the drink.
        #expect(shortNames["latte with oat milk"] == "oat milk latte" && shortNames["flat white with soy milk"] == "soy milk latte")
        #expect(shortNames["cappuccino with whole milk"] == "cappuccino" && shortNames["latte with skim milk"] == nil)
        // A model's name is read the same way.
        let seen = { (name: String) in self.catalog.candidates(name: name, brand: nil).first?.food.name ?? "" }
        #expect(seen("Latte with oat milk") == "Coffee, Latte, with non-dairy milk" && seen("Strawberry banana smoothie").hasPrefix("Fruit smoothie"))
        #expect(seen("Earl Grey tea").hasPrefix("Beverages, tea, black"))
    }

    @Test("a vitamin or a mineral typed alone is the supplement, not a food that says it's added")
    func nutrientsTypedAlone() {
        // The labels named by it lead, not the milk "with added vitamin A and vitamin D", the
        // tofu set with magnesium chloride or the bagel "without calcium propionate".
        for query in ["vitamin d", "vitamin c", "vitamin b12", "magnesium", "calcium", "potassium"] {
            let first = catalog.top(query, 1).first ?? ""
            #expect(matches("(?i)^(liquid )?(vitamin|magnesium|calcium|potassium)", first), "\(query): \(first)")
        }
        // With a food it's the food so fortified, and a compound's name is its own.
        #expect(catalog.top("vitamin d milk", 1).first?.hasPrefix("Milk") == true)
        #expect(catalog.top("magnesium glycinate", 1).first.map { matches("(?i)glycinate", $0) } == true)
        #expect(catalog.names("vitamin water", 1).first.map { matches("(?i)vitamin ?water", $0) } == true)
    }

    @Test("everyday foods the survey has and SR Legacy lacks are found by their names, and a food typed with what names another isn't that one")
    func surveyFoodsAndWhatAFoodComesWith() {
        var missed: [String] = []
        for (query, pattern) in surveyFoods where catalog.top(query, 1).first.map({ matches(pattern, $0) }) != true {
            missed.append("\(query): \(catalog.top(query, 1).first ?? "nothing")")
        }
        print("Foods from the survey: \(surveyFoods.count - missed.count) of \(surveyFoods.count) first")
        #expect(Double(missed.count) <= 0.05 * Double(surveyFoods.count), "\(missed.joined(separator: " | "))")
        // The carton and the can are told apart by name, and the can still leads.
        #expect(
            catalog.top("coconut milk", 3).contains("Coconut milk beverage")
                && catalog.top("coconut milk", 3).contains("Coconut milk, used in cooking"))
        // With "with" between them, a steak sauce is steak and then sauce, a coffee creamer
        // coffee and then the creamer, and beef gravy the beef that comes with it.
        let firsts = { (query: String) in self.catalog.top(query, 2) }
        #expect(firsts("steak with sauce") == ["Steak, cooked", "Sauce"], "\(firsts("steak with sauce"))")
        #expect(firsts("coffee with creamer") == ["Coffee", "Coffee creamer"], "\(firsts("coffee with creamer"))")
        #expect(firsts("beef with gravy").first == "Beef with gravy" && firsts("turkey with gravy").first == "Turkey with gravy")
        #expect(firsts("ice cream with cone").first == "Ice cream")
        // Without it they're the sauce, the creamer and the gravy.
        #expect(firsts("steak sauce").first?.hasPrefix("Steak sauce") == true && firsts("beef gravy").first == "Gravy, beef")
        // What the food itself names, or says "with" of, is still the whole.
        #expect(
            firsts("biscuit with gravy").first == "Biscuit with gravy" && firsts("fries with cheese").first == "Potato, french fries, with cheese")
        #expect(firsts("sandwich with turkey").first?.hasPrefix("Turkey sandwich") == true)
        #expect(firsts("pasta with meat sauce").first?.hasPrefix("Pasta with") == true)
        // A model's name is read the same way.
        let seen = { (name: String) in self.catalog.candidates(name: name, brand: nil).first?.food.name ?? "" }
        #expect(
            seen("Steak with sauce").hasPrefix("Steak") && seen("Coffee with creamer") == "Coffee" && seen("Beef with gravy") == "Beef with gravy")
        #expect(seen("Oat milk") == "Oat milk" && seen("Scone") == "Scone" && seen("Chocolate chip muffin") == "Muffin, chocolate chip")
    }

    @Test("a word alone is the plain food a person means by it, and a food named by just the words typed leads")
    func plainFirstResults() {
        var missed: [String] = []
        for (query, pattern) in plainFirsts where catalog.top(query, 1).first.map({ matches(pattern, $0) }) != true {
            missed.append("\(query): \(catalog.top(query, 1).first ?? "nothing")")
        }
        print("Plain first results: \(plainFirsts.count - missed.count) of \(plainFirsts.count) first")
        #expect(missed.count <= 1, "\(missed.joined(separator: " | "))")
        // The name that is the words typed and no more leads the ones that go on to say
        // which; not a name that goes on to its skin or to another food it may be.
        #expect(catalog.top("snack mix", 2) == ["Snack mix", "Snacks, trail mix, regular"], "\(catalog.top("snack mix", 2))")
        #expect(catalog.top("grilled chicken breast", 1) == ["Chicken breast, grilled, without skin"])
        // Of two cooked as usual and in a microwave, the usual one.
        #expect(catalog.top("green beans", 2).last == "Beans, snap, green, microwaved")
        // A model's name finds the same.
        let seen = { (name: String) in self.catalog.candidates(name: name, brand: nil).first?.food.name ?? "" }
        #expect(seen("Pork") == "Pork, cooked" && seen("Tahini") == "Tahini" && seen("Gnocchi") == "Gnocchi, potato")
        #expect(seen("Green beans").hasPrefix("Beans, snap, green, cooked, boiled") || seen("Green beans").hasPrefix("Green beans, cooked"))
    }

    @Test("small things: the usual curry, nori, a chain's own words, a food's own word and a label no one scans")
    func oddsAndEnds() {
        // Curry with no more said is chicken curry; the kinds asked for are themselves.
        #expect(catalog.top("curry", 1) == ["Chicken curry"] && catalog.top("beef curry", 1) == ["Beef curry"])
        #expect(catalog.top("curry powder", 1).first?.hasPrefix("Spices, curry powder") == true)
        // Nori is the dried seaweed, which the survey has and SR Legacy doesn't.
        #expect(catalog.top("nori", 1) == ["Seaweed, dried"] && catalog.top("dried seaweed", 1) == ["Seaweed, dried"])
        // A label no one has scanned isn't the maker of a food the catalog calls by its name.
        #expect(catalog.top("fish fingers", 1) == ["Fish sticks"])
        // Ribs don't come by the rack as chips do by the bag, nor chicken by the bucket.
        #expect(catalog.top("rack of ribs", 1) == ["Ribs, cooked"] && catalog.top("bucket of chicken", 1) == ["Chicken, fried, coated"])
        // A chain's name is no misspelling, whatever the catalogs have of it.
        #expect(catalog.searchCatalog("el pollo loco", known: [:]).fixes.isEmpty)
        #expect(catalog.top("el pollo loco", 1).first.map { matches("(?i)coconut", $0) } != true)
        // Nor is a word that is a food of its own: chamoy isn't chamomile, a sope spearmint.
        #expect(catalog.top("chamoy", 1).first.map { matches("(?i)chamoy", $0) } == true)
        #expect(catalog.top("sope", 1).first.map { matches("(?i)^sopes?$", $0) } == true)
        #expect(catalog.top("esquites", 1).first.map { matches("(?i)esquites", $0) } == true)
    }

    @Test("a food typed with what it comes in, or with its number as a word, is the food")
    func containersAndNumberWords() {
        let same = amountsSaid.filter { catalog.top($0.typed, 1) == catalog.top($0.food, 1) }
        print("Containers and number words: \(same.count) of \(amountsSaid.count) first as the food alone is")
        let missed = amountsSaid.filter { pair in !same.contains { $0.typed == pair.typed } }.map(\.typed)
        #expect(Double(same.count) >= 0.95 * Double(amountsSaid.count), "\(missed.joined(separator: " | "))")
        // A number word that is part of a name isn't how many: the name goes on in the
        // singular, or isn't an everyday food.
        #expect(catalog.top("three cheese pizza", 1) == ["Three cheese pizza"] && catalog.top("three bean salad", 1) == ["Three bean salad"])
        #expect(catalog.top("two egg omelet", 1) == ["Egg, whole, cooked, omelet"])
        #expect(catalog.names("two good yogurt", 1).first?.contains("[Two Good]") == true)
        #expect(catalog.names("one bar", 1).first?.contains("[One]") == true && catalog.names("one protein bar", 1).first?.contains("[One]") == true)
        // Named last, what a food comes in is part of what it is.
        #expect(catalog.top("cheese stick", 1) == ["Cheese, mozzarella, low moisture, part-skim"] && catalog.top("fish sticks", 1) == ["Fish sticks"])
        #expect(catalog.top("head cheese", 1) == ["Head cheese"] && catalog.top("granola bar", 1) == ["Cereal or Granola bar"])
        #expect(catalog.top("tea bag", 1).first.map { matches("(?i)tea bag", $0) } == true)
        #expect(catalog.top("juice box", 1).first.map { matches("(?i)juice box", $0) } == true)
        // A model's "Two scrambled eggs" is scrambled eggs.
        #expect(catalog.candidates(name: "Two scrambled eggs", brand: nil).first?.food.name == "Egg, whole, cooked, scrambled")
    }

    @Test("a food typed in Spanish or by its Hindi name is the food its English name finds")
    func spanishAndHindi() {
        let same = otherLanguages.filter { catalog.top($0.typed, 1) == catalog.top($0.english, 1) }
        print("Spanish and Hindi names: \(same.count) of \(otherLanguages.count) first as their English is")
        let missed = otherLanguages.filter { pair in !same.contains { $0.typed == pair.typed } }.map(\.typed)
        #expect(Double(same.count) >= 0.95 * Double(otherLanguages.count), "\(missed.joined(separator: " | "))")
        var wrong: [String] = []
        for (query, pattern) in keptAsTyped where catalog.top(query, 1).first.map({ matches(pattern, $0) }) != true {
            wrong.append("\(query): \(catalog.top(query, 1).first ?? "nothing")")
        }
        print("Names kept as typed: \(keptAsTyped.count - wrong.count) of \(keptAsTyped.count) first")
        #expect(Double(wrong.count) <= 0.05 * Double(keptAsTyped.count), "\(wrong.joined(separator: " | "))")
        // The labels that say the Spanish name follow the plain food.
        #expect(catalog.top("frijoles negros", 8).contains { matches("(?i)frijoles negros", $0) })
        // In India curd is yogurt and a lady finger okra; elsewhere they're what they were.
        let india = FoodCatalog(usda: Catalogs.usdaURL, off: Catalogs.offURL, region: "in")
        #expect(india.top("curd", 1).first?.hasPrefix("Yogurt, plain") == true && india.top("lady finger", 1).first?.hasPrefix("Okra") == true)
        #expect(india.top("biscuits", 1) == ["Cookie"] && india.top("cold drink", 1) == ["Soft drink"])
        #expect(catalog.top("lady finger", 1).first?.hasPrefix("Cookie") == true)
    }

    @Test("a food typed with what it's put on or over is the food, then what it's on")
    func servedOnSomething() {
        for seen in [false, true] {
            var missed: [String] = []
            for (query, pattern, _) in servedOnPairs {
                let names = seen ? catalog.candidates(name: query, brand: nil).prefix(1).map(\.food.name) : catalog.top(query, 1)
                if names.first.map({ matches(pattern, $0) }) != true { missed.append("\(query): \(names.first ?? "nothing")") }
            }
            print(
                "Foods on or over another \(seen ? "as a model names them" : "typed"): \(servedOnPairs.count - missed.count) of \(servedOnPairs.count) first"
            )
            #expect(Double(missed.count) <= 0.05 * Double(servedOnPairs.count), "\(seen ? "seen" : "typed"): \(missed.joined(separator: " | "))")
        }
        let pairs = servedOnPairs.filter { !$0.second.isEmpty }
        let second = pairs.filter { pair in catalog.top(pair.typed, 2).dropFirst().first.map { matches(pair.second, $0) } == true }
        print("Foods on or over another: what it's on is second for \(second.count) of \(pairs.count)")
        #expect(Double(second.count) >= 0.95 * Double(pairs.count))
        // The words: only before what food is served on, and not "in".
        #expect(servedWith("eggs on toast") == "eggs with toast" && servedWith("chili over rice") == "chili with rice")
        #expect(servedWith("cream cheese on a bagel") == "cream cheese with a bagel")
        #expect(servedWith("corn on the cob") == nil && servedWith("eggs over easy") == nil && servedWith("on toast") == nil)
        #expect(seenName("Eggs on toast").main == "Eggs" && seenName("Jam on toast").beside == ["toast"])
        #expect(seenName("Corn on the cob").main == "Corn on the cob")
        #expect(seenName("Fruit on the bottom yogurt").main == "Fruit on the bottom yogurt")
        // A model's avocado toast is two foods, so neither is logged without a look.
        #expect(catalog.candidates(name: "Avocado toast", brand: nil).first?.named == false)
        // What's said for a food instead of its name is read whole before it's taken apart.
        #expect(catalog.candidates(name: "Hamburger with cheese", brand: nil).first?.food.name.hasPrefix("Cheeseburger") == true)
        #expect(FoodCatalog.food(in: "Beans on toast") == "baked beans")
        // And a word that stands for a food is judged as that food: roasties aren't something roasted.
        #expect(FoodCatalog.food(in: "Roasties") == "roast potatoes" && FoodCatalog.food(in: "Roast potatoes") == "Roast potatoes")
        #expect(catalog.candidates(name: "Roasties", brand: nil).first?.food.name == "Roasted potatoes")
    }

    @Test("roasted potatoes are the ones roasted in fat, and a potato with no more said the baked one")
    func roastedPotatoes() {
        #expect(catalog.top("roasted potatoes", 1) == ["Roasted potatoes"] && catalog.top("roast potatoes", 1) == ["Roasted potatoes"])
        #expect(catalog.top("potato", 1).first?.hasPrefix("Potatoes, baked") == true)
        #expect(catalog.top("potatoes", 1).first?.hasPrefix("Potatoes, baked") == true)
        #expect(catalog.top("baked potato", 1).first?.hasPrefix("Potatoes, baked") == true)
        // A way of cooking no plain food is named by is still the nearest one cooked so.
        #expect(catalog.top("roasted chicken", 1) == ["Chicken, baked, broiled, or roasted"])
        #expect(catalog.top("roasted broccoli", 1).first?.hasPrefix("Broccoli, cooked") == true)
    }

    @Test("a search just made is found again without searching, for the same foods of the person's own")
    func recentSearches() throws {
        // A catalog of its own, so nothing another test searched is kept.
        let catalog = FoodCatalog(usda: Catalogs.usdaURL, off: Catalogs.offURL, region: "us")
        let first = catalog.search("grilled chicken and brown rice")
        // Each of the foods typed together was searched, and is kept with the search as typed.
        let kept = catalog.recent.withLock { $0.map(\.asked.typed) }
        #expect(kept.contains("grilled chicken") && kept.contains("brown rice") && kept.contains("grilled chicken and brown rice"))
        #expect(catalog.search("grilled chicken and brown rice").map(\.food.id) == first.map(\.food.id))
        #expect(catalog.recent.withLock { $0.map(\.asked.typed) } == kept)
        // A food of the person's own ranks the catalog's foods, so the search is made anew.
        let rice = try #require(first.first { $0.food.name.hasPrefix("Rice, brown") })
        _ = catalog.search("brown rice", personal: [PersonalFood(food: rice.food, score: 3)])
        #expect(catalog.recent.withLock { $0.filter { $0.asked.typed == "brown rice" }.count } == 2)
        // No more than a few are kept, the newest first.
        for word in ["apple", "banana", "bread", "milk", "eggs", "rice", "tea", "salt", "oats", "corn"] { _ = catalog.search(word) }
        #expect(catalog.recent.withLock { $0.count } == RecentSearch.kept)
        #expect(catalog.recent.withLock { $0.first?.asked.typed } == "corn")
    }

    @Test("a word that only describes, typed alone or half typed, is the everyday food it starts")
    func describingAlone() {
        var first = 0
        var missed: [String] = []
        for (query, pattern) in describing {
            let name = catalog.top(query, 1).first
            if name.map({ matches(pattern, $0) }) == true { first += 1 } else { missed.append("\(query): \(name ?? "nothing")") }
        }
        print("Describing words typed alone: \(first) of \(describing.count) first")
        #expect(Double(first) >= 0.95 * Double(describing.count), "\(missed.joined(separator: " | "))")
        // Read as any search of those words is: a bell pepper is USDA's sweet pepper.
        #expect(catalog.respell("bell").text == "bell pepper" && catalog.respell("bell").also["bell"] == ["sweet"])
        #expect(catalog.respell("bell").typed == "bell")
        // The word itself, typed with nothing else: a second word says which food.
        #expect(describingName("french") == "french fries" && describingName("frenchs") == nil && aloneName("french") == nil)
        // And once more is typed it's the start of any name: Swiss Miss, romaine.
        #expect(catalog.respell("swiss m").text != "swiss cheese m")
        #expect(catalog.respell("french toast").text == "french toast")
        // A word still being typed is the one it begins, where it has a meaning alone and
        // nothing else people log starts so; and a short name begun is the name.
        #expect(aloneBegun("mezca") == "mezcal" && aloneBegun("mez") == nil && aloneBegun("mezcal") == nil)
        #expect(shortNameBegun(["mac", "and", "chees"]) == "macaroni and cheese" && shortNameBegun(["mac"]) == nil)
        #expect(catalog.respell("mac and ch").text == "macaroni and cheese")
        // In another of its endings the word it's on its way to is whole: toasted bread is toast.
        #expect(catalog.top("toas", 1) == catalog.top("toast", 1))
    }

    @Test("a food said with how it was cooked beside another is that food and the other")
    func cookedTogether() {
        for seen in [false, true] {
            var first = 0
            var missed: [String] = []
            for (query, pattern, _) in cookedPairs {
                let names = seen ? catalog.candidates(name: query, brand: nil).prefix(1).map(\.food.name) : catalog.top(query, 1)
                if names.first.map({ matches(pattern, $0) }) == true { first += 1 } else { missed.append("\(query): \(names.first ?? "nothing")") }
            }
            print("Cooked foods typed together \(seen ? "as a model names them" : "typed"): \(first) of \(cookedPairs.count) first")
            #expect(
                Double(first) >= 0.95 * Double(cookedPairs.count),
                "\(seen ? "seen" : "typed"): \(missed.joined(separator: " | "))")
        }
        let pairs = cookedPairs.filter { !$0.second.isEmpty }
        let second = pairs.filter { pair in catalog.top(pair.typed, 2).dropFirst().first.map { matches(pair.second, $0) } == true }
        print("Cooked foods typed together: the second food is second for \(second.count) of \(pairs.count)")
        #expect(Double(second.count) >= 0.95 * Double(pairs.count))
        // The way is the food's it's said of: the mixed dish of chicken and rice isn't grilled,
        // and fried rice with chicken isn't a grilled chicken breast and brown rice.
        #expect(catalog.top("grilled chicken and rice", 2).first == "Chicken, grilled")
        #expect(catalog.top("chicken and rice", 1).first == "Chicken or turkey and rice")
        #expect(catalog.top("grilled chicken breast and brown rice", 1).first?.hasPrefix("Chicken breast, grilled") == true)
        // A dish cooked that kind of way, and one that is a dish however it's cooked.
        #expect(catalog.top("fried rice and chicken", 1).first == "Rice, fried, with chicken")
        #expect(catalog.top("baked mac and cheese", 1).first == "Macaroni or noodles with cheese")
        #expect(catalog.top("grilled ham and cheese sandwich", 1).first?.hasPrefix("Ham sandwich") == true)
        #expect(catalog.top("ham and cheese sandw", 1).first?.hasPrefix("Ham sandwich") == true)
        // An everyday name no plain food answers is its foods, each as it comes in the dish;
        // the labels called so follow.
        #expect(catalog.top("fish and chips", 2) == ["Fish, fried", "Potato, french fries"])
        #expect(catalog.top("fish and chips", 4).contains { matches("(?i)^fish (&|and) chips$", $0) })
        #expect(catalog.top("homemade fish and chips", 1).first == "Fish, fried")
        #expect(catalog.top("battered fish and chips", 2).last == "Potato, french fries")
        #expect(catalog.top("chicken and waffles", 2) == ["Chicken, fried, coated", "Waffle"])
        // A model's is offered the same way, and named by neither as the whole.
        let named = catalog.candidates(name: "Fish and chips", brand: nil)
        #expect(named.first?.food.name == "Fish, fried" && named.first?.named == false)
        // Rice and beans with nothing else said are the plain ones.
        #expect(catalog.top("rice and beans", 1).first == "Beans and white rice")
    }

    @Test("two foods typed or named together are each found, unless one food is both")
    func foodsTogether() {
        for seen in [false, true] {
            var first = 0
            var missed: [String] = []
            for (query, pattern, _) in together {
                let names = seen ? catalog.candidates(name: query, brand: nil).prefix(1).map(\.food.name) : catalog.top(query, 1)
                if names.first.map({ matches(pattern, $0) }) == true { first += 1 } else { missed.append("\(query): \(names.first ?? "nothing")") }
            }
            print("Foods typed together \(seen ? "as a model names them" : "typed"): \(first) of \(together.count) first")
            #expect(
                Double(first) >= 0.95 * Double(together.count),
                "\(seen ? "seen" : "typed"): \(missed.joined(separator: " | "))")
        }
        // The second food is right after the first.
        let pairs = together.filter { !$0.second.isEmpty }
        let second = pairs.filter { pair in catalog.top(pair.typed, 2).dropFirst().first.map { matches(pair.second, $0) } == true }
        print("Foods typed together: the second food is second for \(second.count) of \(pairs.count)")
        #expect(Double(second.count) >= 0.95 * Double(pairs.count))
        #expect(catalog.top("burger and fries", 2) == ["Hamburger", "Potato, french fries"])
        #expect(catalog.top("burger & fries", 2) == catalog.top("burger and fries", 2))
        #expect(catalog.top("eggs, bacon and toast", 3).last?.hasPrefix("Bread") == true)
        // With salt, pepper is the black pepper; alone, a pepper is a bell pepper.
        #expect(catalog.top("salt and pepper", 2) == ["Salt, table", "Spices, pepper, black"])
        #expect(catalog.top("pepper", 1).first?.hasPrefix("Peppers, sweet") == true)
        #expect(catalog.top("ground pepper", 1).first == "Spices, pepper, black")
        // One food that is both stays: a dish, a brand, an everyday name, a flavour.
        #expect(catalog.top("rice and beans", 1).first?.contains("eans and") == true)
        #expect(catalog.top("mac and cheese", 1).first == "Macaroni or noodles with cheese")
        #expect(catalog.search("ben and jerrys").first?.food.brand?.hasPrefix("Ben") == true)
        #expect(catalog.top("cookies and cream", 1).first?.lowercased().hasPrefix("cookies & cream") == true)
        // Nor are words split that aren't each a plain food.
        #expect(catalog.top("salt and vinegar chips", 1).first?.lowercased().contains("vinegar") == true)
        // The dish is still the dish with a typo, said to be homemade, or half typed, and
        // by a name the catalog keeps for it; what the last word names is one dish.
        #expect(catalog.top("chiken and rice", 1).first == "Chicken or turkey and rice")
        #expect(catalog.top("homemade biscuits and gravy", 1).first == "Biscuit with gravy")
        #expect(catalog.top("mac and che", 1).first?.hasPrefix("Macaroni") == true)
        #expect(catalog.top("jack and cok", 1).first == "Whiskey and cola")
        #expect(catalog.top("ham and cheese sandwich", 1).first?.hasPrefix("Ham sandwich") == true)
        #expect(catalog.top("red beans and rice", 1).first?.contains("Rice And Red Beans") == true)
        // What follows "with" is what one food comes with.
        #expect(catalog.top("coffee with cream and sugar", 1).first?.lowercased().contains("coffee") == true)
        // A model's name for two foods: the first food leads, and none is named by the
        // whole, so the pipeline logs neither for both without a look.
        let eggs = catalog.candidates(name: "Eggs and bacon", brand: nil)
        #expect(eggs.first?.food.name.hasPrefix("Egg, whole") == true)
        #expect(eggs.prefix(6).allSatisfy { !$0.named && !$0.called })
        #expect(!eggs.contains { $0.food.name == "Egg burrito, with bacon" })
        // A dish it names is named.
        #expect(catalog.candidates(name: "Biscuits and gravy", brand: nil).first?.named == true)
    }

    @Test("plain meats, fish and cereals come first as they're eaten, typed and named as a model would")
    func plainProteins() {
        for seen in [false, true] {
            var first = 0
            var missed: [String] = []
            for (query, pattern) in proteins {
                let names = seen ? catalog.candidates(name: query, brand: nil).prefix(1).map(\.food.name) : catalog.top(query, 1)
                if names.first.map({ matches(pattern, $0) }) == true { first += 1 } else { missed.append("\(query): \(names.first ?? "nothing")") }
            }
            print("Plain meats, fish and cereals \(seen ? "as a model names them" : "typed"): \(first) of \(proteins.count) first")
            #expect(
                Double(first) >= 0.95 * Double(proteins.count),
                "\(seen ? "seen" : "typed"): \(missed.joined(separator: " | "))")
        }
        // The one that only says it's cooked, where no way of cooking is asked for, and the
        // one that says nothing of its skin, or is without it: a chicken breast before the
        // grilled one and the one with skin. Chicken alone goes on to the ways it's cooked
        // (see `Variety`), then the one without skin.
        #expect(catalog.top("chicken", 3) == ["Chicken, cooked", "Chicken, grilled", "Chicken, rotisserie"])
        #expect(catalog.top("chicken", 5).last == "Chicken, cooked, without skin")
        #expect(catalog.top("chicken breast", 2) == ["Chicken breast, cooked, without skin", "Chicken breast, cooked, with skin"])
        #expect(catalog.top("chicken thigh with skin", 1).first == "Chicken thigh, cooked, with skin")
        #expect(catalog.top("skinless chicken thigh", 1).first == "Chicken thigh, cooked, without skin")
        #expect(catalog.top("grilled chicken breast", 1).first == "Chicken breast, grilled, without skin")
        // Named by nothing but what was said, cooked, before a cut or a composite of cuts.
        #expect(catalog.top("lamb", 1).first == "Lamb, cooked")
        #expect(catalog.top("steak", 1).first == "Steak, cooked")
        // A steak by its cut, as it's ordered; and the food is cooked whichever name found it.
        #expect(catalog.top("filet mignon", 1).first == "Beef, steak, tenderloin, cooked")
        #expect(catalog.candidates(name: "New York strip", brand: nil).first?.food.name == "Beef, steak, strip, cooked")
        #expect(catalog.top("turkey bacon", 1).first == "Turkey bacon, cooked")
        // Fish of no one kind is fish, not the kind most logged.
        #expect(catalog.top("fish", 1).first == "Fish, cooked")
        #expect(catalog.top("fried fish", 1).first == "Fish, fried")
        // A label listed under a food's own word isn't whose "Sausage patty" the catalog means.
        #expect(catalog.candidates(name: "Sausage patty", brand: nil).first?.food.name == "Pork sausage, cooked")
        // Shellfish that are steamed are the cooked ones; oysters are still raw.
        #expect(catalog.top("clams", 1).first == "Clams, cooked")
        #expect(catalog.top("oysters", 1).first == "Oysters, raw")
        // The survey's plain meats are read as plain foods, its cold cuts as processed.
        #expect(catalog.search("steak").first?.food.processing == .whole)
        #expect(catalog.search("salami").first?.food.processing == .ultraProcessed)
    }

    @Test("a cut or a kind of fish typed alone is the cooked one, typed and named as a model would")
    func cutsAndFish() {
        for seen in [false, true] {
            var first = 0
            var missed: [String] = []
            for (query, pattern) in cuts {
                let names = seen ? catalog.candidates(name: query, brand: nil).prefix(1).map(\.food.name) : catalog.top(query, 1)
                if names.first.map({ matches(pattern, $0) }) == true { first += 1 } else { missed.append("\(query): \(names.first ?? "nothing")") }
            }
            print("Cuts and fish \(seen ? "as a model names them" : "typed"): \(first) of \(cuts.count) first")
            #expect(Double(first) >= 0.95 * Double(cuts.count), "\(seen ? "seen" : "typed"): \(missed.joined(separator: " | "))")
        }
        // A cut means the cooked piece once it's typed whole: half typed it's still other foods.
        #expect(catalog.top("wings", 1).first == "Chicken wing, cooked")
        #expect(catalog.top("chops", 1).first == "Pork, chop, cooked")
        #expect(catalog.top("brea", 1).first?.hasPrefix("Bread") == true)
        // Said raw, it's the raw one.
        #expect(catalog.top("raw mackerel", 1).first?.hasSuffix(", raw") == true)
        // Tenders and legs with no animal named are a chicken's.
        #expect(catalog.top("tenders", 1).first == "Chicken tenders or strips")
        #expect(catalog.top("legs", 1).first?.hasPrefix("Chicken") == true)
        // By the names they're sold by, which SR Legacy files under its own.
        #expect(catalog.top("black eyed peas", 1).first?.hasPrefix("Cowpeas, common") == true)
        #expect(catalog.top("snow crab", 1).first == "Crustaceans, crab, queen, cooked, moist heat")
        #expect(catalog.candidates(name: "Mahi mahi", brand: nil).first?.food.name == "Fish, mahimahi, cooked, dry heat")
        #expect(catalog.candidates(name: "Chicken strips", brand: nil).first?.food.name == "Chicken tenders or strips")
        // Blackened says how it was cooked, like seared.
        #expect(catalog.top("blackened salmon", 1).first?.hasPrefix("Fish, salmon") == true)
        // A plural isn't a longer name begun: tortilla strips aren't a strip steak.
        #expect(catalog.top("tortilla strips", 1).first.map { matches("(?i)tortilla strips", $0) } == true)
        #expect(catalog.top("fruits", 1).first == "Fruit")
    }

    @Test("a food by how it was cooked is the food cooked that way, or the one the catalog has, typed and named as a model would")
    func waysOfCooking() {
        for seen in [false, true] {
            var first = 0
            var missed: [String] = []
            for (query, pattern) in ways {
                let names = seen ? catalog.candidates(name: query, brand: nil).prefix(1).map(\.food.name) : catalog.top(query, 1)
                if names.first.map({ matches(pattern, $0) }) == true { first += 1 } else { missed.append("\(query): \(names.first ?? "nothing")") }
            }
            print("Ways of cooking \(seen ? "as a model names them" : "typed"): \(first) of \(ways.count) first")
            #expect(Double(first) >= 0.95 * Double(ways.count), "\(seen ? "seen" : "typed"): \(missed.joined(separator: " | "))")
        }
        // A way said in two words is the catalogs' one, and where it was cooked isn't the food.
        #expect(catalog.plainlyCooked("pan seared salmon") == "seared salmon")
        #expect(catalog.plainlyCooked("slow cooker chicken") == "chicken")
        #expect(catalog.plainlyCooked("sunny side up eggs") == "fried eggs")
        #expect(catalog.plainlyCooked("oven baked chicken with pan fried potatoes") == "baked chicken with fried potatoes")
        // Only beside a food, and not a word that is only like one.
        #expect(catalog.plainlyCooked("pan seared") == nil)
        #expect(catalog.plainlyCooked("pancakes") == nil && catalog.plainlyCooked("oven") == nil)
        #expect(catalog.top("air fried chicken", 1).first == "Chicken, baked, broiled, or roasted")
        // A brand's label that says it the way it was typed is still the one found.
        #expect(catalog.top("tyson air fried chicken", 1).first.map { matches("(?i)air fried", $0) } == true)
        #expect(catalog.top("aldi pan seared steak", 1).first.map { matches("(?i)pan-seared", $0) } == true)
        // And with no brand typed it comes right after the first plain foods.
        #expect(catalog.top("pan seared steak", 6).contains { matches("(?i)pan-seared steak", $0) })
        #expect(catalog.top("air fried chicken", 6).contains { matches("(?i)air fried chicken", $0) })
        // Smoked is a way where no plain food is named so.
        #expect(catalog.top("smoked brisket", 1).first == "Beef, brisket, cooked")
        #expect(catalog.top("smoked salmon", 1).first == "Fish, salmon, smoked")
        // A food the catalog has no entry cooked that way for is the uncooked one there is:
        // not a cracker flavoured like it, and not seaweed, which roasting dries.
        #expect(catalog.top("roasted garlic", 1).first == "Garlic, raw")
        #expect(catalog.top("smoked gouda", 1).first == "Cheese, gouda")
        #expect(catalog.top("grilled cheese", 1).first == "Grilled cheese sandwich")
        #expect(catalog.top("grilled chee", 1).first?.hasPrefix("Grilled cheese sandwich") == true)
        #expect(catalog.top("roasted seaweed", 1).first.map { matches("(?i)roasted seaweed", $0) } == true)
        #expect(catalog.top("fried banana", 1).first != nil)
        // The name that is exactly what was said, whichever of a food's other names comes first.
        let stirFry = catalog.candidates(name: "Stir-fried chicken", brand: nil).first
        #expect(stirFry?.food.name == "Chicken or turkey and vegetables, with soy-based sauce" && stirFry?.called == true)
    }

    @Test("a product is first before its name is typed out")
    func productsLetterByLetter() {
        // Every third product, typed a letter at a time: the share of its letters it takes to come first.
        var shares: [Double] = []
        for (query, pattern) in products.enumerated().filter({ $0.offset % 3 == 0 }).map(\.element) {
            let letters = Array(query)
            let needed = (2...letters.count).first { count in
                letters[count - 1] != " " && catalog.names(String(letters[..<count]), 1).first.map { matches(pattern, $0) } == true
            }
            shares.append(Double(needed ?? letters.count) / Double(letters.count))
        }
        let share = shares.reduce(0, +) / Double(shares.count)
        print(String(format: "Products typed a letter at a time: first after %.0f%% of their letters", 100 * share))
        // It was 60% while a brand was only read once typed whole.
        #expect(share <= 0.60)
    }

    @Test("pantry foods, dishes and forms come first typed and named as a model would")
    func pantryBasket() {
        for seen in [false, true] {
            var first = 0
            var missed: [String] = []
            for (query, pattern) in pantry {
                let names = seen ? catalog.candidates(name: query, brand: nil).prefix(3).map(\.food.name) : catalog.top(query)
                if names.first.map({ matches(pattern, $0) }) == true { first += 1 } else { missed.append("\(query): \(names.first ?? "nothing")") }
            }
            print("Pantry foods \(seen ? "as a model names them" : "typed"): \(first) of \(pantry.count) first")
            #expect(Double(first) >= 0.95 * Double(pantry.count), "\(seen ? "seen" : "typed"): \(missed.joined(separator: " | "))")
        }
    }
}
