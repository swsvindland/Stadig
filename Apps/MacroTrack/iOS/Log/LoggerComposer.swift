import NutritionEngine
import SwiftUI
import SystemCore

// The logger on a phone is the composer opened: searching reads as Today's typing state. At the top,
// where the foods go and the day's numbers now → after the best match; in the middle the matches,
// rising from the field with the best nearest it; at the foot the meal so far, the time, and the
// composer's own field, with the camera and the microphone for the other ways. The pane beside
// the Log tab, where there's room, keeps its field at the top (`LoggerHeader`).

/// The logger's top on a phone: where the foods go, the round ×, and under them what's left now and
/// after the best match, as Today's typing header has it. Another way of logging has its name there.
struct LoggerTop: View {
    @Environment(AppModel.self) private var model
    let session: LoggerSession
    let done: () -> Void

    var body: some View {
        let searching = session.mode == .search
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(LogTime.eyebrow(model)).eyebrow().lineLimit(1)
                    .accessibilityIdentifier("logger.when")
                Spacer(minLength: 8)
                if searching {
                    // The one way with no button on the field: a tap from the search.
                    Button {
                        session.openQuickAdd()
                    } label: {
                        InkChip(title: "Quick add", symbol: "plus")
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight()
                    .accessibilityLabel("Quick add calories")
                    .accessibilityIdentifier("logger.quickAdd")
                }
                CircleIconButton(symbol: "xmark", label: "Done", identifier: "logger.done", action: done)
            }
            if searching {
                let day = model.selectedDay
                TypingHeader(targets: model.targets(on: day), eaten: model.dayIntake(on: day).eaten, adding: session.adding(model))
                if session.review != nil { LoggerReviewBanner(session: session).padding(.top, 2) }
            } else {
                PageTitle(session.mode.title, size: 28)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        // As Today's header: the list fades in under it rather than being cut at it.
        .background {
            #if !os(visionOS)
            VStack(spacing: 0) {
                Ink.ground
                LinearGradient(colors: [Ink.ground, Ink.ground.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 22)
            }
            .padding(.bottom, -22)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            #endif
        }
        // As Today's: the header stops growing where the list would lose its room.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// The logger's foot on a phone: the toast, the meal so far, where a search is heading, the time,
/// and the field. While searching it's the composer's ground, the list fading under it; on another
/// way it's solid, since what's above it is often that way's own button (Add, Log, Find foods).
struct LoggerFoot: View {
    @Environment(AppModel.self) private var model
    let session: LoggerSession
    /// An amount or a food is over it: a toast's few seconds would run out unseen.
    let covered: Bool
    var searchFocused: FocusState<Bool>.Binding

    var body: some View {
        let searching = session.mode == .search
        let typed = searching && !session.query.trimmingCharacters(in: .whitespaces).isEmpty
        VStack(alignment: .leading, spacing: 10) {
            // Over the meal it just changed, where the eye already is after a tap on +.
            if !covered, !model.toastCovered { ToastSlot().padding(.horizontal, -16) }
            // While typing the room is the matches': the meal is back once the food's in. With no
            // meal it's nothing, and takes no room (it stays for the sheet it hangs on).
            if !typed { MealTray().padding(.bottom, model.mealBeingLogged(at: nil) == nil ? -10 : 0) }
            // Not for calories typed: the foods "300 kcal" finds aren't where it's heading.
            if typed, session.quickAddPart == nil { SearchCompletionChips(options: session.completions, pick: session.complete) }
            LogTimeBar()
            if searching {
                LoggerField(session: session, focused: searchFocused)
            } else {
                LoggerFieldAtRest(session: session)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        // Over the matches less far than the composer's over the day: the best one sits just above.
        .composerGround(fade: searching ? 24 : 0)
        .animation(.snappy, value: model.toast)
        .animation(.snappy(duration: 0.25), value: typed)
    }
}

/// The logger's search as the composer's field (`ComposerField`): 54 high and round-ended on the
/// surface, the accent's line while typing. Empty, the camera and the microphone are the other ways
/// in; with something typed, clear and the arrow that logs the best match, as Return does, keeping
/// the keyboard for the next food.
struct LoggerField: View {
    @Environment(AppModel.self) private var model
    @Bindable var session: LoggerSession
    var focused: FocusState<Bool>.Binding

    var body: some View {
        let empty = session.query.trimmingCharacters(in: .whitespaces).isEmpty
        HStack(spacing: 4) {
            TextField("Search foods", text: $session.query, prompt: Text("Search foods").foregroundStyle(Ink.text3))
                // The capsule is the field: no bezel of the Mac's inside it.
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(Ink.text)
                .focused(focused)
                .autocorrectionDisabled()
                .noAutocapitalization()
                .submitLabel(.return)
                .onSubmit(submit)
                .accessibilityIdentifier("logger.search")
                .padding(.leading, 18)
                .frame(maxHeight: .infinity)
            if empty {
                LoggerWays(session: session) { focused.wrappedValue = true }
            } else {
                Button("Clear", systemImage: "xmark.circle.fill") {
                    session.query = ""
                    session.focusSearch()
                }
                .labelStyle(.iconOnly)
                .font(.body)
                .foregroundStyle(Ink.text3)
                .frame(width: 40, height: 44)
                .contentShape(.rect)
                .buttonStyle(.plain)
                .accessibilityIdentifier("logger.clearSearch")
                Button(action: submit) {
                    Image(systemName: "arrow.up").font(.body.weight(.bold)).foregroundStyle(Ink.ground)
                        .frame(width: 40, height: 40).background(Color.accentColor, in: .circle).contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Log the best match")
                .accessibilityIdentifier("logger.send")
            }
        }
        .padding(.trailing, 7)
        .frame(height: ComposerField.height)
        .composerCapsule(focused: focused.wrappedValue)
    }

    /// Return logs the best match and keeps the keyboard for the next food; with nothing typed it's
    /// the way out of the keyboard, as the composer's is.
    private func submit() {
        guard !session.query.trimmingCharacters(in: .whitespaces).isEmpty else {
            focused.wrappedValue = false
            return
        }
        session.pressedReturn(model)
        focused.wrappedValue = true
    }
}

/// The field at rest on another way of logging: the same capsule, and a tap on it is the search with
/// the keyboard. The camera and the microphone stay beside it, to go from one way to another.
struct LoggerFieldAtRest: View {
    let session: LoggerSession

    var body: some View {
        HStack(spacing: 4) {
            Button {
                session.backToSearch()
            } label: {
                Text("Search foods")
                    .font(.body)
                    .foregroundStyle(Ink.text3)
                    .padding(.leading, 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search foods")
            .accessibilityIdentifier("logger.backToSearch")
            LoggerWays(session: session) { session.backToSearch() }
        }
        .padding(.trailing, 7)
        .frame(height: ComposerField.height)
        .composerCapsule()
    }
}

/// The camera (a barcode or label, and held for a photo of the plate or one chosen) and the
/// microphone (describe), as the composer has them, going to those ways in the logger. The one the
/// logger is on is lit.
struct LoggerWays: View {
    @Environment(AppModel.self) private var model
    let session: LoggerSession
    /// The microphone where the device's model can't read a sentence: the keyboard's own dictation.
    let dictate: () -> Void

    var body: some View {
        let camera = session.mode == .scan || session.mode.isPhoto
        Button {
            session.mode = .scan
        } label: {
            Image(systemName: "camera").font(.title3).foregroundStyle(camera ? Color.accentColor : Ink.text)
                .frame(width: 44, height: 44).contentShape(.circle)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Scan a Barcode or Label", systemImage: "barcode.viewfinder") { session.mode = .scan }
            if model.ai.canSeePhotos || waiting(on: .camera, .photoLibrary) {
                Button("Photo of Your Plate", systemImage: "camera") { session.mode = .camera }
                Button("Choose a Photo", systemImage: "photo") { session.mode = .photoLibrary }
            }
        }
        .accessibilityLabel("Camera: barcode, label or plate")
        .accessibilityAddTraits(camera ? .isSelected : [])
        .accessibilityIdentifier("logger.camera")
        Button {
            // Said to the model where it can read a sentence (or a review it read is waiting).
            if model.ai.canDescribe || waiting(on: .describe) { session.mode = .describe } else { dictate() }
        } label: {
            Image(systemName: "mic.fill").font(.body.weight(.semibold)).foregroundStyle(Ink.ground)
                .frame(width: 40, height: 40).background(Color.accentColor, in: .circle).contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Say what you ate")
        .accessibilityAddTraits(session.mode == .describe ? .isSelected : [])
        .accessibilityIdentifier("logger.describe")
    }

    /// A review left unlogged is reached through its way of logging, even if the model has gone.
    func waiting(on ways: LogMode...) -> Bool { session.review.map { ways.contains($0.mode) } ?? false }
}

extension LogMode {
    /// A way of logging's name, over it in the logger.
    var title: String {
        switch self {
        case .search: "Search"
        case .scan: LiveScan.isAvailable ? "Scan" : "Barcode"
        case .camera, .photoLibrary: "Photo"
        case .describe: "Describe"
        case .quickAdd: "Quick add"
        }
    }
}

extension LogTime {
    /// Where the logger's foods go, over its header: "Today · Now", "Today · 9:00 AM",
    /// "Yesterday · 7:30 PM", "Thu, Nov 12 · 7:00 PM".
    @MainActor
    static func eyebrow(_ model: AppModel) -> String {
        let date = model.logDate()
        let day = Day(date)
        let name =
            switch model.today.days(until: day) {
            case 0: "Today"
            case -1: "Yesterday"
            default: Format.day(day)
            }
        let when = model.selectedDay == model.today && model.loggerTime == nil ? "Now" : Format.time(date)
        return "\(name) · \(when)"
    }
}
