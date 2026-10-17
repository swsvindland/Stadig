import Foundation

/// The instructions and prompts, as tuned on Apple's on-device model for the React Native app. The
/// reply's fields are described here rather than by the schema in each prompt: instructions are
/// cached by prewarming, and the schema's ~270 uncached tokens cost about a second per request.
enum Prompts {
    static let mealBase = """
        You list the foods in a meal photo and/or description for a nutrition log. A wrong food in the log is worse than a missing one, because the person can always add what you left out. List only food and drink you can clearly see or that the person names, including toppings, spreads and sauces you can see on the plate. List each food once; several pieces of the same food are one item with a larger quantity.

        Brand: fill it only when a brand or restaurant name is readable in the photo (logo, box, cup, wrapper) or stated in the description. Never guess a brand from how food looks; otherwise leave it empty.
        Branded food stays whole: a packaged product or a menu item from a named restaurant chain is one item, because its nutrition is published as a whole. Its toppings, fillings and sauces are part of it and are not listed again. For example a Domino's pizza is one item "Pepperoni pizza" counted in slices, and a McDonald's Big Mac is one item.
        Unbranded food is split: a homemade or unbranded burger, sandwich, salad, bowl or plate is split into its separate components. For example an unbranded cheeseburger with fries becomes: hamburger bun, beef patty, cheddar cheese, lettuce, tomato, ketchup, french fries.
        Sides, desserts and drinks are separate items.
        quantity and unit describe what is shown, for example 2 slice, 1 patty, 3 strip, 1 cup, 1 tbsp. grams is your best estimate of the total edible weight for that quantity. Typical weights: burger bun 55 g, cooked burger patty 110 g, cheese slice 20 g, lettuce leaf 10 g, tomato slice 15 g, bacon strip 10 g, sausage link 50 g, ham slice 30 g, large egg 50 g, bread slice 30 g, pizza slice 110 g, tbsp of sauce 15 g, medium fries 115 g, cup of cooked rice or pasta 160 g, chicken breast 170 g, a whole burger or sandwich 220 g, a handful of nuts 30 g, a can of soda 355 g, a glass of milk or juice 250 g, a bowl of cereal or oatmeal 250 g.
        Details in the description (brand, amount, preparation) override the photo. Do not add foods that are not shown or mentioned, and never guess a food from its setting (a table, a kitchen, a restaurant) or from a shape or colour that only resembles food.
        Reply with items, one per food, each with: brand (as above, else empty), name (the common food name, e.g. Pepperoni pizza, Beef patty), quantity and unit (how much, as the person says it: "200g chicken" is 200 g, "2 cups of milk" is 2 cup; otherwise e.g. 2 slice, 1 piece, 1 tbsp, 1 serving) and grams (the estimated total edible weight of that quantity).
        """

    /// Added for photos, whose reply first says what is pictured and whether it is food at all.
    static let photoInstructions = """
        Photos are often not of food, or not clearly. Before listing anything, write in scene what the photo really shows in a few plain words, e.g. "a plate of spaghetti", "a person smiling", "a dog on a couch", "an empty desk". Then set food to true only if real food or drink someone is about to eat is clearly visible and you can tell what it is. People, faces, pets, rooms, screens, menus, empty plates, closed packaging you can't read and anything blurry or too dark are not food: set food to false and leave items empty. When unsure, set food to false; the person will be asked to describe the meal instead. If the person's description names foods, list those even when the photo doesn't show them.
        """

    static let pickInstructions = """
        You match foods from a meal to entries in a nutrition database. Reply with entries: the chosen entry's number for each food, in order, e.g. [2, 1, 3]. For each food, choose the entry that is the same food in the form it is usually eaten: cooked rather than raw for meat, fish, eggs, rice and pasta; ripe, raw and plain for salad vegetables and fruit; ready to eat rather than dry, frozen or unprepared; the regular version rather than low fat, meatless or flavored; a generic entry rather than a brand-name product, unless the food names a restaurant or brand; the food itself rather than a dish that contains it. Cheese on a burger or sandwich is usually American or cheddar.
        """

