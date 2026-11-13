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

    func body(content: Content) -> some View {
        content
            // Not where there's room: there the logger's pane keeps its keyboard while its foods scroll.
            #if os(iOS)
        .scrollDismissesKeyboard(isEnabled && sizeClass == .compact ? .interactively : .automatic)
            #endif
            // Only while typing: the rest of the time the screen's taps are its own.
            .simultaneousGesture(TapGesture().onEnded { typing = false }, including: typing ? .all : .subviews)
            // Empty without room for it, rather than gone: the screen keeps its state when an iPad
            // window narrows or widens.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isEnabled { TabComposer(tab: tab, typing: $typing) }
            }
    }
}

/// The composer at the foot of a phone's Log, Plan and Progress: Today's field, logging where it
/// is. What's typed raises the same matches over it and Return logs the best of each part (a list
/// with commas, a quick add, words worked out in place, whose rows sit over the field while they're
/// worked out or asked about); the camera opens the scanner and the microphone describe; the toast,
/// with Undo, shows over it. The Log tab's logs to the day it shows, and while foods are picked out
/// there the selection's bar takes the field's place.
struct TabComposer: View {
    @Environment(AppModel.self) private var model
    let tab: AppTab
    var typing: FocusState<Bool>.Binding
    @State private var composer = TodayComposer()

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
                if typed, !composer.matches.isEmpty { ComposerMatches(composer: composer, prefix: "tab") }
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
        .onAppear {
            composer.logsToSelectedDay = tab == .log
            composer.attach(model)
        }
        .onChange(of: model.personalVersion) { _, _ in composer.attach(model) }
        // Again when the person's own foods change: taking them drops the answers kept so far.
        .task(id: TodayComposer.SearchKey(text: composer.text, foods: model.personalVersion)) { await composer.search() }
        // Picking out foods while typing: the bar has the foot, so the keyboard goes.
        .onChange(of: model.selection.isEmpty) { _, empty in if !empty { typing.wrappedValue = false } }
    }

    /// Where Return logs, said where it isn't today: the Log tab on another day.
    var placeholder: String {
        tab == .log ? TodayComposer.placeholder(for: model.selectedDay, today: model.today) : TodayComposer.placeholder
    }
}
