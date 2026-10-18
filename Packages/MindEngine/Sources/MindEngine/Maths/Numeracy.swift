import Foundation
import SystemCore

/// Numeracy: the everyday maths people lose first and use most. Five skills, each with ten levels
/// of its own, drilled for speed as well as accuracy. Problems are short, so a three-minute block
/// gets through fifteen or twenty of them.
public enum NumeracySkill: String, CaseIterable, Codable, Sendable, Identifiable {
    case arithmetic, estimation, percentages, fractions, units

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .arithmetic: "Mental arithmetic"
        case .estimation: "Estimation"
        case .percentages: "Percentages"
        case .fractions: "Fractions"
        case .units: "Unit conversions"
        }
    }

    /// One word, for a row of levels.
    public var short: String {
        switch self {
        case .arithmetic: "Arithmetic"
        case .estimation: "Estimates"
        case .percentages: "Percent"
        case .fractions: "Fractions"
        case .units: "Units"
        }
    }

    /// Seconds a fluent answer takes at a level: a quick sum at level 1, a two-step conversion at 10.
    public func target(_ level: Int) -> Double {
        let base: Double = switch self {
        case .arithmetic: 5
        case .estimation: 6
        case .percentages: 7
        case .fractions, .units: 8
        }
        return (base * (1 + Double(clamp(level, 1, Numeracy.maxLevel) - 1) * 0.25)).rounded()
    }

    /// A problem at a level, the same for the same seed.
    public func problem(level: Int, seed: String) -> Problem {
        let level = clamp(level, 1, Numeracy.maxLevel)
        var rng = SeededRandom("numeracy", rawValue, "\(level)", seed)
        var problem = switch self {
        case .arithmetic: Numeracy.arithmetic(level, &rng)
        case .estimation: Numeracy.estimation(level, &rng)
        case .percentages: Numeracy.percentages(level, &rng)
        case .fractions: Numeracy.fractions(level, &rng)
        case .units: Numeracy.units(level, &rng)
        }
        problem.topic = "numeracy.\(rawValue)"
        problem.expectedSeconds = target(level)
        return problem
    }

    /// The problem as a timed question, keyed by skill and level so the drill's history says
    /// where each skill stands.
    public func question(level: Int, seed: String, kind: AttemptKind) -> Question {
        let level = clamp(level, 1, Numeracy.maxLevel)
        var question = problem(level: level, seed: seed).question(kind: kind, id: "numeracy.\(rawValue).\(level).\(seed)")
        question.key = .numeracy(self, level: level)
        question.timed = true
        return question
    }
}

extension CardKey {
    /// A numeracy skill at a level: "maths.numeracy.percentages.4". Never a card; attempts only.
    public static func numeracy(_ skill: NumeracySkill, level: Int) -> CardKey { CardKey("maths.numeracy.\(skill.rawValue).\(level)") }

    /// The skill and level of a numeracy attempt.
    public var numeracy: (skill: NumeracySkill, level: Int)? {
        let parts = raw.split(separator: ".")
        guard parts.count == 4, parts[0] == "maths", parts[1] == "numeracy", let skill = NumeracySkill(rawValue: String(parts[2])),
              let level = Int(parts[3]) else { return nil }
        return (skill, level)
    }
}

/// The generators, one per skill, by level.
enum Numeracy {
    static let maxLevel = 10

    // MARK: Mental arithmetic

