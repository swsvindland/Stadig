import Foundation
import SystemCore

/// A book to read in a language, from graded readers to native fiction. Readers join the shelf as
/// ordinary books with their language set and their level as the tier, so each language has its
/// own reading level beside the English ladder's (English tier 5, Spanish level 1).
public struct GradedReader: Hashable, Sendable, Identifiable {
    public var id: String
    public var language: Language
    /// 1 is a first reader (a few hundred words), 6 native fiction.
    public var level: Int
    public var title: String
    public var author: String
    /// About this many pages.
    public var pages: Int
    public var about: String
    /// Where to read it free, when it's free.
    public var free: URL?

    public func book(status: BookStatus, started: Day? = nil) -> Book {
        Book(
            ladderID: id, title: title, author: author, tier: level, pages: pages, genres: [], status: status, started: started,
            language: language)
    }
}

/// The readers, and each language's reading level: the highest level finished without it feeling
/// like a slog, as the English ladder does it. Before any is finished, the vocabulary test says
/// where to start.
public enum GradedReaders {
    public static let levels = 1...6

    public static func label(_ level: Int) -> String {
        switch level {
        case 1: "First readers"
        case 2: "Easy readers"
        case 3: "Intermediate readers"
        case 4: "Young adult and easy fiction"
        case 5: "Adult fiction"
        default: "Literary fiction"
        }
    }

    public static func readers(_ language: Language) -> [GradedReader] { all.filter { $0.language == language } }

    public static func reader(_ id: String) -> GradedReader? { all.first { $0.id == id } }

    /// The books on the shelf in a language.
    public static func shelf(_ language: Language, books: [Book]) -> [Book] { books.filter { $0.language == language } }

    public static func current(_ language: Language, books: [Book]) -> Book? {
        shelf(language, books: books).filter { $0.status == .reading }.max { $0.updatedAt < $1.updatedAt }
    }

    /// The highest level finished without it feeling hard. Nil before one is finished.
    public static func comfortLevel(_ language: Language, books: [Book]) -> Int? {
        shelf(language, books: books).filter { $0.done && $0.feel != .hard }.map(\.tier).max()
    }

    /// Where a vocabulary says to start.
    public static func startingLevel(words: Int?) -> Int {
        switch words ?? 0 {
        case ..<600: 1
        case ..<1200: 2
        case ..<2500: 3
        case ..<5000: 4
        case ..<8000: 5
        default: 6
        }
    }

    /// The level to read next: one above comfort, or the same again after a slog or a book put
    /// down; from the vocabulary before any is finished.
    public static func targetLevel(_ language: Language, books: [Book], words: Int?) -> Int {
        let shelf = shelf(language, books: books)
        guard let comfort = comfortLevel(language, books: books) else {
            if let hard = shelf.filter({ $0.done || $0.status == .abandoned }).map(\.tier).min() { return max(1, hard - 1) }
            return startingLevel(words: words)
        }
        let recent = shelf.filter { $0.done || $0.status == .abandoned }.max {
            ($0.finished ?? .init(year: 2000, month: 1, day: 1)) < ($1.finished ?? .init(year: 2000, month: 1, day: 1))
        }
        if let recent, recent.status == .abandoned || recent.feel == .hard { return max(1, min(comfort, recent.tier)) }
        return min(levels.upperBound, comfort + 1)
    }

    /// Up to `count` readers at the target level (then beside it), none already on the shelf.
    public static func suggestions(_ language: Language, books: [Book], words: Int?, count: Int = 3) -> [GradedReader] {
        let target = targetLevel(language, books: books, words: words)
        let owned = Set(books.compactMap(\.ladderID))
        return readers(language).filter { !owned.contains($0.id) && abs($0.level - target) <= 1 }
            .sorted { (abs($0.level - target), $0.level > target ? 1 : 0, $0.id) < (abs($1.level - target), $1.level > target ? 1 : 0, $1.id) }
            .prefix(count).map { $0 }
    }

    static func gutenberg(_ number: Int) -> URL? { URL(string: "https://www.gutenberg.org/ebooks/\(number)") }
    static let tadoku = URL(string: "https://tadoku.org/japanese/en/free-books-en/")

