import Foundation
import SystemCore

/// How much heat a sauna or steam session is: minutes weighted by how hot the room was, so 10
/// minutes at 190 °F and 20 at 175 °F can be compared. The same minutes feel about twice as hard
/// every 6 °C (11 °F) hotter, so the hotter ten minutes is the harder session; how each one felt
/// then moves the next, like a set's rating.
public enum HeatDose {
    /// Doses count minutes at this temperature: 80 °C (176 °F) in a sauna, 45 °C (113 °F) in steam.
    public static func reference(_ room: String) -> Double { room == "steam-room" ? 45 : 80 }

    /// Degrees hotter for the same minutes to feel about twice as hard.
    public static let doublingC = 6.0

    public static func dose(minutes: Double, temperatureC: Double, room: String) -> Double {
        minutes * pow(2, (temperatureC - reference(room)) / doublingC)
    }

    public static func minutes(forDose dose: Double, temperatureC: Double, room: String) -> Double {
        dose / pow(2, (temperatureC - reference(room)) / doublingC)
    }

    /// The most minutes worth suggesting at a temperature, whatever the dose says.
    public static func maximumMinutes(temperatureC: Double, room: String) -> Double {
        if room == "steam-room" { return 20 }
        switch temperatureC {
        case 95...: return 12
        case 90...: return 15
        case 85...: return 20
        default: return 25
        }
    }

    public static let minimumMinutes = 5.0
    /// Where a first session starts: ten minutes at the reference temperature (eight in steam).
    public static func firstDose(_ room: String) -> Double { room == "steam-room" ? 8 : 10 }
    /// The most a dose grows to: twenty minutes at the reference (fifteen in steam).
    public static func ceiling(_ room: String) -> Double { room == "steam-room" ? 15 : 20 }

    /// What today's session is built from.
    public struct Plan: Hashable, Sendable {
        public enum Change: String, Sendable { case first, more, same, less }
        public var dose: Double
        public var change: Change
        /// The last session in this room, to say what the plan comes from.
        public var last: HeatLog?
        /// The temperature to assume until today's is read.
        public var temperatureC: Double

        /// Whole minutes for a temperature, within what's sensible at that heat.
        public func minutes(at temperatureC: Double, room: String) -> Int {
            let raw = HeatDose.minutes(forDose: dose, temperatureC: temperatureC, room: room)
            return Int(min(max(raw, HeatDose.minimumMinutes), HeatDose.maximumMinutes(temperatureC: temperatureC, room: room)).rounded())
        }
    }

    /// Today's dose: the last session's, nudged by how it felt. Easy means a little more next time,
    /// too much means less, just right holds (and creeps up after two in a row).
    public static func plan(_ history: [HeatLog], room: String) -> Plan {
        let logs = history.filter { $0.exerciseID == room }.sorted { $0.date < $1.date }
        guard let last = logs.last else {
            return Plan(dose: firstDose(room), change: .first, last: nil, temperatureC: reference(room))
        }
        let temperature = last.temperatureC ?? reference(room)
        let base = dose(minutes: last.minutes, temperatureC: temperature, room: room)
        let previous = logs.dropLast().last
        let (factor, change): (Double, Plan.Change) =
            switch last.rating {
            case .green: (1.15, .more)
            case .red: (0.8, .less)
            case .orange where previous?.rating == .orange: (1.05, .more)
            default: (1, .same)
            }
        let target = min(base * factor, max(base, ceiling(room)))
        return Plan(dose: max(target, minimumMinutes * 0.5), change: change, last: last, temperatureC: temperature)
    }
}
