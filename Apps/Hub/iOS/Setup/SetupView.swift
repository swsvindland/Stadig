import HubEngine
import SwiftUI
import SystemCore

/// The first run: when you work or study, and when you sleep. That's all it needs, because each app
/// already knows its own part.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var pattern: WorkPattern?
    @State private var wake = Rhythm.standardWake
    @State private var bed = Rhythm.standardBed

    private var monday: Day { model.today.startOfWeek }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Stadig plans around your week")
                    .font(.largeTitle.bold())
                    .accessibilityIdentifier("setup.title")
                Text("Tell it when you work or study. It fits the gym, meals and study around that, and the time that's left stays yours.")
                    .foregroundStyle(.secondary)
                ScheduleCard(
                    pattern: Binding(
                        get: { pattern ?? SchedulePreset.nineToFive.pattern(anchor: monday) },
                        set: { pattern = $0 }), monday: monday)
                SleepCard(wake: $wake, bed: $bed)
                Button("Start") {
                    model.finishSetup(pattern: pattern ?? SchedulePreset.nineToFive.pattern(anchor: monday), wake: wake, bed: bed)
                }
                .primaryAction()
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("setup.start")
            }
            .padding(16)
            .readableWidth(560)
        }
        .background(.pageBackground)
    }
}
