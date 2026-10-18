import Foundation
import MindEngine
import SystemCore
import SystemStore

@testable import MindTrack

/// A clock a test moves by hand, so every date the model makes is known.
@MainActor
final class TestClock {
    var now: Date

    init(_ now: Date = TestApp.wednesday) { self.now = now }

    func advance(_ seconds: TimeInterval) { now += seconds }
    func advance(days: Int) { now += Double(days) * 86_400 }
}

/// App models for tests: an in-memory store and a shared container and drafts folder in a fresh
/// temporary folder, never the real ones, on a fixed clock.
@MainActor
enum TestApp {
    /// Wednesday 14 October 2026, 10:00 here: a study day in the default split.
    static let wednesday = Day(year: 2026, month: 10, day: 14).date().addingTimeInterval(10 * 3600)

    static func folder() -> URL {
        let url = URL.temporaryDirectory.appending(path: "MindTrackTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func store() -> RecordStore { RecordStore(name: "MindTrack", cloudKitContainer: nil, inMemory: true) }

    /// A shared container no other test or app reads: a fresh folder, never an App Group.
    static func sharedContainer() -> SharedContainer {
        SharedContainer(directory: folder().appending(path: "Shared", directoryHint: .isDirectory))
    }

    static func model(store: RecordStore = store(), shared: SharedContainer = sharedContainer(), clock: TestClock = TestClock())
        -> AppModel
    {
        AppModel(
            store: store, shared: shared, drafts: WritingDrafts(folder: folder().appending(path: "Drafts", directoryHint: .isDirectory)),
            now: { clock.now })
    }

    /// Settings for a person who finished setup `daysAgo` days before the clock, with just the
    /// courses given (Focus).
    static func settings(_ domains: [Domain] = [.maths], onboarded: Date? = nil) -> MindSettings {
        var settings = MindSettings(
            courses: Dictionary(uniqueKeysWithValues: domains.map { ($0, CourseMode.focus) }), onboardedAt: onboarded,
            readsKana: domains.contains(.japanese) ? true : nil, genres: [.fantasy])
        settings.updatedAt = onboarded ?? wednesday
        return settings
    }

    /// An onboarded model with no session running: set up yesterday, as if on another day.
    static func onboardedModel(
        _ domains: [Domain] = [.maths], store: RecordStore = store(), shared: SharedContainer = sharedContainer(),
        clock: TestClock = TestClock()
    ) -> AppModel {
        store.save(settings(domains, onboarded: clock.now.addingTimeInterval(-86_400)))
        return model(store: store, shared: shared, clock: clock)
    }
}

/// A student who answers like the sample one: right except every third question, a few seconds
/// each, on the test's clock.
@MainActor
enum Student {
    /// Answers up to `count` steps of the running session (a lesson read, a question answered and
    /// moved on from, a book picked, a passage read). Returns how many it took.
    @discardableResult
    static func answer(_ model: AppModel, steps count: Int, clock: TestClock) -> Int {
        var taken = 0
        for n in 0..<count {
            guard let run = model.run, let step = run.step else { break }
            clock.advance(6)
            let now = clock.now
            switch step {
            case .lesson: model.act { $0.next(now: now) }
            case .question(let question):
                if run.feedback != nil {
                    model.act { $0.next(now: now) }
                } else if let index = question.correctChoice {
                    let pick = n % 3 == 2 ? (index + 1) % max(1, question.choices.count) : index
                    model.act { $0.choose(pick, now: now) }
                } else if case .number(let value, _) = question.answer {
                    model.act { $0.type(n % 3 == 2 ? "0" : value.description, now: now) }
                }
            case .pickBook(let options):
                if let first = options.first { model.act { $0.pickBook(first, now: now) } } else { model.act { $0.skipPart(now: now) } }
            case .read(let book, let minutes):
                clock.advance(Double(minutes) * 60)
                let later = clock.now
                model.act {
                    $0.finishReading(page: min(book.pages, book.page + 10), finished: false, feel: nil, minutes: Double(minutes), now: later)
                }
            case .reflect: model.act { $0.reflect("A chapter that set things up.", now: now) }
            case .passage(let passage): model.act { $0.respond(.passageRead(seconds: Double(passage.words) / 4), now: now) }
            case .speak(let task):
                if run.feedback != nil {
                    model.act { $0.next(now: now) }
                } else {
                    model.act {
                        $0.respond(
                            task.mode == .say ? .spoken(transcript: task.answer, seconds: 3) : .written(text: task.answer, source: .typed), now: now)
                    }
                }
            case .compose: model.act { $0.respond(.skip, now: now) }
            case .compare: model.act { $0.respond(.picked(0), now: now) }
            }
            taken += 1
        }
        return taken
    }

    /// Steps the running session until a question is on screen, unanswered.
    static func toQuestion(_ model: AppModel, clock: TestClock, limit: Int = 60) -> Question? {
        for _ in 0..<limit {
            guard let run = model.run, let step = run.step else { return nil }
            if case .question(let question) = step, run.feedback == nil { return question }
            answer(model, steps: 1, clock: clock)
        }
        return nil
    }
}
