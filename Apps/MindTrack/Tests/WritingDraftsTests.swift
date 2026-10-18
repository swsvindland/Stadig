import Foundation
import PencilKit
import Testing

@testable import MindTrack

/// A piece being written is kept on the device until it's handed in, and nothing written keeps
/// nothing.
@MainActor
struct WritingDraftsTests {
    let key = "prompt.creative-the-last-shift"

    func drafts() -> WritingDrafts { WritingDrafts(folder: TestApp.folder().appending(path: "Drafts", directoryHint: .isDirectory)) }

    @Test func aDraftComesBackUntilItsHandedIn() async throws {
        let drafts = drafts()
        #expect(await drafts.draft(key) == nil)
        await drafts.save(text: "The café’s last night.", handwritten: true, drawing: PKDrawing(), ownPage: "A page of my own", for: key)

        let draft = try #require(await drafts.draft(key))
        #expect(draft.text == "The café’s last night.")
        #expect(draft.handwritten)
        #expect(draft.ownPage == "A page of my own")
        #expect(draft.drawing == nil, "no strokes, no drawing kept")
        #expect(await drafts.draft("prompt.another-task") == nil, "one draft per task")

        await drafts.remove(key)
        #expect(await drafts.draft(key) == nil)
    }

    @Test func clearingThePieceClearsTheDraft() async {
        let drafts = drafts()
        await drafts.save(text: "A first line", handwritten: false, drawing: PKDrawing(), ownPage: nil, for: key)
        await drafts.save(text: "  \n ", handwritten: false, drawing: PKDrawing(), ownPage: nil, for: key)
        #expect(await drafts.draft(key) == nil, "an empty editor doesn't keep an empty draft")
    }
}
