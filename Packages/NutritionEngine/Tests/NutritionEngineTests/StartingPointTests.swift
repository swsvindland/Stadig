import Foundation
import SystemCore
import Testing

@testable import NutritionEngine

@Suite("Onboarding's starting point")
struct StartingPointTests {
    let today = Day(year: 2026, month: 11, day: 12)

    var profile: SharedProfile {
        var profile = SharedProfile(goals: [.leaner], experience: .intermediate, createdBy: .macroTrack)
        profile.sex = .male
        profile.heightCm = 180
        profile.birthYear = 1990
        profile.schedule.daysPerWeek = 4
        return profile
    }

    @Test("The formula's maintenance, split the way the assessment's protein asks")
    func numbers() {
        let point = StartingPoint.make(profile: profile, weightKg: 82, today: today)
        let formula = Energy.formula(sex: .male, kg: 82, heightCm: 180, age: 36, trainingDays: 4, otherActiveMinutes: 0)
        #expect(point.kcal == (formula / 10).rounded() * 10)
        #expect(point.kcal.truncatingRemainder(dividingBy: 10) == 0)
        // 1.8 g a kg at maintenance, as the assessment's protein target is.
        #expect(point.protein == (82 * 1.8 / 5).rounded() * 5)
        #expect(abs(point.protein * 4 + point.carbs * 4 + point.fat * 9 - point.kcal) <= 25)
        #expect(point.assessmentDays == 21)
    }

    @Test("The shares add up to the whole")
    func shares() {
        let shares = StartingPoint.make(profile: profile, weightKg: 82, today: today).shares
        #expect(abs(shares.protein + shares.carbs + shares.fat - 1) < 0.0001)
        #expect(shares.protein > 0.15 && shares.fat > 0.2)
    }

    @Test("A fortnight of weigh-ins already in Health shortens the assessment")
    func shorter() {
        #expect(StartingPoint.make(profile: profile, weightKg: 82, today: today, weighInsBefore: 12).assessmentDays == 14)
    }
}
