import Foundation

/// A short exchange to practise: they say a line (heard, then understood), you answer (said out
/// loud, or picked while speaking is off). Written for Mind Track, levelled by how much of the
/// language it takes.
public struct Dialogue: Hashable, Sendable, Identifiable {
    public struct Line: Hashable, Sendable {
        public enum Speaker: Hashable, Sendable { case them, you }

        public var speaker: Speaker
        public var text: String
        /// Kana for a Japanese line with kanji.
        public var reading: String?
        public var english: String
        /// Other ways of saying it that count.
        public var accept: [String]

        public init(_ speaker: Speaker, _ text: String, reading: String? = nil, _ english: String, accept: [String] = []) {
            self.speaker = speaker
            self.text = text
            self.reading = reading
            self.english = english
            self.accept = accept
        }

        /// Everything that counts as saying this line.
        public var expected: [String] { [text] + (reading.map { [$0] } ?? []) + accept }
    }

    public var id: String
    public var language: Language
    /// 1 needs the first couple of hundred words, 2 about 500, 3 about 1,500.
    public var level: Int
    public var title: String
    public var lines: [Line]

    public var key: CardKey { .practice(language, "dialogue.\(id)") }
}

public enum Dialogues {
    /// The highest dialogue level open at a vocabulary.
    public static func level(frontier: Int, known: Int) -> Int {
        let reach = max(frontier, known)
        if reach >= 1500 { return 3 }
        if reach >= 500 { return 2 }
        return 1
    }

    public static func dialogues(_ language: Language) -> [Dialogue] { all.filter { $0.language == language } }

    /// The next one to practise: the least practised open one, the hardest first on a tie.
    public static func next(_ language: Language, level: Int, practised: [String: Int]) -> Dialogue? {
        dialogues(language).filter { $0.level <= level }
            .min { (practised[$0.id, default: 0], -$0.level, $0.id) < (practised[$1.id, default: 0], -$1.level, $1.id) }
    }

    /// How many sessions have practised each dialogue.
    public static func practised(_ language: Language, sessions: [StudySession]) -> [String: Int] {
        var out: [String: Int] = [:]
        let prefix = "\(language.pack.keyPrefix).dialogue."
        for session in sessions {
            for id in Set(session.attempts.filter { $0.key.raw.hasPrefix(prefix) }.map { String($0.key.raw.dropFirst(prefix.count)) }) {
                out[id, default: 0] += 1
            }
        }
        return out
    }

    public static let all: [Dialogue] = spanish + japanese

