#if DEBUG
import Foundation
import HubEngine
import OSLog
import SystemCore
import SystemStore

/// A real-looking week for screenshots and looking at screens: alternate Fridays, a commute, the
/// gym, two classes on two evenings, meals and four courses, as if the apps had published them.
enum SampleData {
    static func seedIfEmpty(_ model: AppModel) {
        guard !model.onboarded else { return }
        let today = model.today
        let monday = today.startOfWeek
        let now = Date()
        let shared = model.shared
        model.finishSetup(pattern: pattern(monday), wake: 6 * 60, bed: 22 * 60 + 30)
        do {
            try shared.write(profile, to: .profile, by: .liftTrack)
            try shared.write(AppSummary(app: .liftTrack, updated: now, stats: liftStats(now), sessions: []), to: .summary(.liftTrack), by: .liftTrack)
            try shared.write(AppSummary(app: .macroTrack, updated: now, stats: macroStats(now)), to: .summary(.macroTrack), by: .macroTrack)
            try shared.write(AppSummary(app: .knowledge, updated: now, stats: mindStats(now)), to: .summary(.knowledge), by: .knowledge)
            try shared.write(ask(monday, now: now), to: .blockAsk, by: .knowledge)
            let meals = MealRhythm(usual: [.early, .midday, .evening], day: today, eaten: [.early], updated: now)
            try shared.write(meals, to: .mealRhythm, by: .macroTrack)
        } catch {
            appLog.error("Couldn't seed the sample data: \(error.localizedDescription)")
        }
        model.readShared()
    }

    static func pattern(_ monday: Day) -> WorkPattern {
        if LaunchOptions.current.has("-seedHybrid") { return HybridWeek.standard.pattern(anchor: monday, commute: 30) }
        return SchedulePreset.alternateFridays.pattern(anchor: monday).withCommute(30)
    }

    static func liftStats(_ now: Date) -> [StatReading] {
        [
            StatReading(stat: .strength, score: 62, label: "Intermediate", trend: .onPace, updated: now),
            StatReading(stat: .physique, score: 71, label: "Proportions", trend: .notEnoughData, updated: now),
            StatReading(stat: .endurance, score: 48, label: "Engine", trend: .stalled, updated: now),
            StatReading(stat: .agility, score: 54, label: "Limiter: Hips", trend: .notEnoughData, updated: now),
            StatReading(stat: .discipline, score: 84, label: "Training 84%", trend: .notEnoughData, updated: now),
        ]
    }

    static func macroStats(_ now: Date) -> [StatReading] {
        [
            StatReading(stat: .vitality, score: 86, label: "Logged 86% of days", trend: .notEnoughData, updated: now),
            StatReading(stat: .discipline, score: 92, label: "Nutrition 92%", trend: .notEnoughData, updated: now),
        ]
    }

    static func mindStats(_ now: Date) -> [StatReading] {
        [
            StatReading(stat: .intelligence, score: 58, label: "Japanese and maths", trend: .onPace, updated: now),
            StatReading(stat: .wisdom, score: 66, label: "Reading", trend: .ahead, updated: now),
        ]
    }

    static var profile: SharedProfile {
        SharedProfile(
            schedule: TrainingSchedule(daysPerWeek: 5, minutesPerSession: 90, preferredDays: [.monday, .tuesday, .wednesday, .thursday, .friday]),
            recurring: [
                RecurringActivity(activity: .bjj, weekdays: [.monday, .wednesday], minutes: 60),
                RecurringActivity(activity: .muayThai, weekdays: [.monday, .wednesday, .friday], minutes: 60),
            ],
            createdBy: .liftTrack)
    }

    static func ask(_ monday: Day, now: Date) -> BlockAsk {
        var units: [String: Int] = [:]
        for offset in 0..<14 { units[monday.adding(days: offset).iso] = 2 }
        let courses = [
            BlockCourse(id: "japanese", blocks: 4, fit: [.night, .evening, .afternoon, .midday, .morning, .early]),
            BlockCourse(id: "reading", blocks: 3, fit: [.evening, .night, .afternoon, .midday, .morning, .early]),
            BlockCourse(id: "maths", blocks: 2, fit: [.morning, .midday, .early, .afternoon, .evening, .night]),
            BlockCourse(id: "writing", blocks: 1, fit: [.midday, .afternoon, .morning, .early, .evening, .night]),
        ]
        return BlockAsk(monday: monday, since: monday.adding(weeks: -4), courses: courses, units: units, finished: [], updated: now)
    }
}
#endif
