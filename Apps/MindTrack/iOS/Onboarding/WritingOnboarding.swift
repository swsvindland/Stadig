import SwiftUI
import MindEngine

/// Writing: the kinds you want to get better at, and how the writing is done and measured.
struct WritingOnboarding: View {
    @Binding var settings: MindSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Writing").font(.title.bold())
            Text("Which kinds of writing do you want to improve? Pick any. Each session brings one short piece; the notes on it are two or three specific fixes, never a grade.")
                .foregroundStyle(.secondary)
            ForEach(WritingKind.allCases) { kind in
                let on = settings.writingKinds.contains(kind)
                Button {
                    if on { if settings.writingKinds.count > 1 { settings.writingKinds.removeAll { $0 == kind } } }
                    else { settings.writingKinds.append(kind) }
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(kind.label).font(.headline)
                            Text(kind.detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.title2).foregroundStyle(on ? Color.accentColor : .secondary)
                    }
                    .card()
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            VStack(alignment: .leading, spacing: 12) {
                Label("Type, or write by hand: with Apple Pencil on iPad, or on paper and scan it. Handwriting is read on this device, and you check the text before handing it in.",
                      systemImage: "pencil.and.scribble")
                Label("The Franklin method: read a passage, take brief notes, rewrite it from the notes in a later session, then compare with the original.",
                      systemImage: "text.book.closed")
                Label("Measured, not judged: slips per 100 words, range of vocabulary and variety in sentence length, shown as trends. Each term, a benchmark piece and older and newer pieces side by side, unlabelled.",
                      systemImage: "chart.line.uptrend.xyaxis")
            }
            .font(.subheadline)
            .card()
        }
    }

    static func firstSession(_ settings: MindSettings) -> String? { "Writing: one item for each skill" }
}

/// The kinds of writing to work on, and every piece written so far.
struct WritingSettings: View {
    @Environment(AppModel.self) private var model
    let settings: MindSettings

    var body: some View {
        Section {
            ForEach(WritingKind.allCases) { kind in
                Toggle(kind.label, isOn: Binding(get: { settings.writingKinds.contains(kind) }, set: { on in
                    var s = settings
                    s.writingKinds = on ? s.writingKinds + [kind] : s.writingKinds.filter { $0 != kind }
                    if !s.writingKinds.isEmpty { model.save(settings: s) }
                }))
            }
            if !model.pieces.isEmpty {
                NavigationLink {
                    PiecesList()
                } label: {
                    LabeledContent("Your writing", value: "\(model.pieces.count)")
                }
            }
        } header: {
            Text("Writing")
        } footer: {
            Text("Kinds take turns, one piece a session. The term's benchmark uses the first kind you chose, so it stays the same prompt to compare. Handwriting is read on this device.")
        }
    }
}
