import Foundation

/// How processed a food is, by the NOVA groups (Monteiro et al.). Eating mostly ultra-processed
/// food leads people to eat more and gain fat at the same macros (Hall et al., 2019), so the share
/// of calories from each group says something the macros can't.
public enum Processing: Int, Codable, Sendable, CaseIterable, Comparable {
    /// Whole foods, raw or cooked: fruit, vegetables, meat, fish, eggs, milk, plain grains and beans.
    case whole = 1
    /// Kitchen ingredients: oils, butter, sugar, honey, salt.
    case culinary = 2
    /// Whole foods with salt, sugar or oil added: cheese, canned vegetables, cured meat, fresh bread.
    case processed = 3
    /// Industrial formulations: soft drinks, packaged snacks and sweets, most cereals and ready
    /// meals, protein bars and powders.
    case ultraProcessed = 4

    public var label: String {
        switch self {
        case .whole: "Whole"
        case .culinary: "Kitchen staple"
        case .processed: "Processed"
        case .ultraProcessed: "Ultra-processed"
        }
    }

    public static func < (a: Processing, b: Processing) -> Bool { a.rawValue < b.rawValue }
}
