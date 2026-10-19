import MindEngine
import OSLog
import PencilKit
import PhotosUI
import SwiftUI
import SystemCore
import UniformTypeIdentifiers

/// Write something: a prompt, a rewrite, a practical task, Franklin notes. Typed, written with
/// Apple Pencil on iPad, or written on paper and brought in (scanned or photographed on iPhone and
/// iPad; a photo, a scan or a file, dropped on the window, or from an iPhone's camera through
/// Continuity Camera on the Mac); handwriting is read on the device into text to check before
/// handing in. Then the piece comes back with its slips marked and a few notes.
struct ComposeView: View {
    let task: WritingTask

    var body: some View {
        if let id = task.reviewing {
            PieceReview(task: task, pieceID: id)
        } else {
            ComposeEditor(task: task)
        }
    }
}

extension WritingExercise {
    var symbol: String {
        switch self {
        case .franklinNotes, .franklinRewrite: "text.book.closed"
        case .prompt: "sparkles"
        case .sceneRewrite: "theatermasks"
        case .practical: "envelope"
        case .argument: "scalemass"
        case .benchmark: "flag.checkered"
        }
    }
}

/// File ▸ Import a Handwritten Page…, while a piece is being written: opens the editor's importer.
struct HandwrittenPageImport {
    let open: () -> Void
}

extension FocusedValues {
    @Entry var handwrittenPageImport: HandwrittenPageImport?
}