    static let spanish: [Dialogue] = [
        Dialogue(id: "saludos", language: .spanish, level: 1, title: "Meeting someone (you're Alex)", lines: [
            .init(.them, "¡Hola! ¿Cómo estás?", "Hi! How are you?"),
            .init(.you, "Bien, gracias. ¿Y tú?", "Fine, thanks. And you?", accept: ["bien gracias", "muy bien gracias"]),
            .init(.them, "Muy bien. ¿Cómo te llamas?", "Very well. What's your name?"),
            .init(.you, "Me llamo Alex.", "My name's Alex.", accept: ["me llamo", "soy alex"]),
            .init(.them, "Mucho gusto, Alex.", "Nice to meet you, Alex."),
            .init(.you, "Igualmente.", "Likewise.", accept: ["mucho gusto", "encantado", "encantada"]),
        ]),
        Dialogue(id: "cafe", language: .spanish, level: 1, title: "At a café", lines: [
            .init(.them, "Buenos días. ¿Qué le pongo?", "Good morning. What can I get you?"),
            .init(.you, "Un café con leche, por favor.", "A white coffee, please.", accept: ["café con leche"]),
            .init(.them, "¿Algo más?", "Anything else?"),
            .init(.you, "No, gracias. ¿Cuánto es?", "No, thanks. How much is it?", accept: ["cuánto es"]),
            .init(.them, "Son dos euros.", "That's two euros."),
            .init(.you, "Aquí tiene.", "Here you are.", accept: ["aquí tienes", "tome"]),
        ]),
        Dialogue(id: "estacion", language: .spanish, level: 1, title: "Asking the way", lines: [
            .init(.you, "Perdone, ¿dónde está la estación?", "Excuse me, where's the station?", accept: ["dónde está la estación"]),
            .init(.them, "Siga todo recto y gire a la derecha.", "Go straight on and turn right."),
            .init(.you, "¿Está lejos?", "Is it far?"),
            .init(.them, "No, está muy cerca. A cinco minutos a pie.", "No, it's very close. Five minutes on foot."),
            .init(.you, "Muchas gracias.", "Thank you very much.", accept: ["gracias"]),
            .init(.them, "De nada.", "You're welcome."),
        ]),
        Dialogue(id: "restaurante", language: .spanish, level: 2, title: "Ordering dinner", lines: [
            .init(.them, "¿Ya saben qué van a pedir?", "Do you know what you'd like to order?"),
            .init(.you, "Sí, para mí la sopa del día, por favor.", "Yes, the soup of the day for me, please.",
                  accept: ["la sopa del día"]),
            .init(.them, "¿Y de segundo?", "And for the main course?"),
            .init(.you, "El pescado con patatas.", "The fish with potatoes.", accept: ["pescado con patatas"]),
            .init(.them, "¿Y para beber?", "And to drink?"),
            .init(.you, "Agua sin gas, por favor.", "Still water, please.", accept: ["agua sin gas"]),
        ]),
        Dialogue(id: "fin-de-semana", language: .spanish, level: 2, title: "Weekend plans", lines: [
            .init(.them, "¿Qué vas a hacer este fin de semana?", "What are you doing this weekend?"),
            .init(.you, "Voy a ver a unos amigos.", "I'm going to see some friends.", accept: ["voy a ver a mis amigos", "ver a unos amigos"]),
            .init(.them, "¡Qué bien! ¿Adónde van a ir?", "Nice! Where are you going?"),
            .init(.you, "Queremos ir a la playa si hace buen tiempo.", "We want to go to the beach if the weather's good.",
                  accept: ["queremos ir a la playa", "vamos a la playa"]),
            .init(.them, "Que lo pases bien.", "Have a good time."),
            .init(.you, "Gracias, igualmente.", "Thanks, you too.", accept: ["igualmente"]),
        ]),
        Dialogue(id: "tienda", language: .spanish, level: 2, title: "Shopping for clothes", lines: [
            .init(.you, "¿Tiene esta camisa en una talla más grande?", "Do you have this shirt in a bigger size?",
                  accept: ["una talla más grande"]),
            .init(.them, "Sí, un momento. Aquí la tiene.", "Yes, one moment. Here you are."),
            .init(.you, "¿Puedo probármela?", "Can I try it on?", accept: ["puedo probarla", "me la puedo probar"]),
            .init(.them, "Claro, los probadores están al fondo.", "Of course, the fitting rooms are at the back."),
            .init(.you, "Me queda bien. Me la llevo.", "It fits. I'll take it.", accept: ["me la llevo"]),
        ]),
        Dialogue(id: "medico", language: .spanish, level: 3, title: "At the doctor's", lines: [
            .init(.them, "¿Qué le pasa?", "What's the matter?"),
            .init(.you, "Me duele la cabeza desde hace tres días.", "I've had a headache for three days.", accept: ["me duele la cabeza"]),
            .init(.them, "¿Tiene fiebre?", "Do you have a temperature?"),
            .init(.you, "Creo que no, pero estoy muy cansado.", "I don't think so, but I'm very tired.",
                  accept: ["estoy muy cansado", "estoy muy cansada"]),
            .init(.them, "Le voy a recetar algo. Descanse y beba mucha agua.", "I'll prescribe you something. Rest and drink plenty of water."),
            .init(.you, "Muchas gracias, doctora.", "Thank you very much, doctor.", accept: ["gracias doctora", "gracias doctor"]),
        ]),
        Dialogue(id: "trabajo", language: .spanish, level: 3, title: "Talking about work", lines: [
            .init(.them, "¿A qué te dedicas?", "What do you do for a living?"),
            .init(.you, "Trabajo en una empresa de software.", "I work at a software company.", accept: ["trabajo en una empresa"]),
            .init(.them, "¿Y te gusta?", "And do you like it?"),
            .init(.you, "Sí, aunque a veces trabajo demasiado.", "Yes, although sometimes I work too much.",
                  accept: ["a veces trabajo demasiado"]),
            .init(.them, "Te entiendo. Yo también.", "I know what you mean. Me too."),
        ]),
    ]

