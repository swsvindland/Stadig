import NutritionEngine
import SwiftUI
import SystemCore

extension View {
    /// The composer at the foot of a phone's tab, as Today has it: `isEnabled` where there's no room
    /// for the toolbar's ways to log (a compact width). A tap on the screen or a drag down it puts the
    /// keyboard away, as on Today.
    func tabComposer(_ tab: AppTab, isEnabled: Bool) -> some View {
        modifier(TabComposerFoot(tab: tab, isEnabled: isEnabled))
    }
}

private struct TabComposerFoot: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let tab: AppTab
    let isEnabled: Bool
    @FocusState private var typing: Bool
    @State private var composer = TodayComposer()
    /// The composer's height at the foot, for the page's room under its end.
    @State private var footHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            // Not where there's room: there the logger's pane keeps its keyboard while its foods scroll.
            #if os(iOS)
        .scrollDismissesKeyboard(isEnabled && sizeClass == .compact ? .interactively : .automatic)
            #endif
            // Only while typing: the rest of the time the screen's taps are its own.
            .simultaneousGesture(TapGesture().onEnded { typing = false }, including: typing ? .all : .subviews)
            .overlay {
                if covers {
                    TypingCover(composer: composer, tab: tab) { typing = false }
                        .transition(.opacity)
                }
            }
            .animation(.snappy(duration: 0.2), value: covers)
            // What a page's scroll view needs to rest clear of the field and its fade (`roomForComposer`).
            // None on Vision Pro, where the page stops at the field (`pinnedBar`).
            .environment(\.composerRoom, isEnabled && !Platform.isVision ? footHeight + Self.fade : 0)
            // Empty without room for it, rather than gone: the screen keeps its state when an iPad
            // window narrows or widens.
            .pinnedBar(.bottom) {
                if isEnabled {
                    TabComposer(tab: tab, composer: composer, typing: $typing, compact: sizeClass == .compact)
                        .onGeometryChange(for: CGFloat.self) {
                            $0.size.height
                        } action: {
                            footHeight = $0
                        }
                }
            }
    }

    /// While a phone's composer has the keyboard the page gives way to what Today shows then, so
    /// typing reads the same on every tab: what's left now and after what's typed at the top, the
    /// matches rising over the field. An iPad's page stays, with the composer at its foot.
    var covers: Bool { isEnabled && typing && sizeClass == .compact }

    /// How far the composer's ground fades in over the page (`composerGround()`'s default).
    static let fade: CGFloat = 40
}

extension EnvironmentValues {
    /// The room a phone tab's composer takes at the foot of its page, with the fade over it.
    @Entry var composerRoom: CGFloat = 0
}

extension View {
    /// Room under a tab page's scroll view for the composer at its foot. The composer's inset
    /// doesn't reach a scroll view inside the tab's navigation stack, which makes room for the tab
    /// bar only, so a page at its end had its last card under the field and its fade, out of reach
    /// of taps. On the page's own scroll view, not its whole content: a row that scrolls sideways
    /// inside it would take the room too.
    func roomForComposer() -> some View {
        modifier(RoomForComposer())
    }
}

private struct RoomForComposer: ViewModifier {
    @Environment(\.composerRoom) private var room

    func body(content: Content) -> some View {
        content.safeAreaPadding(.bottom, room)
    }
}

/// Today's typing state over a tab: the header in a line for the day the composer logs to, on the
/// ground. A tap on it puts the keyboard away, as a tap on the page does.
private struct TypingCover: View {
    @Environment(AppModel.self) private var model
    let composer: TodayComposer
    let tab: AppTab
    let dismiss: () -> Void

    var body: some View {
        let day = tab == .log ? model.selectedDay : model.today
        TypingHeader(targets: model.targets(on: day), eaten: model.dayIntake(on: day).eaten, adding: composer.adding)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background {
                Ink.ground.ignoresSafeArea()
                    .contentShape(.rect)
                    .onTapGesture(perform: dismiss)
            }
    }
}

/// The composer at the foot of a phone's Log, Plan and Progress: Today's field, logging where it
/// is. What's typed raises the same matches over it and Return logs the best of each part (a list
/// with commas, a quick add, words worked out in place, whose rows sit over the field while they're
/// worked out or asked about); with the keyboard up and nothing typed, today's usual foods are a tap
/// each over it, as on Today; the camera opens the scanner and the microphone describe; the toast,
/// with Undo, shows over it. The Log tab's logs to the day it shows, and while foods are picked out
/// there the selection's bar takes the field's place.
struct TabComposer: View {
    @Environment(AppModel.self) private var model
    let tab: AppTab
    let composer: TodayComposer
    var typing: FocusState<Bool>.Binding
    /// A phone's width, where the page gives way while typing and the tiles have the room.
    let compact: Bool

    var body: some View {
        let typed = !composer.text.trimmingCharacters(in: .whitespaces).isEmpty
        let rows = model.estimates.filter { $0.isRow && composer.asked.contains($0.asked) }
        VStack(alignment: .leading, spacing: 8) {
            if model.logger == nil, !model.toastCovered { ToastSlot().padding(.horizontal, -16) }
            ForEach(rows) { estimate in
                EstimateRow(estimate: estimate)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.cardBackground, in: .rect(cornerRadius: 18, style: .continuous))
            }
            if model.selection.isEmpty {
                if typed, !composer.matches.isEmpty {
                    ComposerMatches(composer: composer, prefix: "tab")
                } else if showsTiles(typed: typed) {
                    UsualTiles(composer: composer, most: rows.isEmpty ? 4 : 2, prefix: "tab")
                        .transition(.opacity)
                }
                if !composer.earlier.isEmpty { ComposerChips(parts: composer.earlier, typed: composer.parts) }
                ComposerField(composer: composer, typing: typing, placeholder: placeholder, prefix: "tab")
            } else {
                SelectionBar().frame(height: ComposerField.height).composerCapsule()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        // As Today's: the foot stops growing where the screen above would lose its room.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .composerGround()
        .animation(.snappy(duration: 0.25), value: composer.matches)
        .animation(.snappy(duration: 0.25), value: rows)
        .animation(.snappy(duration: 0.2), value: typing.wrappedValue)
        .onAppear {
            composer.logsToSelectedDay = tab == .log
            composer.attach(model)
        }
        .onChange(of: model.personalVersion) { _, _ in composer.attach(model) }
        // Again when the person's own foods change: taking them drops the answers kept so far.
        .task(id: TodayComposer.SearchKey(text: composer.text, foods: model.personalVersion)) { await composer.search() }
        // The tiles are for the hour it is when the keyboard comes up, as Today's are when it shows.
        .onChange(of: typing.wrappedValue) { _, now in if now { composer.refreshTiles() } }
        // Picking out foods while typing: the bar has the foot, so the keyboard goes.
        .onChange(of: model.selection.isEmpty) { _, empty in if !empty { typing.wrappedValue = false } }
    }

    /// Today's usual foods, over an empty field with the keyboard up on a phone: only where the
    /// composer logs to today, since "usually around now" means nothing for last Tuesday.
    func showsTiles(typed: Bool) -> Bool {
        compact && typing.wrappedValue && !typed && !composer.tiles.isEmpty && (tab != .log || model.selectedDay == model.today)
    }

    /// Where Return logs, said where it isn't today: the Log tab on another day.
    var placeholder: String {
        tab == .log ? TodayComposer.placeholder(for: model.selectedDay, today: model.today) : TodayComposer.placeholder
    }
}