    public static let all: [GradedReader] = [
        // Spanish
        GradedReader(
            id: "es.pobre-ana", language: .spanish, level: 1, title: "Pobre Ana", author: "Blaine Ray", pages: 60,
            about: "A first novel in a few hundred words: a teenager who thinks her life is hard."),
        GradedReader(
            id: "es.brandon-brown-perro", language: .spanish, level: 1, title: "Brandon Brown quiere un perro", author: "Carol Gaab",
            pages: 60, about: "A boy who wants a dog, told in the simplest Spanish."),
        GradedReader(
            id: "es.agentes-secretos", language: .spanish, level: 1, title: "Agentes secretos y el mural de Picasso",
            author: "Mira Canion", pages: 70, about: "A short mystery around a stolen painting, in present-tense beginner Spanish."),
        GradedReader(
            id: "es.esperanza", language: .spanish, level: 2, title: "Esperanza", author: "Carol Gaab", pages: 80,
            about: "A family forced to flee Guatemala; a true-to-life story in easy Spanish."),
        GradedReader(
            id: "es.short-stories-beginners", language: .spanish, level: 2, title: "Short Stories in Spanish for Beginners",
            author: "Olly Richards", pages: 250, about: "Eight stories with summaries and word lists after each chapter."),
        GradedReader(
            id: "es.easy-spanish-reader", language: .spanish, level: 2, title: "Easy Spanish Reader", author: "William T. Tardy",
            pages: 270, about: "A classic course reader: a story, then Latin American history, a little harder each chapter."),
        GradedReader(
            id: "es.short-stories-intermediate", language: .spanish, level: 3,
            title: "Short Stories in Spanish for Intermediate Learners", author: "Olly Richards", pages: 270,
            about: "Longer stories in natural intermediate Spanish, with support after each chapter."),
        GradedReader(
            id: "es.principito", language: .spanish, level: 3, title: "El principito", author: "Antoine de Saint-Exupéry",
            pages: 100, about: "The Little Prince in Spanish: simple sentences, a story you may know already."),
        GradedReader(
            id: "es.platero", language: .spanish, level: 3, title: "Platero y yo", author: "Juan Ramón Jiménez", pages: 160,
            about: "Short prose poems about a man and his donkey in Andalusia. Free on Project Gutenberg.", free: gutenberg(9980)),
        GradedReader(
            id: "es.harry-potter-1", language: .spanish, level: 4, title: "Harry Potter y la piedra filosofal", author: "J. K. Rowling",
            pages: 250, about: "A familiar story makes a long book in Spanish manageable."),
        GradedReader(
            id: "es.sombrero-tres-picos", language: .spanish, level: 4, title: "El sombrero de tres picos",
            author: "Pedro Antonio de Alarcón", pages: 200,
            about: "A comic novella, in an edition with notes for students. Free on Project Gutenberg.", free: gutenberg(29506)),
        GradedReader(
            id: "es.marina", language: .spanish, level: 4, title: "Marina", author: "Carlos Ruiz Zafón", pages: 290,
            about: "A gothic mystery in Barcelona, written for young adults."),
        GradedReader(
            id: "es.cronica-muerte", language: .spanish, level: 5, title: "Crónica de una muerte anunciada",
            author: "Gabriel García Márquez", pages: 120, about: "A short novel told like a report: a killing everyone saw coming."),
        GradedReader(
            id: "es.cuentos-quiroga", language: .spanish, level: 5, title: "Cuentos de amor de locura y de muerte",
            author: "Horacio Quiroga", pages: 200, about: "Short, dark stories from the jungle. Free on Project Gutenberg.",
            free: gutenberg(13507)),
        GradedReader(
            id: "es.marianela", language: .spanish, level: 5, title: "Marianela", author: "Benito Pérez Galdós", pages: 220,
            about: "A nineteenth-century novel of a blind man and his guide. Free on Project Gutenberg.", free: gutenberg(17340)),
        GradedReader(
            id: "es.sombra-del-viento", language: .spanish, level: 5, title: "La sombra del viento", author: "Carlos Ruiz Zafón",
            pages: 570, about: "A long literary mystery about a forgotten book."),
        GradedReader(
            id: "es.niebla", language: .spanish, level: 6, title: "Niebla", author: "Miguel de Unamuno", pages: 300,
            about: "A novel whose hero argues with his author. Free on Project Gutenberg.", free: gutenberg(49836)),
        GradedReader(
            id: "es.pedro-paramo", language: .spanish, level: 6, title: "Pedro Páramo", author: "Juan Rulfo", pages: 130,
            about: "Short and strange: a son looks for his father in a town of the dead."),
        GradedReader(
            id: "es.cien-anos", language: .spanish, level: 6, title: "Cien años de soledad", author: "Gabriel García Márquez",
            pages: 470, about: "Seven generations of one family in Macondo."),
        GradedReader(
            id: "es.quijote", language: .spanish, level: 6, title: "Don Quijote", author: "Miguel de Cervantes", pages: 1000,
            about: "Seventeenth-century Spanish, the summit. Free on Project Gutenberg.", free: gutenberg(2000)),

        // Japanese
        GradedReader(
            id: "ja.tadoku-0", language: .japanese, level: 1, title: "Tadoku free readers: first books", author: "NPO Tadoku Supporters",
            pages: 16, about: "Very short illustrated readers in kana with a few kanji. Free to read online.", free: tadoku),
        GradedReader(
            id: "ja.graded-readers-0", language: .japanese, level: 1, title: "Japanese Graded Readers: starter booklets",
            author: "NPO Tadoku Supporters", pages: 16,
            about: "Booklets of a few hundred words with pictures and audio."),
        GradedReader(
            id: "ja.tadoku-2", language: .japanese, level: 2, title: "Tadoku free readers: longer books", author: "NPO Tadoku Supporters",
            pages: 30, about: "Longer free readers with more kanji and everyday grammar.", free: tadoku),
        GradedReader(
            id: "ja.graded-readers-2", language: .japanese, level: 2, title: "Japanese Graded Readers: early booklets",
            author: "NPO Tadoku Supporters", pages: 30, about: "Folk tales and short stories in plain Japanese."),
        GradedReader(
            id: "ja.yotsuba-1", language: .japanese, level: 2, title: "よつばと! 1", author: "あずまきよひこ", pages: 210,
            about: "Manga about a curious five-year-old: everyday speech with furigana, and pictures to lean on."),
        GradedReader(
            id: "ja.graded-readers-4", language: .japanese, level: 3, title: "Japanese Graded Readers: longer stories",
            author: "NPO Tadoku Supporters", pages: 60, about: "Longer stories and adapted classics."),
        GradedReader(
            id: "ja.hoshi-no-oujisama", language: .japanese, level: 3, title: "星の王子さま", author: "サン＝テグジュペリ", pages: 150,
            about: "The Little Prince in Japanese, a story you may know already."),
        GradedReader(
            id: "ja.majo-no-takkyubin", language: .japanese, level: 3, title: "魔女の宅急便", author: "角野栄子", pages: 250,
            about: "Kiki's Delivery Service, the children's novel: simple prose, with furigana."),
        GradedReader(
            id: "ja.totto-chan", language: .japanese, level: 4, title: "窓ぎわのトットちゃん", author: "黒柳徹子", pages: 300,
            about: "Short memoir chapters of an unusual school in wartime Tokyo."),
        GradedReader(
            id: "ja.kitchen", language: .japanese, level: 4, title: "キッチン", author: "吉本ばなな", pages: 180,
            about: "A short modern novel in clear, conversational prose."),
        GradedReader(
            id: "ja.breaking-into", language: .japanese, level: 4, title: "Breaking into Japanese Literature", author: "Giles Murray",
            pages: 250, about: "Stories by Sōseki and Akutagawa with a dictionary on every page."),
        GradedReader(
            id: "ja.read-real", language: .japanese, level: 5, title: "Read Real Japanese Fiction", author: "Michael Emmerich (ed.)",
            pages: 150, about: "Contemporary short stories with notes and audio."),
        GradedReader(
            id: "ja.konbini-ningen", language: .japanese, level: 5, title: "コンビニ人間", author: "村田沙耶香", pages: 160,
            about: "A short, sharp novel about a woman who fits in only at work."),
        GradedReader(
            id: "ja.hakase", language: .japanese, level: 5, title: "博士の愛した数式", author: "小川洋子", pages: 290,
            about: "A housekeeper, her son and a mathematician whose memory lasts eighty minutes."),
        GradedReader(
            id: "ja.botchan", language: .japanese, level: 6, title: "坊っちゃん", author: "夏目漱石", pages: 180,
            about: "Sōseki's comic novel of a hot-headed young teacher. Free on Aozora Bunko."),
        GradedReader(
            id: "ja.norwegian-wood", language: .japanese, level: 6, title: "ノルウェイの森", author: "村上春樹", pages: 600,
            about: "Murakami's most realist novel, in two volumes."),
    ]
}
