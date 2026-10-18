import Foundation
import SystemCore

/// One skill's level in one language, from its latest test.
public struct SkillLevel: Hashable, Sendable {
    public var skill: LanguageSkill
    public var test: TestResult
    /// The test's reach in words: sentences understood (or produced) about as far as the language's
    /// this-many most common words.
    public var words: Int
    /// 0 to 6, a level for every doubling of reach from 100 words.
    public var level: Int
    /// 0–100 on the same log scale as the vocabulary test, so the four skills and vocabulary compare.
    public var score: Double

    public var label: String { SkillLevel.label(level) }

    /// What a level means in plain terms.
    public static func label(_ level: Int) -> String {
        switch level {
        case 0: "Starting out"
        case 1: "First words"
        case 2: "Simple phrases"
        case 3: "Everyday sentences"
        case 4: "Most everyday talk"
        case 5: "Most of what's said"
        default: "Broad and deep"
        }
    }
}

/// Four skills tracked separately, like separate lifts: listening, speaking, reading and writing,
/// each from its own test with its own level. Every test is banded by sentence difficulty (the
/// rank of its rarest word), so a skill's level is how far into the language it reaches, on the
/// vocabulary test's scale. Listening and speaking weigh most in the language's score.
public enum LanguageSkills {
    /// Reach in words where each level starts.
    public static let levelStarts = [100, 250, 500, 1000, 2000, 4000]

    public static func test(_ skill: LanguageSkill) -> TestKind {
        switch skill {
        case .listening: .listening
        case .speaking: .speaking
        case .reading: .languageReading
        case .writing: .languageWriting
        }
    }

    public static func skill(_ test: TestKind) -> LanguageSkill? { LanguageSkill.allCases.first { self.test($0) == test } }

    /// The skills a person is measured on. Speaking is left out while speaking exercises are off,
    /// unless it was measured before.
    public static func enabled(_ settings: MindSettings, tests: [TestResult], domain: Domain) -> [LanguageSkill] {
        LanguageSkill.allCases.filter { skill in
            skill != .speaking || settings.speaking || tests.contains { $0.test == .speaking && $0.domain == domain }
        }
    }

    /// A banded test's reach: each band's share times its width, as the vocabulary test counts
    /// words. Older results without it get it from their bands.
    public static func words(_ result: TestResult) -> Int {
        if let words = result.detail["words"] { return Int(words) }
        var total = 0.0
        for (band, levels) in LanguageTests.listeningLevels.enumerated() {
            if let share = result.detail["band\(band)"] { total += share * Double(levels.count) }
        }
        return Int(total.rounded())
    }

    public static func level(words: Int) -> Int { levelStarts.filter { words >= $0 }.count }

    public static func level(_ result: TestResult) -> SkillLevel? {
        guard let skill = skill(result.test) else { return nil }
        let words = words(result)
        return SkillLevel(skill: skill, test: result, words: words, level: level(words: words),
                          score: LanguageTests.vocabularyScore(Double(words)))
    }

    /// The latest level of each skill measured in a course, on or before `day` when given.
    public static func levels(_ domain: Domain, tests: [TestResult], on day: Day? = nil) -> [LanguageSkill: SkillLevel] {
        var out: [LanguageSkill: SkillLevel] = [:]
        for result in tests.sorted(by: { $0.date < $1.date }) where result.domain == domain {
            if let day, result.day > day { continue }
            if let level = level(result) { out[level.skill] = level }
        }
        return out
    }

    /// The language's 0–100 score from its four skills, listening and speaking weighted most. Nil
    /// until every skill measured here has a result, so a skill measured for the first time never
    /// reads as a change.
    public static func score(_ levels: [LanguageSkill: SkillLevel], skills: [LanguageSkill]) -> Double? {
        guard !skills.isEmpty, skills.allSatisfy({ levels[$0] != nil }) else { return nil }
        let weight = skills.map(\.weight).reduce(0, +)
        return skills.map { levels[$0]!.score * $0.weight }.reduce(0, +) / weight
    }
}
