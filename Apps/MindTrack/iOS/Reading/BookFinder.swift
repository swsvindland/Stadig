import MindEngine
import OSLog
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var importingFile = false
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
                    Button(BookScannerView.hasCamera ? "Scan the barcode" : "Type the ISBN", systemImage: "barcode.viewfinder") { scanning = true }
                        .rowButton()
                        .accessibilityIdentifier("bookFinder.scan")
                    #if os(iOS)
                    if CoverCamera.isAvailable {
                        Button("Photograph the cover", systemImage: "camera") { photographing = true }
                            .accessibilityIdentifier("bookFinder.photograph")
                    }
                    #endif
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("Choose a photo of the cover", systemImage: "photo.on.rectangle")
                    }
                    .rowButton()
                    .accessibilityIdentifier("bookFinder.photo")
                    if !Platform.isPhoneOrPad {
                        Button("Open a picture of the cover…", systemImage: "folder") { importingFile = true }
                            .rowButton()
                            .accessibilityIdentifier("bookFinder.openFile")
                    }
                    Button("Enter it yourself", systemImage: "square.and.pencil") { draft = BookDraft(title: query) }
                        .rowButton()
                        .accessibilityIdentifier("bookFinder.enter")
                } footer: {
                    Text(footer).fixedSize(horizontal: false, vertical: true)
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
                            .rowButton(tinted: false)
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
                            .rowButton(tinted: false)
                        }
                    }
                }
            }
            .alwaysSearchable(text: $query, prompt: "Title, author or ISBN")
            .onSubmit(of: .search) { runSearch(now: true) }
            .onChange(of: query) { runSearch(now: false) }
            .navigationTitle(title)
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("bookFinder.cancel") } }
            .sheet(isPresented: $scanning) {
                BookScannerView { isbn in lookUp(isbn) }
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $photographing) {
                CoverCamera { image in
                    photographing = false
                    if let image { readCover { await CoverReader.read(image, ai: model.ai) } }
                }
                .ignoresSafeArea()
            }
            #endif
            .onChange(of: photo) { _, item in
                guard let item else { return }
                photo = nil
                Task {
                    do {
                        if let data = try await item.loadTransferable(type: Data.self) { readCover(data) }
                    } catch {
                        appLog.error("Couldn't load the cover photo: \(error.localizedDescription)")
                        message = "That photo couldn't be opened. Try another, or search by title."
                    }
                }
            }
            .fileImporter(isPresented: $importingFile, allowedContentTypes: [.image]) { result in
                switch result {
                case .success(let url): readCover(url)
                case .failure(let error): message = error.localizedDescription
                }
            }
            // A cover dragged in from Finder or Photos, or taken with an iPhone through the Mac's
            // Continuity Camera (File ▸ Import from iPhone or iPad).
            .dropDestination(for: Data.self) { items, _ in
                guard let data = items.first else { return false }
                readCover(data)
                return true
            }
            #if os(macOS)
            .importsItemProviders([.image]) { providers in
                guard let provider = providers.first else { return false }
                Task {
                    if let data = await ImageImport.data(from: provider) { readCover(data) }
                }
                return true
            }
            .frame(minWidth: 460, idealWidth: 520, minHeight: 520, idealHeight: 640)
            #endif
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

    var footer: String {
        "Covers are read on your \(Platform.deviceName). Lookups go to Open Library, then Google Books, and are kept for next time."
    }

    func readCover(_ data: Data) { readCover { await CoverReader.read(data, ai: model.ai) } }

    /// A picture file chosen in the file importer.
    func readCover(_ url: URL) {
        do {
            readCover(try ImageImport.data(at: url))
        } catch {
            appLog.error("Couldn't open the cover file: \(error.localizedDescription)")
            message = "That file couldn't be opened. Try another, or search by title."
        }
    }

    func readCover(_ work: @escaping () async -> CoverText.Guess?) {
        readingCover = true
        message = nil
        Task {
            let guess = await work()
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
