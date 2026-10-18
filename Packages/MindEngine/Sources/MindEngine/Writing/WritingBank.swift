import Foundation

/// A writing skill: subject–verb agreement, commas, concision. Learned like a maths topic: a short
/// lesson, then items until four of the last five are right, then spaced reviews.
public struct WritingSkill: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var level: Int
    public var lesson: String
    public var example: String

    public var key: CardKey { .skill(id) }
}

/// One objective item: fill the blank, or choose the correct (or clearest) sentence.
public struct WritingItem: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var skill: String
    public var prompt: String
    public var choices: [String]
    public var answer: Int
    public var explanation: String
}

/// The grammar, punctuation and usage bank that ships with the app, and the passages and prompts
/// the writing itself draws on.
public struct WritingBank: Sendable {
    public var skills: [WritingSkill]
    public var items: [WritingItem]
    public var library: WritingLibrary

    public init(skills: [WritingSkill], items: [WritingItem], library: WritingLibrary = .standard) {
        self.skills = skills
        self.items = items
        self.library = library
    }

    private struct File: Decodable {
        var skills: [WritingSkill]
        var items: [WritingItem]
    }

    public static let standard: WritingBank = {
        guard let url = Bundle.module.url(forResource: "writing", withExtension: "json"),
            let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(File.self, from: data)
        else {
            mindLog.error("The writing bank is missing or unreadable")
            return WritingBank(skills: [], items: [])
        }
        return WritingBank(skills: file.skills, items: file.items)
    }()

    public func skill(_ id: String) -> WritingSkill? { skills.first { $0.id == id } }

    public func items(for skill: String) -> [WritingItem] { items.filter { $0.skill == skill } }

    /// An item for a skill, rotating through them so repeats come as late as possible.
    public func item(for skill: String, seen: Int, seed: String) -> WritingItem? {
        let pool = items(for: skill)
        guard !pool.isEmpty else { return nil }
        var rng = SeededRandom("writing", skill, seed)
        let start = Int.random(in: 0..<pool.count, using: &rng)
        return pool[(start + seen) % pool.count]
    }

    public func question(_ item: WritingItem, kind: AttemptKind, seed: String) -> Question {
        var rng = SeededRandom("writing", item.id, seed)
        let order = Array(item.choices.indices).shuffled(using: &rng)
        let sentences = item.choices.contains { $0.count > 40 }
        return Question(
            id: "\(item.id).\(seed)", key: .skill(item.skill), kind: kind,
            instruction: item.prompt.contains("___") ? "Fill the gap" : "Choose one",
            prompt: .text(item.prompt), choices: order.map { item.choices[$0] },
            answer: .choice(order.firstIndex(of: item.answer) ?? 0), expectedSeconds: sentences ? 30 : 15,
            reveal: .note(item.explanation))
    }
}
