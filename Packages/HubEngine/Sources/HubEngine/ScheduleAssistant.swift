import Foundation
import FoundationModels
import OSLog
import SystemCore

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
@Generable(description: "When a person works or studies in a normal week")
struct ScheduleOutput {
    @Guide(description: "The first day of the working week. 1 is Monday and 7 is Sunday.", .range(1...7))
    var firstDay: Int
    @Guide(description: "The last day of the working week. 1 is Monday and 7 is Sunday.", .range(1...7))
    var lastDay: Int
    @Guide(description: "When a working day starts, in minutes after midnight.", .range(0...1439))
    var startMinute: Int
    @Guide(description: "When a working day ends, in minutes after midnight.", .range(1...1439))
    var endMinute: Int
    @Guide(description: "True only if the person says every other Friday is off.")
    var alternateFridaysOff: Bool
    @Guide(description: "True only if the person splits work between an office and home.")
    var isHybrid: Bool
    @Guide(description: "Days in the office, for a hybrid week. 1 is Monday and 7 is Sunday.", .maximumCount(7), .element(.range(1...7)))
    var officeDays: [Int]
    @Guide(description: "Whole days worked at home, for a hybrid week. 1 is Monday and 7 is Sunday.", .maximumCount(7), .element(.range(1...7)))
    var homeDays: [Int]
    @Guide(description: "On an office day, the minutes worked at home before leaving.", .range(0...480))
    var homeMinutesBefore: Int
    @Guide(description: "On an office day, the minutes worked at home after getting back.", .range(0...480))
    var homeMinutesAfter: Int
}

/// Reads a schedule from a sentence. The rules go first, and give the same answer on every device.
/// Apple's on-device model only reads what they can't, and only fills the same draft: it decides
/// nothing, because the person always sees the draft and confirms it. Without a model, a sentence
/// the rules can't read is left for a preset.
public struct ScheduleAssistant: Sendable {
    static let log = Logger(subsystem: "dev.svindland.stadig.hub", category: "schedule")

    public init() {}

    static let instructions = """
        You read a sentence about when someone works or studies in a normal week, and list the days and hours it \
        gives. Use only what the sentence says. If it gives no hours, use 540 for the start and 1020 for the end. If \
        it gives no days, use Monday to Friday. If work is split between an office and home, set isHybrid, use the \
        start and end for the hours at the office, and give the office days, the days at home, and the time worked at \
        home before and after the office. If it only says how many days, count them from Monday.
        """

    public func read(_ sentence: String, anchor: Day) async -> ScheduleReader.Draft? {
        if let rules = ScheduleReader.read(sentence, anchor: anchor) { return rules }
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *), SystemLanguageModel.default.availability == .available else { return nil }
        do {
            let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: Self.instructions)
            let reply = try await session.respond(
                to: sentence, generating: ScheduleOutput.self, options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 120))
            let output = reply.content
            if output.isHybrid {
                var week = HybridWeek.standard
                week.days = (1...7).map { output.officeDays.contains($0) ? .office : output.homeDays.contains($0) ? .home : .off }
                week.officeStart = output.startMinute
                week.officeEnd = output.endMinute
                week.homeBefore = output.homeMinutesBefore
                week.homeAfter = output.homeMinutesAfter
                return ScheduleReader.draft(week, anchor: anchor)
            }
            guard output.firstDay <= output.lastDay else { return nil }
            return ScheduleReader.draft(
                days: (output.firstDay - 1)...(output.lastDay - 1), start: output.startMinute, end: output.endMinute,
                alternatingFridays: output.alternateFridaysOff, anchor: anchor)
        } catch {
            Self.log.error("Couldn't read a schedule: \(error.localizedDescription)")
            return nil
        }
    }
}
