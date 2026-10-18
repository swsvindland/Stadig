import Foundation
import SystemCore

// MARK: - Statistics and logic

/// The discrete and statistics strand: logic, sets, counting, probability and statistics, from
/// reading a chart to a least-squares line. Its graph stands on its own, so it can be learned
/// without the classic ladder. Where the System apps have published enough, about half the
/// problems are about the person's own steps, training and food; every one has a made-up version.
extension MathCurriculum {
    static let discrete: [MathTopic] = [
        MathTopic(id: "reading-charts", title: "Reading charts", level: 1, prerequisites: [],
                  lesson: "Read the scale first, then each bar against it. Differences and totals come straight off the values; a chart that doesn't start at zero makes small differences look big.",
                  seconds: 30, strand: .discrete) { rng in
            let (title, unit, labels) = rng.pick([
                ("Library books borrowed", "books", ["Mon", "Tue", "Wed", "Thu", "Fri"]),
                ("Cups of coffee sold", "cups", ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]),
                ("Rainy days", "days", ["Jan", "Feb", "Mar", "Apr", "May", "Jun"]),
            ])
            let values = labels.map { _ in rng.int(2...9) * 10 }
            return ChartQuestions.problem(DataFigure(title: title, unit: unit, points: zip(labels, values).map { .init(label: $0, value: Double($1)) }), unit: unit,
                                  values: values, labels: labels, rng: &rng)
        }.withData { rng, data in
            guard let week = data.stepWeek?.rounded(to: 100) else { return nil }
            let values = week.map { Int($0.value) }, labels = week.map(\.day.weekday.short)
            return ChartQuestions.problem(week.figure("Your steps, the last seven days", unit: "steps", source: "From Lift Track"), unit: "steps",
                                  values: values, labels: labels, rng: &rng)
        },
        MathTopic(id: "logic-and-or", title: "And, or, not", level: 1, prerequisites: [],
                  lesson: #""A and B" needs both; "A or B" needs at least one (both counts); "not A" is everything else. Count the overlap once."#,
                  seconds: 40, strand: .discrete) { rng in
            let conditions: [(String, @Sendable (Int) -> Bool)] = [
                ("even", { $0 % 2 == 0 }), ("odd", { $0 % 2 == 1 }), ("a multiple of 3", { $0 % 3 == 0 }), ("a multiple of 4", { $0 % 4 == 0 }),
                ("a multiple of 5", { $0 % 5 == 0 }),
            ]
            let first = rng.pick(conditions)
            var second = rng.pick(conditions)
            while second.0 == first.0 { second = rng.pick(conditions) }
            let cut = rng.int(6...14)
            let numbers = Array(1...20)
            let (wording, test): (String, (Int) -> Bool) = switch rng.int(0...2) {
            case 0: ("\(first.0) and greater than \(cut)", { first.1($0) && $0 > cut })
            case 1: ("\(first.0) or \(second.0)", { first.1($0) || second.1($0) })
            default: ("\(first.0) but not \(second.0)", { first.1($0) && !second.1($0) })
            }
            let matches = numbers.filter(test)
            return .number("How many whole numbers from 1 to 20 are \(wording)?", matches.count,
                           steps: [matches.isEmpty ? "None of them." : "They are \(matches.map(String.init).joined(separator: ", ")): \(matches.count)."])
        },
        MathTopic(id: "averages", title: "Mean and median", level: 2, prerequisites: ["reading-charts"],
                  lesson: #"The mean is the total divided by how many. The median is the middle value once they're in order; with an even count, it's halfway between the middle two."#,
                  seconds: 35, strand: .discrete) { rng in
            let count = rng.pick([5, 6, 7])
            let values = (0..<count).map { _ in rng.int(1...20) }
            let list = values.map(String.init).joined(separator: ", ")
            let sorted = values.sorted()
            if rng.chance(0.5) {
                let value = Rational(values.reduce(0, +), count)
                return .number(#"Find the mean of $\#(list)$."#, value,
                               steps: [#"Total $\#(values.reduce(0, +))$, divided by $\#(count)$: $\#(value.tex)$."#])
            }
            let value = count % 2 == 1 ? Rational(sorted[count / 2]) : Rational(sorted[count / 2 - 1] + sorted[count / 2], 2)
            return .number(#"Find the median of $\#(list)$."#, value,
                           steps: [#"In order: $\#(sorted.map(String.init).joined(separator: ", "))$."#, #"The middle: $\#(value.tex)$."#])
        }.withData { rng, data in
            guard let week = data.stepWeek?.rounded(to: 100) else { return nil }
            let values = week.map { Int($0.value) }
            if rng.chance(0.5) {
                let five = Array(values.suffix(5))
                let mean = Rational(five.reduce(0, +), 5)
                return .number(#"Lift Track counted your steps on the last five days: \#(five.map(Numeracy.grouped).joined(separator: ", ")) (to the nearest hundred). What was the mean?"#,
                               mean, steps: [#"Total $\#(Numeracy.grouped(five.reduce(0, +)))$, divided by $5$: $\#(Numeracy.decimal(mean))$."#])
            }
            let odd = values.count % 2 == 1 ? values : Array(values.suffix(values.count - 1))
            let sorted = odd.sorted()
            let days = week.suffix(odd.count)
            return Problem.number("What was the median of these days?", sorted[sorted.count / 2],
                                  steps: ["In order: \(sorted.map(Numeracy.grouped).joined(separator: ", ")).", "The middle one: \(Numeracy.grouped(sorted[sorted.count / 2]))."])
                .with(Array(days).figure("Your steps", unit: "steps", source: "From Lift Track"))
        },
        MathTopic(id: "sets", title: "Sets and Venn diagrams", level: 2, prerequisites: ["logic-and-or"],
                  lesson: #"In two overlapping groups, the overlap gets counted twice if you just add: $|A \cup B| = |A| + |B| - |A \cap B|$. Whatever's left over is in neither."#,
                  seconds: 40, strand: .discrete) { rng in
            let both = rng.int(2...9), a = both + rng.int(3...15), b = both + rng.int(3...15)
            let total = a + b - both + rng.int(2...12)
            let (one, two) = rng.pick([("run", "swim"), ("read fiction", "read non-fiction"), ("own a cat", "own a dog"), ("speak French", "speak Spanish")])
            switch rng.int(0...2) {
            case 0:
                return .number("Of \(total) people, \(a) \(one), \(b) \(two) and \(both) do both. How many do neither?", total - (a + b - both),
                               steps: [#"At least one: $\#(a) + \#(b) - \#(both) = \#(a + b - both)$."#, "Neither: $\(total) - \(a + b - both) = \(total - a - b + both)$."])
            case 1:
                return .number("Of \(total) people, \(a) \(one), \(b) \(two) and \(both) do both. How many do exactly one of the two?", a + b - 2 * both,
                               steps: [#"Only the first: $\#(a) - \#(both) = \#(a - both)$; only the second: $\#(b) - \#(both) = \#(b - both)$."#, "Together: $\(a + b - 2 * both)$."])
            default:
                return .number(#"$|A| = \#(a)$, $|B| = \#(b)$ and $|A \cap B| = \#(both)$. Find $|A \cup B|$."#, a + b - both,
                               steps: [#"$|A \cup B| = \#(a) + \#(b) - \#(both) = \#(a + b - both)$."#])
            }
        }.withData { _, data in
            guard let last = [data.training.last?.day, data.proteinHits.keys.max()].compactMap({ $0 }).max() else { return nil }
            let window = Set((0..<28).map { last.adding(days: -$0) })
            let trained = Set(data.training.map(\.day)).intersection(window), logged = Set(data.proteinHits.keys).intersection(window)
            let both = trained.intersection(logged).count
            guard trained.count >= 3, logged.count >= 5 else { return nil }
            let either = trained.count + logged.count - both
            return .number("In the last 28 days you trained on \(trained.count) days (Lift Track) and logged food on \(logged.count) (Macro Track); \(both) days had both. On how many days did you do neither?",
                           28 - either, steps: [#"At least one: $\#(trained.count) + \#(logged.count) - \#(both) = \#(either)$."#, "Neither: $28 - \(either) = \(28 - either)$."])
        },
        MathTopic(id: "counting-principle", title: "Counting outcomes", level: 2, prerequisites: [],
                  lesson: #"When choices are made one after another, multiply the number of options at each step: 3 shirts and 4 pairs of trousers make $3 \times 4 = 12$ outfits."#,
                  seconds: 35, strand: .discrete) { rng in
            switch rng.int(0...2) {
            case 0:
                let a = rng.int(2...6), b = rng.int(2...5), c = rng.int(2...4)
                return .number("A café offers \(a) breads, \(b) fillings and \(c) sauces. How many different sandwiches have one of each?", a * b * c,
                               steps: [#"$\#(a) \times \#(b) \times \#(c) = \#(a * b * c)$."#])
            case 1:
                let digits = rng.int(3...5)
                var count = 1
                for _ in 0..<digits { count *= 10 }
                return .number("How many different \(digits)-digit PINs are there, using any digits 0 to 9?", count,
                               steps: [#"Ten choices for each of $\#(digits)$ digits: $10^{\#(digits)} = \#(Numeracy.grouped(count))$."#])
            default:
                let starters = rng.int(2...5), mains = rng.int(3...6), puddings = rng.int(2...4)
                return .number("A menu has \(starters) starters, \(mains) mains and \(puddings) puddings. How many different three-course meals are there?", starters * mains * puddings,
                               steps: [#"$\#(starters) \times \#(mains) \times \#(puddings) = \#(starters * mains * puddings)$."#])
            }
        },
        MathTopic(id: "range-spread", title: "Range and interquartile range", level: 3, prerequisites: ["averages"],
                  lesson: "The range is the largest minus the smallest: one outlier can swing it. The interquartile range is steadier: split the ordered list into a lower and an upper half, take the median of each (the quartiles), and subtract.",
                  seconds: 45, strand: .discrete) { rng in
            let values = (0..<8).map { _ in rng.int(3...40) }
            let sorted = values.sorted()
            let list = values.map(String.init).joined(separator: ", ")
            if rng.chance(0.4) {
                return .number(#"Find the range of $\#(list)$."#, sorted[7] - sorted[0],
                               steps: [#"Largest $\#(sorted[7])$, smallest $\#(sorted[0])$: $\#(sorted[7] - sorted[0])$."#])
            }
            let q1 = Rational(sorted[1] + sorted[2], 2), q3 = Rational(sorted[5] + sorted[6], 2)
            return .number(#"Find the interquartile range of $\#(list)$."#, q3 - q1,
                           steps: [#"In order: $\#(sorted.map(String.init).joined(separator: ", "))$."#,
                                   #"Lower half's median $\#(q1.tex)$, upper half's $\#(q3.tex)$: $\#(q3.tex) - \#(q1.tex) = \#((q3 - q1).tex)$."#])
        }.withData { _, data in
            guard let week = data.stepWeek?.rounded(to: 100) else { return nil }
            let values = week.map { Int($0.value) }
            let high = values.max()!, low = values.min()!
            return Problem.number("What was the range of your steps over these days?", high - low,
                                  steps: ["Most \(Numeracy.grouped(high)), fewest \(Numeracy.grouped(low)): \(Numeracy.grouped(high - low))."])
                .with(week.figure("Your steps", unit: "steps", source: "From Lift Track"))
        },
        MathTopic(id: "if-then", title: "If–then reasoning", level: 3, prerequisites: ["logic-and-or"],
                  lesson: #"From "if P then Q": P tells you Q, and not Q tells you not P. But Q doesn't tell you P, and not P doesn't tell you anything about Q: those are the two classic slips."#,
                  seconds: 40, strand: .discrete) { rng in
            let (p, q, notP, notQ) = rng.pick([
                ("it rains", "the match is called off", "it didn't rain", "the match went ahead"),
                ("a number is divisible by 6", "it's even", "it isn't divisible by 6", "it's odd"),
                ("the alarm is set", "the light is red", "the alarm isn't set", "the light isn't red"),
                ("you have a ticket", "you can board", "you don't have a ticket", "you can't board"),
            ])
            let fact = rng.int(0...3)
            let given = [p, q, notP, notQ][fact]
            let nothing = "Nothing certain follows"
            let correct = [q, nothing, nothing, notP][fact]
            let why = [
                "The rule applies directly: \(p), so \(q).",
                "Affirming the consequent: \(q) could happen for other reasons.",
                "Denying the antecedent: the rule says nothing about what happens when it's false.",
                "If \(p) were true, \(q) would be too; it isn't, so \(notP).",
            ][fact]
            let options = [q, notP, p, notQ, nothing].filter { $0 != given }.map { $0.prefix(1).uppercased() + $0.dropFirst() }
            let right = correct.prefix(1).uppercased() + correct.dropFirst()
            return .choice("If \(p), then \(q). You learn that \(given). What follows?", correct: right, wrong: options.filter { $0 != right }.shuffled(using: &rng),
                           steps: [why], rng: &rng)
        },
        MathTopic(id: "probability", title: "Probability", level: 3, prerequisites: ["counting-principle"],
                  lesson: #"Probability is favourable outcomes over all outcomes. For two things in a row, multiply; without replacement, the second fraction changes: two reds from 3 red and 2 blue is $\frac{3}{5} \times \frac{2}{4}$."#,
                  seconds: 45, strand: .discrete) { rng in
            let red = rng.int(2...8), blue = rng.int(2...8), green = rng.int(1...6)
            let total = red + blue + green
            switch rng.int(0...2) {
            case 0:
                return .number(#"A bag has $\#(red)$ red, $\#(blue)$ blue and $\#(green)$ green marbles. One is taken at random. What is the probability it's blue?"#,
                               Rational(blue, total), steps: [#"$\frac{\#(blue)}{\#(total)} = \#(Rational(blue, total).tex)$."#])
            case 1:
                let value = Rational(red, total) * Rational(red - 1, total - 1)
                return .number(#"A bag has $\#(red)$ red, $\#(blue)$ blue and $\#(green)$ green marbles. Two are taken without putting the first back. What is the probability both are red?"#,
                               value, steps: [#"$\frac{\#(red)}{\#(total)} \times \frac{\#(red - 1)}{\#(total - 1)} = \#(value.tex)$."#])
            default:
                let sum = rng.int(3...11)
                let ways = (1...6).flatMap { a in (1...6).map { a + $0 } }.filter { $0 == sum }.count
                return .number(#"Two fair dice are rolled. What is the probability the total is $\#(sum)$?"#, Rational(ways, 36),
                               steps: [#"$\#(ways)$ of the $36$ equally likely pairs add to $\#(sum)$: $\#(Rational(ways, 36).tex)$."#])
            }
        },
        MathTopic(id: "two-way-tables", title: "Two-way tables", level: 4, prerequisites: ["sets", "probability"],
                  lesson: "A two-way table counts every combination of two yes-or-no questions. A probability \"of the coffee drinkers\" divides by that row's total, not by everyone.",
                  seconds: 50, strand: .discrete) { rng in
            let (group, other, one, yes, no) = rng.pick([
                ("coffee drinkers", "non-drinkers", "non-drinker", "slept badly", "slept well"),
                ("cyclists", "drivers", "driver", "arrived late", "arrived on time"),
                ("smokers", "non-smokers", "non-smoker", "had a cough", "had no cough"),
            ])
            let a = rng.int(5...40), b = rng.int(5...40), c = rng.int(5...40), d = rng.int(5...40)
            let table = "Of the \(group), \(a) \(yes) and \(b) \(no). Of the \(other), \(c) \(yes) and \(d) \(no)."
            if rng.chance(0.5) {
                return .number("\(table) What fraction of the \(group) \(yes)?", Rational(a, a + b),
                               steps: [#"Only the \#(group) count: $\frac{\#(a)}{\#(a) + \#(b)} = \#(Rational(a, a + b).tex)$."#])
            }
            let total = a + b + c + d
            return .number("\(table) One person is picked at random from everyone. What's the probability they're a \(one) who \(no)?", Rational(d, total),
                           steps: [#"Everyone counts: $\frac{\#(d)}{\#(total)} = \#(Rational(d, total).tex)$."#])
        }.withData { _, data in
            guard let t = data.trainingAndProtein else { return nil }
            let days = t.trainedHit + t.trainedMissed + t.restHit + t.restMissed
            return .number("Over \(days) days of Macro Track logging: training days, \(t.trainedHit) hit your protein target and \(t.trainedMissed) missed; rest days, \(t.restHit) hit and \(t.restMissed) missed. On what fraction of training days did you hit protein?",
                           Rational(t.trainedHit, t.trainedHit + t.trainedMissed),
                           steps: [#"Training days only: $\frac{\#(t.trainedHit)}{\#(t.trainedHit) + \#(t.trainedMissed)} = \#(Rational(t.trainedHit, t.trainedHit + t.trainedMissed).tex)$."#])
        },
        MathTopic(id: "independence", title: "Independent events", level: 4, prerequisites: ["probability"],
                  lesson: #"Independent events don't affect each other, so the chance of both is the product. For "at least one", it's easier to take away the chance of none: $1 - P(\text{none})$."#,
                  seconds: 45, strand: .discrete) { rng in
            switch rng.int(0...2) {
            case 0:
                let face = rng.int(1...6)
                return .number("A fair coin is flipped and a fair die rolled. What's the probability of heads and a \(face)?", Rational(1, 12),
                               steps: [#"$\frac{1}{2} \times \frac{1}{6} = \frac{1}{12}$."#])
            case 1:
                let rolls = rng.int(2...3)
                let none = Rational(5, 6).power(rolls)
                return .number("A fair die is rolled \(rolls) times. What's the probability of at least one six?", 1 - none,
                               steps: [#"No six: $(\frac{5}{6})^{\#(rolls)} = \#(none.tex)$."#, #"At least one: $1 - \#(none.tex) = \#((1 - none).tex)$."#])
            default:
                let p = rng.pick([9, 8, 7]), times = rng.int(2...3)
                let value = Rational(p, 10).power(times)
                return .number("A bus is on time \(p * 10)% of days, independently. What's the probability it's on time \(times) days running? (A decimal is fine.)", value,
                               steps: [#"$\#(Numeracy.decimal(Rational(p, 10)))^{\#(times)} = \#(Numeracy.decimal(value))$."#])
            }
        },
        MathTopic(id: "conditional-probability", title: "Conditional probability", level: 5, prerequisites: ["two-way-tables"],
                  lesson: #"$P(A \mid B)$ is the chance of A among the cases where B happened: $P(A \mid B) = \frac{P(A \text{ and } B)}{P(B)}$. It's usually not the same as $P(B \mid A)$."#,
                  seconds: 50, strand: .discrete) { rng in
            if rng.chance(0.5) {
                let pb = Rational(rng.pick([2, 4, 5, 8]), 10)
                let given = Rational(rng.pick([1, 2, 3, 5]), 10)
                let both = pb * given
                return .number(#"$P(A \text{ and } B) = \#(Numeracy.decimal(both))$ and $P(B) = \#(Numeracy.decimal(pb))$. Find $P(A \mid B)$."#, given,
                               steps: [#"$\frac{\#(Numeracy.decimal(both))}{\#(Numeracy.decimal(pb))} = \#(Numeracy.decimal(given))$."#])
            }
            let drive = rng.int(40...120), late = rng.int(5...30), lateDrivers = rng.int(2...min(late, drive) - 1)
            return .number("Of 200 commuters, \(drive) drive and \(late) were late; \(lateDrivers) of the late ones drove. Given someone was late, what's the probability they drove?",
                           Rational(lateDrivers, late), steps: [#"Among the late only: $\frac{\#(lateDrivers)}{\#(late)} = \#(Rational(lateDrivers, late).tex)$."#])
        }.withData { _, data in
            guard let t = data.trainingAndProtein, t.trainedHit + t.restHit > 0 else { return nil }
            return .number("Your logged days: training days, \(t.trainedHit) hit protein and \(t.trainedMissed) missed; rest days, \(t.restHit) hit and \(t.restMissed) missed. Given you hit protein, what's the probability it was a training day?",
                           Rational(t.trainedHit, t.trainedHit + t.restHit),
                           steps: [#"Among protein days only: $\frac{\#(t.trainedHit)}{\#(t.trainedHit) + \#(t.restHit)} = \#(Rational(t.trainedHit, t.trainedHit + t.restHit).tex)$."#,
                                   "Not the same as the chance of hitting protein on a training day."])
        },
        MathTopic(id: "sampling", title: "Samples and bias", level: 5, prerequisites: ["averages", "range-spread"],
                  lesson: #"A sample tells you about a population only if it's picked fairly: who answers, who's left out and who survived to be counted all matter. Bigger samples wobble less; a poll's margin of error is roughly $\frac{1}{\sqrt{n}}$."#,
                  seconds: 45, strand: .discrete) { rng in
            if rng.chance(0.5) {
                let (n, margin) = rng.pick([(100, Rational(10)), (400, Rational(5)), (625, Rational(4)), (1600, Rational(5, 2)), (2500, Rational(2)), (10_000, Rational(1))])
                return .number(#"A poll's margin of error is roughly $\frac{1}{\sqrt{n}}$. About what margin, in percent, for $n = \#(Numeracy.grouped(n))$?"#, margin,
                               steps: [#"$\sqrt{\#(n)} = \#(Int(Double(n).squareRoot()))$ and $\frac{1}{\#(Int(Double(n).squareRoot()))} = \#(Numeracy.decimal(margin))\%$."#])
            }
            let (study, right, wrong) = rng.pick([
                ("A gym surveys its members to estimate how much adults exercise.", "Gym members exercise more than most adults",
                 ["The sample is too small to say anything", "Surveys can't measure exercise", "Nothing: the sample is fine"]),
                ("A website asks visitors whether they like the website.", "The people who answer chose to visit and to answer",
                 ["Online polls are always too small", "Visitors can't be trusted", "Nothing: everyone could answer"]),
                ("Planes back from missions are studied to see where to add armour.", "Planes hit in the worst places never came back to be studied",
                 ["Too few planes were studied", "Armour was already in the right places", "Nothing: it's a fair sample"]),
                ("A doctor judges a cure by the patients who return to say they're better.", "Patients who weren't helped are less likely to come back",
                 ["Doctors can't judge cures", "The sample is too large", "Nothing: those patients are typical"]),
            ])
            return .choice("\(study) What's the main problem?", correct: right, wrong: wrong, steps: ["\(right): the sample isn't like the population it's meant to describe."], rng: &rng)
        }.withData { rng, data in
            guard let last = data.steps.last?.day else { return nil }
            let month = data.steps.filter { $0.day > last.adding(days: -28) }, week = data.steps.filter { $0.day > last.adding(days: -7) }
            guard month.count >= 21, week.count >= 5 else { return nil }
            let monthMean = Int((month.map(\.value).reduce(0, +) / Double(month.count) / 100).rounded()) * 100
            let weekMean = Int((week.map(\.value).reduce(0, +) / Double(week.count) / 100).rounded()) * 100
            return .choice("Your steps averaged \(Numeracy.grouped(weekMean)) over the last \(week.count) days and \(Numeracy.grouped(monthMean)) over the last \(month.count). Which better estimates a typical day this past month?",
                           correct: "The \(month.count)-day average: more days, less noise",
                           wrong: ["The \(week.count)-day average: it's more recent", "They're equally good", "Neither: averages can't estimate a typical day"],
                           steps: ["A single week wobbles with what happened that week; four weeks of days average more of that out."], rng: &rng)
        },
        MathTopic(id: "counting", title: "Permutations and combinations", level: 6, prerequisites: ["counting-principle", "probability"],
                  lesson: #"Choosing $r$ from $n$ when order matters: $\frac{n!}{(n - r)!}$. When it doesn't: $\binom{n}{r} = \frac{n!}{r!(n - r)!}$. A team of 3 from 5 people is $\binom{5}{3} = 10$."#,
                  seconds: 45, strand: .discrete) { rng in
            let n = rng.int(5...10), r = rng.int(2...4)
            let ordered = (0..<r).reduce(1) { $0 * (n - $1) }
            var factorial = 1
            for i in 1...r { factorial *= i }
            if rng.chance(0.5) {
                return .number(#"How many ways can a team of $\#(r)$ be chosen from $\#(n)$ people?"#, ordered / factorial,
                               steps: [#"Order doesn't matter: $\binom{\#(n)}{\#(r)} = \frac{\#(ordered)}{\#(factorial)} = \#(ordered / factorial)$."#])
            }
            return .number(#"$\#(r)$ different prizes go to $\#(n)$ runners, at most one each. In how many ways can they be given out?"#, ordered,
                           steps: [#"Order matters: $\#((0..<r).map { "\(n - $0)" }.joined(separator: #" \times "#)) = \#(ordered)$."#])
        },
        MathTopic(id: "expected-value", title: "Expected value", level: 6, prerequisites: ["probability", "averages"],
                  lesson: #"Multiply each outcome by its probability and add: the long-run average per go."#,
                  seconds: 50, strand: .discrete) { rng in
            let a = rng.int(5...12), b = rng.int(1...4), c = rng.int(1...3)
            let value = Rational(a + 2 * b - 3 * c, 6)
            return .number(#"Roll a fair die: a 6 wins $\#(a)$ points, a 4 or 5 wins $\#(b)$, and anything else loses $\#(c)$. What is the expected score per roll?"#,
                           value, steps: [#"$\frac{1}{6}(\#(a)) + \frac{2}{6}(\#(b)) + \frac{3}{6}(-\#(c))$."#, #"$= \#(value.tex)$."#])
        },
        MathTopic(id: "standard-deviation", title: "Standard deviation", level: 6, prerequisites: ["range-spread"],
                  lesson: "The standard deviation is the typical distance from the mean: square each distance, take the mean of the squares, then the square root. Most values sit within one standard deviation of the mean.",
                  seconds: 60, strand: .discrete) { rng in
            let pattern = rng.pick([[-3, -1, -1, -1, 0, 0, 2, 4], [-1, -1, -1, -1, 4], [-2, 2, -2, 2]])
            let k = rng.pick([1, 2, 3, 5]), mean = rng.int(10...50)
            let values = pattern.map { mean + k * $0 }.shuffled(using: &rng)
            let squares = pattern.map { $0 * $0 * k * k }
            let sd = 2 * k
            return .number(#"Find the standard deviation of $\#(values.map(String.init).joined(separator: ", "))$."#, sd,
                           steps: [#"The mean is $\#(mean)$."#,
                                   #"Squared distances: $\#(squares.map(String.init).joined(separator: ", "))$, with mean $\#(squares.reduce(0, +) / squares.count)$."#,
                                   #"$\sqrt{\#(sd * sd)} = \#(sd)$."#])
        }.withData { _, data in
            guard let stats = data.stepStats else { return nil }
            return .number("Over your last \(stats.days) step days, the mean was \(Numeracy.grouped(stats.mean)) with a standard deviation of \(Numeracy.grouped(stats.sd)) (rounded). How many steps is two standard deviations below the mean?",
                           stats.mean - 2 * stats.sd, steps: [#"$\#(Numeracy.grouped(stats.mean)) - 2 \times \#(Numeracy.grouped(stats.sd)) = \#(Numeracy.grouped(stats.mean - 2 * stats.sd))$."#])
        },
        MathTopic(id: "relative-risk", title: "Reading studies: relative and absolute risk", level: 6, prerequisites: ["conditional-probability"],
                  lesson: #""Halves the risk" can mean 2 in 1,000 becoming 1 in 1,000. Look for the absolute change, and the number needed to treat: how many people take it for one of them to benefit, $\frac{1}{\text{absolute change}}$."#,
                  seconds: 50, strand: .discrete) { rng in
            let (before, after) = rng.pick([(2, 1), (4, 2), (5, 4), (10, 8), (20, 15), (8, 6), (4, 3), (10, 5)])
            switch rng.int(0...2) {
            case 0:
                return .number("A study finds a pill cuts the risk of a stroke from \(before) in 1,000 people to \(after) in 1,000. By what percentage does it cut the risk?",
                               Rational(100 * (before - after), before), steps: [#"Relative change: $\frac{\#(before - after)}{\#(before)} = \#(Numeracy.decimal(Rational(100 * (before - after), before)))\%$."#])
            case 1:
                return .number("A study finds a pill cuts the risk of a stroke from \(before) in 1,000 people to \(after) in 1,000. How many fewer strokes per 1,000 people?",
                               before - after, steps: ["Absolute change: $\(before) - \(after) = \(before - after)$ per 1,000."])
            default:
                return .number("A pill cuts the risk of a stroke from \(before) in 1,000 to \(after) in 1,000. How many people need to take it to prevent one stroke?",
                               Rational(1000, before - after),
                               steps: [before - after == 1 ? "One fewer stroke per 1,000 people, so 1,000 people take it for one of them to benefit."
                                                           : #"$\#(before - after)$ fewer per 1,000, so $\frac{1000}{\#(before - after)} = \#(Numeracy.decimal(Rational(1000, before - after)))$ people."#])
            }
        },
        MathTopic(id: "base-rates", title: "Base rates", level: 7, prerequisites: ["conditional-probability"],
                  lesson: "A positive test for something rare is often a false alarm. Imagine 10,000 people: work out how many have it and test positive, how many don't and test positive anyway, and compare.",
                  seconds: 70, strand: .discrete) { rng in
            if rng.chance(0.3) {
                let rate = rng.pick([1000, 500, 2000])
                let truePositive = 0.99, falsePositive = Double(rate - 1) * 0.01
                let share = truePositive / (truePositive + falsePositive)
                let choices = ["About 1 in 20", "About 1 in 10", "About half", "About 90%", "About 99%"]
                let correct = share < 0.075 ? choices[0] : share < 0.2 ? choices[1] : choices[2]
                return .choice("A test is 99% accurate either way. The condition affects 1 in \(Numeracy.grouped(rate)) people. Someone tests positive. How likely is it they have it?",
                               correct: correct, wrong: choices.filter { $0 != correct }.shuffled(using: &rng),
                               steps: [#"In \#(Numeracy.grouped(rate)) people: about $1$ has it and tests positive; $1\%$ of the other \#(Numeracy.grouped(rate - 1)), about $\#(Numeracy.oneDecimal(falsePositive))$, test positive anyway."#,
                                       "So about \(Int((share * 100).rounded()))% of positives have it."], rng: &rng)
            }
            var sick = 0, truePositive = 0, falsePositive = 0, prevalence = 1, sensitivity = 90, falseRate = 5
            repeat {
                prevalence = rng.pick([1, 2, 5]); sensitivity = rng.pick([80, 90, 95]); falseRate = rng.pick([2, 5, 10, 8])
                sick = 10_000 * prevalence / 100
                truePositive = sick * sensitivity / 100
                falsePositive = (10_000 - sick) * falseRate / 100
            } while sick * sensitivity % 100 != 0 || (10_000 - sick) * falseRate % 100 != 0
            let positives = truePositive + falsePositive
            let question = "\(prevalence)% of people have a condition. A test catches \(sensitivity)% of those who have it, and wrongly flags \(falseRate)% of those who don't."
            let work = "In 10,000 people: \(Numeracy.grouped(sick)) have it and \(Numeracy.grouped(truePositive)) of them test positive; \(Numeracy.grouped(10_000 - sick)) don't, and \(Numeracy.grouped(falsePositive)) of them test positive too."
            if rng.chance(0.5) {
                return .number("\(question) Out of 10,000 people, how many test positive?", positives, steps: [work, "$\(truePositive) + \(falsePositive) = \(positives)$."])
            }
            return .number("\(question) What fraction of the people who test positive actually have it?", Rational(truePositive, positives),
                           steps: [work, #"$\frac{\#(truePositive)}{\#(positives)} = \#(Rational(truePositive, positives).tex)$, about $\#(Int((Double(truePositive) / Double(positives) * 100).rounded()))\%$."#])
        },
        MathTopic(id: "normal-distribution", title: "The normal distribution", level: 7, prerequisites: ["standard-deviation"],
                  lesson: "In a normal distribution, about 68% of values are within one standard deviation of the mean, 95% within two and 99.7% within three. Half are above the mean, so 16% are more than one standard deviation above.",
                  seconds: 50, strand: .discrete) { rng in
            let (what, unit, mean, sd) = rng.pick([("Adult heights", "cm", 170, 8), ("IQ scores", "points", 100, 15), ("Exam marks", "marks", 60, 10), ("Commute times", "minutes", 40, 6)])
            let cases: [(String, Rational, String)] = [
                ("between \(mean - sd) and \(mean + sd)", 68, "Within one standard deviation: $68\\%$."),
                ("between \(mean - 2 * sd) and \(mean + 2 * sd)", 95, "Within two: $95\\%$."),
                ("above \(mean + sd)", 16, #"Outside one is $32\%$, half of it above: $16\%$."#),
                ("above \(mean + 2 * sd)", Rational(5, 2), #"Outside two is $5\%$, half of it above: $2.5\%$."#),
                ("between \(mean) and \(mean + sd)", 34, #"Half of the middle $68\%$: $34\%$."#),
                ("below \(mean - 2 * sd)", Rational(5, 2), #"Outside two is $5\%$, half of it below: $2.5\%$."#),
            ]
            let (range, value, why) = rng.pick(cases)
            return .number("\(what) are roughly normal with mean \(mean) \(unit) and standard deviation \(sd). About what percentage are \(range)?", value, steps: [why])
        }.withData { _, data in
            guard let stats = data.stepStats, stats.sd > 0 else { return nil }
            return .number("Say your daily steps are roughly normal, with mean \(Numeracy.grouped(stats.mean)) and standard deviation \(Numeracy.grouped(stats.sd)) (your last \(stats.days) days, rounded). On about what percentage of days would you walk more than \(Numeracy.grouped(stats.mean + stats.sd))?",
                           16, steps: ["That's one standard deviation above the mean: outside one is about 32%, half of it above, so about 16%."])
        },
        MathTopic(id: "correlation", title: "Correlation and causation", level: 7, prerequisites: ["standard-deviation", "relative-risk"],
                  lesson: "Two things moving together doesn't show one causes the other. Look for a third thing driving both (a confounder), for cause running the other way, and for chance in small samples.",
                  seconds: 45, strand: .discrete) { rng in
            let (finding, right, wrong) = rng.pick([
                ("Across a summer, ice cream sales and drownings rise and fall together.", "Hot weather drives both",
                 ["Ice cream makes people drown", "Drownings make people buy ice cream", "It must be a coincidence"]),
                ("Children with bigger feet read better.", "Older children have bigger feet and read better",
                 ["Big feet help reading", "Reading makes feet grow", "It must be a coincidence"]),
                ("The more firefighters at a fire, the more damage is done.", "Bigger fires bring more firefighters and do more damage",
                 ["Firefighters cause damage", "Damage summons firefighters by itself", "It must be a coincidence"]),
                ("People who carry lighters get lung cancer more often.", "Smokers carry lighters, and smoking causes cancer",
                 ["Lighters cause cancer", "Cancer makes people carry lighters", "It must be a coincidence"]),
            ])
            return .choice("\(finding) What's the best explanation?", correct: right, wrong: wrong,
                           steps: ["\(right): a third thing behind both, a confounder."], rng: &rng)
        }.withData { rng, data in
            let trained = Set(data.training.map(\.day))
            let on = data.steps.filter { trained.contains($0.day) }, off = data.steps.filter { !trained.contains($0.day) }
            guard on.count >= 3, off.count >= 3 else { return nil }
            let onMean = Int((on.map(\.value).reduce(0, +) / Double(on.count) / 100).rounded()) * 100
            let offMean = Int((off.map(\.value).reduce(0, +) / Double(off.count) / 100).rounded()) * 100
            let more = onMean >= offMean
            return .choice("On days you trained, you averaged \(Numeracy.grouped(onMean)) steps; on other days, \(Numeracy.grouped(offMean)). Does this show training makes you walk \(more ? "more" : "less")?",
                           correct: "Not on its own: what kind of day it was could drive both",
                           wrong: ["Yes: the averages prove it", "Yes, as long as there are more than ten days", "No: steps and training can't be related"],
                           steps: ["It's a correlation. A day off work, say, could mean both a session and more walking; only changing one on purpose would show cause."], rng: &rng)
        },
        MathTopic(id: "binomial", title: "Binomial probability", level: 8, prerequisites: ["counting", "independence"],
                  lesson: #"The chance of exactly $k$ successes in $n$ independent tries, each with chance $p$, is $\binom{n}{k} p^{k} (1 - p)^{n - k}$. The expected number is $np$."#,
                  seconds: 70, strand: .discrete) { rng in
            if rng.chance(0.3) {
                let p = rng.pick([60, 70, 75, 80, 90]), n = rng.pick([10, 20, 40])
                return .number("A free throw goes in \(p)% of the time. In \(n) shots, how many would you expect to go in?", Rational(p * n, 100),
                               steps: [#"$np = \#(n) \times \#(Numeracy.decimal(Rational(p, 100))) = \#(Numeracy.decimal(Rational(p * n, 100)))$."#])
            }
            let coin = rng.chance(0.6)
            let n = coin ? rng.int(3...6) : 3, k = rng.int(1...(n - 1))
            let p = coin ? Rational(1, 2) : Rational(1, 6)
            let ways = (0..<k).reduce(1) { $0 * (n - $1) } / (1...k).reduce(1, *)
            let value = Rational(ways) * p.power(k) * (1 - p).power(n - k)
            let setup = coin ? "\(n) fair coins are flipped. What's the probability of exactly \(k) heads?"
                             : "A fair die is rolled 3 times. What's the probability of exactly \(k) six\(k == 1 ? "" : "es")?"
            return .number(setup, value, steps: [#"$\binom{\#(n)}{\#(k)} \times \#(p.tex)^{\#(k)} \times \#((1 - p).tex)^{\#(n - k)} = \#(ways) \times \#(p.power(k).tex) \times \#((1 - p).power(n - k).tex) = \#(value.tex)$."#])
        },
        MathTopic(id: "bayes", title: "Bayes' theorem", level: 8, prerequisites: ["base-rates"],
                  lesson: #"$P(A \mid B) = \frac{P(B \mid A) P(A)}{P(B)}$, where $P(B)$ adds up every way B can happen. It's the base-rate table written as a formula."#,
                  seconds: 75, strand: .discrete) { rng in
            let share = Rational(rng.pick([3, 4, 6, 7]), 10)
            let defectA = Rational(rng.pick([1, 2, 3]), 100), defectB = Rational(rng.pick([4, 5, 6]), 100)
            let both = share * defectA + (1 - share) * defectB
            let value = (1 - share) * defectB / both
            return .number(#"Machine A makes $\#(Numeracy.decimal(share * 100))\%$ of the parts and machine B the rest. A's parts are faulty $\#(Numeracy.decimal(defectA * 100))\%$ of the time, B's $\#(Numeracy.decimal(defectB * 100))\%$. A part is faulty. What's the probability it came from B?"#,
                           value, steps: [#"$P(\text{faulty}) = \#(Numeracy.decimal(share)) \times \#(Numeracy.decimal(defectA)) + \#(Numeracy.decimal(1 - share)) \times \#(Numeracy.decimal(defectB)) = \#(Numeracy.decimal(both))$."#,
                                          #"$P(B \mid \text{faulty}) = \frac{\#(Numeracy.decimal((1 - share) * defectB))}{\#(Numeracy.decimal(both))} = \#(value.tex)$."#])
        },
        MathTopic(id: "confidence-intervals", title: "Confidence intervals", level: 9, prerequisites: ["normal-distribution", "sampling"],
                  lesson: #"A sample mean wobbles by its standard error, $\frac{s}{\sqrt{n}}$. A 95% confidence interval is about two standard errors either side. Four times the sample halves the width."#,
                  seconds: 60, strand: .discrete) { rng in
            let n = rng.pick([16, 25, 36, 64, 100, 400]), root = Int(Double(n).squareRoot())
            let se = rng.int(1...5), sd = se * root, mean = rng.int(4...20) * 10
            if rng.chance(0.3) {
                return .number("A survey of \(n) people gives a 95% interval 8 units wide. About how many people would make it 4 units wide?", 4 * n,
                               steps: ["Width goes with $\\frac{1}{\\sqrt{n}}$: halving it takes four times the sample, $4 \\times \(n) = \(4 * n)$."])
            }
            let low = rng.chance(0.5)
            return .number(#"A sample of $\#(n)$ has mean $\#(mean)$ and standard deviation $\#(sd)$. What's the \#(low ? "lower" : "upper") end of the 95% interval, mean $\pm 2 \times \frac{s}{\sqrt{n}}$?"#,
                           low ? mean - 2 * se : mean + 2 * se,
                           steps: [#"Standard error $\frac{\#(sd)}{\sqrt{\#(n)}} = \#(se)$."#, #"$\#(mean) \#(low ? "-" : "+") 2 \times \#(se) = \#(low ? mean - 2 * se : mean + 2 * se)$."#])
        },
        MathTopic(id: "significance", title: "Significance and p-values", level: 9, prerequisites: ["normal-distribution", "independence"],
                  lesson: "A p-value is how often results at least this extreme would turn up if there were no effect at all. It isn't the chance the finding is wrong. Run enough tests and some come out \"significant\" by luck.",
                  seconds: 55, strand: .discrete) { rng in
            switch rng.int(0...2) {
            case 0:
                let tests = rng.pick([20, 40, 60, 100])
                return .number("A study tests \(tests) foods for a link to headaches. None has any effect. Testing each at the 5% level, about how many would you expect to come out significant?",
                               Rational(tests, 20), steps: [#"$5\%$ of $\#(tests)$: $\#(tests / 20)$, by luck alone."#])
            case 1:
                let tests = rng.pick([5, 10, 14])
                let value = 1 - pow(0.95, Double(tests))
                return .number("\(tests) independent tests are run at the 5% level on effects that don't exist. What's the probability at least one comes out significant? (Two decimal places.)",
                               Rational(Int((value * 100).rounded()), 100),
                               steps: [#"None: $0.95^{\#(tests)} \approx \#(String(format: "%.2f", 1 - value))$. At least one: $\#(String(format: "%.2f", value))$."#],
                               tolerance: 0.011)
            default:
                let p = rng.pick([1, 2, 3, 4])
                return .choice("A trial reports p = 0.0\(p). What does that mean?",
                               correct: "If there were no effect, results this extreme would turn up \(p)% of the time",
                               wrong: ["There's a \(p)% chance the result is wrong", "There's a \(100 - p)% chance the effect is real", "The effect is large"],
                               steps: ["A p-value assumes no effect and asks how surprising the data would be. It says nothing directly about how big the effect is, or how likely it's real."], rng: &rng)
            }
        },
        MathTopic(id: "regression", title: "Least squares", level: 10, prerequisites: ["correlation"],
                  lesson: #"The least-squares line $y = a + bx$ has slope $b = \frac{\sum (x - \bar{x})(y - \bar{y})}{\sum (x - \bar{x})^{2}}$ and passes through the point of means, so $a = \bar{y} - b\bar{x}$."#,
                  seconds: 90, strand: .discrete) { rng in
            let b = rng.nonZero(-4...5), a = rng.int(1...20)
            let noise = rng.pick([[1, -1, 0, -1, 1], [-1, 1, 0, 1, -1], [0, 0, 0, 0, 0], [2, -2, 0, -2, 2]])
            let ys = (1...5).map { a + b * $0 + noise[$0 - 1] }
            let pairs = (1...5).map { "(\($0), \(ys[$0 - 1]))" }.joined(separator: ", ")
            let sxy = (1...5).map { ($0 - 3) * (ys[$0 - 1] - (a + 3 * b)) }.reduce(0, +)
            if rng.chance(0.5) {
                return .number(#"Find the slope of the least-squares line through $\#(pairs)$."#, b,
                               steps: [#"$\bar{x} = 3$, $\bar{y} = \#(a + 3 * b)$."#, #"$\sum (x - \bar{x})(y - \bar{y}) = \#(sxy)$ and $\sum (x - \bar{x})^{2} = 10$."#,
                                       #"$b = \frac{\#(sxy)}{10} = \#(b)$."#])
            }
            let x = rng.int(6...10)
            return .number(#"The least-squares line through $\#(pairs)$ predicts what $y$ at $x = \#(x)$?"#, a + b * x,
                           steps: [#"Slope $\frac{\#(sxy)}{10} = \#(b)$; through $(3, \#(a + 3 * b))$, so $a = \#(a + 3 * b) - \#(3 * b) = \#(a)$."#,
                                   #"At $x = \#(x)$: $\#(a) + \#(TeX.paren(b)) \times \#(x) = \#(a + b * x)$."#])
        },
    ]
}

/// Bar-chart questions, for made-up charts and the person's own.
enum ChartQuestions {
    static func problem(_ figure: DataFigure, unit: String, values: [Int], labels: [String], rng: inout SeededRandom) -> Problem {
        let high = values.indices.max { values[$0] < values[$1] }!, low = values.indices.min { values[$0] < values[$1] }!
        switch rng.int(0...2) {
        case 0 where high != low:
            return Problem.number("How many more \(unit) on \(labels[high]) than on \(labels[low])?", values[high] - values[low],
                                  steps: ["\(Numeracy.grouped(values[high])) − \(Numeracy.grouped(values[low])) = \(Numeracy.grouped(values[high] - values[low]))."])
                .with(figure)
        case 1:
            let step = values.max()! >= 1000 ? 1000 : 10
            var cut = (values.min()! / step + 1) * step
            if values.contains(cut) { cut += step / 2 }
            let over = values.filter { $0 > cut }
            return Problem.number("On how many of these was it more than \(Numeracy.grouped(cut)) \(unit)?", over.count,
                                  steps: [over.isEmpty ? "None of them." : "\(zip(labels, values).filter { $0.1 > cut }.map(\.0).joined(separator: ", ")): \(over.count)."])
                .with(figure)
        default:
            let total = values.reduce(0, +)
            return Problem.number("What's the total across the chart?", total,
                                  steps: ["\(values.map(Numeracy.grouped).joined(separator: " + ")) = \(Numeracy.grouped(total))."])
                .with(figure)
        }
    }
}

extension SystemData {
    /// The mean and standard deviation of the last four weeks of steps, rounded to the hundred.
    var stepStats: (mean: Int, sd: Int, days: Int)? {
        guard let last = steps.last?.day else { return nil }
        let month = steps.filter { $0.day > last.adding(days: -28) }.map(\.value)
        guard month.count >= 14 else { return nil }
        let mean = month.reduce(0, +) / Double(month.count)
        let sd = (month.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(month.count)).squareRoot()
        return (Int((mean / 100).rounded()) * 100, max(100, Int((sd / 100).rounded()) * 100), month.count)
    }
}
