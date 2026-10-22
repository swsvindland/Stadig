import Foundation
import SystemCore

/// New words (and kana): taught, asked a couple of items later, asked again a different way, then
/// graduated. Words below the placement level get a quick check instead of a lesson.
struct LearnRunner: PartRunner {
    struct Task: Sendable {
        enum Stage: Sendable { case teach, probe, first, second }
        var item: LanguagePlan.NewItem
        var stage: Stage
        var notBefore: Int
    }

    let language: Language
    /// New items the part asks for.
    let count: Int
    /// Chosen when the part starts, not when the run is built, so a vocabulary placement earlier
    /// in the same session decides what's checked and what's taught.
    var fresh: [LanguagePlan.NewItem]?
    var tasks: [Task] = []
    var wrong: [CardKey: Int] = [:]
    var tick = 0
    var current: Int?

    init(language: Language, count: Int) {
        self.language = language
        self.count = count
    }

    mutating func next(_ run: inout StudyRun) -> StudyRun.Step? {
        tick += 1
        if fresh == nil {
            fresh =
                run.catalogs.deck(language).map {
                    LanguagePlan.next(
                        count: count, cards: Set(run.cards.keys), deck: $0, readsKana: run.settings.readsKana,
                        frontier: run.frontier(language))
                } ?? []
        }
        // A new item joins while fewer than four are in flight and there's time for it.
        let ready = tasks.indices.filter { tasks[$0].notBefore <= tick }
        if ready.isEmpty, let item = fresh?.first, tasks.count < 4, run.partSeconds < run.budget * 0.8 {
            fresh?.removeFirst()
            let probe = if case .probe = item { true } else { false }
            tasks.append(Task(item: item, stage: probe ? .probe : .teach, notBefore: tick))
        }
        let index =
            tasks.indices.filter { tasks[$0].notBefore <= tick }.first
            ?? (run.partSeconds < run.budget * 1.4 ? tasks.indices.min { tasks[$0].notBefore < tasks[$1].notBefore } : nil)
        guard let index else { return nil }
        let task = tasks[index]
        current = index
        switch task.stage {
        case .teach:
            tasks[index].stage = .first
            tasks[index].notBefore = tick + 2
            return .lesson(lesson(for: task.item, run: run))
        case .probe, .first, .second:
            return question(for: task, run: run).map(StudyRun.Step.question)
        }
    }

    func lesson(for item: LanguagePlan.NewItem, run: StudyRun) -> Lesson {
        switch item {
        case .kana(let kana): return .kana(kana)
        case .teach(let word), .probe(let word):
            let deck = run.catalogs.deck(language)
            let example = deck?.sentences(with: word.id, maxLevel: max(run.frontier(language), word.rank + 200), limit: 1).first
            return .word(word, kanji: deck?.kanji(in: word) ?? [], example: example)
        }
    }

    func question(for task: Task, run: StudyRun) -> Question? {
        // A retry after a miss, and the first ask after a failed check, get other choices in
        // another order, so they can't be passed by remembering where the right one was.
        let seed = "learn.\(run.today.iso).\(task.stage).\(wrong[task.item.key, default: 0])"
        switch task.item {
        case .kana(let kana):
            let introduced = KanaTable.all.filter { run.cards[$0.key] != nil || $0.group == kana.group }
            return LanguageQuiz.question(kana, reps: task.stage == .second ? 1 : 0, kind: .learn, introduced: introduced, seed: seed)
        case .teach(let word), .probe(let word):
            guard let deck = run.catalogs.deck(language) else { return nil }
            let reading = word.hasKanji && LanguagePlan.asksReading(run.settings) { run.cards[$0] != nil }
            let ask: LanguageQuiz.WordAsk = task.stage == .second ? (reading ? .reading : .listening) : .meaning
            return LanguageQuiz.question(
                word, ask: ask, kind: task.stage == .probe ? .probe : .learn, deck: deck, seed: seed,
                help: run.scaffold(word))
        }
    }

    mutating func record(_ question: Question, correct: Bool, _ run: inout StudyRun) {
        guard let index = current, tasks.indices.contains(index), tasks[index].item.key == question.key else { return }
        let key = question.key
        switch tasks[index].stage {
        case .probe:
            if correct {
                // Known already: back for a check in about a week.
                run.graduate(key, memory: Scheduler.known(stability: 7, at: run.now), knownBefore: true)
                tasks.remove(at: index)
            } else {
                tasks[index].stage = .teach
                tasks[index].notBefore = tick
            }
        case .first:
            if correct {
                tasks[index].stage = .second
                tasks[index].notBefore = tick + 3
            } else {
                wrong[key, default: 0] += 1
                tasks[index].notBefore = tick + 2
            }
        case .second:
            if correct {
                run.graduate(key, memory: Scheduler.first(wrong[key, default: 0] == 0 ? .good : .hard, at: run.now))
                tasks.remove(at: index)
            } else {
                wrong[key, default: 0] += 1
                tasks[index].notBefore = tick + 2
            }
        case .teach:
            break
        }
        current = nil
    }

    mutating func finish(_ run: inout StudyRun) {
        // Taught but not yet shown to stick: back tomorrow.
        for task in tasks where task.stage == .first || task.stage == .second {
            run.graduate(task.item.key, memory: Scheduler.first(.again, at: run.now))
        }
        tasks = []
    }
}

/// The vocabulary test: five words from each frequency band. A placement stops once a band is
/// mostly unknown; a check-in covers every band but stops after two almost all unknown.
struct VocabularyRunner: PartRunner {
    let language: Language
    var band = 0
    var queue: [Question]
    var placement: Bool

    mutating func next(_ run: inout StudyRun) -> StudyRun.Step? {
        guard let deck = run.catalogs.deck(language) else { return nil }
        if queue.isEmpty {
            let attempts = run.partAttempts.filter { $0.test == .vocabulary }
            let goOn: Bool
            if placement {
                goOn = LanguageTests.continuePlacement(after: band, attempts: attempts, deck: deck)
            } else {
                let last = LanguageTests.known(attempts.filter { $0.band == band })
                let before = band > 0 ? LanguageTests.known(attempts.filter { $0.band == band - 1 }) : 1
                goOn = band + 1 < LanguageTests.bandsAvailable(in: deck) && !(last < 0.2 && before < 0.2)
            }
            guard goOn else { return nil }
            band += 1
            queue = LanguageTests.vocabulary(band: band, deck: deck, seed: placement ? "placement" : run.today.iso)
        }
        guard !queue.isEmpty else { return nil }
        return .question(queue.removeFirst())
    }

    mutating func finish(_ run: inout StudyRun) {
        let tested = run.partAttempts.filter { $0.test == .vocabulary }
        // It takes at least a whole band to say anything.
        guard tested.count >= LanguageTests.wordsPerBand else { return }
        run.newTests.append(LanguageTests.result(tested, date: run.now, placement: placement, language: language))
    }
}