private struct ComposeEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let task: WritingTask

    enum Input: String { case keyboard, pencil }
    enum Target: String, Identifiable {
        /// The piece itself, written by hand.
        case writing
        /// A printed page of the book being read, for the Franklin method.
        case ownPage
        var id: String { rawValue }
    }

    /// Kept per device: Pencil on the iPad, the keyboard elsewhere.
    @AppStorage("writing.input") private var input: Input = .keyboard
    @State private var text = ""
    @State private var source: WritingSource = .typed
    @State private var drawing = PKDrawing()
    @State private var erasing = false
    @State private var reading = false
    @State private var problem: String?
    @State private var scanning: Target?
    @State private var choosingPhoto = false
    @State private var importingFile = false
    @State private var photoTarget: Target = .writing
    @State private var photo: PhotosPickerItem?
    @State private var ownPage: String?
    @State private var sourceShown = true
    @State private var dropping = false
    /// A draft left from an earlier go at this task has been looked for; until then nothing is kept,
    /// so an empty editor can't overwrite it.
    @State private var draftLoaded = false
    @State private var handedIn = false
    @FocusState private var writing: Bool

    var pencil: Bool { Platform.isPad && input == .pencil }
    var notesOnly: Bool { task.exercise == .franklinNotes }
    var words: Int { text.split { $0.isWhitespace || $0.isNewline }.count }
    var draftKey: String { WritingDrafts.key(task) }
    /// Changes whenever something worth keeping does.
    var draftVersion: String { "\(text.hashValue).\(drawing.strokes.count).\(ownPage?.hashValue ?? 0)" }
    /// A wide window: the editor fills the height, beside the passage or notes when there are any.
    var wide: Bool { sizeClass == .regular && !pencil }
    var sideBySide: Bool { wide && SessionLayout.sideBySide(task) }
    var canHandIn: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !reading }
    var keys: [SessionKeyBinding] {
        // Not while a picker or the scanner is up over the editor: a presented sheet still hears these on iPad.
        guard !choosingPhoto, !importingFile, scanning == nil else { return [] }
        return SessionKeys.bindings(step: .compose(task), feedback: nil, typing: writing, canHandIn: canHandIn)
    }
    var handInTitle: String { notesOnly ? "Keep these notes" : "Hand it in" }

    /// VisionKit's document camera, on an iPhone or iPad that has one.
    var canScan: Bool {
        #if os(iOS)
        return DocumentScanner.isAvailable
        #else
        return false
        #endif
    }

    /// The file importer is for an iPad, a Mac or Vision Pro: an iPhone has the camera and Photos.
    var canOpenFiles: Bool { !Platform.isPhoneOrPad || Platform.isPad }

    var body: some View {
        VStack(spacing: 0) {
            if pencil {
                pencilPage
            } else if sideBySide {
                HStack(alignment: .top, spacing: 0) {
                    ScrollView { header.padding(24).readableWidth(620) }
                        .frame(maxWidth: .infinity)
                    Divider()
                    editor(fills: true)
                        .padding(24)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: 1400)
                .frame(maxWidth: .infinity)
            } else if wide {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    editor(fills: true)
                }
                .padding(24)
                .readableWidth(780)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        editor(fills: false)
                    }
                    .padding(20)
                    .readableWidth(680)
                }
                .dismissesKeyboard(.interactively)
            }
            BottomBar {
                bottom
                KeyLegend(bindings: keys, titles: [.handIn: handInTitle])
            }
        }
        #if os(iOS)
        .fullScreenCover(item: $scanning) { target in
            DocumentScanner(
                done: { pages in
                    scanning = nil
                    read(into: target) { try await TextRecognizer.read(pages, handwriting: target == .writing) }
                }, cancel: { scanning = nil }
            )
            .ignoresSafeArea()
        }
        #endif
        .task { await restoreDraft() }
        .task(id: draftVersion) {
            // Kept a moment after typing pauses, and when the step is left.
            guard draftLoaded else { return }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            keepDraft()
        }
        .onDisappear(perform: keepDraft)
        .photosPicker(isPresented: $choosingPhoto, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            let target = photoTarget
            read(into: target) {
                guard let data = try await item.loadTransferable(type: Data.self) else { return "" }
                return try await Self.text(in: [data], handwriting: target == .writing)
            }
        }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: ImageImport.pageTypes, allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                let target = photoTarget
                read(into: target) {
                    var files: [Data] = []
                    for url in urls { files.append(try await ImageImport.data(at: url)) }
                    return try await Self.text(in: files, handwriting: target == .writing)
                }
            case .failure(let error):
                problem = "The file couldn't be opened. \(error.localizedDescription)"
            }
        }
        .focusedSceneValue(\.handwrittenPageImport, HandwrittenPageImport { openFiles(for: .writing) })
        .sessionKeys(keys) { key in if key == .handIn { handIn() } }
        #if DEBUG
        .task {
            let launch = LaunchOptions.current
            if launch.has("-pencil") { input = .pencil }
            // -readImage page.png reads a picture from the app's Documents as handwriting.
            if let name = launch.value(after: "-readImage") {
                do {
                    let data = try Data(contentsOf: URL.documentsDirectory.appending(path: name))
                    read(into: .writing) { try await Self.text(in: [data], handwriting: true) }
                } catch {
                    appLog.error("No picture to read at \(name, privacy: .public): \(error.localizedDescription)")
                }
                if launch.has("-handIn") {
                    while reading { try? await Task.sleep(for: .milliseconds(200)) }
                    handIn()
                }
            }
            if launch.has("-autoWrite") {
                text = SampleWriting.text(for: task, week: 8)
                handIn()
            }
        }
        #endif
    }

    // MARK: The task

    @ViewBuilder var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(task.exercise.label, systemImage: task.exercise.symbol)
                .font(.subheadline.weight(.semibold)).foregroundStyle(Domain.writing.color)
            Text(task.instruction).font(.title3.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            if task.showsSource, let original = task.source {
                if pencil {
                    DisclosureGroup(sourceTitle, isExpanded: $sourceShown) { sourceCard(original).padding(.top, 8) }
                        .font(.subheadline.weight(.semibold))
                } else {
                    sourceCard(original)
                }
            }
            if let notes = task.notes {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your notes").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(notes).font(sideBySide ? .writing : .callout).lineSpacing(sideBySide ? LineSpacing.writing : 0)
                }
                .card()
            }
        }
    }

    var sourceTitle: String {
        switch task.exercise {
        case .franklinNotes: ownPage == nil ? "The passage" : "Your page"
        case .practical: "The original"
        case .sceneRewrite: "The scene"
        default: "The text"
        }
    }

    @ViewBuilder func sourceCard(_ original: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let ownPage {
                TextEditor(text: Binding(get: { ownPage }, set: { self.ownPage = $0 }))
                    .font(.body)
                    .frame(minHeight: 180)
                    .scrollContentBackground(.hidden)
                Text("Read from your page. Trim it to a paragraph or two.").font(.caption).foregroundStyle(.secondary)
                Button("Use the passage Mind Track chose", systemImage: "arrow.uturn.backward") { self.ownPage = nil }
                    .font(.subheadline)
                    .accessibilityIdentifier("compose.useChosenPassage")
            } else {
                // Beside the editor it's read like a page; above it, kept short.
                Text(original)
                    .font(sideBySide ? .passage : .body)
                    .lineSpacing(sideBySide ? LineSpacing.passage : 3)
                    .textSelection(.enabled)
                if let credit = task.sourceCredit { Text(credit).font(.caption).foregroundStyle(.secondary) }
                if notesOnly, let book = model.state?.currentBook {
                    Menu {
                        if canScan {
                            Button("Scan a page", systemImage: "doc.viewfinder") { scanning = .ownPage }
                                .accessibilityIdentifier("compose.scanOwnPage")
                        }
                        Button("Choose a photo of a page", systemImage: "photo") {
                            photoTarget = .ownPage
                            choosingPhoto = true
                        }
                        .accessibilityIdentifier("compose.photoOwnPage")
                        if canOpenFiles {
                            Button("Open a picture of a page…", systemImage: "folder") { openFiles(for: .ownPage) }
                                .accessibilityIdentifier("compose.fileOwnPage")
                        }
                    } label: {
                        Label("Use a page of \(book.title) instead", systemImage: "book")
                    }
                    .font(.subheadline)
                    .macFixedSize()
                    .accessibilityIdentifier("compose.ownPage")
                }
            }
        }
        .card()
    }

    // MARK: Writing it

    /// The editor: in a wide window it fills the height beside or below the task; on a phone it
    /// scrolls with it.
    func editor(fills: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if Platform.isPad {
                    Picker("Write with", selection: $input) {
                        Label("Keyboard", systemImage: "keyboard").tag(Input.keyboard)
                        Label("Apple Pencil", systemImage: "pencil.tip").tag(Input.pencil)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)
                }
                Spacer()
                paperMenu
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.writing)
                    .lineSpacing(fills ? LineSpacing.writing : 0)
                    .frame(minHeight: notesOnly ? 160 : 280, maxHeight: fills ? .infinity : nil)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .focused($writing)
                    .accessibilityLabel(notesOnly ? "Your notes" : "Your piece")
                    .accessibilityIdentifier("compose.text")
                if text.isEmpty {
                    Text(notesOnly ? "A few words for each sentence’s point" : "Start writing")
                        .font(.writing)
                        .foregroundStyle(.tertiary).padding(.horizontal, 13).padding(.vertical, 16).allowsHitTesting(false)
                }
            }
            .background(.cardBackground, in: .rect(cornerRadius: 14))
            .overlay {
                if dropping {
                    RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }
            }
            // A photo or scan of a written page dropped on the editor is read into it.
            .dropDestination(for: Data.self) { files, _ in
                guard !files.isEmpty else { return false }
                read(into: .writing) { try await Self.text(in: files, handwriting: true) }
                return true
            } isTargeted: {
                dropping = $0
            }
            #if os(macOS)
            // Continuity Camera: File ▸ Import from iPhone or iPad, a photo or a document scan.
            .importsItemProviders(ImageImport.pageTypes) { providers in
                guard !providers.isEmpty else { return false }
                read(into: .writing) {
                    var files: [Data] = []
                    for provider in providers {
                        if let data = await ImageImport.data(from: provider) { files.append(data) }
                    }
                    return try await Self.text(in: files, handwriting: true)
                }
                return true
            }
            #endif
            if reading { ProgressView("Reading your handwriting…").font(.caption) }
            if let problem { Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            if source == .handwritten && !text.isEmpty {
                Label("Read from your handwriting. Check it over, then hand it in.", systemImage: "pencil.and.scribble")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(notesOnly ? "Notes, not sentences: you’ll rewrite from these next time." : "\(words) words · about \(task.minutes) minutes")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("compose.words")
        }
    }

    var paperMenu: some View {
        Menu {
            if canScan {
                Button("Scan a written page", systemImage: "doc.viewfinder") { scanning = .writing }
                    .accessibilityIdentifier("compose.scanPaper")
            }
            Button("Choose a photo of it", systemImage: "photo") {
                photoTarget = .writing
                choosingPhoto = true
            }
            .accessibilityIdentifier("compose.photoPaper")
            if canOpenFiles {
                Button("Open a scan or photo…", systemImage: "folder") { openFiles(for: .writing) }
                    .accessibilityIdentifier("compose.filePaper")
            }
            #if os(macOS)
            Text("Or drop it here, or take it with your iPhone: File ▸ Import from iPhone or iPad.")
            #endif
        } label: {
            Label("Written on paper", systemImage: "doc.text.viewfinder").font(.subheadline)
        }
        .macFixedSize()
        .help("Bring in a page you wrote by hand: it's read into text on this \(Platform.deviceName) for you to check.")
        .accessibilityIdentifier("compose.paper")
    }

    @ViewBuilder var pencilPage: some View {
        #if os(iOS)
        ScrollView { header.padding(20).readableWidth(760) }
            .frame(maxHeight: (sourceShown && task.showsSource) || task.notes != nil ? 320 : 150)
        Divider()
        HandwritingPad(drawing: $drawing, erasing: erasing)
            .overlay(alignment: .topLeading) {
                if drawing.strokes.isEmpty {
                    Text(notesOnly ? "Write your notes here with Apple Pencil." : "Write here with Apple Pencil.")
                        .font(.callout).foregroundStyle(.tertiary).padding(20).allowsHitTesting(false)
                }
            }
        #endif
    }

    @ViewBuilder var bottom: some View {
        if pencil {
            #if os(iOS)
            HStack(spacing: 12) {
                Button(erasing ? "Pen" : "Eraser", systemImage: erasing ? "pencil.tip" : "eraser") { erasing.toggle() }
                    .secondaryAction().controlSize(.large)
                    .accessibilityIdentifier("compose.eraser")
                Button("Keyboard", systemImage: "keyboard") { input = .keyboard }
                    .secondaryAction().controlSize(.large)
                    .accessibilityIdentifier("compose.keyboard")
                Button {
                    // The strokes read are taken off the page once they're text, so writing more
                    // and reading again doesn't read the first paragraph twice.
                    let page = drawing
                    read(into: .writing, onRead: { drawing = PKDrawing(strokes: drawing.strokes.dropFirst(page.strokes.count)) }) {
                        guard let image = await HandwritingPad.inkImage(of: page) else { return "" }
                        return try await TextRecognizer.read([image])
                    }
                } label: {
                    Label(reading ? "Reading…" : "Read my handwriting", systemImage: "text.viewfinder").font(.headline).frame(maxWidth: .infinity)
                }
                .primaryAction()
                .controlSize(.large)
                .disabled(drawing.strokes.isEmpty || reading)
                .accessibilityIdentifier("compose.readHandwriting")
            }
            #endif
        } else {
            Button(action: handIn) {
                Text(handInTitle).font(.headline).frame(maxWidth: .infinity)
            }
            .primaryAction()
            .controlSize(.large)
            .accessibilityIdentifier("compose.handIn")
            .disabled(!canHandIn)
        }
    }

    func openFiles(for target: Target) {
        photoTarget = target
        importingFile = true
    }

    /// The text on pages brought in as files' bytes (pictures, or scans saved as PDFs), in order:
    /// each page decoded and read before the next, so a long scan never sits in memory whole.
    static func text(in files: [Data], handwriting: Bool) async throws -> String {
        var texts: [String] = []
        var opened = false
        for file in files {
            let count = await ImageImport.pageCount(file)
            for index in 0..<count {
                guard let page = await ImageImport.page(file, at: index) else { continue }
                opened = true
                let text = try await TextRecognizer.read([page], handwriting: handwriting)
                if !text.isEmpty { texts.append(text) }
            }
        }
        guard opened else { throw TextRecognizer.RecognitionError.unreadableImage }
        return texts.joined(separator: "\n\n")
    }

    /// Reads a page into text: handwriting into the piece (for checking before it's handed in),
    /// or a printed page of the book being read in place of the library's passage. `onRead` runs
    /// once handwriting has gone into the piece.
    func read(into target: Target, onRead: (() -> Void)? = nil, _ work: @escaping () async throws -> String) {
        reading = true
        problem = nil
        Task {
            defer { reading = false }
            do {
                let found = try await work().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !found.isEmpty else {
                    problem = "No writing found. Try again with the page flat, well lit and close up."
                    return
                }
                switch target {
                case .writing:
                    text = text.isEmpty ? found : text + "\n\n" + found
                    source = .handwritten
                    input = .keyboard
                    onRead?()
                case .ownPage:
                    ownPage = found
                }
            } catch TextRecognizer.RecognitionError.unreadableImage {
                problem = "That picture couldn't be opened. Try a photo or a scan of the page."
            } catch {
                problem = "The page couldn't be read. Try again, or type it."
                appLog.error("Text recognition failed: \(error.localizedDescription)")
            }
        }
    }

    func handIn() {
        let written = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !written.isEmpty else { return }
        let misspelled = notesOnly ? [] : WritingAssistant.misspelled(written)
        let own = notesOnly ? ownPage?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let before = model.run?.newPieces.count ?? 0
        model.act { $0.submitWriting(written, source: source, misspelled: misspelled, original: own?.isEmpty == false ? own : nil, now: Date()) }
        if (model.run?.newPieces.count ?? 0) > before {
            handedIn = true
            let (key, drafts) = (draftKey, model.drafts)
            Task { await drafts.remove(key) }
        }
        if case .compose(let next)? = model.run?.step, let id = next.reviewing, let piece = model.run?.piece(id) {
            WritingAssistant.shared.requestNotes(for: piece, source: task.source, model: model)
        }
    }

    /// What was written last time this task came round, unless something's been written already.
    func restoreDraft() async {
        defer { draftLoaded = true }
        guard let draft = await model.drafts.draft(draftKey), text.isEmpty, drawing.strokes.isEmpty, ownPage == nil else { return }
        text = draft.text
        if draft.handwritten { source = .handwritten }
        ownPage = draft.ownPage
        if let data = draft.drawing {
            do { drawing = try PKDrawing(data: data) } catch { appLog.error("Couldn't read the handwriting draft: \(error.localizedDescription)") }
        }
    }

    /// Keeps the piece so far on the device until it's handed in.
    func keepDraft() {
        guard draftLoaded, !handedIn else { return }
        let (text, handwritten, drawing, ownPage, key, drafts) = (text, source == .handwritten, drawing, ownPage, draftKey, model.drafts)
        Task { await drafts.save(text: text, handwritten: handwritten, drawing: drawing, ownPage: ownPage, for: key) }
    }
}

