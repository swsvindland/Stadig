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
        #if os(macOS)
        // One main window: its tab and sheets live in the shared model, so a second would mirror the
        // first. "New" is the session instead, in the Session menu.
        CommandGroup(replacing: .newItem) {}
        #else
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { model?.showSettings = true }
                .keyboardShortcut(",")
                .disabled(model?.onboarded != true)
        }
        #endif
        CommandMenu("Session") {
            Button("Start Today's Session") {
                showMain()
                model?.startToday()
            }
            .keyboardShortcut("n")
            .disabled(model?.onboarded != true || model?.canStartToday != true)
            Button("Resume Session") { model?.showSession = true }
                .keyboardShortcut("r")
                .disabled(model?.live == nil || model?.showSession == true)
            Divider()
            Button("Finish Session…") {
                model?.showSession = true
                model?.sessionRequest = .finish
            }
            .keyboardShortcut(.return, modifiers: [.command, .shift])
            .disabled(model?.live == nil)
            Button("Discard Session…") {
                model?.showSession = true
                model?.sessionRequest = .discard
            }
            .disabled(model?.live == nil)
        }
        CommandMenu("Log") {
            Button("Outside Activity…") { present(.logActivity) }
                .keyboardShortcut("l")
            Button("Check-in…") { present(.checkIn) }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Button("Measurements…") { present(.measurements) }
                .keyboardShortcut("m", modifiers: [.command, .shift])
        }
        CommandMenu("Plan") {
            Button("Plan Next Block…") { present(.nextBlock) }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(model?.nextBlockOffered != true)
            Divider()
            Button("Show Program") { go(.program) }
            Button("Show Library") { go(.library) }
        }
        CommandMenu("Go") {
            ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) { go(tab) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
            }
        }
    }

    private func present(_ sheet: AppSheet) {
        guard let model, model.onboarded else { return }
        showMain()
        model.sheet = sheet
    }

    private func go(_ tab: AppTab) {
        guard let model, model.onboarded else { return }
        showMain()
        model.tab = tab
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
/// Session menu); finishing or discarding closes it.
struct SessionWindow: View {
    static let id = "session"
    let model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        SessionScreen()
            .formStyle(.grouped)
            .environment(model)
            .environment(model.purchases)
            .frame(minWidth: 820, minHeight: 600)
            .onDisappear { model.showSession = false }
            .onChange(of: model.live == nil) { _, ended in
                if ended { dismissWindow(id: Self.id) }
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
                    Tab("Training", systemImage: "dumbbell") { TrainingSettings().formStyle(.grouped) }
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