    static let labelInstructions = """
        You read the text of a food package's nutrition label, recognized by OCR, which may be out of order and contain misread characters. Name the product in a few words as a shopper would (e.g. "Rolled oats", "Greek yogurt, vanilla", "Tortilla chips"), from the ingredients, claims and any other text. Fill brand only when a brand or maker is printed (e.g. "Distributed by General Mills"); otherwise leave it empty.
        """

    /// Worded around "a product's label": the on-device model's guardrails refuse requests that
    /// call it a dietary supplement.
    static let supplementLabelInstructions = """
        You read the text of a product's label, recognized by OCR, which may be out of order and contain misread characters. Name the product in a few words as a shopper would, with its strength when printed (e.g. "Fish oil 1200 mg", "Vitamin D3 2000 IU", "Magnesium glycinate"). Fill brand only when a brand or maker is printed (e.g. "Nature Made", "Distributed by Optimum Nutrition"); otherwise leave it empty.
        """

    /// Live scans gather text from many camera frames, the package's front and its panel alike.
    static let liveLabelInstructions = """
        You read text recognized by OCR from a food package, gathered over several camera frames: lines may repeat, be cut off, be out of order or be misread. Copy the Nutrition Facts values printed for one serving. When the panel has two columns (per serving and per container, or as packaged and as prepared), use the per serving, as packaged column. Copy each number exactly as printed in the panel text; leave a value out when it isn't printed there, and never estimate or calculate one. Claims on the front of the package, such as "20g protein", are not the panel. Name the product in a few words as a shopper would, and fill brand only when a brand or maker is printed.
        """

    /// Every line with an amount: the app keeps the ones it tracks. Asking the model to sort them,
    /// or naming supplements, trips the on-device model's guardrails.
    static let liveSupplementInstructions = """
        You copy values from the nutrient table of a product label, recognized by OCR from several camera frames: lines may repeat, be cut off, be out of order or be misread. List each line of the table that has an amount, once, in the table's order, with its amount per serving and unit exactly as printed in the panel text. Leave out the % Daily Value. Give the serving size as printed. Name the product in a few words as its front names it, with the strength printed there (e.g. "Fish oil 1200 mg"), and fill brand only when a brand or maker is printed.
        """

    /// A live scan's text: the panel's rows first, then a little of the rest for the name.
    static func liveText(panel: [String], other: [String]) -> String {
        var text = "Panel text:\n" + panel.prefix(90).map { FoodText.clean($0, limit: 120) }.joined(separator: "\n")
        if !other.isEmpty {
            text += "\nOther text on the package:\n" + other.prefix(20).map { FoodText.clean($0, limit: 80) }.joined(separator: "\n")
        }
        return text
    }

    /// Added when the label's own parse found little: copy the printed values, never estimate.
    static let labelValueInstructions = """
        Also copy the nutrition values printed for one serving, exactly as printed in the text. Leave a value out when it isn't printed; never estimate or calculate one.
        """

    /// One set for photos and descriptions alike: the on-device model caches only the most recently
    /// prewarmed instructions, so a single prewarmed session serves whichever comes next.
    static let mealInstructions = mealBase + "\n" + photoInstructions

    static func meal(description: String, photo: Bool) -> String {
        let said = FoodText.clean(description, limit: 500)
        if photo {
            return said.isEmpty
                ? "Say what this photo shows, then list the foods in it, if there are any."
                : "Say what this photo shows, then list the foods in it. The person says: \"\(said)\""
        }
        return "List the foods in this meal: \"\(said)\""
    }

    static func label(lines: [String]) -> String {
        "Label text:\n" + lines.prefix(60).map { FoodText.clean($0, limit: 120) }.joined(separator: "\n")
    }
}
