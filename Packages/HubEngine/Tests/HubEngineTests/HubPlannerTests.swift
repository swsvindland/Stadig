import Foundation
import SystemCore
import Testing

@testable import HubEngine

@Suite("The hub's day")
struct HubPlannerTests {
    let utc = TimeZone(identifier: "UTC")!
    /// A Monday.
    let monday = Day(year: 2026, month: 11, day: 2)
    var now: Date { monday.at(hour: 10, minute: 0, timeZone: utc) }

    func at(_ hour: Int, _ minute: Int = 0) -> Int { hour * 60 + minute }

    func rhythm(_ preset: SchedulePreset = .nineToFive, clear: Int = 0) -> Rhythm {
        Rhythm(pattern: preset.pattern(anchor: monday), wake: at(6), bed: at(22, 30), clearEvenings: clear)
    }

    func profile() -> SharedProfile {
        SharedProfile(
            schedule: TrainingSchedule(daysPerWeek: 3, minutesPerSession: 90, preferredDays: [.monday, .wednesday, .friday]),
            recurring: [
                RecurringActivity(activity: .bjj, weekdays: [.monday], minutes: 60),
                RecurringActivity(activity: .muayThai, weekdays: [.monday], minutes: 60),
            ],
            createdBy: .liftTrack)
    }

    func liftSummary(_ sessions: [SessionSummary] = []) -> AppSummary {
        AppSummary(app: .liftTrack, updated: now, sessions: sessions)
    }

    func inputs(
        _ rhythm: Rhythm, changes: [DayChange] = [], profile: SharedProfile? = nil, lift: AppSummary? = nil, meals: MealRhythm? = nil,
        today: Day? = nil
    ) -> HubInputs {
        HubInputs(rhythm: rhythm, changes: changes, profile: profile, lift: lift, meals: meals, today: today ?? monday, now: now, timeZone: utc)
    }

    @Test func aDayShowsWorkAcrossItsParts() {
        let day = HubPlanner.day(on: monday, inputs(rhythm()))
        let work = day.items.filter { $0.kind == .work }
        #expect(work.map(\.part) == [.morning, .midday, .afternoon])
        #expect(work.map(\.minutes).reduce(0, +) == 480)
        #expect(work.allSatisfy { !$0.isYours && $0.app == nil })
    }

    @Test func aHubAloneShowsOnlyWhatItKnows() {
        let day = HubPlanner.day(on: monday, inputs(rhythm()))
        #expect(day.items.allSatisfy { $0.kind == .work })
        #expect(HubPlanner.next(in: day, at: .early) == nil)
    }

    @Test func aDoneLiftAndALoggedMealAreTicked() {
        let lift = SessionSummary(
            id: UUID(), app: .liftTrack, kind: .strength, start: monday.at(hour: 6, minute: 30, timeZone: utc), minutes: 90, planned: true)
        let meals = MealRhythm(usual: [.morning, .midday, .evening], day: monday, eaten: [.morning], updated: now)
        let day = HubPlanner.day(on: monday, inputs(rhythm(), profile: profile(), lift: liftSummary([lift]), meals: meals))
        #expect(day.items.first { $0.kind == .lift }?.done == true)
        #expect(day.items.filter { $0.kind == .meal }.map(\.done) == [true, false, false])
        #expect(day.items.first { $0.kind == .lift }?.app == .liftTrack)
    }

    @Test func nextSkipsWorkAndGoesToWhatsYours() throws {
        let meals = MealRhythm(usual: [.morning, .evening], day: monday, eaten: [.morning], updated: now)
        let day = HubPlanner.day(on: monday, inputs(rhythm(), meals: meals))
        #expect(HubPlanner.next(in: day, at: .morning)?.part == .evening)
        // Past everything, what's left today is still the next thing, with no blame attached.
        #expect(HubPlanner.next(in: day, at: .night)?.part == .evening)
    }

