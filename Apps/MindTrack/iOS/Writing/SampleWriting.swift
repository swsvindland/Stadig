#if DEBUG
import Foundation
import SwiftUI
import MindEngine
import SystemCore
import SystemStore

/// Pieces for the sample student: plain and slip-prone in the first weeks, more varied and
/// cleaner later, so the trends and blind comparisons have something real to show. Franklin notes
/// and rewrites are made from the passage itself.
enum SampleWriting {
    /// What the platform's spell checker would flag in these.
    static let misspelled = ["recieved"]

    static func text(for task: WritingTask, week: Int) -> String {
        let later = week >= 4
        let base: String
        switch task.exercise {
        case .franklinNotes:
            return notes(task.source ?? "")
        case .franklinRewrite:
            base = rewrite(task.source ?? creative[0])
        case .practical:
            base = later ? practical[1] : practical[0]
        case .argument:
            base = later ? argument[1] : argument[0]
        case .benchmark where task.writingKind == .practical:
            base = later ? practical[1] : practical[0]
        case .benchmark where task.writingKind == .argument:
            base = later ? argument[1] : argument[0]
        default:
            base = later ? creative[1] : creative[0]
        }
        return slips(base, count: max(0, 3 - week / 3))
    }

    /// Up to `count` of the usual slips, in place of the right forms.
    static func slips(_ text: String, count: Int) -> String {
        var out = text
        for (right, wrong) in [("would have", "would of"), ("received", "recieved"), ("a lot", "alot")].prefix(count) {
            if let range = out.range(of: right) { out.replaceSubrange(range, with: wrong) }
        }
        return out
    }

