import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

// The scoreboard (docs/lift-track.md): an iPad propped against the wall three metres from the bar.
// In landscape the session's left two-thirds is the set at cinema scale, with three rating zones big
// enough for a knuckle; the right third is the whole session as a tape. Rest takes the left side
// over with the countdown at the same scale. Everything it does goes through the calls the dock
// makes (`SetDraft`, `AppModel.update`), so logging here is logging there.

/// The iPad's scoreboard: the set or the rest on the left, the session's tape on the right.
struct Scoreboard: View {
    @Environment(AppModel.self) private var model
    let live: LiveSession
    let finish: () -> Void

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                left
                    .frame(width: geometry.size.width * 2 / 3)
                    .frame(maxHeight: .infinity)
                SessionTape(live: live)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.cardBackground)
            }
        }
        .background(.pageBackground)
        // A container of its own, so the identifier isn't given to every element in it.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session.scoreboard")
        // Read from across the room: the screen stays on while the board is up.
        .onAppear { Platform.keepScreenAwake(true) }
        .onDisappear { Platform.keepScreenAwake(false) }
    }

    @ViewBuilder
    private var left: some View {
        if let rest = model.activeRest {
            BoardRest(live: live, rest: rest)
        } else if let (item, set) = live.current, let kind = FloorSet(current: live, catalog: model.catalog) {
            BoardSet(live: live, item: item, set: set, kind: kind)
                .id(live.items[item].sets[set].id)
        } else {
            // A conditioning piece, the sauna, or every set done: the logger as the two panes have it.
            VStack(alignment: .leading, spacing: 16) {
                if let index = live.current?.item {
                    Text(model.catalog.resolve(live.items[index].exerciseID).name)
                        .font(.system(size: 56, weight: .heavy)).tracking(-2)
                        .foregroundStyle(Ink.text)
                        .lineLimit(2).minimumScaleFactor(0.5)
                }
                Spacer(minLength: 0)
                BottomPanel(finish: finish)
            }
            .padding(40)
        }
    }
}
