#if DEBUG
import NutritionEngine
import SwiftUI
import SystemCore
import WidgetKit

/// `-complications`: every complication at about its size on a 46 mm face, with the app's own
/// numbers, to look at in the simulator, which a script can't put a complication on a face in.
/// The face's own chrome (the corner's curved gauge, the inline row) is the system's, so it's only
/// roughly here.
struct ComplicationGallery: View {
    @Environment(WristModel.self) private var model

    var body: some View {
        let snapshot = model.today.map { WristSnapshot($0) } ?? .sample(on: .today)
        ScrollView {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    tile(.kcal, snapshot, .accessoryCircular).frame(width: 52, height: 52)
                    tile(.protein, snapshot, .accessoryCircular).frame(width: 52, height: 52)
                    tile(.kcal, snapshot, .accessoryCorner).frame(width: 32, height: 32)
                    tile(.protein, snapshot, .accessoryCorner).frame(width: 32, height: 32)
                }
                tile(.kcal, snapshot, .accessoryRectangular).frame(width: 180, height: 58)
                tile(.protein, snapshot, .accessoryRectangular).frame(width: 180, height: 58)
                tile(.kcal, snapshot, .accessoryInline).frame(width: 180, height: 20)
                tile(.protein, snapshot, .accessoryInline).frame(width: 180, height: 20)
                TodayStackView(snapshot: snapshot)
                    .padding(8)
                    .frame(width: 180, height: 70)
                    .background(Color.accentColor.opacity(0.25).gradient, in: .rect(cornerRadius: 14))
                HStack(spacing: 8) {
                    fast(snapshot, .accessoryCircular).frame(width: 52, height: 52)
                    fast(snapshot, .accessoryCorner).frame(width: 32, height: 32)
                }
                fast(snapshot, .accessoryRectangular).frame(width: 180, height: 58)
                fast(snapshot, .accessoryInline).frame(width: 180, height: 20)
            }
        }
        .navigationTitle("Complications")
    }

    private func fast(_ snapshot: WristSnapshot, _ family: WidgetFamily) -> some View {
        FastComplication(snapshot: snapshot, date: Date(), family: family)
            .overlay { RoundedRectangle(cornerRadius: 4).stroke(.gray.opacity(0.4), lineWidth: 0.5) }
    }

    private func tile(_ macro: ComplicationMacro, _ snapshot: WristSnapshot, _ family: WidgetFamily) -> some View {
        MacroComplication(macro: macro, snapshot: snapshot, family: family)
            .overlay { RoundedRectangle(cornerRadius: 4).stroke(.gray.opacity(0.4), lineWidth: 0.5) }
    }
}
#endif