    static func arithmetic(_ level: Int, _ rng: inout SeededRandom) -> Problem {
        switch level {
        case 1:
            if rng.chance(0.5) {
                let a = rng.int(2...9), b = rng.int(2...9)
                return .number("$\(a) + \(b)$", a + b, steps: ["$\(a) + \(b) = \(a + b)$."])
            }
            let a = rng.int(2...5), b = rng.int(2...5)
            return .number(#"$\#(a) \times \#(b)$"#, a * b, steps: [#"$\#(a) \times \#(b) = \#(a * b)$."#])
        case 2:
            switch rng.int(0...2) {
            case 0:
                // b always takes the sum past the ten, so the second step adds something.
                let tens = rng.int(2...8), ones = rng.int(3...9)
                let a = tens * 10 + ones, b = rng.int(max(4, 11 - ones)...9)
                let up = 10 - ones
                return .number("$\(a) + \(b)$", a + b, steps: ["Make the ten: $\(a) + \(up) = \(a + up)$, then $+ \(b - up)$ is $\(a + b)$."])
            case 1:
                let a = rng.int(2...9) * 10 + rng.int(1...5), b = rng.int(6...9)
                let down = a % 10
                return .number("$\(a) - \(b)$", a - b, steps: ["Back to the ten: $\(a) - \(down) = \(a - down)$, then $- \(b - down)$ is $\(a - b)$."])
            default:
                let a = rng.int(6...9), b = rng.int(6...9)
                return .number(#"$\#(a) \times \#(b)$"#, a * b, steps: [#"$\#(a) \times \#(b) = \#(a * b)$."#])
            }
        case 3:
            switch rng.int(0...2) {
            case 0:
                let a = rng.int(21...69), b = rng.int(15...29)
                // A round b has no ones to add.
                let ones = b % 10 == 0 ? [] : ["Then the ones: $+ \(b % 10)$ is $\(a + b)$."]
                return .number("$\(a) + \(b)$", a + b, steps: ["Tens first: $\(a) + \(b / 10 * 10) = \(a + b / 10 * 10)$."] + ones)
            case 1:
                let b = rng.int(17...39), a = b + rng.int(12...45)
                let round = (b + 9) / 10 * 10
                return .number("$\(a) - \(b)$", a - b,
                               steps: ["Take $\(round)$ and give back $\(round - b)$: $\(a) - \(round) + \(round - b) = \(a - b)$."])
            default:
                let a = rng.int(6...9), b = rng.int(4...9)
                return .number(#"$\#(a * b) \div \#(a)$"#, b, steps: [#"$\#(a) \times \#(b) = \#(a * b)$, so $\#(a * b) \div \#(a) = \#(b)$."#])
            }
        case 4:
            if rng.chance(0.5) {
                let a = rng.int(13...49), b = rng.int(3...8)
                return .number(#"$\#(a) \times \#(b)$"#, a * b,
                               steps: [#"$\#(a / 10 * 10) \times \#(b) = \#(a / 10 * 10 * b)$ and $\#(a % 10) \times \#(b) = \#(a % 10 * b)$."#,
                                       "Together: $\(a * b)$."])
            }
            let a = rng.int(120...480), b = rng.int(25...79)
            let ones = b % 10 == 0 ? "." : ", then $+ \(b % 10)$ is $\(a + b)$."
            return .number("$\(a) + \(b)$", a + b, steps: ["$\(a) + \(b / 10 * 10) = \(a + b / 10 * 10)$\(ones)"])
        case 5:
            switch rng.int(0...2) {
            case 0:
                let a = rng.int(21...59) * 10 + rng.pick([0, 5]), b = rng.int(12...39) * 10 + rng.pick([0, 5])
                return .number("$\(a) + \(b)$", a + b, steps: ["Hundreds, then tens: $\(a) + \(b / 100 * 100) = \(a + b / 100 * 100)$, $+ \(b % 100) = \(a + b)$."])
            case 1:
                let b = rng.int(213...489), a = b + rng.int(150...420)
                return .number("$\(a) - \(b)$", a - b, steps: ["Count up from $\(b)$ to $\(a)$: that's $\(a - b)$."])
            default:
                let whole = rng.int(12...98), power = rng.pick([10, 100, 1000])
                let value = Rational(whole, 10)
                if rng.chance(0.5) {
                    return .number(#"$\#(decimal(value)) \times \#(power)$"#, value * Rational(power),
                                   steps: ["Each zero moves the digits one place left: $\(decimal(value * Rational(power)))$."])
                }
                let big = Rational(whole * rng.pick([1, 10, 100]))
                return .number(#"$\#(decimal(big)) \div \#(power)$"#, big / Rational(power),
                               steps: ["Each zero moves the digits one place right: $\(decimal(big / Rational(power)))$."])
            }
        case 6:
            switch rng.int(0...2) {
            case 0:
                let a = rng.pick([25, 50]), b = rng.int(3...19) * 4
                return .number(#"$\#(a) \times \#(b)$"#, a * b,
                               steps: [a == 25 ? #"$25 \times 4 = 100$, and $\#(b) = 4 \times \#(b / 4)$: $\#(b / 4) \times 100 = \#(a * b)$."#
                                               : #"$50 \times 2 = 100$, and $\#(b) = 2 \times \#(b / 2)$: $\#(b / 2) \times 100 = \#(a * b)$."#])
            case 1:
                let a = rng.int(12...89)
                return .number(#"$11 \times \#(a)$"#, 11 * a, steps: [#"$10 \times \#(a) + \#(a) = \#(10 * a) + \#(a) = \#(11 * a)$."#])
            default:
                let a = Rational(rng.int(11...89), 10), b = Rational(rng.int(101...499), 100)
                if rng.chance(0.5) {
                    return .number("$\(decimal(a)) + \(decimal(b))$", a + b, steps: ["Line up the points: $\(decimal(a + b))$."])
                }
                let big = a + b
                return .number("$\(decimal(big)) - \(decimal(b))$", a, steps: ["Line up the points: $\(decimal(a))$."])
            }
        case 7:
            if rng.chance(0.6) {
                let a = rng.int(23...79), b = rng.int(13...39)
                return .number(#"$\#(a) \times \#(b)$"#, a * b,
                               steps: [#"$\#(a) \times \#(b / 10 * 10) = \#(a * (b / 10 * 10))$ and $\#(a) \times \#(b % 10) = \#(a * (b % 10))$."#,
                                       "Together: $\(a * b)$."])
            }
            // The digits are kept as typed: a Rational is in lowest terms, so 0.5 is 1/2.
            let digits = rng.int(2...19), b = rng.int(3...9)
            let a = Rational(digits, 10)
            return .number(#"$\#(decimal(a)) \times \#(b)$"#, a * Rational(b),
                           steps: [#"$\#(digits) \times \#(b) = \#(digits * b)$, then one decimal place back: $\#(decimal(a * Rational(b)))$."#])
        case 8:
            if rng.chance(0.5) {
                let b = rng.int(3...9), q = rng.int(21...98)
                return .number(#"$\#(b * q) \div \#(b)$"#, q,
                               steps: [#"$\#(b) \times \#(q / 10 * 10) = \#(b * (q / 10 * 10))$, leaving $\#(b * (q % 10))$, which is $\#(b) \times \#(q % 10)$."#,
                                       "So $\(q)$."])
            }
            let a = rng.int(13...25)
            return .number("$\(a)^{2}$", a * a, steps: [#"$\#(a)^{2} = \#(a) \times \#(a) = \#(a * a)$."#])
        case 9:
            if rng.chance(0.5) {
                let aDigits = rng.int(2...15), bDigits = rng.int(2...9)
                let a = Rational(aDigits, 10), b = Rational(bDigits, 10)
                return .number(#"$\#(decimal(a)) \times \#(decimal(b))$"#, a * b,
                               steps: [#"$\#(aDigits) \times \#(bDigits) = \#(aDigits * bDigits)$, then two decimal places back: $\#(decimal(a * b))$."#])
            }
            let a = rng.int(213...789), b = rng.int(3...9)
            return .number(#"$\#(a) \times \#(b)$"#, a * b,
                           steps: [#"$\#(a / 100 * 100) \times \#(b) = \#(a / 100 * 100 * b)$, $\#(a % 100) \times \#(b) = \#(a % 100 * b)$."#,
                                   "Together: $\(a * b)$."])
        default:
            switch rng.int(0...3) {
            case 0:
                let b = rng.int(3...19) * 8
                return .number(#"$125 \times \#(b)$"#, 125 * b, steps: [#"$125 \times 8 = 1000$: $\#(b) = 8 \times \#(b / 8)$, so $\#(b / 8) \times 1000 = \#(125 * b)$."#])
            case 1:
                let a = rng.pick([99, 999]), b = rng.int(3...9)
                return .number(#"$\#(a) \times \#(b)$"#, a * b, steps: [#"$\#(a + 1) \times \#(b) - \#(b) = \#((a + 1) * b - b)$."#])
            case 2:
                let a = rng.int(213...489), b = rng.int(150...420)
                return .number("$1000 - \(a) - \(b)$", 1000 - a - b, steps: ["$\(a) + \(b) = \(a + b)$, and $1000 - \(a + b) = \(1000 - a - b)$."])
            default:
                let bDigits = rng.int(2...9), q = rng.int(3...12)
                let b = Rational(bDigits, 10), a = b * Rational(q)
                return .number(#"$\#(decimal(a)) \div \#(decimal(b))$"#, q,
                               steps: [#"Times both by 10: $\#(decimal(a * Rational(10))) \div \#(bDigits) = \#(q)$."#])
            }
        }
    }

    // MARK: Estimation

    /// "About how much is …?": four choices at least twice apart, so any sensible estimate picks
    /// the right one and it's never a test of exact arithmetic.
    static func estimation(_ level: Int, _ rng: inout SeededRandom) -> Problem {
        let close = rng.chance(0.5) ? [0.4, 2.5, 5] : [0.2, 0.4, 2.5]
        let magnitudes = [0.1, 10, rng.chance(0.5) ? 2.5 : 0.4]
        switch level {
        case 1:
            let a = rng.int(21...89), b = rng.int(21...89)
            return estimate("$\(a) + \(b)$", Double(a + b), factors: close, steps: ["$\(a) + \(b) \\approx \(round(a, 10)) + \(round(b, 10)) = \(round(a, 10) + round(b, 10))$."], rng: &rng)
        case 2:
            let a = rng.int(210...890), b = rng.int(110...690)
            return estimate("$\(a) + \(b)$", Double(a + b), factors: close,
                            steps: ["$\(a) + \(b) \\approx \(round(a, 100)) + \(round(b, 100)) = \(round(a, 100) + round(b, 100))$."], rng: &rng)
        case 3:
            let a = rng.int(21...89), b = rng.int(3...9)
            return estimate(#"$\#(a) \times \#(b)$"#, Double(a * b), factors: close,
                            steps: [#"$\#(a) \times \#(b) \approx \#(round(a, 10)) \times \#(b) = \#(round(a, 10) * b)$."#], rng: &rng)
        case 4:
            let a = rng.int(21...89), b = rng.int(21...89)
            return estimate(#"$\#(a) \times \#(b)$"#, Double(a * b), factors: close,
                            steps: [#"$\#(a) \times \#(b) \approx \#(round(a, 10)) \times \#(round(b, 10)) = \#(round(a, 10) * round(b, 10))$."#], rng: &rng)
        case 5:
            let b = rng.int(12...48), a = b * rng.int(12...45) + rng.int(-9...9)
            return estimate(#"$\#(a) \div \#(b)$"#, Double(a) / Double(b), factors: close,
                            steps: [#"$\#(a) \div \#(b) \approx \#(round(a, 100)) \div \#(round(b, 10))$, about $\#(Int((Double(round(a, 100)) / Double(round(b, 10))).rounded()))$."#],
                            rng: &rng)
        case 6:
            let a = Double(rng.int(21...98)) / 10, b = Double(rng.int(21...98)) / 10
            return estimate(#"$\#(oneDecimal(a)) \times \#(oneDecimal(b))$"#, a * b, factors: close,
                            steps: [#"$\#(oneDecimal(a)) \times \#(oneDecimal(b)) \approx \#(Int(a.rounded())) \times \#(Int(b.rounded())) = \#(Int(a.rounded()) * Int(b.rounded()))$."#],
                            rng: &rng)
        case 7:
            let a = rng.int(1200...9800), b = Double(rng.int(11...49)) / 100
            return estimate(#"$\#(a) \times \#(String(format: "%.2f", b))$"#, Double(a) * b, factors: magnitudes,
                            steps: [#"$\#(String(format: "%.2f", b))$ is about $\#(String(format: "%.1f", (b * 10).rounded() / 10))$: a little under a \#(b < 0.3 ? "quarter" : "half") of $\#(a)$."#],
                            rng: &rng)
        case 8:
            let p = rng.pick([9, 11, 19, 21, 24, 26, 31, 49, 51, 74]), n = rng.int(180...980)
            let nice = [9: 10, 11: 10, 19: 20, 21: 20, 24: 25, 26: 25, 31: 30, 49: 50, 51: 50, 74: 75][p]!
            let rough = Rational(nice * round(n, 100), 100)
            return estimate(#"$\#(p)\%$ of $\#(n)$"#, Double(p * n) / 100, factors: magnitudes,
                            steps: [#"About $\#(nice)\%$ of $\#(round(n, 100))$: $\#(decimal(rough))$."#], rng: &rng)
        case 9:
            let a = rng.int(12...89) * 1000, b = rng.int(12...89) * 100
            let roughA = Int(nice(Double(a))), roughB = Int(nice(Double(b)))
            return estimate(#"$\#(grouped(a)) \times \#(grouped(b))$"#, Double(a) * Double(b), factors: [0.1, 10, 0.01],
                            steps: [#"$\#(grouped(roughA)) \times \#(grouped(roughB))$: multiply the leading digits, then count the zeros."#,
                                    "About \(plain(Double(roughA) * Double(roughB)))."], rng: &rng)
        default:
            switch rng.int(0...2) {
            case 0:
                let (what, value, working) = rng.pick([
                    ("seconds in a day", 86_400.0, #"$60 \times 60 \times 24 \approx 3600 \times 24$, about $86\,000$."#),
                    ("seconds in a week", 604_800.0, #"About $86\,000$ a day, times 7: about $600\,000$."#),
                    ("minutes in a year", 525_600.0, #"$60 \times 24 = 1440$ a day, times 365: about $500\,000$."#),
                    ("hours in a year", 8_760.0, #"$24 \times 365$, about $25 \times 360 = 9000$."#),
                ])
                return estimate("About how many \(what)?", value, factors: [0.1, 10, 0.01], steps: [working], rng: &rng, asked: true)
            case 1:
                let n = rng.int(110...950)
                let root = Int(Double(n).squareRoot().rounded())
                return estimate(#"$\sqrt{\#(n)}$"#, Double(n).squareRoot(), factors: [0.4, 2.5, 5],
                                steps: [#"$\#(root)^{2} = \#(root * root)$, so $\sqrt{\#(n)}$ is close to $\#(root)$."#], rng: &rng)
            default:
                let rate = rng.pick([3, 4, 6, 8, 9, 12])
                return estimate(#"Something grows $\#(rate)\%$ a year. About how many years until it doubles?"#, 72.0 / Double(rate), factors: [0.4, 2.5, 5],
                                steps: [#"The rule of 72: $72 \div \#(rate) = \#(72 / rate)$ years."#], rng: &rng, asked: true)
            }
        }
    }

    /// Four choices: a round estimate and others a factor away from it.
    static func estimate(_ expression: String, _ value: Double, factors: [Double], steps: [String], rng: inout SeededRandom,
                         asked: Bool = false) -> Problem {
        let right = nice(value)
        var wrong: [String] = []
        for factor in factors {
            let option = plain(nice(right * factor))
            if option != plain(right) && !wrong.contains(option) { wrong.append(option) }
        }
        let prompt = asked ? expression : "About how much is \(expression)?"
        return .choice(prompt, correct: plain(right), wrong: wrong, steps: steps, rng: &rng)
    }

    /// One significant figure when that's within 12%, else two: 1976 is 2,000 and 42.7 is 40.
    static func nice(_ value: Double) -> Double {
        guard value > 0 else { return 0 }
        let magnitude = pow(10, floor(log10(value)))
        let one = (value / magnitude).rounded() * magnitude
        if abs(one - value) / value <= 0.12 { return one }
        let tenth = magnitude / 10
        return (value / tenth).rounded() * tenth
    }

    /// A round number in words where it's big: "2,000", "90 million", "0.5".
    static func plain(_ value: Double) -> String {
        if value >= 1_000_000_000, (value / 1_000_000_000).rounded() == value / 1_000_000_000 { return "\(grouped(Int(value / 1_000_000_000))) billion" }
        if value >= 1_000_000 {
            let millions = value / 1_000_000
            return millions.rounded() == millions ? "\(grouped(Int(millions))) million" : "\(String(format: "%.1f", millions)) million"
        }
        if value.rounded() == value { return grouped(Int(value)) }
        return String(format: value < 1 ? "%.2g" : "%.1f", value)
    }

    // MARK: Percentages

    static func percentages(_ level: Int, _ rng: inout SeededRandom) -> Problem {
        switch level {
        case 1:
            if rng.chance(0.5) {
                let n = rng.int(2...19) * 10
                return .number(#"$10\%$ of $\#(n)$"#, n / 10, steps: [#"$10\%$ is a tenth: $\#(n) \div 10 = \#(n / 10)$."#])
            }
            let n = rng.int(6...49) * 2
            return .number(#"$50\%$ of $\#(n)$"#, n / 2, steps: [#"$50\%$ is a half: $\#(n / 2)$."#])
        case 2:
            let (p, d) = rng.pick([(25, 4), (20, 5), (5, 20)])
            let n = d * rng.int(2...19)
            let how = p == 25 ? "a quarter" : p == 20 ? "a fifth" : #"half of $10\%$"#
            return .number(#"$\#(p)\%$ of $\#(n)$"#, n / d, steps: [#"$\#(p)\%$ is \#(how): $\#(n / d)$."#])
        case 3:
            switch rng.int(0...2) {
            case 0:
                let n = rng.int(2...16) * 20
                return .number(#"$15\%$ of $\#(n)$"#, Rational(15 * n, 100),
                               steps: [#"$10\%$ is $\#(decimal(Rational(n, 10)))$ and $5\%$ is half that: $\#(decimal(Rational(n, 20)))$."#, "Together: $\(decimal(Rational(15 * n, 100)))$."])
            case 1:
                let n = rng.int(2...19) * 4
                return .number(#"$75\%$ of $\#(n)$"#, 3 * n / 4, steps: [#"A quarter is $\#(n / 4)$; three quarters is $\#(3 * n / 4)$."#])
            default:
                let n = rng.int(2...29) * 10
                return .number(#"$30\%$ of $\#(n)$"#, 3 * n / 10, steps: [#"$10\%$ is $\#(n / 10)$, so $30\%$ is $\#(3 * n / 10)$."#])
            }
        case 4:
            if rng.chance(0.5) {
                let p = rng.int(1...19) * 5, n = rng.int(1...8) * 40
                let value = Rational(p * n, 100)
                return .number(#"$\#(p)\%$ of $\#(n)$"#, value,
                               steps: [#"$1\%$ of $\#(n)$ is $\#(decimal(Rational(n, 100)))$; times $\#(p)$ is $\#(decimal(value))$."#])
            }
            let (part, whole) = rng.pick([(12, 48), (9, 36), (15, 60), (18, 24), (7, 35), (30, 120), (45, 75), (27, 90)])
            return .number(#"What percentage of $\#(whole)$ is $\#(part)$?"#, Rational(100 * part, whole),
                           steps: [#"$\frac{\#(part)}{\#(whole)} = \#(Rational(part, whole).tex) = \#(decimal(Rational(100 * part, whole)))\%$."#])
        case 5:
            let p = rng.pick([5, 10, 12, 15, 20, 25, 30, 40]), n = rng.int(2...12) * 20
            let change = Rational(p * n, 100)
            if rng.chance(0.5) {
                return .number(#"Increase $\#(n)$ by $\#(p)\%$."#, Rational(n) + change,
                               steps: [#"$\#(p)\%$ of $\#(n)$ is $\#(decimal(change))$."#, "$\(n) + \(decimal(change)) = \(decimal(Rational(n) + change))$."])
            }
            return .number(#"Decrease $\#(n)$ by $\#(p)\%$."#, Rational(n) - change,
                           steps: [#"$\#(p)\%$ of $\#(n)$ is $\#(decimal(change))$."#, "$\(n) - \(decimal(change)) = \(decimal(Rational(n) - change))$."])
        case 6:
            if rng.chance(0.5) {
                let (from, to) = rng.pick([(40, 50), (80, 100), (25, 30), (60, 75), (50, 80), (20, 23), (120, 150), (200, 260)])
                return .number(#"A price goes from $\#(from)$ to $\#(to)$. By what percentage did it rise?"#, Rational(100 * (to - from), from),
                               steps: [#"It rose $\#(to - from)$, out of the starting $\#(from)$: $\frac{\#(to - from)}{\#(from)} = \#(decimal(Rational(100 * (to - from), from)))\%$."#])
            }
            let (from, to) = rng.pick([(50, 40), (100, 80), (30, 24), (75, 60), (80, 50), (40, 30), (150, 120), (200, 150)])
            return .number(#"A price falls from $\#(from)$ to $\#(to)$. By what percentage did it fall?"#, Rational(100 * (from - to), from),
                           steps: [#"It fell $\#(from - to)$, out of the starting $\#(from)$: $\frac{\#(from - to)}{\#(from)} = \#(decimal(Rational(100 * (from - to), from)))\%$."#])
        case 7:
            let p = rng.pick([10, 20, 25, 40, 50]), before = rng.int(2...12) * 20
            if rng.chance(0.5) {
                let after = Rational(before * (100 - p), 100)
                return .number(#"After $\#(p)\%$ off, something costs $\#(decimal(after))$. What did it cost before?"#, before,
                               steps: [#"$\#(decimal(after))$ is $\#(100 - p)\%$ of the old price."#, #"$\#(decimal(after)) \div \#(decimal(Rational(100 - p, 100))) = \#(before)$."#])
            }
            let tax = rng.pick([20, 25, 10])
            let after = Rational(before * (100 + tax), 100)
            return .number(#"A bill is $\#(decimal(after))$ including $\#(tax)\%$ tax. What was it before tax?"#, before,
                           steps: [#"$\#(decimal(after))$ is $\#(100 + tax)\%$ of the price before tax."#, #"$\#(decimal(after)) \div \#(decimal(Rational(100 + tax, 100))) = \#(before)$."#])
        case 8:
            let (from, to) = rng.pick([(20, 25), (10, 12), (40, 50), (8, 10), (25, 20), (50, 40), (12, 15), (30, 33)])
            if rng.chance(0.5) {
                return .number(#"A rate moves from $\#(from)\%$ to $\#(to)\%$. By how many percentage points did it change? (Negative for a fall.)"#, to - from,
                               steps: [#"Points are a plain difference: $\#(to) - \#(from) = \#(to - from)$."#])
            }
            return .number(#"A rate moves from $\#(from)\%$ to $\#(to)\%$. By what percentage did it change? (Negative for a fall.)"#, Rational(100 * (to - from), from),
                           steps: [#"Percent change is relative: $\frac{\#(to - from)}{\#(from)} = \#(decimal(Rational(100 * (to - from), from)))\%$, though it's only $\#(abs(to - from))$ points."#])
        case 9:
            let (a, b) = rng.pick([(10, -10), (20, -20), (50, -50), (20, 50), (10, 20), (-20, 25), (25, -20), (-10, 10)])
            let total = Rational(100 + a, 100) * Rational(100 + b, 100) - 1
            return .number(#"Something \#(a > 0 ? "rises" : "falls") $\#(abs(a))\%$, then \#(b > 0 ? "rises" : "falls") $\#(abs(b))\%$. What is the overall change, in percent? (Negative for a fall.)"#,
                           total * 100,
                           steps: [#"Multiply the factors: $\#(decimal(Rational(100 + a, 100))) \times \#(decimal(Rational(100 + b, 100))) = \#(decimal(total + 1))$."#,
                                   "That's \(total >= 0 ? "up" : "down") $\(decimal(total >= 0 ? total * 100 : -total * 100))\\%$ overall, not $\(abs(a + b))\\%$."])
        default:
            switch rng.int(0...2) {
            case 0:
                let p = rng.pick([10, 20, 5]), years = rng.pick([2, 3])
                let total = Rational(100 + p, 100).power(years) - 1
                return .number(#"Something grows $\#(p)\%$ a year for $\#(years)$ years. What is the total growth, in percent?"#, total * 100,
                               steps: [#"$\#(decimal(Rational(100 + p, 100)))^{\#(years)} = \#(decimal(total + 1))$: growth on growth."#, "Total: $\(decimal(total * 100))\\%$."])
            case 1:
                let (a, b) = rng.pick([(30, 20), (20, 10), (50, 20), (40, 25), (25, 20)])
                let total = 1 - Rational(100 - a, 100) * Rational(100 - b, 100)
                return .number(#"A sale takes $\#(a)\%$ off, then a further $\#(b)\%$ off the sale price. What is the total discount, in percent?"#, total * 100,
                               steps: [#"$\#(decimal(Rational(100 - a, 100))) \times \#(decimal(Rational(100 - b, 100))) = \#(decimal(1 - total))$ of the price is left."#,
                                       "So $\(decimal(total * 100))\\%$ off, not $\(a + b)\\%$."])
            default:
                let (down, up) = rng.pick([(20, 25), (50, 100), (25, 33), (10, 11)])
                let back = down == 25 ? Rational(100, 3) : down == 10 ? Rational(100, 9) : Rational(up)
                return .number(#"Something falls $\#(down)\%$. By what percentage must it rise to get back to where it was? (A fraction like 100/3 is fine.)"#, back,
                               steps: [#"It's at $\#(100 - down)\%$ of where it was: the rise needed is $\frac{\#(down)}{\#(100 - down)}$ of the new value, $\#(back.isInteger ? "\(back.numerator)" : back.tex)\%$."#])
            }
        }
    }

    // MARK: Fractions

    static func fractions(_ level: Int, _ rng: inout SeededRandom) -> Problem {
        switch level {
        case 1:
            let d = rng.pick([2, 4, 3]), n = d * rng.int(2...12)
            return .number(#"$\frac{1}{\#(d)}$ of $\#(n)$"#, n / d, steps: [#"Divide by $\#(d)$: $\#(n / d)$."#])
        case 2:
            let d = rng.pick([3, 4, 5, 8, 10]), top = rng.int(2...(d - 1)), n = d * rng.int(2...12)
            return .number(#"$\frac{\#(top)}{\#(d)}$ of $\#(n)$"#, n / d * top,
                           steps: [#"$\frac{1}{\#(d)}$ of $\#(n)$ is $\#(n / d)$; times $\#(top)$ is $\#(n / d * top)$."#])
        case 3:
            let (n, d) = rng.pick([(1, 4), (3, 4), (1, 5), (2, 5), (3, 5), (1, 8), (3, 8), (5, 8), (1, 20), (7, 20), (3, 25)])
            let value = Rational(n, d)
            let wrong = [decimal(Rational(d, 100)), "0.\(n)\(d)", decimal(value + Rational(1, 10)), decimal(Rational(d, n * 10))]
            return .choice(#"$\frac{\#(n)}{\#(d)}$ as a decimal"#, correct: decimal(value), wrong: wrong,
                           steps: [#"$\frac{\#(n)}{\#(d)} = \#(n) \div \#(d) = \#(decimal(value))$."#], rng: &rng)
        case 4:
            let (a, b, c) = rng.pick([(1, 2, 4), (1, 4, 2), (1, 3, 6), (3, 4, 8), (2, 5, 10), (1, 2, 8), (2, 3, 6)])
            let value = Rational(a, b) + Rational(1, c)
            return .number(#"$\frac{\#(a)}{\#(b)} + \frac{1}{\#(c)}$"#, value,
                           steps: [#"Over $\#(lcm(b, c))$: $\frac{\#(a * lcm(b, c) / b)}{\#(lcm(b, c))} + \frac{\#(lcm(b, c) / c)}{\#(lcm(b, c))} = \#(value.tex)$."#])
        case 5:
            var options: [Rational] = []
            while options.count < 4 {
                let d = rng.int(3...12), n = rng.int(1...(d - 1))
                let value = Rational(n, d)
                if !options.contains(value) && options.allSatisfy({ abs($0.double - value.double) > 0.04 }) { options.append(value) }
            }
            let biggest = options.max()!
            return .choice("Which is biggest?", correct: "$\(biggest.tex)$", wrong: options.filter { $0 != biggest }.map { "$\($0.tex)$" },
                           steps: [#"As decimals: \#(options.map { "$\($0.tex) \\approx \(String(format: "%.2f", $0.double))$" }.joined(separator: ", "))."#], rng: &rng)
        case 6:
            let a = Rational(rng.int(1...4), rng.int(2...6)), b = Rational(rng.int(1...5), rng.int(2...7))
            return .number(#"$\#(a.tex) \times \#(b.tex)$"#, a * b,
                           steps: [#"Tops times tops, bottoms times bottoms: $\frac{\#(a.numerator * b.numerator)}{\#(a.denominator * b.denominator)} = \#((a * b).tex)$."#])
        case 7:
            let b = rng.pick([3, 4, 5, 6]), d = rng.pick([2, 3, 4, 5, 8].filter { $0 != b })
            let a = rng.int(1...(b - 1)), c = rng.int(1...(d - 1))
            let common = lcm(b, d)
            if rng.chance(0.5) || Rational(a, b) < Rational(c, d) {
                let value = Rational(a, b) + Rational(c, d)
                return .number(#"$\frac{\#(a)}{\#(b)} + \frac{\#(c)}{\#(d)}$"#, value,
                               steps: [#"Over $\#(common)$: $\frac{\#(a * common / b)}{\#(common)} + \frac{\#(c * common / d)}{\#(common)} = \#(value.tex)$."#])
            }
            let value = Rational(a, b) - Rational(c, d)
            return .number(#"$\frac{\#(a)}{\#(b)} - \frac{\#(c)}{\#(d)}$"#, value,
                           steps: [#"Over $\#(common)$: $\frac{\#(a * common / b)}{\#(common)} - \frac{\#(c * common / d)}{\#(common)} = \#(value.tex)$."#])
        case 8:
            if rng.chance(0.5) {
                let whole = rng.int(2...9), d = rng.pick([2, 3, 4, 5])
                return .number(#"How many $\frac{1}{\#(d)}$s are there in $\#(whole)$?"#, whole * d, steps: [#"$\#(d)$ in each whole: $\#(whole) \times \#(d) = \#(whole * d)$."#])
            }
            let a = Rational(rng.int(1...7), rng.pick([4, 8, 6, 3])), b = Rational(rng.int(1...5), rng.pick([8, 4, 3, 6]))
            return .number(#"$\#(a.tex) \div \#(b.tex)$"#, a / b,
                           steps: [#"Flip and multiply: $\#(a.tex) \times \frac{\#(b.denominator)}{\#(b.numerator)} = \#((a / b).tex)$."#])
        case 9:
            let a = Rational(rng.int(1...3)) + Rational(1, rng.pick([2, 3, 4])), b = Rational(rng.int(1...2)) + Rational(1, rng.pick([2, 3, 5]))
            return .number(#"$\#(mixed(a)) \times \#(mixed(b))$ (a mixed number like 3 1/3 is fine)"#, a * b,
                           steps: [#"As improper fractions: $\#(a.tex) \times \#(b.tex) = \#((a * b).tex)$."#])
        default:
            if rng.chance(0.5) {
                let (n, d) = rng.pick([(3, 8), (2, 5), (3, 4), (5, 8), (2, 3)]), p = rng.pick([20, 25, 40, 50, 60, 75])
                let base = lcm(d * 100 / gcd(p, 100), 40) * rng.int(1...3)
                let value = Rational(n, d) * Rational(p, 100) * Rational(base)
                return .number(#"$\frac{\#(n)}{\#(d)}$ of $\#(p)\%$ of $\#(base)$"#, value,
                               steps: [#"$\#(p)\%$ of $\#(base)$ is $\#(decimal(Rational(p * base, 100)))$."#, #"$\frac{\#(n)}{\#(d)}$ of that is $\#(decimal(value))$."#])
            }
            let first = Rational(rng.int(1...3), rng.pick([4, 5])), second = Rational(rng.int(1...2), rng.pick([3, 2]))
            let base = first.denominator * second.denominator * rng.int(2...6)
            let value = second * first * Rational(base)
            return .number(#"$\#(second.tex)$ of $\#(first.tex)$ of $\#(base)$"#, value,
                           steps: [#"$\#(first.tex)$ of $\#(base)$ is $\#((first * Rational(base)).tex)$."#, #"$\#(second.tex)$ of that is $\#(value.tex)$."#])
        }
    }

    // MARK: Units

    static func units(_ level: Int, _ rng: inout SeededRandom) -> Problem {
        switch level {
        case 1:
            let (from, to, factor) = rng.pick([("m", "cm", 100), ("kg", "g", 1000), ("hours", "minutes", 60), ("km", "m", 1000), ("minutes", "seconds", 60)])
            let n = rng.int(2...9)
            return .number("How many \(to) in \(n) \(from)?", n * factor, steps: ["$\(factor)$ \(to) in each: $\(n) \\times \(factor) = \(n * factor)$."])
        case 2:
            let (from, to, factor) = rng.pick([("kg", "g", 1000), ("litres", "ml", 1000), ("km", "m", 1000), ("hours", "minutes", 60)])
            let n = Rational(rng.int(0...4)) + (factor == 60 ? Rational(rng.pick([1, 2, 3]), 4) : Rational(rng.pick([20, 25, 40, 50, 75]), 100))
            let value = n * Rational(factor)
            return .number("How many \(to) in \(decimal(n)) \(from)?", value, steps: ["$\(decimal(n)) \\times \(factor) = \(decimal(value))$."])
        case 3:
            if rng.chance(0.5) {
                let h = rng.int(1...4), m = rng.pick([15, 20, 25, 35, 40, 45, 50])
                return .number("How many minutes in \(h) hour\(h == 1 ? "" : "s") \(m) minutes?", h * 60 + m, steps: ["$\(h) \\times 60 + \(m) = \(h * 60 + m)$."])
            }
            let m = rng.pick([90, 150, 210, 45, 75, 135])
            return .number("How many hours is \(m) minutes? (A decimal or fraction is fine.)", Rational(m, 60),
                           steps: ["$\(m) \\div 60 = \(decimal(Rational(m, 60)))$ hours."])
        case 4:
            let (from, to, factor, up) = rng.pick([("km", "m", 1000, true), ("mm", "cm", 10, false), ("g", "kg", 1000, false), ("ml", "litres", 1000, false),
                                                  ("cm", "m", 100, false)])
            if up {
                let n = Rational(rng.int(11...99), 10)
                return .number("How many \(to) in \(decimal(n)) \(from)?", n * Rational(factor), steps: ["$\(decimal(n)) \\times \(factor) = \(decimal(n * Rational(factor)))$."])
            }
            let n = rng.int(5...95) * (factor == 10 ? 1 : 10)
            return .number("How many \(to) in \(n) \(from)?", Rational(n, factor), steps: ["$\(n) \\div \(factor) = \(decimal(Rational(n, factor)))$."])
        case 5:
            let speed = rng.pick([40, 48, 60, 80, 90, 100, 120])
            if rng.chance(0.5) {
                let minutes = rng.pick([15, 30, 45, 90])
                let value = Rational(speed * minutes, 60)
                return .number("At \(speed) km/h, how many km do you go in \(minutes) minutes?", value,
                               steps: [#"$\#(minutes)$ minutes is $\#(Rational(minutes, 60).tex)$ of an hour: $\#(speed) \times \#(Rational(minutes, 60).tex) = \#(decimal(value))$ km."#])
            }
            let hours = Rational(rng.pick([1, 3, 5, 2, 3]), 2)
            let distance = Rational(speed) * hours
            return .number("How many hours does \(decimal(distance)) km take at \(speed) km/h? (A decimal or fraction is fine.)", hours,
                           steps: [#"Time is distance over speed: $\#(decimal(distance)) \div \#(speed) = \#(decimal(hours))$."#])
        case 6:
            switch rng.int(0...2) {
            case 0:
                let miles = rng.int(2...12) * 5
                return .number("A mile is about 1.6 km. About how many km is \(miles) miles?", Rational(miles * 16, 10),
                               steps: [#"$\#(miles) \times 1.6 = \#(decimal(Rational(miles * 16, 10)))$."#])
            case 1:
                let inches = rng.int(2...12)
                return .number("An inch is 2.54 cm. How many cm is \(inches) inches?", Rational(inches * 254, 100),
                               steps: [#"$\#(inches) \times 2.54 = \#(decimal(Rational(inches * 254, 100)))$."#])
            default:
                let kg = rng.int(4...20) * 5
                return .number("A kilogram is about 2.2 lb. About how many pounds is \(kg) kg?", Rational(kg * 22, 10),
                               steps: [#"$\#(kg) \times 2 = \#(kg * 2)$, plus a tenth of that, $\#(decimal(Rational(kg * 2, 10)))$: $\#(decimal(Rational(kg * 22, 10)))$."#])
            }
        case 7:
            if rng.chance(0.5) {
                let m2 = rng.int(2...9)
                return .number(#"How many $\text{cm}^{2}$ in $\#(m2) \text{ m}^{2}$?"#, m2 * 10_000,
                               steps: [#"$1 \text{ m}^{2}$ is $100 \times 100 = 10\,000 \text{ cm}^{2}$: $\#(m2 * 10_000)$."#])
            }
            let a = Rational(rng.int(5...12) * 2 + 1, 2), b = rng.int(3...8)
            return .number(#"A room is $\#(decimal(a))$ m by $\#(b)$ m. What is its area in $\text{m}^{2}$?"#, a * Rational(b),
                           steps: [#"$\#(decimal(a)) \times \#(b) = \#(decimal(a * Rational(b)))$."#])
        case 8:
            if rng.chance(0.5) {
                let km = rng.pick([5, 10, 4, 8]), pace = rng.pick([4, 5, 6, 7])
                return .number("You run \(km) km in \(km * pace) minutes. How many minutes per km?", pace, steps: ["$\(km * pace) \\div \(km) = \(pace)$ minutes per km."])
            }
            let per100 = rng.pick([5, 6, 8, 4]), km = rng.pick([150, 250, 350, 50, 450])
            return .number("A car uses \(per100) litres per 100 km. How many litres for \(km) km?", Rational(per100 * km, 100),
                           steps: [#"$\#(km)$ km is $\#(decimal(Rational(km, 100)))$ lots of 100: $\#(decimal(Rational(km, 100))) \times \#(per100) = \#(decimal(Rational(per100 * km, 100)))$."#])
        case 9:
            if rng.chance(0.5) {
                let c = rng.int(-2...8) * 5
                let f = Rational(9 * c, 5) + 32
                return .number(#"$°\text{F} = 1.8 \times °\text{C} + 32$. What is $\#(c)°\text{C}$ in °F?"#, f,
                               steps: [#"$1.8 \times \#(c) = \#(decimal(Rational(9 * c, 5)))$, plus $32$: $\#(decimal(f))$."#])
            }
            let c = rng.int(-2...8) * 5
            let f = 9 * c / 5 + 32
            return .number(#"$°\text{C} = (°\text{F} - 32) \div 1.8$. What is $\#(f)°\text{F}$ in °C?"#, c,
                           steps: [#"$\#(f) - 32 = \#(f - 32)$, and $\#(f - 32) \div 1.8 = \#(c)$."#])
        default:
            switch rng.int(0...2) {
            case 0:
                let kmh = rng.pick([18, 36, 54, 72, 90, 108])
                return .number("How many metres per second is \(kmh) km/h?", kmh * 5 / 18,
                               steps: [#"$1000$ m an hour is $\frac{1000}{3600} = \frac{5}{18}$ m a second: $\#(kmh) \times \frac{5}{18} = \#(kmh * 5 / 18)$."#])
            case 1:
                let m3 = Rational(rng.int(3...19), 2)
                return .number(#"How many litres in $\#(decimal(m3)) \text{ m}^{3}$?"#, m3 * Rational(1000),
                               steps: [#"$1 \text{ m}^{3}$ is $1000$ litres: $\#(decimal(m3 * Rational(1000)))$."#])
            default:
                let ms = rng.pick([5, 10, 15, 20, 25])
                return .number("How many km/h is \(ms) metres per second?", ms * 18 / 5,
                               steps: [#"$\#(ms) \times 3600 = \#(ms * 3600)$ m an hour, which is $\#(decimal(Rational(ms * 18, 5)))$ km/h."#])
            }
        }
    }

    // MARK: Writing numbers

    /// A terminating fraction as a decimal: 3/4 is "0.75", -5/2 is "-2.5".
    static func decimal(_ value: Rational) -> String { value.decimal ?? String(format: "%.2f", value.double) }

    /// "3.1", and "5" rather than "5.0".
    static func oneDecimal(_ value: Double) -> String {
        let text = String(format: "%.1f", value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    /// "12,000".
    static func grouped(_ n: Int) -> String {
        let digits = Array(String(abs(n)))
        var out = ""
        for (index, digit) in digits.enumerated() {
            if index > 0 && (digits.count - index) % 3 == 0 { out.append(",") }
            out.append(digit)
        }
        return (n < 0 ? "-" : "") + out
    }

    /// "2 1/2" as TeX: 2\frac{1}{2}.
    static func mixed(_ value: Rational) -> String {
        let whole = value.numerator / value.denominator
        let rest = value - Rational(whole)
        return whole == 0 ? rest.tex : rest == 0 ? "\(whole)" : "\(whole)\(rest.tex)"
    }

    static func round(_ n: Int, _ to: Int) -> Int { Int((Double(n) / Double(to)).rounded()) * to }
}