// MARK: The piece back, with notes

private struct PieceReview: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let task: WritingTask
    let pieceID: UUID
    @State private var slips: [WritingSlip] = []

    var keys: [SessionKeyBinding] { SessionKeys.bindings(step: .compose(task), feedback: nil) }

    var body: some View {
        let piece = model.run?.piece(pieceID)
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(task.exercise == .franklinRewrite ? "Your rewrite beside the original" : "Notes on your piece").font(.title2.bold())
                    if let piece {
                        if task.exercise == .franklinRewrite, let original = task.source {
                            let layout =
                                sizeClass == .regular ? AnyLayout(HStackLayout(alignment: .top, spacing: 14)) : AnyLayout(VStackLayout(spacing: 14))
                            layout {
                                TextCard(title: "Original", detail: task.sourceCredit ?? "From your book", text: Text(original))
                                TextCard(title: "Yours", detail: "From your notes", text: MarkedText.text(piece.text, slips: slips))
                            }
                        } else {
                            TextCard(title: "Your piece", detail: "\(piece.words) words", text: MarkedText.text(piece.text, slips: slips))
                        }
                        SlipList(slips: slips)
                        NotesCard(state: WritingAssistant.shared.state(for: piece)) {
                            WritingAssistant.shared.requestNotes(for: piece, source: task.source, model: model, again: true)
                        }
                    }
                    Text(
                        "Notes are suggestions, never a grade. Slips, range of vocabulary and variety in sentence length show as trends in Progress."
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(20)
                .readableWidth(sizeClass == .regular && task.exercise == .franklinRewrite ? 980 : 680)
            }
            BottomBar {
                Button {
                    model.act { $0.respond(.skip, now: Date()) }
                } label: {
                    Text("Done").font(.headline).frame(maxWidth: .infinity)
                }
                .primaryAction()
                .controlSize(.large)
                .accessibilityIdentifier("pieceReview.done")
                KeyLegend(bindings: keys, titles: [.submit: "Done"])
            }
        }
        .sessionKeys(keys) { key in if key == .submit { model.act { $0.respond(.skip, now: Date()) } } }
        .task(id: pieceID) {
            guard let piece = model.run?.piece(pieceID) else { return }
            slips = WritingAssistant.slips(piece.text)
            WritingAssistant.shared.requestNotes(for: piece, source: task.source, model: model)
        }
    }
}

