#if DEBUG
import NutritionEngine
import SwiftUI
import SystemCore
import WidgetKit

/// `-complications`: every complication at about its size, with the app's own numbers, to look at in
/// the simulator, which a script can't put a complication on a face in. The first screen is the
/// design's face (calories in the corner, calories left across the middle, Your shape, protein and
/// water along the foot); the rest scroll below. The face's own chrome (the corner's curved gauge,
/// the inline row) is the system's, so it's only roughly here. With no scores published yet (a
/// sample store has none), Your shape shows the design's.
struct ComplicationGallery: View {
    @Environment(WristModel.self) private var model

    var body: some View {
        let snapshot = gallerySnapshot
        ScrollView {
            VStack(spacing: 8) {
                face(snapshot)
                    .frame(width: WristFace.width, height: WristFace.height)
                tile(.protein, snapshot, .accessoryRectangular).frame(width: 180, height: 58)
                tile(.kcal, snapshot, .accessoryInline).frame(width: 180, height: 20)
                tile(.protein, snapshot, .accessoryInline).frame(width: 180, height: 20)
                WaterComplication(water: snapshot.water, fluidOunces: snapshot.fluidOunces ?? false, family: .accessoryInline)
                    .frame(width: 180, height: 20)
                HStack(spacing: 8) {
                    tile(.kcal, snapshot, .accessoryCircular).frame(width: 52, height: 52)
                    tile(.protein, snapshot, .accessoryCorner).frame(width: 32, height: 32)
                }
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
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
    }

    /// The app's own numbers, with the design's shape and a litre of water where the sample has none.
    private var gallerySnapshot: WristSnapshot {
        var snapshot = model.today.map { WristSnapshot($0) } ?? .sample(on: .today)
        if snapshot.shape == nil { snapshot.shape = WristSnapshot.sampleShape }
        if snapshot.water == nil { snapshot.water = MacroProgress(eaten: 1_200, target: 3_000) }
        return snapshot
    }

    /// The design's face: the corner, the rectangular across the middle, three circulars at the foot.
    private func face(_ snapshot: WristSnapshot) -> some View {
        ZStack(alignment: .topLeading) {
            tile(.kcal, snapshot, .accessoryCorner)
                .frame(width: 44, height: 44)
                .padding(.leading, 14)
                .padding(.top, 14)
            tile(.kcal, snapshot, .accessoryRectangular)
                .frame(height: 58)
                .padding(.horizontal, 16)
                .padding(.top, 95 * WristFace.scale)
            HStack {
                ShapeComplication(shape: snapshot.shape).frame(width: 52, height: 52)
                Spacer()
                tile(.protein, snapshot, .accessoryCircular).frame(width: 52, height: 52)
                Spacer()
                WaterComplication(water: snapshot.water, fluidOunces: snapshot.fluidOunces ?? false, family: .accessoryCircular)
                    .frame(width: 52, height: 52)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 13)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func fast(_ snapshot: WristSnapshot, _ family: WidgetFamily) -> some View {
        FastComplication(snapshot: snapshot, date: Date(), family: family)
            .overlay { RoundedRectangle(cornerRadius: 4).stroke(.gray.opacity(0.4), lineWidth: 0.5) }
    }

    private func tile(_ macro: ComplicationMacro, _ snapshot: WristSnapshot, _ family: WidgetFamily) -> some View {
        MacroComplication(macro: macro, snapshot: snapshot, family: family)
    }
}
#endif
