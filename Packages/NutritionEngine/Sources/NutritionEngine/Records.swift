import Foundation
import SystemCore

// Stadig Macro's own records. Each is stored whole and synced; trends, estimates, targets and
// scores are recomputed from them, so two devices can never disagree.

/// How an entry got into the log, which says how far its numbers can be trusted.
public enum EntrySource: String, Codable, Sendable {
    case search, barcode, recent, favorite, copied, quickAdd, photo, description, label, shortcut
    /// One of the foods of a saved meal (``SavedMeal``), logged with the rest.
    case recipe
    /// A meal from the week's meal plan, eaten as planned.
    case plan
    /// One tap in the drinks card: a coffee, a tea.
    case drink
}

/// One thing eaten, at a time. There are no meal slots: a day is a timeline, three meals or five.
public struct FoodEntry: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var day: Day
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
    /// Vitamins, minerals and other values by catalog key ("potassium" in mg, "vitaminD" in µg;
    /// see ``Micronutrients``), as logged. A key the food didn't list is unknown, not zero.
    public var micros: [String: Double]?
    /// The food's NOVA group and whether it was fermented, as logged; nil when the food didn't say.
    public var processing: Processing?
    public var fermented: Bool?
    /// Millilitres of fluid, for a drink; nil for food, or an entry from before drinks were counted
    /// (``Hydration/fluid(of:)`` reads those by name).
    public var fluid: Double?
    public var source: EntrySource
    /// 0–1 for estimates (a photo, a description); nil when the numbers are exact.
    public var confidence: Double?
    public var updatedAt: Date
    /// When this entry first went into the log, kept from its first edit on. Nil until then, when
    /// `updatedAt` still says so: read ``firstLogged``.
    public var loggedAt: Date?

    public init(
        id: UUID = UUID(), date: Date = Date(), day: Day? = nil, name: String, brand: String? = nil,
        foodID: String? = nil, amountLabel: String, grams: Double? = nil, unitID: String? = nil, count: Double? = nil,
        nutrients: Nutrients, micros: [String: Double]? = nil, processing: Processing? = nil, fermented: Bool? = nil,
        fluid: Double? = nil, source: EntrySource, confidence: Double? = nil, updatedAt: Date = Date(), loggedAt: Date? = nil
    ) {
        self.id = id
        self.date = date
        self.day = day ?? Day(date)
        self.name = name
        self.brand = brand
        self.foodID = foodID
        self.amountLabel = amountLabel
        self.grams = grams
        self.unitID = unitID
        self.count = count
        self.nutrients = nutrients
        self.micros = micros?.isEmpty == true ? nil : micros
        self.processing = processing
        self.fermented = fermented
        self.fluid = fluid
        self.source = source
        self.confidence = confidence
        self.updatedAt = updatedAt
        self.loggedAt = loggedAt
    }

    public var isEstimate: Bool { confidence != nil }

    /// When this entry first went into the log, whatever's been edited since. An entry from before
    /// that was kept reads as its last edit, which was as much as anyone could tell.
    public var firstLogged: Date { loggedAt ?? updatedAt }

    /// This entry with `change` made to it, as every edit has to be saved: it keeps when it was first
    /// logged, its stamp is past the last one even with a clock behind another device's (the store
    /// ignores older saves), and its day moves only with its date, so a day logged in another time
    /// zone stays that day.
    public func edited(at now: Date, calendar: Calendar = .current, change: (inout FoodEntry) -> Void = { _ in }) -> FoodEntry {
        var entry = self
        change(&entry)
        entry.loggedAt = firstLogged
        entry.updatedAt = max(now, updatedAt.addingTimeInterval(0.001))
        entry.day = entry.date == date ? day : Day(entry.date, calendar: calendar)
        return entry
    }
}

/// What a day's food adds up to.
public enum Intake {
    /// `entries` with what `doses` of supplements add. Their few calories count on a day with food
    /// logged; alone, they don't make a day logged, so a day of pills is nothing eaten.
    public static func total(_ entries: [FoodEntry], doses: [SupplementLog] = []) -> Nutrients {
        guard !entries.isEmpty else { return .zero }
        return doses.reduce(Nutrients.sum(entries.map(\.nutrients))) { $0 + calories(of: $1) }
    }

    /// The part of a dose that counts as intake: macros only, since a label's vitamins are read apart.
    static func calories(of dose: SupplementLog) -> Nutrients {
        guard dose.taken, let n = dose.nutrients else { return .zero }
        return Nutrients(kcal: n.kcal, protein: n.protein, carbs: n.carbs, fat: n.fat)
    }
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

/// Stadig Macro's settings. Shared setup answers live in ``SharedProfile``.
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
    /// Show the drinks card: water, and caffeine against a limit. Off until turned on.
    public var tracksDrinks: Bool?
    /// The day's caffeine limit, mg; nil is ``Caffeine/defaultLimit``.
    public var caffeineLimit: Double?
    /// A cut-back in progress.
    public var caffeineCutBack: CaffeineCutBack?
    /// Millilitres to drink a day; nil is ``Hydration/target(sex:)``.
    public var waterTarget: Double?
    /// The person's own times for each part of the day, minutes after midnight; bedtime also
    /// times the caffeine report.
    public var doseTimes: [DoseTime: Int]?
    /// Notify at each time of day with doses due, with a button to mark them taken.
    public var supplementReminders: Bool?
    /// Show meal timing and fasting: time since the last meal, gaps, the overnight fast, fasts with a
    /// goal. Off until turned on.
    public var tracksMealTiming: Bool?
    /// Notify at each phase of a fast and at its goal; nil is on.
    public var fastAlerts: Bool?
    /// When the person read who shouldn't fast for more than a day; nil until they have.
    public var fastingScreenSeen: Date?
    /// The day of the check-in the person put away on Today, or saw to themselves (a plan chosen or
    /// kept, their own targets set), so Today doesn't show it again on this device or another
    /// (`CheckIns.shown`).
    public var checkInPutAway: Day?
    /// The first and last hours the Log tab offers, 0 to 23; nil follows sleep, then ``LogHours/standard``.
    public var logFirstHour: Int?
    public var logLastHour: Int?
    public var updatedAt: Date

    public init(
        id: UUID = UUID(), onboardedAt: Date? = nil, assessmentStart: Day? = nil, dietHistory: DietHistory = .none,
        phaseOverride: PhaseKind? = nil, showAllMacros: Bool = true, allowCloudAI: Bool = true, saveToHealth: Bool = true,
        updatedAt: Date = Date()
    ) {
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

    public var drinks: Bool { tracksDrinks ?? false }
    public var mealTiming: Bool { tracksMealTiming ?? false }

    /// Minutes after midnight for a time of day.
    public func minutes(_ time: DoseTime) -> Int { doseTimes?[time] ?? time.defaultMinutes }
}

extension MacroSettings {
    /// The settings record in force. There's normally one; a second appears when setup was finished
    /// on a new device before the first device's settings had synced in. The one set up first wins,
    /// so the person's settings aren't shadowed by the new device's defaults; between two never set
    /// up, the newer edit.
    public static func inForce(_ all: [MacroSettings]) -> MacroSettings? {
        all.min { a, b in
            switch (a.onboardedAt, b.onboardedAt) {
            case (let x?, let y?): x != y ? x < y : a.updatedAt > b.updatedAt
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): a.updatedAt > b.updatedAt
            }
        }
    }
}
