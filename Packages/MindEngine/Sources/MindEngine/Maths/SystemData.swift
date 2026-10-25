import Foundation
import SystemCore

/// A small chart a problem is about: a week of steps as bars, say. The app draws it natively.
public struct DataFigure: Hashable, Sendable {
    public enum Style: String, Hashable, Sendable { case bars, line }

    public struct Point: Hashable, Sendable {
        public var label: String
        public var value: Double

        public init(label: String, value: Double) {
            self.label = label
            self.value = value
        }
    }

    public var title: String
    /// What the values are in: "steps", "g".
    public var unit: String
    public var style: Style
    public var points: [Point]
    /// Where the numbers came from, when they're the person's own: "From Stadig Lift".
    public var source: String?

    public init(title: String, unit: String, style: Style = .bars, points: [Point], source: String? = nil) {
        self.title = title
        self.unit = unit
        self.style = style
        self.points = points
        self.source = source
    }
}

/// Numbers the other System apps publish, so a statistics problem can be about the person's own
/// weeks: steps and strength sessions from Stadig Lift, protein and calories from Stadig Macro. The
/// app reads the shared container and passes this in through the catalogs; the engine never reads
/// it itself, and every problem that uses it has a made-up version for when it's empty.
public struct SystemData: Hashable, Sendable {
    public struct Point: Hashable, Sendable {
        public var day: Day
        public var value: Double

        public init(day: Day, value: Double) {
            self.day = day
            self.value = value
        }
    }

    /// Steps a day, complete days the phone was carried, oldest first.
    public var steps: [Point]
    /// Minutes of strength training on each day trained, oldest first.
    public var training: [Point]
    /// Protein grams and calories on each day food was logged, oldest first.
    public var protein: [Point]
    public var calories: [Point]
    /// Logged days and whether the protein target was hit.
    public var proteinHits: [Day: Bool]

    public static let none = SystemData()

    public init(steps: [Point] = [], training: [Point] = [], protein: [Point] = [], calories: [Point] = [], proteinHits: [Day: Bool] = [:]) {
        self.steps = steps.sorted { $0.day < $1.day }
        self.training = training.sorted { $0.day < $1.day }
        self.protein = protein.sorted { $0.day < $1.day }
        self.calories = calories.sorted { $0.day < $1.day }
        self.proteinHits = proteinHits
    }

    /// From what Stadig Lift and Stadig Macro published.
    public init(lift: AppSummary?, macro: AppSummary?, nutrition: NutritionSummary?) {
        let steps = (lift?.steps?.days ?? []).filter { $0.steps >= Steps.carriedMinimum }.map { Point(day: $0.day, value: Double($0.steps)) }
        var minutes: [Day: Double] = [:]
        for session in lift?.sessions ?? [] where session.kind == .strength && session.minutes > 0 {
            minutes[session.day, default: 0] += Double(session.minutes)
        }
        let food = (macro?.sessions ?? []).filter { $0.kind == .nutrition }
        var hits: [Day: Bool] = [:]
        for day in nutrition?.days ?? [] where day.logged {
            if let hit = day.proteinHit { hits[day.day] = hit }
        }
        self.init(
            steps: steps, training: minutes.map { Point(day: $0.key, value: $0.value) },
            protein: food.compactMap { session in session.metrics["protein"].map { Point(day: session.day, value: $0) } },
            calories: food.compactMap { session in session.metrics["kcal"].map { Point(day: session.day, value: $0) } },
            proteinHits: hits)
    }

    public var isEmpty: Bool { steps.isEmpty && training.isEmpty && protein.isEmpty && proteinHits.isEmpty }

    /// The last seven step days, when at least five of the last seven days are known.
    var stepWeek: [Point]? {
        guard let last = steps.last?.day else { return nil }
        let week = steps.filter { $0.day > last.adding(days: -7) }
        return week.count >= 5 ? week : nil
    }

    /// Days in the last four weeks of Stadig Macro data, split by whether Stadig Lift logged a
    /// strength session and whether protein was hit. Nil without enough of both.
    var trainingAndProtein: (trainedHit: Int, trainedMissed: Int, restHit: Int, restMissed: Int)? {
        guard let last = proteinHits.keys.max(), !training.isEmpty else { return nil }
        let trained = Set(training.map(\.day))
        let days = proteinHits.filter { $0.key > last.adding(days: -28) }
        var table = (trainedHit: 0, trainedMissed: 0, restHit: 0, restMissed: 0)
        for (day, hit) in days {
            switch (trained.contains(day), hit) {
            case (true, true): table.trainedHit += 1
            case (true, false): table.trainedMissed += 1
            case (false, true): table.restHit += 1
            case (false, false): table.restMissed += 1
            }
        }
        let trainedDays = table.trainedHit + table.trainedMissed
        let restDays = table.restHit + table.restMissed
        return days.count >= 10 && trainedDays >= 3 && restDays >= 3 ? table : nil
    }
}

extension Array where Element == SystemData.Point {
    /// Values rounded to a step (steps to the nearest 100), so a chart can be read exactly.
    func rounded(to step: Double) -> [SystemData.Point] {
        map { SystemData.Point(day: $0.day, value: ($0.value / step).rounded() * step) }
    }

    func figure(_ title: String, unit: String, source: String) -> DataFigure {
        DataFigure(title: title, unit: unit, points: map { DataFigure.Point(label: $0.day.weekday.short, value: $0.value) }, source: source)
    }
}
