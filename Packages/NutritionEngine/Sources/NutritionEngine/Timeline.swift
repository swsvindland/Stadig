import Foundation
import SystemCore

/// Foods eaten together: logged within a short while of each other. A day is a list of these,
/// however many there are.
public struct Moment: Hashable, Sendable, Identifiable {
    public var entries: [FoodEntry]

    public var id: UUID { entries.first?.id ?? UUID() }
    public var start: Date { entries.first?.date ?? .distantPast }
    public var end: Date { entries.last?.date ?? .distantPast }
    public var nutrients: Nutrients { Nutrients.sum(entries.map(\.nutrients)) }
}

public enum Timeline {
    /// Entries this close to the one before belong to the same moment.
    public static let gap: TimeInterval = 45 * 60

    /// A day's entries as moments, earliest first.
    public static func moments(_ entries: [FoodEntry], gap: TimeInterval = gap) -> [Moment] {
        var moments: [Moment] = []
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            if let last = moments.last?.entries.last, entry.date.timeIntervalSince(last.date) <= gap {
                moments[moments.count - 1].entries.append(entry)
            } else {
                moments.append(Moment(entries: [entry]))
            }
        }
        return moments
    }
}
