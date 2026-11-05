import MindEngine
import SwiftUI

/// The language courses' page: what a language session is now, what Japanese script you read
/// already, how two languages share the week, and whether speaking exercises can use the microphone.
struct LanguageOnboarding: View {
    @Binding var settings: MindSettings
    @State private var recognizer = SpeechRecognizer.shared
    @State private var allowed: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Languages").font(.title.bold())
                .accessibilityIdentifier("onboarding.languagesTitle")
            Text(
                "The aim is understanding real people and being understood, not conjugation tables. The first block finds how many words you know already."
            )
            .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                Label("Four skills, four levels", systemImage: "square.grid.2x2").font(.headline)
                Text(
                    "Listening, speaking, reading and writing each get their own level, like separate lifts, from their own short tests. Listening and speaking count most."
                )
                .font(.subheadline)
                Label("Real use, with drills as support", systemImage: "bubble.left.and.bubble.right").font(.headline)
                Text(
                    "New words go on spaced repetition; the rest of a block is a short dialogue, sentences by ear, saying and writing what you know, and pictures. Help under new words (furigana, romaji, a stress guide) fades word by word as each one sticks."
                )
                .font(.subheadline)
            }
            .card()
            if settings.mode(.japanese)?.learns == true {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Can you read hiragana and katakana?", systemImage: Domain.japanese.symbol).font(.headline)
                    Picker("Kana", selection: Binding(get: { settings.readsKana ?? true }, set: { settings.readsKana = $0 })) {
                        Text("Yes").tag(true)
                        Text("Not yet").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("onboarding.kana")
                    Text(
                        settings.readsKana == false
                            ? "Words start in the first block, with romaji under each kana until it sticks, and hiragana then katakana come in beside them."
                            : "You'll start with a word test to find your vocabulary."
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                }
                .card()
            }
            if settings.languages.count > 1 { TwoLanguages(settings: $settings) }
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $settings.speaking) {
                    Label("Speaking exercises", systemImage: "mic.fill").font(.headline)
                }
                .accessibilityIdentifier("onboarding.speaking")
                .onChange(of: settings.speaking) { _, on in if on { ask() } }
                Text(
                    "You answer out loud and on-device speech recognition checks you. Nothing leaves your \(Platform.deviceName). Off skips speaking without leaving a gap; turn it on again in Settings."
                )
                .font(.footnote).foregroundStyle(.secondary)
                if settings.speaking {
                    if allowed == false {
                        Text(
                            "The microphone or speech recognition isn't allowed. You can allow it in Settings later; until then, speaking is skipped."
                        )
                        .font(.footnote).foregroundStyle(.orange)
                    } else if allowed == nil {
                        Button("Allow the microphone", systemImage: "mic") { ask() }.secondaryAction()
                            .accessibilityIdentifier("onboarding.allowMicrophone")
                    }
                }
            }
            .card()
            Text("Real-world tests stay the benchmark: now and then an episode without subtitles or a real conversation, logged and never scored.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .onAppear { if settings.readsKana == nil { settings.readsKana = true } }
    }

    func ask() {
        Task { allowed = await recognizer.authorise() }
    }

    static func firstSession(_ domain: Domain, settings: MindSettings) -> String? {
        if domain == .japanese, settings.readsKana == false { return "Japanese: your first words and hiragana" }
        return "\(domain.label): words from common to rare"
    }
}

/// Two languages at once: feasible, especially dissimilar ones, but each extra Main language
/// dilutes the others. The suggestion follows the doc: Japanese as Main, Spanish in small daily
/// doses (Secondary) until kana are solid.
private struct TwoLanguages: View {
    @Binding var settings: MindSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Two languages", systemImage: "globe").font(.headline)
            Text(
                "Dissimilar languages interfere less (Japanese and Spanish less than Spanish and Italian), but time is the real limit: languages need near-daily exposure, so a second one thins out the first. If kana are new, give Spanish fewer blocks until they're solid."
            )
            .font(.subheadline)
        }
        .card()
    }
}

/// Settings for the language courses: script, speaking, recognition and the voice each one is read in.
struct LanguageSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let settings: MindSettings
    @State private var recognizer = SpeechRecognizer.shared
    @State private var recognises: [Language: Bool] = [:]

    var body: some View {
        Section {
            if settings.has(.japanese) {
                Toggle(
                    "I can read kana",
                    isOn: Binding(
                        get: { settings.readsKana != false },
                        set: { on in
                            var s = settings
                            s.readsKana = on
                            model.save(settings: s)
                        })
                )
                .accessibilityIdentifier("settings.readsKana")
            }
            Toggle(
                "Speaking exercises",
                isOn: Binding(
                    get: { settings.speaking },
                    set: { on in
                        var s = settings
                        s.speaking = on
                        model.save(settings: s)
                        if on { Task { _ = await recognizer.authorise() } }
                    })
            )
            .accessibilityIdentifier("settings.speaking")
            if settings.speaking, recognizer.permissionDenied {
                Button(Platform.isMac ? "Allow the microphone in System Settings" : "Allow the microphone in Settings", systemImage: "mic.slash") {
                    if let url = Platform.settingsURL { openURL(url) }
                }
                .accessibilityIdentifier("settings.allowMicrophone")
            }
            ForEach(settings.languages) { domain in
                if let language = domain.language {
                    LabeledContent("\(domain.label) voice", value: model.speech.voiceName(language))
                    if settings.speaking {
                        LabeledContent(
                            "\(domain.label) recognition",
                            value: recognises[language].map { $0 ? "On this device" : "Not on this device" } ?? "Checking…")
                    }
                }
            }
            if settings.languages.contains(where: { $0.language.map { !model.speech.hasNaturalVoice($0) } ?? false }) {
                Text("For a more natural voice, download an enhanced voice for the language in \(Speech.voicesSettings).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Languages")
        } footer: {
            Text(
                "Speaking is checked by on-device speech recognition, leniently: being understood is the bar. Turn it off for a while if you're often somewhere you can't talk; nothing is missed. Help under new words fades as each one is mastered. The dialogues and the list of graded readers were written for Stadig Mind."
            )
        }
        // Again when a language is turned on, which keeps this section on screen.
        .task(id: settings.languages) {
            for domain in settings.languages {
                if let language = domain.language, recognises[language] == nil { recognises[language] = await recognizer.supports(language) }
            }
        }
    }
}