    static let japanese: [Dialogue] = [
        Dialogue(id: "hajimemashite", language: .japanese, level: 1, title: "Meeting someone (you're Alex)", lines: [
            .init(.them, "はじめまして。田中です。", reading: "はじめまして。たなかです。", "Nice to meet you. I'm Tanaka."),
            .init(.you, "はじめまして。アレックスです。", "Nice to meet you. I'm Alex.", accept: ["はじめまして"]),
            .init(.them, "どちらから来ましたか。", reading: "どちらからきましたか。", "Where are you from?"),
            .init(.you, "イギリスから来ました。", reading: "いぎりすからきました。", "I'm from the UK.", accept: ["から来ました", "からきました"]),
            .init(.them, "そうですか。よろしくお願いします。", reading: "そうですか。よろしくおねがいします。", "I see. Pleased to meet you."),
            .init(.you, "こちらこそ、よろしくお願いします。", reading: "こちらこそ、よろしくおねがいします。", "Pleased to meet you too.",
                  accept: ["よろしくお願いします", "よろしくおねがいします", "こちらこそ"]),
        ]),
        Dialogue(id: "kafe", language: .japanese, level: 1, title: "At a café", lines: [
            .init(.them, "いらっしゃいませ。ご注文は？", reading: "いらっしゃいませ。ごちゅうもんは？", "Welcome. What would you like?"),
            .init(.you, "コーヒーをひとつください。", "One coffee, please.", accept: ["コーヒーを一つください", "コーヒーをください", "コーヒーください"]),
            .init(.them, "ホットとアイス、どちらにしますか。", "Hot or iced?"),
            .init(.you, "ホットでお願いします。", reading: "ほっとでおねがいします。", "Hot, please.", accept: ["ホットで"]),
            .init(.them, "四百円です。", reading: "よんひゃくえんです。", "That's four hundred yen."),
            .init(.you, "はい、どうぞ。", "Here you are.", accept: ["どうぞ"]),
        ]),
        Dialogue(id: "eki", language: .japanese, level: 1, title: "Asking the way", lines: [
            .init(.you, "すみません、駅はどこですか。", reading: "すみません、えきはどこですか。", "Excuse me, where's the station?",
                  accept: ["駅はどこですか", "えきはどこですか"]),
            .init(.them, "まっすぐ行って、二つ目の角を右です。", reading: "まっすぐいって、ふたつめのかどをみぎです。",
                  "Go straight on; it's right at the second corner."),
            .init(.you, "遠いですか。", reading: "とおいですか。", "Is it far?"),
            .init(.them, "いいえ、歩いて五分ぐらいです。", reading: "いいえ、あるいてごふんぐらいです。", "No, it's about five minutes' walk."),
            .init(.you, "ありがとうございます。", "Thank you very much.", accept: ["ありがとう"]),
        ]),
        Dialogue(id: "resutoran", language: .japanese, level: 2, title: "At a restaurant", lines: [
            .init(.them, "何名様ですか。", reading: "なんめいさまですか。", "How many of you?"),
            .init(.you, "二人です。", reading: "ふたりです。", "Two."),
            .init(.them, "こちらへどうぞ。メニューです。", "This way, please. Here's the menu."),
            .init(.you, "おすすめは何ですか。", reading: "おすすめはなんですか。", "What do you recommend?", accept: ["おすすめは"]),
            .init(.them, "今日は天ぷらがおすすめです。", reading: "きょうはてんぷらがおすすめです。", "Today the tempura is very good."),
            .init(.you, "じゃあ、それにします。", "Then I'll have that.", accept: ["それにします"]),
        ]),
        Dialogue(id: "shuumatsu", language: .japanese, level: 2, title: "Weekend plans", lines: [
            .init(.them, "週末は何をしますか。", reading: "しゅうまつはなにをしますか。", "What are you doing at the weekend?"),
            .init(.you, "友達と映画を見に行きます。", reading: "ともだちとえいがをみにいきます。", "I'm going to see a film with friends.",
                  accept: ["映画を見に行きます", "えいがをみにいきます"]),
            .init(.them, "いいですね。何の映画ですか。", reading: "いいですね。なんのえいがですか。", "Nice. Which film?"),
            .init(.you, "まだ決めていません。", reading: "まだきめていません。", "We haven't decided yet.", accept: ["まだ決めてない", "まだきめてない"]),
            .init(.them, "楽しんでくださいね。", reading: "たのしんでくださいね。", "Have fun."),
        ]),
        Dialogue(id: "kaimono", language: .japanese, level: 2, title: "Shopping for clothes", lines: [
            .init(.you, "これのもう少し大きいサイズはありますか。", reading: "これのもうすこしおおきいさいずはありますか。",
                  "Do you have this in a slightly bigger size?", accept: ["大きいサイズはありますか", "おおきいさいずはありますか"]),
            .init(.them, "はい、少々お待ちください。", reading: "はい、しょうしょうおまちください。", "Yes, one moment, please."),
            .init(.you, "試着してもいいですか。", reading: "しちゃくしてもいいですか。", "May I try it on?"),
            .init(.them, "どうぞ。試着室はあちらです。", reading: "どうぞ。しちゃくしつはあちらです。", "Go ahead. The fitting room is over there."),
            .init(.you, "ちょうどいいです。これをください。", "It's just right. I'll take this.", accept: ["これをください"]),
        ]),
        Dialogue(id: "byouin", language: .japanese, level: 3, title: "At the doctor's", lines: [
            .init(.them, "どうしましたか。", "What seems to be the problem?"),
            .init(.you, "三日前から頭が痛いんです。", reading: "みっかまえからあたまがいたいんです。", "I've had a headache for three days.",
                  accept: ["頭が痛い", "あたまがいたい"]),
            .init(.them, "熱はありますか。", reading: "ねつはありますか。", "Do you have a temperature?"),
            .init(.you, "熱はないと思いますが、とても疲れています。", reading: "ねつはないとおもいますが、とてもつかれています。",
                  "I don't think so, but I'm very tired.", accept: ["とても疲れています", "とてもつかれています"]),
            .init(.them, "薬を出しておきますね。ゆっくり休んでください。", reading: "くすりをだしておきますね。ゆっくりやすんでください。",
                  "I'll give you some medicine. Get plenty of rest."),
            .init(.you, "ありがとうございました。", "Thank you very much.", accept: ["ありがとうございます"]),
        ]),
        Dialogue(id: "shigoto", language: .japanese, level: 3, title: "Talking about work", lines: [
            .init(.them, "お仕事は何をされていますか。", reading: "おしごとはなにをされていますか。", "What do you do for work?"),
            .init(.you, "ソフトウェアの会社で働いています。", reading: "そふとうぇあのかいしゃではたらいています。", "I work at a software company.",
                  accept: ["会社で働いています", "かいしゃではたらいています"]),
            .init(.them, "大変ですか。", reading: "たいへんですか。", "Is it hard work?"),
            .init(.you, "忙しいですが、楽しいです。", reading: "いそがしいですが、たのしいです。", "It's busy, but fun.",
                  accept: ["楽しいです", "たのしいです"]),
            .init(.them, "それはいいですね。", "That's good to hear."),
        ]),
    ]
}