    @Test func outTonightDropsTheClass() {
        var profile = profile()
        profile.recurring = [RecurringActivity(activity: .muayThai, weekdays: [.friday], minutes: 90)]
        let friday = monday.adding(days: 4)
        let before = HubPlanner.week(of: monday, inputs(rhythm(), profile: profile, lift: liftSummary()))
        let after = HubPlanner.week(of: monday, inputs(rhythm(), changes: [.outTonight(on: friday)], profile: profile, lift: liftSummary()))
        #expect(before.days[4].items.contains { $0.kind == .activity })
        #expect(!after.days[4].items.contains { $0.kind == .activity }, "the class passes with no mark")
        #expect(after.days[4].parts.first { $0.part == .evening }?.items.isEmpty == true)
        #expect(after.gym == before.gym, "the gym found another part")
    }

    @Test func aLiftInsideAShiftGoesToTheDaysNextRoom() {
        // A late shift on Monday afternoon and evening, with the lift usually in the evening.
        let week = Rhythm(
            pattern: WorkPattern(anchor: monday, weeks: [[[DaySpan(.work, "Late", from: at(14), to: at(22))], [], [], [], [], [], []]]),
            clearEvenings: 0)
        let item = HubPlanner.day(on: monday, inputs(week, profile: profile(), lift: liftSummary())).items.first { $0.kind == .lift }
        #expect(item != nil)
        #expect(item?.part != .evening && item?.part != .afternoon)
    }

    @Test func aPartPastATermsEndSaysItIsntKnown() {
        var pattern = SchedulePreset.university.pattern(anchor: monday)
        pattern.endsOn = monday.adding(days: -1)
        let day = HubPlanner.day(on: monday, inputs(Rhythm(pattern: pattern)))
        #expect(!day.isKnown)
    }

    @Test func staleDataIsLeftOut() {
        let meals = MealRhythm(usual: [.morning], day: monday.adding(days: -40), eaten: [], updated: monday.adding(days: -40).date(timeZone: utc))
        let day = HubPlanner.day(on: monday, inputs(rhythm(), meals: meals))
        #expect(day.items.allSatisfy { $0.kind == .work })
    }

    @Test func aFullWeekCountsItsClearEvenings() {
        let week = HubPlanner.week(of: monday, inputs(rhythm()))
        #expect(week.clearEvenings == 7)
        #expect(week.freeMinutes > 0)
    }

    @Test func nightShiftsFallInTheRightParts() {
        let night = [DaySpan(.work, "Night shift", from: at(22), to: at(30))]
        let pattern = WorkPattern(anchor: monday, weeks: [[night, [], [], [], [], [], []]])
        let day = HubPlanner.day(on: monday, inputs(Rhythm(pattern: pattern, clearEvenings: 0)))
        #expect(day.items.filter { $0.kind == .work }.map(\.part) == [.night])
    }
}

@Suite("Schedules")
struct ScheduleTests {
    let monday = Day(year: 2026, month: 11, day: 2)

    @Test func everyPresetIsAWeekOfSevenDays() {
        for preset in SchedulePreset.allCases {
            let pattern = preset.pattern(anchor: monday)
            #expect(pattern.weeks.allSatisfy { $0.count == 7 }, "\(preset)")
        }
    }

    @Test func aPlainWeekReadsBack() {
        #expect(ScheduleSummary.lines(SchedulePreset.nineToFive.pattern(anchor: monday)) == ["Mon to Fri: 9 AM to 5 PM", "Sat to Sun: off"])
    }

    @Test func alternateFridaysReadAsTwoWeeks() {
        let lines = ScheduleSummary.lines(SchedulePreset.alternateFridays.pattern(anchor: monday))
        #expect(lines.first == "Week 1")
        #expect(lines.contains("Mon to Thu: 8 AM to 5:30 PM"))
        #expect(lines.contains("Week 2"))
        #expect(lines.contains("Fri to Sun: off"))
    }

    @Test func clocksReadPlainly() {
        #expect(ScheduleSummary.clock(0) == "12 AM")
        #expect(ScheduleSummary.clock(750) == "12:30 PM")
        #expect(ScheduleSummary.clock(1800) == "6 AM", "past midnight it wraps")
    }

