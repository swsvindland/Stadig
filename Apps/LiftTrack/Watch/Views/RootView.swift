import SwiftUI

/// Home, the session in progress, or the summary of the one just finished.
struct RootView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        if let summary = model.summary {
            NavigationStack { SummaryView(summary: summary) }
        } else if model.session != nil {
            SessionView()
        } else {
            NavigationStack { HomeView() }
        }
    }
}
