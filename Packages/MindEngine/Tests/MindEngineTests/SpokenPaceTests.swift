import Foundation
import Testing

@testable import MindEngine

/// How the voice is paced: short things slower than sentences, slow slower still, and room either
/// side of everything.
@Suite("Spoken pace")
struct SpokenPaceTests {
    @Test("a lone kana is a sound, a few characters a word, more a sentence")
    func japaneseLengths() {
        for text in ["あ", "ア", "きゃ", "キョ", "ん", "日"] { #expect(SpokenPace.pace(text, language: .japanese).length == .sound, "\(text)") }
        for text in ["ねこ", "がっこう", "食べる", "お元気ですか"] { #expect(SpokenPace.pace(text, language: .japanese).length == .word, "\(text)") }
        #expect(SpokenPace.pace("毎朝コーヒーを飲みます。", language: .japanese).length == .sentence)
    }

    @Test("in Spanish, a letter or two is a sound and a few words a sentence")
    func spanishLengths() {
        #expect(SpokenPace.pace("ñ", language: .spanish).length == .sound)
        #expect(SpokenPace.pace("rr", language: .spanish).length == .sound)
        #expect(SpokenPace.pace("gato", language: .spanish).length == .word)
        #expect(SpokenPace.pace("buenos días", language: .spanish).length == .word)
        #expect(SpokenPace.pace("¿Dónde está la estación?", language: .spanish).length == .sentence)
    }

    @Test("shorter is slower, slow is slower again, and nothing runs at full speed")
    func rates() {
        let lengths = ["あ", "ねこ", "毎朝コーヒーを飲みます。"]
        let normal = lengths.map { SpokenPace.pace($0, language: .japanese).rate }
        let slow = lengths.map { SpokenPace.pace($0, language: .japanese, slow: true).rate }
        #expect(normal == normal.sorted() && slow == slow.sorted())
        #expect(zip(slow, normal).allSatisfy { $0 < $1 })
        #expect(normal.allSatisfy { $0 < 1 })
    }

    @Test("the markup pauses either side and keeps the text as written")
    func markup() {
        let pace = SpokenPace.pace("ねこ", language: .japanese)
        #expect(pace.markup("ねこ") == #"<speak><break time="250ms"/><prosody rate="80%">ねこ</prosody><break time="250ms"/></speak>"#)
        #expect(SpokenPace.pace("A & B <3", language: .spanish).markup("A & B <3").contains("A &amp; B &lt;3"))
    }
}
