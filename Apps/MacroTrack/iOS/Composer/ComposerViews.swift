import FoodDatabase
import NutritionEngine
import SwiftUI
import SystemCore

// The composer's pieces, the same on a phone's every tab: Today's foot (`TodayLogger`) and the foot
// of Log, Plan and Progress (`TabComposer`). `prefix` names where it is for the UI tests: "today" on
// Today, "tab" on the others.

/// What the food being typed could be, rising above the field: the best one nearest it, marked
/// with the key that logs it.
struct ComposerMatches: View {
    @Environment(AppModel.self) private var model
    let composer: TodayComposer
    var prefix = "today"

    var body: some View {
        let count = composer.earlier.compactMap(\.entry).count + 1
        VStack(spacing: 4) {
            ForEach(Array(composer.matches.enumerated().reversed()), id: \.element.id) { index, match in
                Button {
                    composer.log(match)
                } label: {
                    row(match, best: index == 0, count: count)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(prefix).match.\(index)")
            }
        }
    }

    func row(_ match: TodayComposer.Candidate, best: Bool, count: Int) -> some View {
        HStack(spacing: 12) {
            switch match.kind {
            // Each match's marker on the surface, as the thread's are; the best one's is on its card.
            case .food: FoodTile(name: match.entry.name, size: 40, fill: best ? Ink.raised : Ink.surface)
            case .quickAdd, .unmatched:
                Text("≈").font(.title3.weight(.semibold)).foregroundStyle(Ink.text2).frame(width: 40, height: 40)
                    .background(best ? Ink.raised : Ink.surface, in: .rect(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 2) {
                // The name it's said by, then what tells it from the next one: catalog names differ
                // late ("…, meat only" from "…, meat and skin"). Two lines at most.
                title(match).lineLimit(2)
                Text(detail(match)).font(.caption).foregroundStyle(Ink.text3).lineLimit(1)
            }
            Spacer(minLength: 6)
            if best {
                Text(count > 1 ? "return · logs \(count)" : "return")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Ink.text2)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Ink.raised, in: .rect(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Ink.hairline))
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .frame(minHeight: 56)
        // Only the best one is a card, outlined in the accent: the key that logs it is on it.
        .background(best ? Color.cardBackground : .clear, in: .rect(cornerRadius: 18, style: .continuous))
        .overlay {
            if best { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.accentColor, lineWidth: 1.5) }
        }
        .contentShape(.rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityHint(best ? "Return logs it" : "")
    }

    func title(_ match: TodayComposer.Candidate) -> Text {
        let name = match.title(canDescribe: model.ai.canDescribe)
        let short = Text(name.short).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
        guard let rest = name.rest else { return short }
        return Text("\(short)  \(Text(rest).font(.caption).foregroundStyle(Ink.text2))")
    }

    func detail(_ match: TodayComposer.Candidate) -> String { match.detail(model.ai) }
}

/// The foods typed before the one being typed, as they'll be logged.
struct ComposerChips: View {
    let parts: [TodayComposer.Resolved]
    let typed: [AddFoodPart]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(parts) { part in
                    Text(label(part))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Ink.text)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Color.cardBackground, in: .capsule)
                        .overlay(Capsule().stroke(Ink.hairline))
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Also logging")
    }

    func label(_ part: TodayComposer.Resolved) -> String {
        if let entry = part.entry {
            if entry.source == .quickAdd { return "≈ \(Format.kcal(entry.nutrients.kcal))" }
            return "\(FoodMarker.of(entry.name)) \(FoodLabel.title(entry.name)) · \(entry.amountLabel)"
        }
        if let words = part.unmatched { return "≈ \(words)" }
        return typed.indices.contains(part.id) ? "\(typed[part.id].text)…" : "…"
    }
}

/// The one field: type or dictate what was eaten; the camera for a barcode, a label or a plate; the
/// microphone to say it.
struct ComposerField: View {
    @Environment(AppModel.self) private var model
    @Bindable var composer: TodayComposer
    var typing: FocusState<Bool>.Binding
    var placeholder = TodayComposer.placeholder
    var prefix = "today"

    /// The board's composer: 54 high, round-ended, on the surface.
    static let height: CGFloat = 54