/// A piece with its slips marked.
enum MarkedText {
    static func text(_ text: String, slips: [WritingSlip]) -> Text { Text(attributed(text, slips: slips)) }

    /// The text with each slip underlined. Offsets count Characters, as the checker's do; a slip
    /// that doesn't lie inside the text (one from before an edit) is left unmarked, since indexing
    /// past either end would trap.
    static func attributed(_ text: String, slips: [WritingSlip]) -> AttributedString {
        var marked = AttributedString(text)
        let count = marked.characters.count
        for slip in slips where slip.offset >= 0 && slip.length > 0 && slip.offset <= count && slip.length <= count - slip.offset {
            let start = marked.characters.index(marked.startIndex, offsetBy: slip.offset)
            let end = marked.characters.index(start, offsetBy: slip.length)
            marked[start..<end].underlineStyle = Text.LineStyle(pattern: .solid, color: .orange)
            marked[start..<end].backgroundColor = Color.orange.opacity(0.14)
        }
        return marked
    }
}

struct TextCard: View {
    let title: String
    let detail: String?
    let text: Text

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            text.font(.writing).lineSpacing(LineSpacing.writing).textSelection(.enabled)
        }
        .card()
    }
}

/// What the checker marked: a short list, not a wall of corrections.
private struct SlipList: View {
    let slips: [WritingSlip]
    static let shown = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                slips.isEmpty ? "The checker found no slips." : "Marked in your text", systemImage: slips.isEmpty ? "checkmark.circle" : "highlighter"
            )
            .font(.subheadline.weight(.semibold))
            ForEach(Array(slips.prefix(Self.shown).enumerated()), id: \.offset) { _, slip in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("“\(slip.text)”").font(.callout.weight(.medium))
                    Text(slip.note).font(.callout).foregroundStyle(.secondary)
                }
            }
            if slips.count > Self.shown {
                Text("And \(slips.count - Self.shown) more, marked above.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }
}

/// The AI's two or three fixes, on their way, or a plain word on why there aren't any.
struct NotesCard: View {
    let state: WritingAssistant.Notes?
    /// Nil means notes were never asked for (an older piece), rather than on their way.
    var asked = true
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Notes", systemImage: "text.bubble").font(.subheadline.weight(.semibold))
            switch state {
            case .ready(let items):
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)").font(.callout.weight(.bold).monospacedDigit()).foregroundStyle(Domain.writing.color)
                        Text(item).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
            case .failed(let message):
                Text("No notes this time. \(message)").font(.callout).foregroundStyle(.secondary)
                Button("Try again", systemImage: "arrow.clockwise", action: retry).font(.subheadline)
                    .accessibilityIdentifier("pieceReview.retry")
            case nil where !asked:
                Text("Two or three specific fixes from Apple Intelligence, never a grade.").font(.callout).foregroundStyle(.secondary)
                Button("Ask for notes", systemImage: "text.bubble", action: retry).font(.subheadline)
                    .accessibilityIdentifier("pieceReview.askForNotes")
            case .working, nil:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading your piece…").font(.callout).foregroundStyle(.secondary)
                }
                Text("You can carry on: the notes stay with the piece in Progress.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }
}
