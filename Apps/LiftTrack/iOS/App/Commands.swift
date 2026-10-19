import LiftEngine
import SwiftUI
import SystemCore

/// The menu bar on the Mac and the iPad: the session, logging, planning and the destinations, each
/// with its shortcut. One shared model drives every window, so the commands act on it directly.
struct LiftCommands: Commands {
    /// Nil while XCTest hosts the unit tests and the app builds no model: the menus are inert.
    let model: AppModel?
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some Commands {
        // One main window: its tab and sheets live in the shared model, so a second would mirror the
        // first. ⌘N starts today's session instead, in the Session menu.
        CommandGroup(replacing: .newItem) {}
        #if !os(macOS)
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { model?.showSettings = true }
                .keyboardShortcut(",")
                .disabled(!canPresent)
        }
        #endif
        CommandMenu("Session") {
            Button("Start Today's Session") {
                model?.startToday()
                showSession()
            }
            .keyboardShortcut("n")
            .disabled(model?.onboarded != true || model?.canStartToday != true)
            Button("Resume Session") {
                model?.showSession = true
                showSession()
            }
            .keyboardShortcut("r")
            .disabled(model?.live == nil || model?.showSession == true)
            Divider()
            Button("Finish Session…") {
                model?.showSession = true
                model?.sessionRequest = .finish
                showSession()
            }
            .keyboardShortcut(.return, modifiers: [.command, .shift])
            .disabled(model?.live == nil)
            Button("Discard Session…") {
                model?.showSession = true
                model?.sessionRequest = .discard
                showSession()
            }
            .disabled(model?.live == nil)
        }
        CommandMenu("Log") {
            Button("Outside Activity…") { present(.logActivity) }
                .keyboardShortcut("l")
                .disabled(!canPresent)
            Button("Check-in…") { present(.checkIn) }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(!canPresent)
            Button("Measurements…") { present(.measurements) }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(!canPresent)
        }
        CommandMenu("Plan") {
            Button("Plan Next Block…") { present(.nextBlock) }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!canPresent || model?.nextBlockOffered != true)
            Divider()
            // In a narrow window these open Plan, the tab that reaches them (`AppTab.tabBarFallback`).
            Button("Show Program") { go(.program) }
                .disabled(!canPresent)
            Button("Show Library") { go(.library) }
                .disabled(!canPresent)
        }
        CommandMenu("Go") {
            ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) { go(tab) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                    .disabled(!canPresent)
            }
        }
    }

    /// Whether a sheet or a destination can open now. On iPhone, iPad and Vision Pro the session
    /// covers the screen, and a sheet asked for behind it can't show: it would wait, and pop up over
    /// the session's summary when the session closes. The Mac's session has a window of its own, so
    /// the main window stays usable beside it.
    private var canPresent: Bool {
        guard let model, model.onboarded else { return false }
        return Platform.isMac || !model.showSession
    }

    private func present(_ sheet: AppSheet) {
        guard let model, canPresent else { return }
        showMain()
        model.sheet = sheet
    }

    private func go(_ tab: AppTab) {
        guard let model, canPresent else { return }
        showMain()
        model.tab = tab
    }

    /// On the Mac, the session's window, whether or not the main window is open to open it.
    private func showSession() {
        #if os(macOS)
        if model?.showSession == true { openWindow(id: SessionWindow.id) }
        #endif
    }

    /// Brings the main window back if it was closed: the sheets and destinations are in it.
    private func showMain() {
        #if os(macOS)
        openWindow(id: LiftTrackApp.mainWindow)
        #endif
    }
}

#if os(macOS)
/// The session in a window of its own on the Mac, so the program and the library stay in view
/// beside it. Closing it minimizes the session (Resume is in the main window's toolbar and the
/// Session menu); finishing or discarding closes it. It looks after itself rather than leaving it to
/// the main window, which may be closed: it closes when the session is minimized or ends, and when
/// it opens without being asked for (restored at launch) it shows the session, or closes if
/// there's none.
struct SessionWindow: View {
    static let id = "session"
    let model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @State private var closing: Task<Void, Never>?

    var body: some View {
        SessionScreen()
            .formStyle(.grouped)
            .environment(model)
            .environment(model.purchases)
            .frame(minWidth: 820, minHeight: 600)
            .onAppear {
                if model.live == nil { dismissWindow(id: Self.id) } else { model.showSession = true }
            }
            .onDisappear {
                closing?.cancel()
                model.showSession = false
            }
            // Minimized, finished or discarded.
            .onChange(of: model.showSession && model.live != nil) { _, shown in
                closing?.cancel()
                guard !shown else { return }
                // A finished session's summary is a sheet on the main window: bring that back (or
                // forward) to show it.
                if model.finished != nil { openWindow(id: LiftTrackApp.mainWindow) }
                closing = Task { await close() }
            }
    }

    /// Closes the window once nothing holds it open. It can't close while a sheet is still leaving
    /// it (the feedback sheet that finished the session, the discard confirmation), and asking then
    /// does nothing, so it asks again until the window goes, for a few seconds at most.
    private func close() async {
        for _ in 0..<30 where !Task.isCancelled {
            dismissWindow(id: Self.id)
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}

/// Lift Track's settings as a Mac settings window: a pane for each part.
struct MacSettings: View {
    let model: AppModel

    var body: some View {
        Group {
            if model.onboarded, let profile = model.profile {
                TabView {
                    Tab("Training", systemImage: "dumbbell") {
                        // A stack for Focus, which opens from a row.
                        NavigationStack { TrainingSettings().formStyle(.grouped) }
                    }
                    Tab("About You", systemImage: "person.crop.circle") { ProfileEditor(profile: profile).formStyle(.grouped) }
                    Tab("Outside the Gym", systemImage: "figure.martial.arts") { RecurringScreen(profile: profile) }
                    Tab("Gym", systemImage: "building.2") { GymEditor(gym: model.gym).formStyle(.grouped) }
                    Tab("Data", systemImage: "externaldrive") { DataSettings().formStyle(.grouped) }
                }
            } else {
                ContentUnavailableView("Set up Lift Track first", systemImage: "gearshape", description: Text("Settings open once setup is done."))
            }
        }
        .environment(model)
        .environment(model.purchases)
        .frame(width: 560, height: 600)
    }
}
#endif
