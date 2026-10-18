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

    /// The skill to learn next: the one in learning, else the easiest not yet started.
    public static func next(_ cards: [CardKey: MemoryCard], bank: WritingBank) -> WritingSkill? { candidates(cards, bank: bank).first }

    /// Skills to learn, in order: those in learning, oldest first, then those not yet started,
    /// easiest first and in bank order. Skills have no prerequisites. A skill the bank no longer
    /// has, or has no items for, is left out, so a content update can't hold up the rest or leave
    /// a lesson with nothing to practise. The plan and the session both take their order from here.
    public static func candidates(_ cards: [CardKey: MemoryCard], bank: WritingBank) -> [WritingSkill] {
        let askable = Set(bank.items.map(\.skill))
        let writing = cards.values.filter { $0.domain == .writing }
        let learning = writing.filter(\.learning).sorted { ($0.introduced, $0.key) < ($1.introduced, $1.key) }
            .compactMap { bank.skill($0.key.item) }.filter { askable.contains($0.id) }
        let started = Set(writing.map(\.key.item))
        let fresh = bank.skills.enumerated().filter { !started.contains($0.element.id) && askable.contains($0.element.id) }
            .sorted { ($0.element.level, $0.offset) < ($1.element.level, $1.offset) }.map(\.element)
        return learning + fresh
    }
}
