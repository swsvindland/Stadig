import Foundation

/// What the AI is asked about writing, and how its replies are read. The calls go through
/// SystemAI in the app, and nothing in the engine waits on them. Feedback is two or three
/// specific fixes, never a grade: a line that looks like a score is dropped before it's shown.
public enum WritingCoach {
    public static let maximumNotes = 3

    public static func instructions(for exercise: WritingExercise) -> String {
        let rules = """
        Never give a score, grade, mark, rating or percentage, and never sum up how good the piece is. British and American \
        spelling are both fine. Write each note on its own line starting with "- ". No headings, no introduction, no summary.
        """
        if exercise == .franklinRewrite {
            return """
            You coach writers using Benjamin Franklin's method: they read a passage, took brief notes, and later rewrote it from \
            the notes alone. Compare the rewrite with the original. Give exactly two or three notes on what the original does \
            that the rewrite doesn't (a word chosen, a sentence's shape, the order of ideas, a detail kept or lost), quoting \
            both versions briefly, and say what to borrow next time. \(rules)
            """
        }
        return """
        You are a writing coach giving brief, specific notes on a short piece. Give exactly two or three fixes, the ones that \
        would help most, drawn from: grammar and spelling, clarity (does each sentence make sense?), logical flow (does each \
        part lead to the next?) and craft (concrete detail, sentence variety, pacing). For each fix, quote the words it's \
        about, say what to change and why in one or two plain sentences, and show a better version where it helps. If the \
        piece is strong, say what to try next rather than inventing errors. \(rules)
        """
    }

    /// The job: the task as it was set, the text it rewrote (or the original, for a Franklin
    /// rewrite), the piece, and the slips the checker already marked so they aren't repeated.
    public static func prompt(_ piece: WritingPiece, source: String?, slips: [WritingSlip]) -> String {
        var parts = ["The task: \(piece.prompt)"]
        if let source {
            parts.append(piece.exercise == .franklinRewrite ? "The original passage:\n\(source)" : "The text being rewritten:\n\(source)")
        }
        if let notes = piece.notes, piece.exercise == .franklinRewrite { parts.append("The writer's notes:\n\(notes)") }
        parts.append(piece.exercise == .franklinRewrite ? "The rewrite:\n\(piece.text)" : "The piece:\n\(piece.text)")
        let marked = Array(Set(slips.map(\.text))).sorted().prefix(12)
        if !marked.isEmpty {
            parts.append("A checker has already marked these, so leave them out: \(marked.map { "“\($0)”" }.joined(separator: ", ")).")
        }
        return parts.joined(separator: "\n\n")
    }

    /// The fixes in a reply, at most three, with list markers, bold and anything that grades the
    /// piece removed. Empty when nothing usable came back.
    public static func notes(from reply: String) -> [String] {
        var out: [String] = []
        for raw in reply.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "**", with: "")
            if let marker = line.firstMatch(of: /^(?:[-•*]|\d+[.)])\s+/) { line.removeSubrange(marker.range) }
            line = line.trimmingCharacters(in: .whitespaces)
            let words = line.split(separator: " ").count
            guard words >= 4, !grades(line), !(line.hasSuffix(":") && words < 8) else { continue }
            out.append(line)
            if out.count == maximumNotes { break }
        }
        return out
    }

    /// Whether a line grades the piece: "7/10", "85%", "I'd score it", "Grade: B".
    static func grades(_ line: String) -> Bool {
        line.contains(/(?i)\b(score[sd]?|grade[sd]?|rating|rated)\b/) || line.contains(/\b\d{1,3}\s*(?:\/|out of)\s*\d{1,3}\b/)
            || line.contains(/\d\s*%/)
    }

    // MARK: The blind second opinion

    /// Weaknesses first, then the verdict: reading both before choosing makes the small model less
    /// likely to pick whichever came first.
    public static let comparisonInstructions = """
    You judge writing blind. You'll see two short pieces, A and B, each with the task it was written for. Decide which is the \
    stronger piece of writing for its task: clearer, better organised, more precise, and more vivid or persuasive as the task \
    needs. Don't favour the longer one for its length, or the first one for coming first. Write one line naming piece A's main \
    weakness, one line naming piece B's, then a last line that is exactly "Stronger: A" or "Stronger: B".
    """

    /// The pair as the model sees it: in the order shown, or swapped. It's asked both ways, since
    /// models tend to favour one position.
    public static func comparisonPrompt(_ pair: BlindPair, swapped: Bool) -> String {
        let (a, b) = swapped ? (pair.second, pair.first) : (pair.first, pair.second)
        return "Piece A\nTask: \(a.prompt)\n\n\(a.text)\n\n---\n\nPiece B\nTask: \(b.prompt)\n\n\(b.text)"
    }

    /// 0 for A, 1 for B: from a "Stronger: B" line, or else a letter alone on the first line.
    public static func pick(from reply: String) -> Int? {
        let lines = reply.split(whereSeparator: \.isNewline).map(String.init)
        if let verdict = lines.reversed().lazy.compactMap({ $0.firstMatch(of: /(?i:stronger)\W*(?:(?i:piece)\s+)?([AB])\b/) }).first {
            return verdict.1 == "A" ? 0 : 1
        }
        guard let line = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
        let text = String(line)
        // "Piece B is stronger", or the letter on its own: "A", "**B**.", "A: clearer". Not "A clearer piece…".
        guard let match = text.firstMatch(of: /^\W*(?i:piece)\s+([AB])\b/) ?? text.firstMatch(of: /^\W*([AB])(?:\W*$|[.:)*,]|\s+[-–—]\s)/)
        else { return nil }
        return match.1 == "A" ? 0 : 1
    }

    /// The AI's blind pick: whether it chose the newer piece, from its answers in the shown order
    /// and swapped. Answers that contradict each other are no opinion at all; one answer alone stands.
    public static func secondOpinion(_ pair: BlindPair, shown: Int?, swapped: Int?) -> Bool? {
        let fromSwapped = swapped.map { 1 - $0 }
        let index: Int
        switch (shown, fromSwapped) {
        case let (a?, b?): guard a == b else { return nil }; index = a
        case let (a?, nil): index = a
        case let (nil, b?): index = b
        case (nil, nil): return nil
        }
        return (index == 0 ? pair.first : pair.second).id == pair.newer.id
    }
}