    static func sentences(_ text: String) -> [String] {
        var flat = text.replacingOccurrences(of: "\n", with: " ")
        for title in ["Mr.", "Mrs.", "Dr.", "St."] { flat = flat.replacingOccurrences(of: title, with: String(title.dropLast())) }
        return flat.components(separatedBy: ". ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// A few words for each sentence's point.
    static func notes(_ passage: String) -> String {
        sentences(passage).prefix(8).map { sentence in
            sentence.split(separator: " ").prefix(4).joined(separator: " ").lowercased().trimmingCharacters(in: .punctuationCharacters)
        }.joined(separator: "; ")
    }

    /// The passage as someone might rebuild it from notes: each sentence's first clause.
    static func rewrite(_ passage: String) -> String {
        sentences(passage).map { sentence in
            let clause = sentence.split(separator: ",").first.map(String.init) ?? sentence
            return clause.trimmingCharacters(in: CharacterSet(charactersIn: ".;: ")) + "."
        }.joined(separator: " ")
    }

    static let creative = [
        """
        The café was closing for good. The owner stacked the chairs by the window. One man was still drinking his tea. He had come \
        every morning for years. The owner did not want to rush him. She wiped the counter again and again. The radio played an old \
        song. The man finally stood up and put on his coat. He said he would have come back tomorrow. She said there would be no \
        tomorrow. They both laughed at that. He had received a card from her that morning and a lot of thanks. Then he left and \
        she turned off the lights.
        """,
        """
        By nine the café was empty except for Mr Hale and his tea. Marta stacked the chairs around him, one table at a time, the way \
        you might tidy around a sleeping cat. She didn’t hurry him. Thirty years of mornings had earned him that.

        The radio found an old song, and he hummed the chorus, badly. When he finally stood, he left a coin on the saucer as he \
        always had, though they both knew it would have bought nothing tomorrow. He had received her card that morning and said \
        nothing about it. “Same time?” he said. She laughed, and a lot of what she had meant to say went unsaid.

        Outside, the street shone. Then the lights went out behind him, all at once.
        """,
    ]

    static let practical = [
        """
        Hi Dana, I hope you had a good weekend. I wanted to give you an update on the project and where things are. The team has \
        been working hard on the pages and we have received a lot of good feedback. There was a problem with payment testing which \
        took longer than planned. Because of that the launch will move from the 7th to the 14th. We would have told you sooner. We \
        need you to approve the new date. Please could you let us know by Thursday. Thanks, Sam
        """,
        """
        Hi Dana,

        The launch is moving from the 7th to the 14th. Could you approve the new date by Thursday, so we can confirm it with the \
        payment provider?

        Payment testing took a week longer than planned, because the provider’s test system was down. Everything else is on \
        schedule, and we’ve received a lot of good feedback on the mobile pages. We would have warned you sooner, but we only heard \
        on Friday.

        If the 14th doesn’t work for you, tell me which dates would, and I’ll see what we can move.

        Thanks,
        Sam
        """,
    ]

    static let argument = [
        """
        I think cities should close their centres to private cars. Cars make the air dirty and the streets loud. People would walk \
        and cycle more. Shops would get more customers on foot. Some people say this is unfair to drivers. But buses and trams can \
        still run. I would have liked this in my city years ago. A lot of cities have done it already and the idea has received \
        support. So I think it is a good idea.
        """,
        """
        City centres should be closed to private cars, and the best evidence is what happened where it was tried. Pontevedra, in \
        Spain, closed its centre to through traffic in 1999, and streets that had been emptying filled again with shops and children. \
        A lot of the road went to cafés, benches and cycle lanes.

        The strongest objection is that a ban punishes people who can’t walk or cycle far: older people, disabled people, \
        tradespeople with tools. It would, if the ban were absolute. It needn’t be. Permits for blue-badge holders and deliveries, \
        with buses and trams running through, keep the centre open to everyone who needs to reach it.

        Drivers would have lost a shortcut. The city would have received its streets back.
        """,
    ]
}

extension AppModel {
    /// Sample comparisons, saved alongside the rest of the sample data. `-samplePair` adds an early
    /// short piece too, so a forced check-in (`-checkIn writing`) has an older and a newer one to compare.
    func seedWriting(comparisons: [BlindComparison]) {
        store.save(comparisons)
        if ProcessInfo.processInfo.arguments.contains("-samplePair"), let first = sessions.first {
            let text = SampleWriting.slips(SampleWriting.creative[0], count: 3)
            store.save(WritingPiece(date: first.start.addingTimeInterval(3 * 86_400), exercise: .prompt, writingKind: .creative,
                                    prompt: "It’s the last shift before the corner café closes for good. Write about three paragraphs.",
                                    text: text, metrics: WritingCheck.measure(text, misspelled: SampleWriting.misspelled).dictionary,
                                    taskID: "creative-the-last-shift"))
        }
        reload()
    }

    /// A check-in now, whatever the calendar says (`-checkIn`), to see the benchmark and the blind
    /// comparisons without waiting for a review week.
    func debugCheckIn(_ domains: [Domain]) {
        guard let state else { return }
        run = StudyRun(plan: SessionPlanner.plan(.checkIn, domains: domains, state: state, catalogs: catalogs), state: state, catalogs: catalogs,
                       now: Date())
    }
}
#endif

#if DEBUG
/// `-writingScreen plan|progress|pieces|piece` opens a writing card or list full screen from the
/// Progress tab, to see all of it without scrolling.
struct WritingDebugScreen: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var screen: String?
    /// Once only: the card inside the cover has this modifier too.
    @MainActor static var opened = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !Self.opened else { return }
                Self.opened = true
                let arguments = ProcessInfo.processInfo.arguments
                if let i = arguments.firstIndex(of: "-writingScreen"), arguments.indices.contains(i + 1) { screen = arguments[i + 1] }
            }
            .fullScreenCover(item: Binding(get: { screen.map(Screen.init) }, set: { screen = $0?.id })) { screen in
                NavigationStack {
                    Group {
                        switch screen.id {
                        case "pieces": PiecesList()
                        case "piece": PieceDetail(id: model.pieces.last { !$0.text.isEmpty }?.id ?? UUID())
                        default:
                            ScrollView {
                                if let analysis = model.analysis, let state = model.state {
                                    Group {
                                        if screen.id == "plan" { WritingPlanCard(analysis: analysis, state: state) }
                                        else { WritingProgressCard(analysis: analysis, state: state) }
                                    }
                                    .padding()
                                    .readableWidth()
                                }
                            }
                            .background(.pageBackground)
                        }
                    }
                    .toolbar { Button("Close") { self.screen = nil } }
                }
            }
    }

    struct Screen: Identifiable {
        var id: String
    }
}
#endif
