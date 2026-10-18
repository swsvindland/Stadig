import SwiftUI
import MindEngine

/// The language courses' questions: what Japanese script you read already, and whether speaking
/// exercises can use the microphone.
struct LanguageOnboarding: View {
    @Binding var settings: MindSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Languages").font(.title.bold())
            Text("Listening and speaking come first. The first session finds how many words you know already.").foregroundStyle(.secondary)
            if settings.mode(.japanese) == .focus {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Can you read hiragana and katakana?", systemImage: Domain.japanese.symbol).font(.headline)
                    Picker("Kana", selection: Binding(get: { settings.readsKana ?? true }, set: { settings.readsKana = $0 })) {
                        Text("Yes").tag(true)
                        Text("Not yet").tag(false)
                    }
                    .pickerStyle(.segmented)
                    Text(settings.readsKana == false ? "You'll start with hiragana; words follow once it's in." : "You'll start with a word test to find your vocabulary.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .card()
            }
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $settings.speaking) {
                    Label("Speaking exercises", systemImage: "mic.fill").font(.headline)
                }
                Text("You answer out loud and on-device speech recognition checks you. Nothing leaves the phone. Turn it off for now if you're often somewhere you can't speak.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .card()
        }
        .onAppear { if settings.readsKana == nil { settings.readsKana = true } }
    }

    static func firstSession(_ domain: Domain, settings: MindSettings) -> String? {
        if domain == .japanese, settings.readsKana == false { return "Japanese: your first hiragana" }
        return "\(domain.label): words from common to rare"
    }
}

/// Settings for the language courses: script, speaking and the voice each one is read in.
struct LanguageSettings: View {
    @Environment(AppModel.self) private var model
    let settings: MindSettings

    var body: some View {
        Section {
            if settings.has(.japanese) {
                Toggle("I can read kana", isOn: Binding(get: { settings.readsKana != false }, set: { on in
                    var s = settings
                    s.readsKana = on
                    model.save(settings: s)
                }))
            }
            Toggle("Speaking exercises", isOn: Binding(get: { settings.speaking }, set: { on in
                var s = settings
                s.speaking = on
                model.save(settings: s)
            }))
            ForEach(settings.languages) { domain in
                if let language = domain.language {
                    LabeledContent("\(domain.label) voice", value: model.speech.voiceName(language))
                }
            }
            if settings.languages.contains(where: { $0.language.map { !model.speech.hasNaturalVoice($0) } ?? false }) {
                Text("For a more natural voice, download an enhanced voice for the language in Settings → Accessibility → Spoken Content → Voices.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Languages")
        } footer: {
            Text("Speaking is checked by on-device speech recognition. Turn it off for a while if you're often somewhere you can't talk.")
        }
    }
}
