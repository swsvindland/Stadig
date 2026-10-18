import Foundation
import SystemCore

/// Free-text search over exercise names, aliases, muscles, equipment and mobility targets, forgiving
/// of gym shorthand, plurals and a typo.
public enum ExerciseSearch {
    /// Gym shorthand people type, expanded before matching.
    static let synonyms: [String: String] = [
        "db": "dumbbell", "dbs": "dumbbell", "bb": "barbell", "kb": "kettlebell", "ez": "ez bar", "bw": "bodyweight",
        "ohp": "overhead press", "rdl": "romanian deadlift", "sldl": "stiff leg deadlift", "bss": "bulgarian split squat",
        "ssb": "safety bar", "cgbp": "close grip bench press", "ghr": "glute ham raise", "dl": "deadlift",
        "tri": "triceps", "tris": "triceps", "bi": "biceps", "bis": "biceps", "delt": "delt", "delts": "delt",
        "quad": "quads", "ham": "hamstring", "hams": "hamstring", "pullup": "pull up", "pullups": "pull up",
        "chinup": "chin up", "chinups": "chin up", "pushup": "push up", "pushups": "push up", "situp": "sit up",
        "situps": "sit up", "flyes": "fly", "flies": "fly", "erg": "rower", "stairs": "stairmaster",
        "hiit": "intervals", "tspine": "t spine", "thoracic": "t spine", "warmup": "warm up", "cooldown": "stretch",
    ]

    /// What lifters mean by the bare name of a lift, keyed by its normalized words.
    static let canonical: [String: String] = [
        "bench": "barbell-bench-press", "bench press": "barbell-bench-press", "incline bench": "barbell-incline-bench-press",
        "squat": "barbell-back-squat", "back squat": "barbell-back-squat", "front squat": "front-squat",
        "deadlift": "conventional-deadlift", "romanian deadlift": "barbell-rdl", "row": "barbell-row",
        "overhead press": "barbell-overhead-press", "military press": "barbell-overhead-press",
        "shoulder press": "db-shoulder-press", "bulgarian split squat": "db-bulgarian-split-squat", "curl": "db-curl",
        "dip": "chest-dip", "pull up": "pull-up", "chin up": "chin-up", "push up": "push-up", "hip thrust": "barbell-hip-thrust",
        "calf raise": "standing-calf-raise", "shrug": "barbell-shrug", "skull crusher": "ez-bar-skull-crusher",
        "leg press": "leg-press", "pulldown": "lat-pulldown", "lat pulldown": "lat-pulldown", "face pull": "face-pull",
        "lateral raise": "db-lateral-raise", "plank": "plank",
    ]

    /// Words that carry no meaning in an exercise name.
    static let stopWords: Set<String> = ["with", "the", "and", "on", "a", "to", "of"]

    /// Lowercase ASCII letters and digits, everything else collapsed to single spaces.
    static func fold(_ text: String) -> String {
        let plain = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        var out = ""
        var space = false
        for scalar in plain.unicodeScalars {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
                out.unicodeScalars.append(scalar)
                space = false
            } else if !space {
                out.append(" ")
                space = true
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// A light plural stemmer, applied to both sides of a match so it only has to be consistent.
    static func stem(_ word: String) -> String {
        if word.count > 4, word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.count > 4, ["sses", "ches", "shes", "xes"].contains(where: word.hasSuffix) { return String(word.dropLast(2)) }
        if word.count >= 3, word.hasSuffix("s"), !word.hasSuffix("ss"), !word.hasSuffix("us") { return String(word.dropLast()) }
        return word
    }

    /// Folded, synonym-expanded, stemmed words. A possessive "s" is dropped.
    static func words(_ text: String) -> [String] {
        fold(text).split(separator: " ").flatMap { raw -> [String] in
            let word = String(raw)
            let expanded = synonyms[word] ?? synonyms[stem(word)] ?? word
            return expanded.split(separator: " ").map(String.init)
        }.filter { !$0.isEmpty && $0 != "s" }.map(stem)
    }

    /// Edit distance of at most one, for typos in longer words ("tricpes", "lateal"). `a` is the
    /// list's word, which must have five letters or more. Both are folded words, so plain ASCII:
    /// their UTF-8 counts are their lengths, checked before anything is allocated.
    static func nearly(_ a: String, _ b: String) -> Bool {
        if abs(a.utf8.count - b.utf8.count) > 1 || a.utf8.count < 5 { return false }
        let a = Array(a)
        let b = Array(b)
        var i = 0
        var j = 0
        var edits = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] {
                i += 1
                j += 1
                continue
            }
            edits += 1
            if edits > 1 { return false }
            if a.count > b.count {
                i += 1
            } else if b.count > a.count {
                j += 1
            } else if i + 1 < a.count, j + 1 < b.count, a[i + 1] == b[j], a[i] == b[j + 1] {
                i += 2
                j += 2
            } else {
                i += 1
                j += 1
            }
        }
        return edits + (a.count - i) + (b.count - j) <= 1
    }

