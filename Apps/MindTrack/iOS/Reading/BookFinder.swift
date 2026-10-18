import MindEngine
import PhotosUI
import SwiftUI

/// Adding a book: search by title, author or ISBN, scan the barcode, or photograph the cover, then
/// confirm the details and level. The ladder and earlier lookups answer at once, offline; Open
/// Library and then Google Books answer the rest.
struct BookFinder: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Reading now, or finished in the last year.
    var status: BookStatus = .reading
    var title = "Add a book"
    var initialQuery = ""
    let save: (Book) -> Void

    @State private var query = ""
    @State private var results = BookLookup.Results()
    @State private var searching = false
    @State private var scanning = false
    @State private var photographing = false
    @State private var photo: PhotosPickerItem?
    @State private var readingCover = false
    @State private var message: String?
    @State private var draft: BookDraft?
    @State private var saved: Book?
    @State private var search: Task<Void, Never>?
    /// The ISBN just scanned, looked up already: the query set to it doesn't search again.
    @State private var scannedISBN: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(ISBNCamera.isAvailable ? "Scan the barcode" : "Type the ISBN", systemImage: "barcode.viewfinder") { scanning = true }
                        .accessibilityIdentifier("bookFinder.scan")
                    if CoverCamera.isAvailable {
                        Button("Photograph the cover", systemImage: "camera") { photographing = true }
                            .accessibilityIdentifier("bookFinder.photograph")
                    }
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("Choose a photo of the cover", systemImage: "photo.on.rectangle")
                    }
                    .accessibilityIdentifier("bookFinder.photo")
                    Button("Enter it yourself", systemImage: "square.and.pencil") { draft = BookDraft(title: query) }
                        .accessibilityIdentifier("bookFinder.enter")
                } footer: {
                    Text("Covers are read on your iPhone. Lookups go to Open Library, then Google Books, and are kept for next time.")
                }
                if readingCover || searching {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(readingCover ? "Reading the cover…" : "Searching…").foregroundStyle(.secondary)
                        }
                    }
                }
                if let message {
                    Section { Text(message).foregroundStyle(.secondary) }
                }
                if !results.ladder.isEmpty {
                    Section("On the ladder") {
                        ForEach(results.ladder) { book in
                            Button {
                                draft = BookDraft(ladder: book)
                            } label: {
                                FoundRow(
                                    title: book.title, author: book.author,
                                    detail: "Tier \(book.tier)\(book.levelledFromText ? " · levelled from its text" : "")")
                            }
                            .foregroundStyle(.primary)
                            .accessibilityIdentifier("bookFinder.ladder.\(book.id)")
                        }
                    }
                }
                if !results.found.isEmpty {
                    Section("Found") {
                        ForEach(results.found) { meta in
                            Button {
                                pick(meta)
                            } label: {
                                FoundRow(
                                    title: meta.title, author: meta.author,
                                    detail: [meta.year.map(String.init), meta.pages.map { "\($0) pages" }].compactMap { $0 }.joined(separator: " · "))
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Title, author or ISBN")
            .onSubmit(of: .search) { runSearch(now: true) }
            .onChange(of: query) { runSearch(now: false) }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("bookFinder.cancel") } }
            .sheet(isPresented: $scanning) {
                BookScannerView { isbn in lookUp(isbn) }
            }
            .fullScreenCover(isPresented: $photographing) {
                CoverCamera { image in
                    photographing = false
                    if let image { readCover(image) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { readCover(image) }
                    photo = nil
                }
            }
            .sheet(item: $draft, onDismiss: finish) { draft in
                BookEditor(draft: draft, status: status) { book in
                    if let meta = draft.lookup { BookLookup.keep(meta, estimate: draft.estimate, model: model) }
                    saved = book
                }
            }
            .onAppear {
                guard query.isEmpty, !initialQuery.isEmpty else { return }
                query = initialQuery
                runSearch(now: true)
            }
        }
    }

    /// Ladder and cached matches straight away; the catalogues after a pause in typing.
    func runSearch(now: Bool) {
        let text = query.trimmingCharacters(in: .whitespaces)
        if !now, let scannedISBN, ISBN.normalize(text) == scannedISBN { return }
        scannedISBN = nil
        search?.cancel()
        // A search cut short leaves nothing running until a new one starts.
        searching = false
        message = nil
        results = BookLookup.local(text, model: model)
        guard text.count >= 3 else { return }
        search = Task {
            if !now { try? await Task.sleep(for: .milliseconds(700)) }
            guard !Task.isCancelled else { return }
            searching = true
            let found = await BookLookup.search(text, model: model)
            guard !Task.isCancelled else { return }
            searching = false
            results = found
            if found.unreachable {
                message = "Couldn't reach Open Library or Google Books. Books on the ladder and ones looked up before still work offline."
            } else if found.ladder.isEmpty && found.found.isEmpty {
                message = "Nothing found. Try fewer words, or enter it yourself."
            }
        }
    }

    func pick(_ meta: BookMeta) {
        draft = BookDraft(meta: meta, estimate: BookLookup.estimate(meta, model: model))
    }

    func lookUp(_ isbn: String) {
        search?.cancel()
        scannedISBN = isbn
        query = isbn
        searching = true
        message = nil
        search = Task {
            let meta = await BookLookup.isbn(isbn, model: model)
            guard !Task.isCancelled else { return }
            searching = false
            if let meta { pick(meta) } else { message = "No catalogue knows ISBN \(isbn). Search by title, or enter it yourself." }
        }
    }

    func readCover(_ image: UIImage) {
        readingCover = true
        message = nil
        Task {
            let guess = await CoverReader.read(image, ai: model.ai)
            readingCover = false
            guard let guess else {
                message = "Couldn't read the cover. Try again straight on and in good light, or search by title."
                return
            }
            query = guess.query
            runSearch(now: true)
        }
    }

    /// The editor closed: if it saved, the book goes where it was asked for and the finder closes.
    func finish() {
        guard let book = saved else { return }
        saved = nil
        save(book)
        dismiss()
    }
}

private struct FoundRow: View {
    let title: String
    let author: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text([author, detail].filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
        }
        .contentShape(.rect)
    }
}
