import Foundation
import SystemCore

/// What a subject brings to the shared engine: the parts it plans, the runners that run them, the
/// questions for its review cards and the honest measure behind its score. Every course maps to
/// one module; each module lives in its subject's folder.
protocol SubjectModule {
    /// Whether a course still needs its placement before new material.
    static func needsPlacement(_ domain: Domain, state: StudyState, catalogs: Catalogs) -> Bool
    /// The placement parts for a course: its first block.
    static func placementParts(_ domain: Domain, state: StudyState, catalogs: Catalogs) -> [PlanPart]
    /// Whether the placement cards what it finds known, so a Maintenance course with nothing
    /// learned yet has reviews once it's placed. A test that only measures gives it nothing.
    static var placementCardsKnown: Bool { get }
    /// A block's main part, after its warm-up: new material in a regular week, practice in a review
    /// week.
    static func mainParts(
        _ domain: Domain, minutes: Int, kind: StudyKind, state: StudyState, catalogs: Catalogs,
        notes: inout [String]
    ) -> [PlanPart]
    /// The plain tests at a check-in.
    static func checkInParts(_ domain: Domain, state: StudyState, catalogs: Catalogs) -> [PlanPart]
    /// The runner for one of this subject's parts.
    static func runner(for part: PlanPart, state: StudyState, catalogs: Catalogs) -> (any PartRunner)?
    /// A question for a review card of this subject.
    static func question(for key: CardKey, kind: AttemptKind, run: StudyRun) -> Question?
    /// Whether a card can be asked about (its catalog is installed, its item still exists).
    static func usable(_ key: CardKey, catalogs: Catalogs) -> Bool
    /// Seconds a review usually takes.
    static func reviewSeconds(_ card: MemoryCard) -> Double
    /// The course's 0–100 reading from its tests, oldest first. Only tests and real outcomes.
    static func series(_ domain: Domain, state: StudyState) -> [(day: Day, score: Double)]
    /// The last `count` points of `series`, for a trend. A subject whose series is costly to work
    /// out computes only those.
    static func recent(_ domain: Domain, state: StudyState, count: Int) -> [(day: Day, score: Double)]
    /// A few words for the stat card: "Japanese ~1,400 words".
    static func label(_ domain: Domain, state: StudyState) -> String
}

extension SubjectModule {
    static var placementCardsKnown: Bool { false }

    static func recent(_ domain: Domain, state: StudyState, count: Int) -> [(day: Day, score: Double)] {
        Array(series(domain, state: state).suffix(count))
    }
}

enum Subjects {
    static func module(_ domain: Domain) -> any SubjectModule.Type {
        switch domain {
        case .japanese, .spanish: LanguageModule.self
        case .maths: MathsModule.self
        case .writing: WritingModule.self
        case .reading: ReadingModule.self
        }
    }

    /// The runner for any part: reviews and practice are shared, the rest belong to a subject.
    static func runner(for part: PlanPart, state: StudyState, catalogs: Catalogs) -> any PartRunner {
        switch part.kind {
        case .reviews:
            // A block keeps to its own course's reviews; without a course they're across every one.
            let due = part.domain.map { state.due(on: state.today, catalogs: catalogs, in: $0) } ?? state.due(on: state.today, catalogs: catalogs)
            // Most forgotten first; ties in key order, so a session is the same on every run.
            func retrievability(_ card: MemoryCard) -> Double {
                card.memory.map { Scheduler.retrievability($0, at: state.today.date()) } ?? 0
            }
            return ReviewsRunner(queue: due.sorted { (retrievability($0), $0.key) < (retrievability($1), $1.key) }.map(\.key))
        case .practice:
            // Review week: the soonest-due cards of the course, reviewed ahead of schedule. As with
            // extra practice, a card answered today (in an earlier session) keeps its schedule.
            guard let domain = part.domain else { return EmptyRunner() }
            let ahead = state.cards.values.filter { card in
                guard card.domain == domain, let memory = card.memory else { return false }
                return state.day(memory.lastReview) != state.today && !card.isDue(on: state.today, dayStart: state.dayStart)
                    && module(domain).usable(card.key, catalogs: catalogs)
            }.sorted { ($0.memory?.due ?? .distantFuture, $0.key) < ($1.memory?.due ?? .distantFuture, $1.key) }
            return ReviewsRunner(queue: Array(ahead.prefix(60)).map(\.key))
        default:
            guard let domain = part.domain else { return EmptyRunner() }
            return module(domain).runner(for: part, state: state, catalogs: catalogs) ?? EmptyRunner()
        }
    }
}