    @Test func aSentenceWithHoursAndDays() throws {
        let draft = try #require(ScheduleReader.read("I work 8:30 to 5 Monday to Thursday", anchor: monday))
        #expect(!draft.asksWhichWeek)
        let week = try #require(draft.pattern.weeks.first)
        #expect(week[3].first?.start == 510 && week[3].first?.end == 1020)
        #expect(week[4].isEmpty)
    }

    @Test func aSentenceWithAmAndPm() throws {
        let draft = try #require(ScheduleReader.read("9am-5pm on weekdays", anchor: monday))
        #expect(draft.pattern.weeks[0][0].first?.end == 1020)
        #expect(draft.pattern.weeks[0][4].isEmpty == false)
    }

    @Test func alternateFridaysFromASentenceAskWhichWeek() throws {
        let draft = try #require(ScheduleReader.read("I do 9 hours Monday to Thursday, and every other Friday is off", anchor: monday))
        #expect(draft.asksWhichWeek)
        #expect(draft.pattern.weeks.count == 2)
        #expect(draft.pattern.weeks[0][0].first.map(\.minutes) == 570)
        #expect(draft.pattern.weeks[0][4].isEmpty == false)
        #expect(draft.pattern.weeks[1][4].isEmpty)
    }

    @Test func shiftsAndLecturesStartFromTheirPresets() throws {
        #expect(try #require(ScheduleReader.read("I work rotating shifts", anchor: monday)).pattern.weeks.count == 2)
        #expect(try #require(ScheduleReader.read("Lectures most mornings this semester", anchor: monday)).pattern.weeks.count == 1)
    }

    @Test func whatItCantReadItSaysSo() {
        #expect(ScheduleReader.read("whenever the boss calls", anchor: monday) == nil)
    }
}

@Suite("The hub's words and shapes")
struct WordsTests {
    let monday = Day(year: 2026, month: 11, day: 2)

    @Test func lengths() {
        #expect(HubText.length(45) == "45 min")
        #expect(HubText.length(120) == "2 hr")
        #expect(HubText.length(90) == "1 hr 30 min")
    }

    @Test func freeTimeIsARoughAmountAndNeverAClockTime() {
        #expect(HubText.free(0) == "Full")
        #expect(HubText.free(29) == "Full")
        #expect(HubText.free(30) == "30 min free")
        #expect(HubText.free(127) == "2 hr free")
        #expect(HubText.free(133) == "2 hr 15 min free")
    }

    @Test func aNoteNeverSaysWhatWasSkipped() {
        #expect(HubText.note(on: monday, changes: []) == nil)
        let out = [DayChange.outTonight(on: monday)]
        #expect(HubText.note(on: monday, changes: out) == "Out tonight. Whatever was tonight moves on.")
        #expect(HubText.note(on: monday.adding(days: 1), changes: out) == nil)
        #expect(HubText.note(on: monday.adding(days: 3), changes: [.lighterWeek(of: monday)]) == "Lighter week, ends Sunday. A shorter gym session.")
        #expect(HubText.note(on: monday, changes: [DayChange.outTonight(on: monday).deleted()]) == nil)
    }

    @Test func onlyWhatAnAppTracksOpensOne() {
        let gym = HubItem(id: "a", title: "Gym", kind: .lift, part: .evening, minutes: 60, app: .liftTrack)
        #expect(gym.action == "Open Stadig Lift")
        #expect(HubItem(id: "b", title: "Work", kind: .work, part: .morning, minutes: 180).action == nil)
        #expect(HubLink.url(for: .liftTrack)?.scheme == "lifttrack")
        #expect(HubLink.url(for: .macroTrack)?.scheme == "macrotrack")
        // Stadig Mind left the family: nothing opens it.
        #expect(HubLink.url(for: .knowledge) == nil)
        #expect(HubLink.url(for: .hub) == nil)
    }

