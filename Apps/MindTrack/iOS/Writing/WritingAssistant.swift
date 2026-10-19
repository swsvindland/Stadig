import Foundation
import MindEngine
import OSLog
import Observation
import SystemAI
import SystemStore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The writing jobs that use the platform: spelling from the system dictionary, notes on a piece
/// and a blind second opinion from Apple Intelligence through SystemAI. Notes are a heavy job
/// (Private Cloud Compute when it's allowed). Each can finish after the session it started in,
/// and lands on the running session or the saved record, whichever has the piece. Nothing waits
/// on any of it.
@MainActor @Observable
final class WritingAssistant {
    static let shared = WritingAssistant()

    enum Notes: Equatable {
        case working
        case ready([String])
        case failed(String)
    }

    enum Opinion: Equatable {
        case working
        /// Whether the AI picked the newer piece; nil when its two answers disagreed.
        case picked(Bool?)
        case failed(String)
    }

    private(set) var notes: [UUID: Notes] = [:]
    private(set) var opinions: [String: Opinion] = [:]

    // MARK: Spelling

    /// Words the system dictionary doesn't know under British or American English. A word fine in
    /// either counts as spelt right, so "colour" and "color" are both fine. iPhone, iPad and Vision Pro
    /// ask UIKit's checker; the Mac asks its own spelling checker, the one its text views use.
    static func misspelled(_ text: String) -> [String] {
        let languages = spellingLanguages
        guard let first = languages.first else { return [] }
        let whole = NSRange(location: 0, length: (text as NSString).length)
        var found: Set<String> = []
        var location = 0
        while location < whole.length {
            let range = misspelling(in: text, from: location, language: first)
            guard range.location != NSNotFound, range.length > 0 else { break }
            let word = (text as NSString).substring(with: range)
            let known = languages.dropFirst().contains { misspelling(in: word, from: 0, language: $0).location == NSNotFound }
            if !known { found.insert(word) }
            location = range.location + range.length
        }
        return found.sorted()
    }

    #if os(macOS)
    /// The Mac names its English dictionaries "en_GB" and "en" (American), or "en_US" on some setups.
    private static var spellingLanguages: [String] {
        let available = Set(NSSpellChecker.shared.availableLanguages)
        var languages = ["en_GB"].filter(available.contains)
        if let american = ["en_US", "en"].first(where: available.contains) { languages.append(american) }
        return languages
    }

