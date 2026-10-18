import Foundation

/// Pictures for picture matching: an SF Symbol for each concrete meaning that has a clear one.
/// Words are matched by their English meaning, so the table serves every language.
public enum Pictures {
    /// Meaning (without "to" or an article) to symbol. Synonyms share a symbol; no symbol stands for
    /// two different things, so no two answers look alike.
    public static let symbols: [String: String] = [
        "dog": "dog.fill", "cat": "cat.fill", "bird": "bird.fill", "fish": "fish.fill", "rabbit": "hare.fill",
        "turtle": "tortoise.fill", "tortoise": "tortoise.fill", "ant": "ant.fill", "ladybird": "ladybug.fill", "ladybug": "ladybug.fill",
        "tree": "tree.fill", "leaf": "leaf.fill", "sun": "sun.max.fill", "moon": "moon.fill", "star": "star.fill",
        "cloud": "cloud.fill", "rain": "cloud.rain.fill", "snow": "snowflake", "wind": "wind", "fire": "flame.fill",
        "water": "drop.fill", "mountain": "mountain.2.fill", "sea": "water.waves", "thunder": "cloud.bolt.fill", "rainbow": "rainbow",
        "house": "house.fill", "car": "car.fill", "bus": "bus.fill", "train": "train.side.front.car", "bicycle": "bicycle",
        "bike": "bicycle", "aeroplane": "airplane", "airplane": "airplane", "plane": "airplane", "boat": "sailboat.fill",
        "ship": "ferry.fill", "book": "book.fill", "newspaper": "newspaper.fill", "pencil": "pencil", "scissors": "scissors",
        "key": "key.fill", "clock": "clock.fill", "telephone": "phone.fill", "phone": "phone.fill", "television": "tv.fill",
        "camera": "camera.fill", "computer": "desktopcomputer", "glasses": "eyeglasses", "shirt": "tshirt.fill", "t-shirt": "tshirt.fill",
        "bag": "bag.fill", "umbrella": "umbrella.fill", "gift": "gift.fill", "present": "gift.fill", "money": "banknote.fill",
        "coffee": "cup.and.saucer.fill", "cup": "mug.fill", "mug": "mug.fill", "wine": "wineglass.fill", "cake": "birthday.cake.fill",
        "carrot": "carrot.fill", "heart": "heart.fill", "eye": "eye.fill", "ear": "ear.fill", "hand": "hand.raised.fill",
        "mouth": "mouth.fill", "nose": "nose.fill", "brain": "brain.head.profile", "person": "person.fill",
        "family": "figure.2.and.child.holdinghands", "door": "door.left.hand.closed", "bed": "bed.double.fill", "chair": "chair.fill",
        "sofa": "sofa.fill", "lamp": "lamp.desk.fill", "light bulb": "lightbulb.fill", "letter": "envelope.fill",
        "envelope": "envelope.fill", "map": "map.fill", "flag": "flag.fill", "music": "music.note", "guitar": "guitars.fill",
        "piano": "pianokeys", "football": "soccerball", "soccer": "soccerball", "tennis": "tennisball.fill", "trophy": "trophy.fill",
        "medal": "medal.fill", "crown": "crown.fill", "medicine": "pills.fill", "school": "graduationcap.fill",
        "briefcase": "briefcase.fill", "shop": "storefront.fill", "store": "storefront.fill", "building": "building.2.fill",
        "world": "globe", "globe": "globe", "ticket": "ticket.fill", "calendar": "calendar", "bell": "bell.fill", "lock": "lock.fill",
        "box": "shippingbox.fill", "brush": "paintbrush.fill", "hammer": "hammer.fill", "tent": "tent.fill", "shower": "shower.fill",
        "bath": "bathtub.fill", "toilet": "toilet.fill", "stairs": "stairs", "beach": "beach.umbrella.fill", "road": "road.lanes",
        "walk": "figure.walk", "run": "figure.run", "swim": "figure.pool.swim", "dance": "figure.dance", "eat": "fork.knife",
        "sleep": "zzz", "sing": "music.mic", "buy": "cart.fill", "pay": "creditcard.fill", "doctor": "stethoscope",
        "hot": "thermometer.sun.fill", "cold": "thermometer.snowflake", "photo": "photo.fill", "photograph": "photo.fill",
        "film": "film.fill", "movie": "film.fill", "game": "gamecontroller.fill", "night": "moon.stars.fill", "sunrise": "sunrise.fill",
        "sunset": "sunset.fill", "battery": "battery.100", "lightning": "bolt.fill", "baby": "stroller.fill", "teddy bear": "teddybear.fill",
        "paw": "pawprint.fill", "basket": "basket.fill", "hospital": "cross.case.fill",
        "shoe": "shoe.fill", "shoes": "shoe.fill", "headphones": "headphones", "microphone": "mic.fill",
    ]

    /// The meaning a word's picture is looked up by: its first sense, without "to" or an article.
    static func heads(_ meaning: String) -> [String] {
        meaning.lowercased().split(whereSeparator: { $0 == ";" || $0 == "," }).map { part in
            var head = part.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            for article in ["to ", "a ", "an ", "the "] where head.hasPrefix(article) { head = String(head.dropFirst(article.count)) }
            return head
        }
    }

    public static func symbol(for word: Word) -> String? {
        heads(word.meaning).lazy.compactMap { symbols[$0] }.first
    }
}