    /// Ranks exercises for a query. Every query word must match a word of the name, an alias, a
    /// muscle, the equipment or a mobility target, as a prefix or with one typo. Name matches beat
    /// alias matches, which beat the rest; the canonical lift for a bare name and exact names or
    /// aliases come first; shorter names win among equals ("Squat" before "Squat to Box"); `boost`
    /// lifts recent and favorite exercises. An empty query returns everything by boost.
    public static func search(_ exercises: [Exercise], _ query: String, boost: (Exercise) -> Double = { _ in 0 }) -> [Exercise] {
        let terms = words(query)
        let classic = canonical[terms.joined(separator: " ")]
        if terms.isEmpty {
            return exercises.enumerated().sorted { a, b in
                let (x, y) = (boost(a.element), boost(b.element))
                return x != y ? x > y : a.offset < b.offset
            }.map(\.element)
        }
        var scored: [(exercise: Exercise, score: Double, offset: Int)] = []
        for (offset, exercise) in exercises.enumerated() {
            let tokens = SearchTokens.of(exercise)
            let name = tokens.name
            let aliases = tokens.aliasWords
            let tags = tokens.tags
            var score = 0.0
            var matched = true
            for term in terms {
                func hit(_ list: [String]) -> Double {
                    if list.contains(term) { return 3 }
                    if list.contains(where: { $0.hasPrefix(term) }) { return 2 }
                    if list.contains(where: { nearly($0, term) }) { return 1 }
                    return 0
                }
                let best = max(hit(name) * 3, hit(aliases) * 2, hit(tags))
                if best == 0 {
                    matched = false
                    break
                }
                score += best
            }
            guard matched else { continue }
            score -= Double(name.count) * 0.1
            if exercise.id == classic { score += 30 }
            if name == terms { score += 20 } else if tokens.aliases.contains(terms) { score += 15 }
            scored.append((exercise, score + boost(exercise), offset))
        }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset }.map(\.exercise)
    }

    /// The exercise a free-text name most likely means ("incline db press", "RDL"). Confident when
    /// it's the canonical lift for that name, or every word matched the exercise's own name or aliases.
    public static func match(_ exercises: [Exercise], _ name: String) -> (exercise: Exercise?, confident: Bool) {
        let terms = words(name).filter { !stopWords.contains($0) }
        guard !terms.isEmpty else { return (nil, false) }
        if let id = canonical[terms.joined(separator: " ")], let classic = exercises.first(where: { $0.id == id }) {
            return (classic, true)
        }
        func covered(_ exercise: Exercise) -> Bool {
            let tokens = SearchTokens.of(exercise)
            let own = tokens.name + tokens.aliasWords
            return terms.allSatisfy { term in own.contains { $0 == term || $0.hasPrefix(term) || nearly($0, term) } }
        }
        // Drop trailing words until something matches: "cable fly high to low" still finds a fly.
        for count in stride(from: terms.count, to: 0, by: -1) {
            if let first = search(exercises, terms.prefix(count).joined(separator: " ")).first {
                return (first, count == terms.count && covered(first))
            }
        }
        return (nil, false)
    }
}

/// An exercise's searchable words, worked out once per bundled exercise rather than on every
/// keystroke: folding, synonyms and stemming are the slow part of a search.
struct SearchTokens: Sendable {
    var name: [String]
    /// Each alias's words, for exact alias matches.
    var aliases: [[String]]
    var aliasWords: [String]
    /// Muscles, equipment and mobility targets.
    var tags: [String]

    init(_ exercise: Exercise) {
        name = ExerciseSearch.words(exercise.name)
        aliases = exercise.aliases.map(ExerciseSearch.words)
        aliasWords = aliases.flatMap { $0 }
        tags =
            exercise.muscles.flatMap { ExerciseSearch.words($0.muscle.label) } + ExerciseSearch.words(exercise.equipment.label)
            + exercise.mobilityTargets.flatMap { ExerciseSearch.words($0.label) }
    }

    static let bundled: [String: SearchTokens] = ExerciseLibrary.byID.mapValues(SearchTokens.init)

    /// The precomputed words for a bundled exercise, or fresh ones for a custom exercise (or one that
    /// shares a bundled id but not its contents).
    static func of(_ exercise: Exercise) -> SearchTokens {
        if let tokens = bundled[exercise.id], ExerciseLibrary.byID[exercise.id] == exercise { return tokens }
        return SearchTokens(exercise)
    }
}
