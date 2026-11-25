import SystemCore
import Testing

@testable import FoodDatabase

/// Everyday foods as they're typed with no brand, a word or two, each with a pattern for the plain
/// food that should come first: the cooked chicken, the whole milk, the raw apple, and the food
/// itself where USDA files it under another word ("Pork, cured, bacon", "Salad dressing,
/// mayonnaise", "Frankfurter").
let staples: [(String, String)] = [
    // Meat, fish and eggs.
    ("chicken", "^Chicken, (broilers or fryers|roasting), .*cooked, roasted"),
    ("chicken breast", "^Chicken, broilers or fryers, breast, .*cooked, roasted"),
    ("chicken thigh", "^Chicken, broilers or fryers, thigh, .*cooked"),
    ("chicken wings", "^Chicken, broilers or fryers, wing, .*cooked"),
    ("ground beef", "^Beef, ground, .*cooked"),
    ("steak", "^Beef, .*steak.*cooked"),
    ("ribeye", "^Beef, rib ?eye"),
    ("sirloin", "^Beef, .*sirloin"),
    ("pork chop", "^Pork, fresh, .*chops.*cooked"),
    ("bacon", "^Pork, cured, bacon, .*cooked"),
    ("ham", "^Ham, "),
    ("sausage", "^Sausage, "),
    ("hot dog", "^Frankfurter, (beef|meat|pork)"),
    ("turkey", "^Turkey, .*cooked, roasted"),
    ("ground turkey", "^Turkey, [Gg]round, .*cooked"),
    ("turkey breast", "^Turkey, .*breast, .*(cooked|roasted)"),
    ("salmon", "^Fish, salmon, .*cooked"),
    ("tuna", "^Fish, tuna, "),
    ("shrimp", "^Crustaceans, shrimp, .*cooked"),
    ("tilapia", "^Fish, tilapia, cooked"),
    ("cod", "^Fish, cod, .*cooked"),
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
    ("almond milk", "^Beverages, almond milk, (unsweetened|sweetened)"),
    ("soy milk", "^Soymilk, original"),
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
    ("granola", "^Cereals ready-to-eat, granola"),
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
    ("chips", "^Snacks, potato chips, plain"),
    ("potato chips", "^Snacks, potato chips, plain, salted"),
    ("tortilla chips", "^(Snacks, )?[Tt]ortilla chips"),
    ("popcorn", "^Snacks, popcorn, (air-popped|oil-popped|home-prepared)"),
    ("pretzels", "^(Snacks, pretzels|Pretzels)"),
    ("cookie", "^Cookies?, |^Cookie$"),
    ("chocolate", "^(Chocolate|Candies, milk chocolate)"),
    ("dark chocolate", "^Chocolate, dark"),
    ("brownie", "^Cookies, brownies|^Cookie, brownie$"),
    ("donut", "^Doughnuts|^Doughnut$"),
    ("muffin", "^Muffins, (blueberry|plain)"),
    ("granola bar", "granola bars?"),
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
    ("ribs", "^Pork, fresh, .*ribs.*cooked"),
    ("cereal", "^Cereals ready-to-eat"),
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
    ("tuna", "^Fish, tuna, (light|white), canned"),
    ("canned tuna", "^Fish, tuna, (light|white), canned"),
    ("anchovies", "^Fish, anchovy, european, canned"),
    ("sourdough bread", "^Bread, french or vienna"),
    ("cornbread", "^Bread, cornbread, (prepared|dry mix, prepared)"),
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
    ("turkey bacon", "^Bacon, turkey"),
    ("pulled pork", "^Pulled pork"),
    ("pork tenderloin", "^Pork, fresh, loin, tenderloin, .*cooked"),
    ("tuna salad", "^Fish, tuna salad|^Tuna salad$"),
    ("crab", "^Crustaceans, crab, .*cooked"),
    ("lobster", "^Crustaceans, lobster, .*cooked"),
    ("2% milk", "^Milk, reduced fat, fluid, 2% milkfat"),
    ("chocolate milk", "^Milk, chocolate"),
    ("provolone", "^Cheese, provolone"),
    ("goat cheese", "^Cheese, goat"),
    ("ricotta", "^Cheese, ricotta"),
    ("pancakes", "^Pancakes, plain|^Pancakes$"),
    ("waffles", "^Waffles, plain|^Waffle$"),
    ("french toast", "^French toast"),
    ("naan", "^Bread, naan"),
    ("biscuit", "^Biscuits, plain"),
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
    ("baked salmon", "^Fish, salmon, .*cooked, dry heat"),
    ("grilled salmon", "^Fish, salmon, .*cooked, dry heat"),
    ("roasted salmon", "^Fish, salmon, .*cooked, dry heat"),
    ("salmon fillet", "^Fish, salmon, .*cooked"),
    ("grilled salmon fillet", "^Fish, salmon, .*cooked, dry heat"),
    ("poached salmon", "^Fish, salmon, .*cooked"),
    ("baked cod", "^Fish, cod, .*cooked"),
    ("baked tilapia", "^Fish, tilapia, cooked"),
    ("grilled tilapia", "^Fish, tilapia, cooked"),
    ("cod fillet", "^Fish, cod, .*cooked"),
    ("grilled shrimp", "^Crustaceans, shrimp, (mixed species, )?cooked(?!, breaded)"),
    ("steamed shrimp", "^Crustaceans, shrimp, (mixed species, )?cooked(?!, breaded)"),
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
    ("roasted potatoes", "^Potatoes, (roasted|baked)"),
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
    ("grilled chicken breast", "^Chicken, .*breast.*grilled"),
    ("baked chicken breast", "^Chicken.*breast.*(roasted|baked)"),
    ("roasted chicken breast", "^Chicken, .*breast.*roasted"),
    ("boiled chicken breast", "^Chicken, .*breast.*(stewed|cooked)"),
    ("grilled chicken thigh", "^Chicken, .*thigh.*(roasted|grilled|cooked)"),
    ("baked chicken thigh", "^Chicken, .*thigh, meat.*roasted"),
    ("skinless chicken thigh", "^Chicken, .*thigh, meat only"),
    ("boneless skinless chicken thigh", "^Chicken, .*thigh, meat only"),
    ("boneless skinless chicken breast", "^Chicken, .*breast.*(skinless|meat only)"),
    ("chicken cutlet", "^Chicken, "),
    ("grilled pork chop", "^Pork, .*chops.*(broiled|grilled)"),
    ("baked pork chop", "^Pork, .*chops.*(broiled|roasted)"),
    ("grilled pork tenderloin", "^Pork, .*tenderloin.*(broiled|roasted)"),
    ("roasted turkey breast", "^Turkey, .*breast.*roasted"),
    ("grilled steak", "^Beef, .*steak.*(grilled|broiled)"),
    ("grilled tofu", "^Tofu, (raw|firm|fried|extra firm)"),
    ("baked tofu", "(?i)tofu"),
    ("chicken pieces", "(?i)chicken"),
    // How lean, how fat, how salted, how smooth.
    ("lean ground beef", "^Beef, ground, 9[0-7]% lean.*cooked"),
    ("extra lean ground beef", "^Beef, ground, 9[5-7]% lean.*cooked"),
    ("lean ground turkey", "^Turkey, ground, 93% lean"),
    ("fat free milk", "^Milk, nonfat"),
    ("fat free yogurt", "^Yogurt, .*(nonfat|fat free)"),
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
    ("Grilled chicken breast (skinless)", "^Chicken, .*breast.*grilled"),
    ("Grilled chicken breast, sliced", "^Chicken, .*breast.*grilled"),
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
    ("Hamburger patty", "^Beef, ground, .*patty, cooked"),
    ("Beef burger patty (grilled)", "^Beef, ground, .*patty, cooked"),
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
    ("Chicken thigh, roasted, with skin", "^Chicken, .*thigh, meat and skin, cooked, roasted"),
    ("Chicken wings (buffalo)", "^Chicken, .*wing.*cooked|^Chicken .wings. with hot sauce"),
    ("Ground beef, cooked", "^Beef, ground, .*cooked"),
    ("Ground turkey (93% lean)", "^Turkey, ground, 93% lean"),
    ("Pan-seared salmon fillet", "^Fish, salmon, .*cooked, dry heat"),
    ("Salmon, baked", "^Fish, salmon, .*cooked, dry heat"),
    ("Tuna steak, seared", "^Fish, tuna, .*fresh.*cooked"),
    ("Shrimp, grilled", "^Crustaceans, shrimp, (mixed species, )?cooked(?!, breaded)"),
    ("Bacon strips (2)", "^Pork, cured, bacon, .*cooked"),
    ("Sausage patty", "^Pork sausage, .*cooked"),
    ("Pork chop, grilled", "^Pork, fresh, .*chops.*cooked"),
    ("Sirloin steak, grilled", "^Beef, .*sirloin.*cooked"),
    ("Baked potato with sour cream", "^Potatoes, baked"),
    ("Mashed potatoes with gravy", "^Potato(es)?, mashed.*gravy"),
    ("Roasted potatoes", "^Potatoes, (baked|roasted)"),
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
    ("Cereal with milk", "^Cereals ready-to-eat"),
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
    ("diet coke", "(?i)diet coke|diet cola"), ("sprite", "(?i)\\[sprite"), ("dr pepper", "(?i)dr.? pepper"), ("mountain dew", "(?i)mountain dew"),
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
    ("root beer", "^Beverages, carbonated, root beer"), ("almond milk", "^Beverages, almond milk"),
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
    ("chocolate chips", "^Candies, semisweet chocolate"), ("yeast", "^Leavening agents, yeast"),
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
    ("ravioli", "^Ravioli"), ("tortellini", "^Tortellini"), ("bratwurst", "^Bratwurst"), ("chorizo", "^Sausage, pork, chorizo"),
    ("pastrami", "^Pastrami, beef|^Beef, cured, pastrami"), ("corned beef", "^Beef, cured, corned beef"),
    ("liver", "^Beef, variety meats and by-products, liver"), ("chicken liver", "^Chicken, liver"), ("lamb", "^Lamb"),
    ("duck", "^Duck, domesticated"), ("venison", "^Game meat, deer"), ("bison", "^Game meat, bison"), ("anchovies", "^Fish, anchovy"),
    ("mackerel", "^Fish, mackerel, Atlantic"), ("trout", "^Fish, trout"), ("halibut", "^Fish, halibut"), ("mahi mahi", "^Fish, mahimahi"),
    ("swordfish", "^Fish, swordfish"), ("catfish", "^Fish, catfish"), ("clams", "^Mollusks, clam"), ("mussels", "^Mollusks, mussel"),
    ("oysters", "^Mollusks, oyster"), ("calamari", "^Mollusks, squid"), ("octopus", "^Mollusks, octopus"), ("crawfish", "^Crustaceans, crayfish"),
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
    ("rice and beans", "(?i)rice (and|with) beans|beans (and|with) rice"),
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
    ("fish sticks", "(?i)fish sticks?"), ("crab cake", "(?i)crab cake|^Crab, cake$"), ("shrimp scampi", "(?i)scampi|^Shrimp in garlic sauce"),
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
    ("fresh potatoes", "^Potatoes, .*raw"), ("fresh lemon juice", "^Lemon juice, raw"), ("fresh lime juice", "^Lime juice, raw"),
    ("fresh orange juice", "^Orange juice, raw"), ("fresh squeezed orange juice", "(?i)orange juice"), ("fresh salmon", "^Fish, salmon, .*raw"),
    ("fresh salmon fillet", "^Fish, salmon, .*raw"), ("fresh tuna", "^Fish, tuna, fresh"), ("fresh cod", "^Fish, cod, Atlantic, raw"),
    ("fresh shrimp", "^Crustaceans, shrimp, raw"), ("fresh scallops", "^Mollusks, scallop, .*raw"), ("fresh oysters", "^Mollusks, oyster, .*raw"),
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
    ("cooked chicken", "^Chicken, broilers or fryers, meat only, cooked, roasted"),
    ("cooked chicken breast", "^Chicken, broilers or fryers, breast, meat only, cooked, roasted"),
    ("cooked chicken thigh", "^Chicken, broilers or fryers, thigh, meat only, cooked, roasted"),
    ("cooked ground chicken", "^Chicken, ground, .*cooked"), ("cooked chicken wings", "^Chicken, .*wing.*cooked"),
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
    ("cooked beef", "^Beef, .*cooked"), ("cooked steak", "^Beef, .*steak.*cooked"), ("cooked pork", "^Pork, fresh, (composite|loin).*cooked"),
    ("cooked pork chop", "^Pork, fresh, loin.*chops.*cooked"), ("cooked pork tenderloin", "^Pork, fresh, loin, tenderloin.*cooked"),
    ("cooked ground pork", "^Pork, fresh, ground, cooked"), ("cooked bacon", "^Pork, cured, bacon, cooked"),
    ("cooked ham", "^(Ham|Pork, cured, ham)"), ("cooked sausage", "^(Sausage|Pork sausage).*cooked"), ("cooked lamb", "^Lamb, .*cooked"),
    ("cooked veal", "^Veal, .*cooked"), ("cooked turkey", "^Turkey, whole, meat only, cooked"),
    ("cooked turkey breast", "^Turkey, whole, breast, meat only, cooked"), ("cooked ground turkey", "^Turkey, [Gg]round, cooked"),
    ("cooked duck", "^Duck, .*cooked"), ("cooked egg", "^Egg, whole, cooked"), ("cooked eggs", "^Egg, whole, cooked"),
    ("cooked salmon", "^Fish, salmon, .*cooked"), ("cooked shrimp", "^Crustaceans, shrimp, cooked"), ("cooked tilapia", "^Fish, tilapia, cooked"),
    ("cooked cod", "^Fish, cod, (Pacific|Atlantic), cooked"), ("cooked tuna", "^Fish, tuna, .*cooked"), ("cooked trout", "^Fish, trout, .*cooked"),
    ("cooked halibut", "^Fish, halibut, .*cooked"), ("cooked catfish", "^Fish, catfish, .*cooked"), ("cooked crab", "^Crustaceans, crab, .*cooked"),
    ("cooked lobster", "^Crustaceans, lobster, northern, cooked"), ("cooked scallops", "^Mollusks, scallop.*cooked"), ("cooked tofu", "^Tofu"),
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
]

