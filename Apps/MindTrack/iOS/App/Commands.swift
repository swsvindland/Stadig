import MindEngine
import SwiftUI

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
                .disabled(!model.onboarded)
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
                    .disabled(!model.onboarded)
            }
        }
        CommandMenu("Study") {
            if Platform.isMac, model.run != nil {
                Button("Show the Session") { showSession() }
                    .keyboardShortcut("n")
            } else {
                Button(model.analysis?.today?.kind == .checkIn ? "Start the Check-In" : "Start Today's Session") { model.startToday() }
                    .keyboardShortcut("n")
                    .disabled(!canStart || model.analysis?.today == nil)
            }
            Menu("Study Anyway") {
                ForEach(model.settings?.domains ?? []) { domain in
                    Button(domain.label) { model.startSession(Self.session(of: domain, settings: model.settings)) }
                }
            }
            .disabled(!canStart)
            Button("Extra Review") { model.startExtraReview() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!canStart || (model.analysis?.dueToday ?? 0) == 0)
            Divider()
            Button("End Session…") { model.endRequested = true }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model.run == nil)
        }
        CommandMenu("Shelf") {
            Button("Add a Book…") { model.addingBook = true }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(!model.onboarded || model.run != nil)
        }
    }

    /// Nothing starts over a session already running.
    var canStart: Bool { model.onboarded && model.run == nil }

    /// Maths brings its writing segment with it, as on Today.
    static func session(of domain: Domain, settings: MindSettings?) -> [Domain] {
        domain == .maths && settings?.has(.writing) == true ? [.maths, .writing] : [domain]
    }

    func showSession() {
        #if os(macOS)
        openWindow(id: SessionWindow.id)
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
