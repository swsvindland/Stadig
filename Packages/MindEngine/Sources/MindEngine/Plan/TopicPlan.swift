import Foundation
import SystemCore

/// Mastery for maths topics and writing skills: a topic is learned at four of the last five right
/// (at least four tried, ending on a right one), and set aside for the day after three of the last
/// five wrong, so a struggle ends with the worked solution, not a spiral. A lucky streak doesn't
/// stick for long: two missed reviews in a row put a topic back into learning.
public enum Mastery {
    public static let window = 5
    public static let needed = 4
    public static let minimumAttempts = 4
    public static let maximumPerVisit = 9

    public static func mastered(_ recent: [Bool]) -> Bool {
        recent.count >= minimumAttempts && recent.last == true && recent.suffix(window).filter { $0 }.count >= needed
    }

    public static func struggling(_ recent: [Bool]) -> Bool {
        recent.count >= 3 && recent.suffix(window).filter { !$0 }.count >= 3
    }

    /// The first grade for a just-mastered topic: Good if it came cleanly, Hard if it took a while.
    public static func grade(_ recent: [Bool]) -> Grade { recent.filter { !$0 }.isEmpty ? .good : .hard }
}

public enum WritingPlan {
    public static func known(_ cards: [CardKey: MemoryCard]) -> Set<String> {
        Set(cards.values.filter { $0.domain == .writing && $0.memory != nil }.map(\.key.item))
    }

    /// Skills not yet started, easiest first. Skills have no prerequisites.
    public static func next(_ cards: [CardKey: MemoryCard], bank: WritingBank) -> WritingSkill? {
        let learning = cards.values.filter { $0.domain == .writing && $0.learning }.sorted { $0.introduced < $1.introduced }
        if let current = learning.first, let skill = bank.skill(current.key.item) { return skill }
        let started = Set(cards.values.filter { $0.domain == .writing }.map(\.key.item))
        return bank.skills.filter { !started.contains($0.id) }.min { ($0.level, bank.skills.firstIndex(of: $0)!) < ($1.level, bank.skills.firstIndex(of: $1)!) }
    }
}