/// Breakfast, snacks, wraps and what's drunk from a can, as they're logged through a day: each
/// with a pattern for the plain food that should come first ("oatmeal with milk" FNDDS's oatmeal
/// made with milk, "pretzels" the hard ones, "shredded chicken" cooked chicken, "sparkling
/// water" its plain carbonated water).
let snacks: [(String, String)] = [
    ("oatmeal with milk", "^Oatmeal, regular or quick, made with milk$"), ("protein shake", "^Nutritional drink or shake, high protein"),
    ("yogurt parfait", "^Yogurt parfait"), ("egg and cheese sandwich", "^Egg sandwich on .*with cheese"),
    ("blueberry pancakes", "^Pancakes, blueberry"), ("turkey bacon", "^Bacon, turkey"), ("turkey sausage", "^Sausage, turkey"),
    ("sausage patty", "^Pork sausage, link/patty"), ("hash brown patty", "hash browns, round pieces or patty"),
    ("english muffin", "^Muffins, English"), ("granola", "granola"), ("granola bar", "^Snacks, granola bars"), ("trail mix", "^Snacks, trail mix"),
    ("beef jerky", "beef jerky"), ("rice cakes", "^Snacks, rice cakes"), ("pretzels", "^Snacks, pretzels, hard, plain"),
    ("popcorn", "^Snacks, popcorn"), ("microwave popcorn", "^Popcorn, microwave"), ("crackers", "^Crackers"), ("pita chips", "^Snacks, pita chips"),
    ("tortilla chips", "^Tortilla chips|^Snacks, tortilla chips"), ("applesauce", "^Applesauce"), ("fruit salad", "^Fruit salad"),
    ("mixed nuts", "^Nuts, mixed nuts"), ("dried mango", "^Mango, dried"), ("banana chips", "^Snacks, banana chips"),
    ("dark chocolate", "^Chocolate, dark"), ("turkey wrap", "^Turkey sandwich wrap"), ("tuna wrap", "^Tuna salad sandwich wrap"),
    ("burrito bowl", "^Burrito bowl"), ("spaghetti squash", "^Squash, winter, spaghetti"), ("sweet potato", "^Sweet potato, cooked"),
    ("mixed vegetables", "^Vegetables, mixed"), ("side salad", "^Lettuce, salad with assorted vegetables"), ("rotisserie chicken", "rotisserie"),
    ("grilled chicken", "^Chicken, .*grilled"), ("shredded chicken", "^Chicken, broilers or fryers, .*cooked"),
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
        #expect(nameWords("Watermelon cubes") == ["watermelon"])
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
        #expect(catalog.top("meat", 1).first.map { matches("^Beef, ground", $0) } == true)
        #expect(catalog.top("protein", 1).first.map { matches("(?i)protein powder", $0) } == true)
        #expect(catalog.top("salad", 1).first.map { matches("^Lettuce, salad", $0) } == true)
        // A few letters aren't the start of a brand that isn't sold here.
        #expect(catalog.top("dal", 1).first.map { matches("(?i)^dal\\b", $0) } == true)
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
        #expect(catalog.top("chiken brest", 1).first.map { matches("^Chicken, .*breast", $0) } == true)
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
        #expect(catalog.top("liver", 1).first?.hasPrefix("Beef, variety meats and by-products, liver") == true)
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
            catalog.candidates(name: "Shredded chicken", brand: nil).first?.food.name == "Chicken, broilers or fryers, meat only, cooked, roasted")
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
        #expect(catalog.top("pork", 1).first.map { matches("^Pork, fresh, composite of trimmed retail cuts", $0) } == true)
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
            // The last eight are packaged foods' names, which the bundled catalog alone hasn't.
            #expect(
                Double(first) >= (Catalogs.hasOFF ? 0.95 : 0.85) * Double(world.count),
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
        // The person's own food is found by the word meant.
        let own = Food(id: "custom:broccoli", name: "Roasted Broccoli", basis: .g, nutrients: .zero, source: .custom)
        #expect(catalog.search("brocolli", personal: [PersonalFood(food: own, score: 1)]).first?.food.id == own.id)
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
