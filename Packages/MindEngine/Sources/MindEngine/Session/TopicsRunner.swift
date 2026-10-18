import Foundation
import SystemCore

/// Mastery learning for maths topics and writing skills: a short lesson, then problems until four
/// of the last five are right, then the next one. Topics at or below the placement level get a
/// quick check first and skip the lesson when both answers are right.
struct TopicsRunner: PartRunner {
    let domain: Domain
    /// The maths strand to learn in; nil for writing.
    let strand: MathsStrand?
    var current: String?
    var probing = false
    var probeRight = 0
    var needsLesson = false
    var visit = 0
    var done: Set<String> = []

    init(domain: Domain, strand: MathsStrand? = nil) {
        self.domain = domain
        self.strand = strand
    }

    func key(_ id: String) -> CardKey { domain == .maths ? .topic(id) : .skill(id) }

    func lesson(_ id: String, run: StudyRun) -> Lesson? {
        if domain == .maths, let topic = MathCurriculum.topic(id) { return .topic(topic.info, example: topic.problem(seed: "lesson")) }
        return run.catalogs.writing.skill(id).map(Lesson.skill)
    }

    func nextCandidate(_ run: StudyRun) -> String? {
        if domain == .maths {
            return (MathsPlan.inProgress(run.cards, strand: strand) + MathsPlan.frontier(run.cards, strand: strand)).map(\.id).first { !done.contains($0) }
        }
        let learning = run.cards.values.filter { $0.domain == .writing && $0.learning }.sorted { ($0.introduced, $0.key) < ($1.introduced, $1.key) }
            .map(\.key.item)
        let started = Set(run.cards.values.filter { $0.domain == .writing }.map(\.key.item))
        let fresh = run.catalogs.writing.skills.filter { !started.contains($0.id) }.sorted { $0.level < $1.level }.map(\.id)
        return (learning + fresh).first { !done.contains($0) }
    }

    mutating func next(_ run: inout StudyRun) -> StudyRun.Step? {
        if current == nil {
            guard run.partSeconds < run.budget * 0.8, let id = nextCandidate(run) else { return nil }
            current = id
            visit = 0
            probeRight = 0
            let placed = MathsPlan.placedLevel(run.cards, strand: MathCurriculum.topic(id)?.strand ?? .classic)
            let level = MathCurriculum.topic(id)?.level ?? 99
            probing = domain == .maths && run.cards[key(id)] == nil && level <= placed
            if !probing {
                var card = run.cards[key(id)] ?? MemoryCard(key: key(id), introduced: run.now)
                card.recent = []
                card.updatedAt = run.now
                run.save(card)
                needsLesson = true
            }
        }
        guard let id = current else { return nil }
        if needsLesson {
            needsLesson = false
            if let lesson = lesson(id, run: run) { return .lesson(lesson) }
        }
        guard run.partSeconds < run.budget * 1.3 else {
            current = nil
            return nil
        }
        let kind: AttemptKind = probing ? .probe : .learn
        if domain == .maths {
            return MathCurriculum.topic(id).map {
                .question($0.problem(seed: run.seed, data: run.catalogs.systemData).question(kind: kind, id: "\(id).\(run.seed)"))
            }
        }
        let bank = run.catalogs.writing
        return bank.item(for: id, seen: run.asked, seed: run.today.iso).map { .question(bank.question($0, kind: kind, seed: run.seed)) }
    }

    mutating func record(_ question: Question, correct: Bool, _ run: inout StudyRun) {
        guard let id = current else { return }
        let key = key(id)
        visit += 1
        if probing {
            if correct {
                probeRight += 1
                if probeRight >= 2 {
                    run.graduate(key, memory: Scheduler.known(stability: 10, at: run.now), knownBefore: true)
                    done.insert(id)
                    current = nil
                }
            } else {
                // Not known after all: teach it.
                probing = false
                needsLesson = true
                run.save(MemoryCard(key: key, recent: [false], introduced: run.now, updatedAt: run.now))
            }
            return
        }
        guard var card = run.cards[key] else { return }
        card.recent = Array((card.recent + [correct]).suffix(10))
        card.updatedAt = run.now
        run.save(card)
        if Mastery.mastered(card.recent) {
            run.graduate(key, memory: Scheduler.first(Mastery.grade(card.recent), at: run.now))
            done.insert(id)
            current = nil
        } else if Mastery.struggling(card.recent) || visit >= Mastery.maximumPerVisit {
            // Set aside for today: the worked solutions have been shown, and it comes back next time.
            done.insert(id)
            current = nil
        }
    }
}