    private static func misspelling(in text: String, from location: Int, language: String) -> NSRange {
        NSSpellChecker.shared.checkSpelling(
            of: text, startingAt: location, language: language, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
    }
    #else
    private static var spellingLanguages: [String] { ["en_GB", "en_US"].filter(UITextChecker.availableLanguages.contains) }
    private static let checker = UITextChecker()

    private static func misspelling(in text: String, from location: Int, language: String) -> NSRange {
        checker.rangeOfMisspelledWord(
            in: text, range: NSRange(location: 0, length: (text as NSString).length), startingAt: location, wrap: false,
            language: language)
    }
    #endif

    static func slips(_ text: String) -> [WritingSlip] { WritingCheck.slips(text, misspelled: misspelled(text)) }

    // MARK: Notes on a piece

    func state(for piece: WritingPiece) -> Notes? {
        if let feedback = piece.feedback { return .ready(piece.feedbackItems.isEmpty ? [feedback] : piece.feedbackItems) }
        return notes[piece.id]
    }

    /// Asks for two or three notes on a piece, unless they're on their way or already given.
    func requestNotes(for piece: WritingPiece, source: String?, model: AppModel, again: Bool = false) {
        guard piece.exercise.composes, !piece.text.isEmpty, piece.feedback == nil else { return }
        if !again, notes[piece.id] != nil { return }
        notes[piece.id] = .working
        let instructions = WritingCoach.instructions(for: piece.exercise)
        let prompt = WritingCoach.prompt(piece, source: source, slips: Self.slips(piece.text))
        let ai = model.ai
        Task {
            do {
                let reply = try await ai.respond(instructions: instructions, prompt: prompt, weight: .heavy, maxTokens: 500)
                let items = WritingCoach.notes(from: reply)
                guard !items.isEmpty else {
                    notes[piece.id] = .failed("No usable notes came back this time.")
                    return
                }
                notes[piece.id] = .ready(items)
                save(items.joined(separator: "\n"), to: piece.id, model: model)
            } catch let error as AIError {
                notes[piece.id] = .failed(error.message)
            } catch {
                notes[piece.id] = .failed("Notes couldn't be made just now.")
            }
        }
    }

    private func save(_ feedback: String, to id: UUID, model: AppModel) {
        if model.run?.piece(id) != nil {
            model.act { $0.attachFeedback(feedback, to: id) }
        } else if var piece = model.pieces.last(where: { $0.id == id }) {
            piece.feedback = feedback
            model.save(piece: piece)
        }
    }

    // MARK: The blind second opinion

    /// Asks the AI to judge the pair blind, in both orders, as soon as it's shown. The answer is
    /// kept back until the person has picked.
    func requestOpinion(on pair: BlindPair, model: AppModel) {
        guard opinions[pair.id] == nil else { return }
        opinions[pair.id] = .working
        let ai = model.ai
        Task {
            do {
                let shown = try await ai.respond(
                    instructions: WritingCoach.comparisonInstructions,
                    prompt: WritingCoach.comparisonPrompt(pair, swapped: false), weight: .heavy, maxTokens: 200)
                let swapped = try await ai.respond(
                    instructions: WritingCoach.comparisonInstructions,
                    prompt: WritingCoach.comparisonPrompt(pair, swapped: true), weight: .heavy, maxTokens: 200)
                let picked = WritingCoach.secondOpinion(pair, shown: WritingCoach.pick(from: shown), swapped: WritingCoach.pick(from: swapped))
                appLog.info("Blind second opinion: \(picked.map { $0 ? "newer" : "older" } ?? "no clear pick", privacy: .public)")
                opinions[pair.id] = .picked(picked)
                if let picked { record(picked, pair: pair, model: model) }
            } catch let error as AIError {
                appLog.error("Blind second opinion failed: \(error.message, privacy: .public)")
                opinions[pair.id] = .failed(error.message)
            } catch {
                opinions[pair.id] = .failed("No second opinion this time.")
            }
        }
    }

    /// Puts the AI's pick on the comparison, once the person's pick has made one. It's saved
    /// straight away, since a session saves each comparison once, when it's first picked.
    func record(_ pickedNewer: Bool, pair: BlindPair, model: AppModel) {
        let older = pair.older.id
        let newer = pair.newer.id
        if model.run?.newComparisons.contains(where: { $0.older == older && $0.newer == newer }) == true {
            model.act { $0.attachSecondOpinion(pickedNewer, older: older, newer: newer) }
        }
        if var comparison = model.comparisons.last(where: { $0.older == older && $0.newer == newer }), comparison.aiPickedNewer == nil {
            comparison.aiPickedNewer = pickedNewer
            model.save(comparison: comparison)
        }
    }
}

extension AppModel {
    /// A comparison changed after its session: the AI's second opinion arriving late.
    func save(comparison: BlindComparison) {
        var comparison = comparison
        comparison.updatedAt = now()
        store.save(comparison)
        reload()
    }

    /// The source a piece worked from: the text rewritten, the scene, or the Franklin original.
    func source(of piece: WritingPiece) -> String? {
        let library = catalogs.writing.library
        guard let id = piece.taskID else { return nil }
        if let prompt = library.prompt(id) { return prompt.source }
        if let passage = library.passage(String(id.split(separator: "#").first ?? "")) { return passage.text }
        if piece.exercise == .franklinRewrite {
            return pieces.last { $0.exercise == .franklinNotes && $0.taskID == id }?.original
        }
        return piece.original
    }
}
