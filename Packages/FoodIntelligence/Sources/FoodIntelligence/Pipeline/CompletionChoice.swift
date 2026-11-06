import Foundation

/// The on-device model choosing among a search's suggestions.
protocol CompletionModel: Sendable {
    /// Suggestion numbers, likeliest first.
    func choose(instructions: String, prompt: String, options: Int) async throws -> [Int]
    /// Loads the model ahead of the first search, so its answer lands inside the budget.
    func prewarmChoosing() async
}

extension CompletionModel {
    func prewarmChoosing() async {}
}

/// Putting a search's suggestions in the order this person is likeliest to want. The model only
/// ever answers with numbers, so it can't offer a phrase the search wouldn't find anything for.
enum CompletionChoice {
    static let pastLimit = 12
    /// Past this the suggestions have been on screen long enough to be tapped, and moving them
    /// then would put the wrong one under a thumb.
    static let budget = Duration.seconds(2)

    static let instructions = """
        You order search suggestions in a food diary. You're given what the person has typed, the time of \
        day, foods they've logged and numbered suggestions. Reply with the suggestions' numbers, the one they \
        most likely want first. Prefer foods they've logged and foods that suit the time of day. Use only \
        the numbers given.
        """

    static func prompt(typed: String, options: [String], past: [String], part: String) -> String {
        let eaten = past.prefix(pastLimit).map { "- \(FoodText.clean($0, limit: 60))" }
        let listed = options.enumerated().map { "\($0.offset + 1). \($0.element)" }
        return """
            Typed: \(FoodText.clean(typed, limit: 60))
            Time: \(part)
            Often logged:
            \(eaten.isEmpty ? "- nothing yet" : eaten.joined(separator: "\n"))
            Suggestions:
            \(listed.joined(separator: "\n"))
            """
    }

    /// The model's order, then whatever it left out as it was. Numbers that aren't suggestions and
    /// repeats are ignored.
    static func apply(_ picks: [Int], to options: [String]) -> [String] {
        var seen = Set<Int>()
        let chosen = picks.map { $0 - 1 }.filter { options.indices.contains($0) && seen.insert($0).inserted }
        return chosen.map { options[$0] } + options.indices.filter { !seen.contains($0) }.map { options[$0] }
    }

    static func part(of date: Date, calendar: Calendar) -> String {
        switch calendar.component(.hour, from: date) {
        case 4..<11: "morning"
        case 11..<15: "midday"
        case 15..<17: "afternoon"
        case 17..<22: "evening"
        default: "late night"
        }
    }
}

/// Asks the model for an order, and settles for the one it was given: a suggestion in the search's
/// order is always a fine answer, so nothing here fails out loud.
actor CompletionRanker {
    private let model: any CompletionModel
    private let budget: Duration
    /// Backspacing goes back over the same text, and the model's answer needn't be paid for twice.
    private var answers: [String: [String]] = [:]

    private static let remembered = 64

    init(model: any CompletionModel, budget: Duration = CompletionChoice.budget) {
        self.model = model
        self.budget = budget
    }

    func prewarm() async { await model.prewarmChoosing() }

    func rank(typed: String, options: [String], past: [String], at date: Date, calendar: Calendar) async -> [String] {
        guard options.count > 1 else { return options }
        let part = CompletionChoice.part(of: date, calendar: calendar)
        let key = ([typed, part] + options + past).joined(separator: "\n")
        if let known = answers[key] { return known }
        let prompt = CompletionChoice.prompt(typed: typed, options: options, past: past, part: part)
        guard let picks = await picks(prompt, options: options.count) else { return options }
        let ranked = CompletionChoice.apply(picks, to: options)
        if answers.count >= Self.remembered { answers.removeAll() }
        answers[key] = ranked
        return ranked
    }

    /// The model's answer inside the budget, or nil.
    private func picks(_ prompt: String, options: Int) async -> [Int]? {
        let model = model
        let budget = budget
        return await withTaskGroup(of: [Int]?.self) { group in
            group.addTask {
                do {
                    return try await model.choose(instructions: CompletionChoice.instructions, prompt: prompt, options: options)
                } catch {
                    Trace.note { "completions: \(error)" }
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(for: budget)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
