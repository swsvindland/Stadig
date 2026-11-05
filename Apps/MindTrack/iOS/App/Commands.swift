import MindEngine
import SwiftUI
import SystemPurchases

/// The menu bar on the Mac (and an iPad's, and its list of shortcuts when ⌘ is held): study,
/// the shelf, a handwritten page while writing, and the destinations by number. There's one
/// model, so commands act on it; the page import acts on the editor in the focused window.
struct MindCommands: Commands {
    let model: AppModel
    @FocusedValue(\.handwrittenPageImport) private var handwrittenPage
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some Commands {
        // One main window: a second would show the same day. A session gets its own on the Mac.
        CommandGroup(replacing: .newItem) {}
        #if os(macOS)
        // Continuity Camera: a photo or a scan from an iPhone or iPad, into a piece being written
        // or the book finder's cover.
        ImportFromDevicesCommands()
        #else
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { model.showSettings = true }
                .keyboardShortcut(",")
                .disabled(!model.onboarded || behindSession)
        }
        #endif
        CommandGroup(after: .importExport) {
            Button("Import a Handwritten Page…") { handwrittenPage?.open() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(handwrittenPage == nil)
        }
        CommandMenu("Go") {
            ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) { model.tab = tab }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                    .disabled(!model.onboarded || behindSession)
            }
        }
        CommandMenu("Study") {
            if Platform.isMac, model.sessionOpen {
                Button("Show the Session") { showSession() }
                    .keyboardShortcut("n")
            } else {
                Button("Start the Next Block") {
                    model.startToday()
                    showSession()
                }
                .keyboardShortcut("n")
                .disabled(!canStart || model.analysis?.today == nil)
            }
            Menu("Study Anyway") {
                ForEach(model.settings?.domains ?? []) { domain in
                    Button(domain.label) {
                        model.startBlock(domain)
                        showSession()
                    }
                    // The Mac's menu bar keeps a submenu open to its items whatever the menu says.
                    .disabled(!canStart)
                }
            }
            .disabled(!canStart)
            Button("Extra Review") {
                model.startExtraReview()
                showSession()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!canStart || (model.analysis?.dueToday ?? 0) == 0)
            Divider()
            Button("End Session…") { model.endRequested = true }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!model.sessionOpen)
        }
        CommandMenu("Shelf") {
            Button("Add a Book…") { model.addingBook = true }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(!model.onboarded || model.sessionOpen)
        }
    }

    /// Nothing starts over a session already running.
    var canStart: Bool { model.onboarded && !model.sessionOpen }

    /// On iPhone, iPad and Vision Pro a session covers the screen: what's behind it waits until it
    /// ends, rather than opening there unseen. The Mac's main window stays usable beside the session's.
    var behindSession: Bool { model.sessionOpen && !Platform.isMac }

    /// On the Mac a session started from the menu bar opens its window here, since the main window
    /// (which opens it otherwise) may be closed; so does the unlock, when the session waits for it.
    func showSession() {
        #if os(macOS)
        if model.sessionOpen { openWindow(id: SessionWindow.id) }
        if model.showPaywall {
            model.showPaywall = false
            openWindow(id: PaywallView.windowID)
        }
        #endif
    }
}

extension AppTab {
    var title: String {
        switch self {
        case .today: "Today"
        case .plan: "Plan"
        case .progress: "Progress"
        case .shelf: "Shelf"
        case .writing: "Writing"
        case .courses: "Courses"
        }
    }
}