    var body: some View {
        let empty = composer.text.trimmingCharacters(in: .whitespaces).isEmpty
        HStack(spacing: 4) {
            TextField(placeholder, text: $composer.text, prompt: Text(placeholder).foregroundStyle(Ink.text3))
                .font(.body)
                .foregroundStyle(Ink.text)
                .focused(typing)
                .autocorrectionDisabled()
                .noAutocapitalization()
                .submitLabel(.return)
                .onSubmit(submit)
                .accessibilityIdentifier("\(prefix).composer")
                .padding(.leading, 18)
                .frame(maxHeight: .infinity)
            if empty {
                Button {
                    typing.wrappedValue = false
                    model.openLogger(.scan)
                } label: {
                    Image(systemName: "camera").font(.title3).foregroundStyle(Ink.text).frame(width: 44, height: 44).contentShape(.circle)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Scan a Barcode or Label", systemImage: "barcode.viewfinder") { model.openLogger(.scan) }
                    if model.ai.canSeePhotos {
                        Button("Photo of Your Plate", systemImage: "camera") { model.openLogger(.camera) }
                        Button("Choose a Photo", systemImage: "photo") { model.openLogger(.photoLibrary) }
                    }
                }
                .accessibilityLabel("Camera: barcode, label or plate")
                .accessibilityIdentifier("\(prefix).camera")
                if typing.wrappedValue {
                    // Nothing typed: the way out of the keyboard sits where the eye already is.
                    // The keyboard has its own dictation, so the microphone waits until it's down.
                    Button("Close Keyboard", systemImage: "keyboard.chevron.compact.down", action: closeKeyboard)
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(Ink.text2)
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("\(prefix).closeKeyboard")
                } else {
                    Button {
                        // Said to the model where it can read a sentence; else the keyboard's own dictation.
                        if model.ai.canDescribe { model.openLogger(.describe) } else { typing.wrappedValue = true }
                    } label: {
                        Image(systemName: "mic.fill").font(.body.weight(.semibold)).foregroundStyle(Ink.ground)
                            .frame(width: 40, height: 40).background(Color.accentColor, in: .circle).contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Say what you ate")
                    .accessibilityIdentifier("\(prefix).describe")
                }
            } else {
                Button {
                    Task { await composer.submit() }
                } label: {
                    Image(systemName: "arrow.up").font(.body.weight(.bold)).foregroundStyle(Ink.ground)
                        .frame(width: 40, height: 40).background(Color.accentColor, in: .circle).contentShape(.circle)
                }
                .buttonStyle(.plain)
                .disabled(composer.submitting)
                .accessibilityLabel("Log it")
                .accessibilityIdentifier("\(prefix).send")
            }
        }
        .padding(.trailing, 7)
        .frame(height: Self.height)
        .composerCapsule(focused: typing.wrappedValue)
    }

    /// Return logs what's typed and keeps the keyboard for the next food; with nothing typed it's
    /// the way out, as Return is in Messages.
    private func submit() {
        guard !composer.text.trimmingCharacters(in: .whitespaces).isEmpty else {
            closeKeyboard()
            return
        }
        Task { await composer.submit() }
        typing.wrappedValue = true
    }

    private func closeKeyboard() { typing.wrappedValue = false }
}

extension View {
    /// The composer's capsule: the surface with a hairline, the accent's line while typing. The
    /// selection's bar takes it too when it stands in for the field.
    func composerCapsule(focused: Bool = false) -> some View {
        background(Color.cardBackground, in: .capsule)
            .overlay(Capsule().stroke(focused ? Color.accentColor : Ink.hairline, lineWidth: focused ? 1.5 : 1))
    }

    /// The ground behind a composer's foot, solid down to the screen's foot: what's on the screen
    /// scrolls under the composer and the tab bar, not out below them, and fades out over the 40
    /// points above it rather than being sliced at a label.
    func composerGround() -> some View {
        background {
            VStack(spacing: 0) {
                LinearGradient(colors: [Ink.ground.opacity(0), Ink.ground.opacity(0.85), Ink.ground], startPoint: .top, endPoint: .bottom)
                    .frame(height: 40)
                Ink.ground
            }
            .padding(.top, -40)
            .ignoresSafeArea(edges: .bottom)
        }
    }
}
