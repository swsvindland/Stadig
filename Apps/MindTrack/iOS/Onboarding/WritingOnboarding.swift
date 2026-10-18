import SwiftUI
import MindEngine

/// Writing: the kinds you want to get better at.
struct WritingOnboarding: View {
    @Binding var settings: MindSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Writing").font(.title.bold())
            Text("Which kinds of writing do you want to improve? Feedback is always a few specific fixes, never a grade.").foregroundStyle(.secondary)
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
        }
    }

    static func firstSession(_ settings: MindSettings) -> String? { "Writing: one item for each skill" }
}

/// The kinds of writing to work on.
struct WritingSettings: View {
    @Environment(AppModel.self) private var model
    let settings: MindSettings

    var body: some View {
        Section("Writing") {
            ForEach(WritingKind.allCases) { kind in
                Toggle(kind.label, isOn: Binding(get: { settings.writingKinds.contains(kind) }, set: { on in
                    var s = settings
                    s.writingKinds = on ? s.writingKinds + [kind] : s.writingKinds.filter { $0 != kind }
                    if !s.writingKinds.isEmpty { model.save(settings: s) }
                }))
            }
        }
    }
}
