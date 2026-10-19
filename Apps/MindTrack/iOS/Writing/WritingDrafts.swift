import Foundation
import MindEngine
import OSLog
import PencilKit

/// A piece being written, kept on the device until it's handed in, so ending the session (or iOS
/// closing the app in the background) doesn't lose it. It comes back the next time its task does,
/// which is the next writing session: nothing was handed in for that prompt, so it's still next.
nonisolated struct WritingDraft: Codable, Sendable {
    var text: String
    var handwritten: Bool
    /// The Apple Pencil page not yet read into text.
    var drawing: Data?
    /// A page of your own book read in for the Franklin method.
    var ownPage: String?
}

/// The drafts, one small file each in Application Support, written in order and off the main actor.
/// The app model owns the one every editor shares, so writes to a draft never cross.
actor WritingDrafts {
    nonisolated private static let log = Logger(subsystem: "dev.svindland.stadig.mind", category: "drafts")
    nonisolated static var defaultFolder: URL { URL.applicationSupportDirectory.appending(path: "Writing drafts", directoryHint: .isDirectory) }

    private let folder: URL

    /// `folder`: the default, or a temporary one for tests and UI tests.
    init(folder: URL) {
        self.folder = folder
    }

    /// One draft per task: the exercise and the prompt, passage or notes it works from.
    nonisolated static func key(_ task: WritingTask) -> String {
        let raw = "\(task.exercise.rawValue).\(task.taskID ?? task.id)"
        return String(raw.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? $0 : "_" })
    }

    func draft(_ key: String) -> WritingDraft? {
        let url = file(key)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        do {
            return try JSONDecoder().decode(WritingDraft.self, from: Data(contentsOf: url))
        } catch {
            Self.log.error("Couldn't read a writing draft: \(error.localizedDescription)")
            return nil
        }
    }

    /// Keeps what's written so far; nothing written, nothing kept.
    func save(text: String, handwritten: Bool, drawing: PKDrawing, ownPage: String?, for key: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !drawing.strokes.isEmpty || ownPage != nil else {
            remove(key)
            return
        }
        let draft = WritingDraft(
            text: text, handwritten: handwritten, drawing: drawing.strokes.isEmpty ? nil : drawing.dataRepresentation(),
            ownPage: ownPage)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(draft).write(to: file(key), options: [.atomic, .completeFileProtection])
        } catch {
            Self.log.error("Couldn't keep a writing draft: \(error.localizedDescription)")
        }
    }

    /// A draft kept on the device, with when it was last saved, for the Writing destination's list.
    nonisolated struct Entry: Identifiable, Sendable {
        var key: String
        var draft: WritingDraft
        var saved: Date
        var id: String { key }
        /// The exercise it's for, from its key ("prompt.creative-the-last-shift").
        var exercise: WritingExercise? { WritingExercise(rawValue: String(key.prefix { $0 != "." })) }
    }

    /// Every draft waiting for its task, most recently saved first.
    func all() -> [Entry] {
        let files: [URL]
        do {
            guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { return [] }
            files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
        } catch {
            Self.log.error("Couldn't list the writing drafts: \(error.localizedDescription)")
            return []
        }
        return files.filter { $0.pathExtension == "json" }.compactMap { url -> Entry? in
            let key = url.deletingPathExtension().lastPathComponent
            guard let draft = draft(key) else { return nil }
            let saved = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return Entry(key: key, draft: draft, saved: saved)
        }
        .sorted { ($0.saved, $0.key) > ($1.saved, $1.key) }
    }

    /// Handed in: the piece is kept with the session now.
    func remove(_ key: String) {
        let url = file(key)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Self.log.error("Couldn't remove a writing draft: \(error.localizedDescription)")
        }
    }

    private func file(_ key: String) -> URL { folder.appending(path: key + ".json") }
}
