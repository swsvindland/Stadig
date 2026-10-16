import Foundation
import SystemCore

// Macro Track's own records. Each is stored whole and synced; trends, estimates, targets and
// scores are recomputed from them, so two devices can never disagree.

public enum MealSlot: String, CaseIterable, Codable, Sendable, Identifiable, Comparable {
    case breakfast, lunch, dinner, snacks

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snacks: "Snacks"
        }
    }

    public var symbol: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon.stars"
        case .snacks: "takeoutbag.and.cup.and.straw"
        }
    }

    /// The slot people most likely mean at a time of day, so logging needs no choice.
    public static func guess(for date: Date, calendar: Calendar = .current) -> MealSlot {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 4..<11: return .breakfast
        case 11..<15: return .lunch
        case 17..<22: return .dinner
        default: return .snacks
        }
    }

    public static func < (a: MealSlot, b: MealSlot) -> Bool { allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)! }
}

/// How an entry got into the log, which says how far its numbers can be trusted.
public enum EntrySource: String, Codable, Sendable {
    case search, barcode, recent, favorite, copied, quickAdd, recipe, photo, description, label, shortcut
}

/// One thing eaten.
public struct FoodEntry: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var day: Day
    public var meal: MealSlot
    public var name: String
    public var brand: String?
    /// The library or custom food it came from, when there is one.
    public var foodID: String?
    /// "1 cup", "2 large", "150 g": how the person thinks of the amount.
    public var amountLabel: String
    public var grams: Double?
    /// The portion unit and count picked, so the next log of this food starts there.
    public var unitID: String?
    public var count: Double?
    /// The numbers as logged, kept even if the food later changes.
    public var nutrients: Nutrients
    public var source: EntrySource
    /// 0–1 for estimates (a photo, a description); nil when the numbers are exact.
    public var confidence: Double?
    public var updatedAt: Date

    public init(id: UUID = UUID(), date: Date = Date(), day: Day? = nil, meal: MealSlot, name: String, brand: String? = nil,
                foodID: String? = nil, amountLabel: String, grams: Double? = nil, unitID: String? = nil, count: Double? = nil,
                nutrients: Nutrients, source: EntrySource, confidence: Double? = nil, updatedAt: Date = Date()) {
        self.id = id
        self.date = date
        self.day = day ?? Day(date)
        self.meal = meal
        self.name = name
        self.brand = brand
        self.foodID = foodID
        self.amountLabel = amountLabel
        self.grams = grams
        self.unitID = unitID
        self.count = count
        self.nutrients = nutrients
        self.source = source
        self.confidence = confidence
        self.updatedAt = updatedAt
    }

    public var isEstimate: Bool { confidence != nil }
}

/// A morning weigh-in. Health supplies most of them; manual ones fill the gaps.
public struct WeighIn: Hashable, Codable, Sendable, Identifiable {
    public enum Source: Codable, Hashable, Sendable {
        case health(UUID)
        case manual
    }

    public var id: UUID
    public var date: Date
    public var kg: Double
    public var source: Source
    /// Ignored by the person (a misread, or weighed after a big meal).
    public var excluded: Bool
    public var updatedAt: Date

    public init(id: UUID = UUID(), date: Date, kg: Double, source: Source = .manual, excluded: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.date = date
        self.kg = kg
        self.source = source
        self.excluded = excluded
        self.updatedAt = updatedAt
    }

    public var day: Day { Day(date) }
}

/// What a day's log is: still going, finished, only partly logged, or a deliberate fast. Only
/// complete and fasting days teach the estimate; the rest are unknown, never zero.
public enum DayState: String, Codable, Sendable, CaseIterable {
    case inProgress, complete, partial, fasting

    public var label: String {
        switch self {
        case .inProgress: "In progress"
        case .complete: "Complete"
        case .partial: "Partly logged"
        case .fasting: "Fasted"
        }
    }
}

public struct DayStatus: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var day: Day
    public var state: DayState
    public var updatedAt: Date

    public init(id: UUID = UUID(), day: Day, state: DayState, updatedAt: Date = Date()) {
        self.id = id
        self.day = day
        self.state = state
        self.updatedAt = updatedAt
    }
}

/// How the person has been eating lately: a long cut lowers maintenance and calls for a reverse diet.
public enum DietHistory: String, CaseIterable, Codable, Sendable, Identifiable {
    case none, recentCut, longCut, bulking

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .none: "Eating normally"
        case .recentCut: "Dieting for a few weeks"
        case .longCut: "Dieting for months"
        case .bulking: "Eating to gain"
        }
    }
}

/// Macro Track's settings. Shared setup answers live in ``SharedProfile``.
public struct MacroSettings: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var onboardedAt: Date?
    public var assessmentStart: Day?
    public var dietHistory: DietHistory
    /// The person's own override of the recommended phase; nil follows the recommendation.
    public var phaseOverride: PhaseKind?
    /// Show carbs and fat, or just calories and protein.
    public var showAllMacros: Bool
    /// Use Private Cloud Compute for photos and descriptions when the device can't.
    public var allowCloudAI: Bool
    /// Write logged food and manual weigh-ins to Health.
    public var saveToHealth: Bool
    public var updatedAt: Date

    public init(id: UUID = UUID(), onboardedAt: Date? = nil, assessmentStart: Day? = nil, dietHistory: DietHistory = .none,
                phaseOverride: PhaseKind? = nil, showAllMacros: Bool = true, allowCloudAI: Bool = true, saveToHealth: Bool = true,
                updatedAt: Date = Date()) {
        self.id = id
        self.onboardedAt = onboardedAt
        self.assessmentStart = assessmentStart
        self.dietHistory = dietHistory
        self.phaseOverride = phaseOverride
        self.showAllMacros = showAllMacros
        self.allowCloudAI = allowCloudAI
        self.saveToHealth = saveToHealth
        self.updatedAt = updatedAt
    }
}
