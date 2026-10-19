import Foundation
import MindEngine
import PencilKit
import SystemCore
import SystemStore
import Testing

@testable import MindTrack

/// What the iPad, the Mac and Vision Pro add: the sidebar's destinations, the menu bar's study
/// commands, the drafts Writing lists, and the cards' revision the words table rebuilds on.
@MainActor
struct DesktopTests {
    @Test func theIPhoneTabBarKeepsItsThreeTabs() {
        #expect(AppTab.allCases.filter(\.inTabBar) == [.today, .plan, .progress])
        // The Go menu numbers them in this order: ⌘1 is Today, ⌘6 Courses.
        #expect(AppTab.allCases.map(\.title) == ["Today", "Plan", "Progress", "Shelf", "Writing", "Courses"])
    }

    @Test func studyAnywayBringsMathsItsWritingSegment() {
        let both = TestApp.settings([.maths, .writing])
        #expect(MindCommands.session(of: .maths, settings: both) == [.maths, .writing])
        #expect(MindCommands.session(of: .writing, settings: both) == [.writing])
        #expect(MindCommands.session(of: .maths, settings: TestApp.settings([.maths])) == [.maths])
    }

    @Test func draftsAreListedNewestFirstWithTheirExercise() async throws {
        let drafts = WritingDrafts(folder: TestApp.folder().appending(path: "Drafts", directoryHint: .isDirectory))
        #expect(await drafts.all().isEmpty, "no folder yet, no drafts")
        await drafts.save(text: "First go", handwritten: false, drawing: PKDrawing(), ownPage: nil, for: "prompt.creative-the-last-shift")
        try await Task.sleep(for: .milliseconds(1100))
        await drafts.save(text: "Notes so far", handwritten: true, drawing: PKDrawing(), ownPage: nil, for: "franklinNotes.austen-1")
        let all = await drafts.all()
        #expect(all.map(\.key) == ["franklinNotes.austen-1", "prompt.creative-the-last-shift"])
        #expect(all.map(\.exercise) == [.franklinNotes, .prompt])
        #expect(all.first?.draft.handwritten == true)

        await drafts.remove("franklinNotes.austen-1")
        #expect(await drafts.all().map(\.key) == ["prompt.creative-the-last-shift"], "handed in, it leaves the list")
    }

    @Test func theCardsRevisionMovesWhenCardsAreReadAgain() {
        let clock = TestClock()
        let model = TestApp.onboardedModel(clock: clock)
        let before = model.cardsRevision
        model.reload()
        #expect(model.cardsRevision == before, "nothing new, nothing to rebuild")
        // A card saved, as a session or another device saves one: the words table rebuilds.
        model.store.save(MemoryCard(key: .word(1_001), introduced: clock.now))
        model.reload()
        #expect(model.cardsRevision == before + 1)
        #expect(model.cards.contains { $0.key == .word(1_001) })
    }
}
