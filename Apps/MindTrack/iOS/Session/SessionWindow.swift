import MindEngine
import SwiftUI

#if os(macOS)
/// The Mac's session window. It opens when a session starts and closes when it ends; closing it
/// ends the session the way End does (everything answered is kept, a piece being written stays as
/// a draft), so nothing runs on unseen behind the main window.
struct SessionWindow: View {
    static let id = "session"

    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if model.run != nil {
                SessionView()
            } else {
                ContentUnavailableView {
                    Label("No session running", systemImage: "brain.head.profile")
                } description: {
                    Text("Start today's session from Today, or from Study in the menu bar.")
                }
            }
        }
        .frame(minWidth: 640, minHeight: 560)
        .onChange(of: model.run == nil) { _, ended in
            if ended { dismissWindow(id: Self.id) }
        }
        .onDisappear {
            if model.run != nil { model.endSession() }
        }
    }
}
#endif
