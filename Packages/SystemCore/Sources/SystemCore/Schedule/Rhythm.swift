import Foundation

/// When someone usually eats, and what they've eaten today, by part of the day. Published by Stadig
/// Macro, so a day's meals can sit where they usually do. Meals are the one thing the apps track that
/// has no plan behind it: these are habits, not targets.
public struct MealRhythm: Hashable, Codable, Sendable {
    public static let schemaVersion = 1

    /// A part for each usual meal, earliest first; a part can come twice.
    public var usual: [DayPart]
    public var day: Day
    /// A part for each meal eaten on `day`.
    public var eaten: [DayPart]
    public var updated: Date

    public init(usual: [DayPart], day: Day, eaten: [DayPart], updated: Date = Date()) {
        self.usual = usual
        self.day = day
        self.eaten = eaten
        self.updated = updated
    }
}