    @Test func theBarJoinsARunOfOneKind() {
        let items = [
            HubItem(id: "1", title: "Work", kind: .work, part: .morning, minutes: 180),
            HubItem(id: "2", title: "Work", kind: .work, part: .midday, minutes: 180),
            HubItem(id: "3", title: "Meal", kind: .meal, part: .evening, minutes: 30),
        ]
        let part = HubPart(part: .morning, items: items, freeMinutes: 0, isClosed: false)
        #expect(
            HubDay(day: monday, parts: [part], isKnown: true).bar == [BarSegment(kind: .work, minutes: 360), BarSegment(kind: .meal, minutes: 30)])
    }

    @Test func theCommuteFollowsWorkAroundIt() {
        let day = [DaySpan(.work, "Work", from: 540, to: 1020)]
        let pattern = WorkPattern(anchor: monday, weeks: [[day, [], [], [], [], [], []]])
        let commuted = pattern.withCommute(30)
        #expect(commuted.commuteMinutes == 30)
        #expect(commuted.weeks[0][0].map(\.start) == [510, 540, 1020])
        #expect(commuted.weeks[0][1].isEmpty, "a day off has nowhere to go")
        // Changing it replaces it, and off takes it away.
        #expect(commuted.withCommute(45).weeks[0][0].map(\.start) == [495, 540, 1020])
        #expect(commuted.withCommute(0) == pattern)
    }

    @Test func aPresetIsRecognisedWhateverItsCommute() {
        let pattern = SchedulePreset.nineToFive.pattern(anchor: monday)
        #expect(SchedulePreset.matching(pattern) == .nineToFive)
        #expect(SchedulePreset.matching(pattern.withCommute(30)) == .nineToFive)
        var own = pattern
        own.weeks[0][0] = [DaySpan(.work, "Work", from: 600, to: 1020)]
        #expect(SchedulePreset.matching(own) == nil)
    }

    @Test func sayingWhichWeekThisIsMovesTheCycle() {
        let pattern = SchedulePreset.alternateFridays.pattern(anchor: monday)
        let later = monday.adding(weeks: 5)
        #expect(pattern.cycleWeek(of: later) == 1)
        let moved = pattern.settingWeek(0, of: later)
        #expect(moved.cycleWeek(of: later) == 0)
        #expect(moved.cycleWeek(of: later.adding(weeks: 1)) == 1)
        #expect(pattern.settingWeek(1, of: later).cycleWeek(of: later) == 1)
    }

    @Test func aShiftsEndIsOnTheMorningAfterIt() {
        // Ten at night to six in the morning.
        let night = [DaySpan(.work, "Night shift", from: 22 * 60, to: 30 * 60)]
        let rhythm = Rhythm(pattern: WorkPattern(anchor: monday, weeks: [[night, [], [], [], [], [], []]]))
        let inputs = HubInputs(rhythm: rhythm, today: monday, now: monday.date())
        let tuesday = HubPlanner.day(on: monday.adding(days: 1), inputs)
        let early = tuesday.parts.first { $0.part == .early }
        #expect(early?.items.map(\.minutes) == [120], "four to six")
        #expect(HubPlanner.day(on: monday, inputs).items.map(\.minutes) == [360], "ten to four is the night before it")
    }

    @Test func aPartYoureOutOfSaysSo() {
        let inputs = HubInputs(rhythm: Rhythm(), changes: [.outTonight(on: monday)], today: monday, now: monday.date())
        let evening = HubPlanner.day(on: monday, inputs).parts.first { $0.part == .evening }
        #expect(evening?.isClosed == true)
        #expect(evening.map { HubText.status($0, isEarlier: false) } == "Out")
        #expect(evening.map { HubText.status($0, isEarlier: true) } == "Earlier")
    }

    @Test func theRhythmListsOnlyWhatsBeenPublished() {
        let today = monday
        var inputs = HubInputs(rhythm: Rhythm(), today: today, now: today.date())
        #expect(RhythmSummary.lines(inputs).isEmpty)
        inputs.meals = MealRhythm(usual: [.morning, .midday], day: today, eaten: [], updated: today.date())
        #expect(RhythmSummary.lines(inputs).map(\.value) == ["Morning, Midday"])
        #expect(RhythmSummary.lines(inputs).map(\.source) == ["Stadig Macro"])
        // Four weeks unopened, and it's not said to be how things are.
        inputs.meals?.updated = today.adding(days: -40).date()
        #expect(RhythmSummary.lines(inputs).isEmpty)
    }

    @Test func withinAPartThingsGoInTheOrderTheyHappen() {
        // Two classes fill the evening, so the gym moves to the early part: up at six, gym, then the
        // commute at half past seven.
        let work = [DaySpan(.work, "Work", from: 480, to: 1020)]
        let rhythm = Rhythm(pattern: WorkPattern(anchor: monday, weeks: [[work, [], [], [], [], [], []]]).withCommute(30))
        let profile = SharedProfile(
            schedule: TrainingSchedule(daysPerWeek: 1, minutesPerSession: 60, preferredDays: [.monday]),
            recurring: [
                RecurringActivity(activity: .bjj, weekdays: [.monday], minutes: 90),
                RecurringActivity(activity: .muayThai, weekdays: [.monday], minutes: 90),
            ], createdBy: .liftTrack)
        let lift = AppSummary(app: .liftTrack, updated: monday.date(), sessions: [])
        let inputs = HubInputs(rhythm: rhythm, profile: profile, lift: lift, today: monday, now: monday.date())
        let day = HubPlanner.day(on: monday, inputs)
        #expect(day.parts.first { $0.part == .early }?.items.map(\.kind) == [.lift, .commute])
        // Tight as the evening is, both classes stay: they run on into the night.
        #expect(day.parts.first { $0.part == .evening }?.items.map(\.title) == ["Commute", "BJJ", "Muay Thai"])
        #expect(day.parts.first { $0.part == .evening }?.freeMinutes == 0)
        #expect(day.parts.first { $0.part == .night }?.freeMinutes == 120)
    }

    @Test func eachAppSeesWhatsLeftOfTheDay() {
        let meals = MealRhythm(usual: [.morning, .midday, .evening], day: monday, eaten: [.morning], updated: monday.date())
        let inputs = HubInputs(rhythm: Rhythm(), meals: meals, today: monday, now: monday.date())
        #expect(HubPlanner.ahead(inputs, at: .morning) == "Meal, Meal")
        #expect(HubPlanner.ahead(inputs, at: .night) == nil)
        #expect(HubPlanner.ahead(inputs, at: .early, limit: 1) == "Meal and 1 more")
    }

    @Test func aModelCantPutASentenceOutOfBounds() {
        #expect(ScheduleReader.draft(days: 0...4, start: 540, end: 1020, alternatingFridays: false, anchor: monday) != nil)
        #expect(ScheduleReader.draft(days: 0...4, start: 1020, end: 540, alternatingFridays: false, anchor: monday) == nil)
        #expect(ScheduleReader.draft(days: 0...7, start: 540, end: 1020, alternatingFridays: false, anchor: monday) == nil)
        #expect(ScheduleReader.draft(days: 0...4, start: 0, end: 1400, alternatingFridays: false, anchor: monday) == nil)
    }

    @Test func aSentenceTheRulesReadNeedsNoModel() async {
        let draft = await ScheduleAssistant().read("9 to 5 Monday to Friday", anchor: monday)
        #expect(draft?.pattern.weeks.first?.first?.first?.start == 540)
    }

    @Test func aLighterWeeksGymIsShorter() {
        let lift = AppSummary(app: .liftTrack, updated: monday.date(), sessions: [])
        let profile = SharedProfile(
            schedule: TrainingSchedule(daysPerWeek: 1, minutesPerSession: 90, preferredDays: [.monday]), recurring: [], createdBy: .liftTrack)
        let inputs = HubInputs(rhythm: Rhythm(), changes: [.lighterWeek(of: monday)], profile: profile, lift: lift, today: monday, now: monday.date())
        #expect(HubPlanner.day(on: monday, inputs).items.first { $0.kind == .lift }?.minutes == 60)
    }

    @Test func somethingStillThereFromEarlierIsntNext() {
        let item = HubItem(id: "a", title: "Meal", kind: .meal, part: .morning, minutes: 30)
        #expect(HubText.heading(item, at: .morning) == "Now, morning")
        #expect(HubText.heading(item, at: .early) == "Next, morning")
        #expect(HubText.heading(item, at: .afternoon) == "Still today")
    }
}
