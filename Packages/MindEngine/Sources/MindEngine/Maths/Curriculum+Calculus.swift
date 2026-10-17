import Foundation

// MARK: - Geometry and trigonometry

extension MathCurriculum {
    static let geometry: [MathTopic] = [
        MathTopic(id: "angles", title: "Angles in polygons", level: 3, prerequisites: ["order-of-operations"],
                  lesson: #"The interior angles of an $n$-sided polygon add to $(n - 2) \times 180°$. In a regular polygon they're all equal, and each exterior angle is $\frac{360°}{n}$."#,
                  seconds: 35) { rng in
            let n = rng.pick([3, 4, 5, 6, 8, 9, 10, 12])
            switch rng.int(0...2) {
            case 0:
                let value = (n - 2) * 180
                return .number(#"What do the interior angles of a \#(n)-sided polygon add to, in degrees?"#, value,
                               steps: [#"$(\#(n) - 2) \times 180 = \#(value)$."#])
            case 1:
                let value = (n - 2) * 180 / n
                return .number(#"What is each interior angle of a regular \#(n)-sided polygon, in degrees?"#, value,
                               steps: [#"Total $(\#(n) - 2) \times 180 = \#((n - 2) * 180)$."#, #"Shared by $\#(n)$: $\#(value)$."#])
            default:
                return .number(#"What is each exterior angle of a regular \#(n)-sided polygon, in degrees?"#, 360 / n,
                               steps: [#"Exterior angles add to $360°$: $\frac{360}{\#(n)} = \#(360 / n)$."#])
            }
        },
        MathTopic(id: "circles", title: "Circles: area and circumference", level: 3, prerequisites: ["powers"],
                  lesson: #"Area is $\pi r^{2}$ and circumference is $2\pi r$, where $r$ is the radius (half the diameter). Leave answers in terms of $\pi$."#,
                  seconds: 35) { rng in
            let r = rng.int(2...12)
            switch rng.int(0...2) {
            case 0:
                return .number(#"A circle has radius $\#(r)$. Its area is $k\pi$. What is $k$?"#, r * r,
                               steps: [#"$\pi r^{2} = \pi \times \#(r)^{2} = \#(r * r)\pi$."#])
            case 1:
                return .number(#"A circle has diameter $\#(2 * r)$. Its circumference is $k\pi$. What is $k$?"#, 2 * r,
                               steps: [#"Radius $\#(r)$; $2\pi r = \#(2 * r)\pi$."#])
            default:
                return .number(#"A circle's area is $\#(r * r)\pi$. What is its radius?"#, r,
                               steps: [#"$\pi r^{2} = \#(r * r)\pi$, so $r^{2} = \#(r * r)$ and $r = \#(r)$."#])
            }
        },
        MathTopic(id: "pythagoras", title: "Pythagoras' theorem", level: 4, prerequisites: ["powers"],
                  lesson: #"In a right-angled triangle, $a^{2} + b^{2} = c^{2}$, where $c$ is the hypotenuse, the side opposite the right angle. Legs 3 and 4 give a hypotenuse of 5."#,
                  seconds: 40) { rng in
            let (a0, b0, c0) = rng.pick([(3, 4, 5), (5, 12, 13), (8, 15, 17), (7, 24, 25), (20, 21, 29)])
            let k = a0 == 3 ? rng.int(1...4) : 1
            let a = a0 * k, b = b0 * k, c = c0 * k
            if rng.chance(0.5) {
                return .number(#"A right-angled triangle has shorter sides $\#(a)$ and $\#(b)$. How long is the hypotenuse?"#, c,
                               steps: [#"$\#(a)^{2} + \#(b)^{2} = \#(a * a + b * b)$."#, #"$\sqrt{\#(c * c)} = \#(c)$."#])
            }
            return .number(#"A right-angled triangle has hypotenuse $\#(c)$ and one side $\#(a)$. How long is the other side?"#, b,
                           steps: [#"$\#(c)^{2} - \#(a)^{2} = \#(c * c - a * a)$."#, #"$\sqrt{\#(b * b)} = \#(b)$."#])
        },
        MathTopic(id: "trig-ratios", title: "Sine, cosine and tangent", level: 5, prerequisites: ["pythagoras", "fractions-multiply"],
                  lesson: #"In a right-angled triangle: $\sin\theta = \frac{\text{opposite}}{\text{hypotenuse}}$, $\cos\theta = \frac{\text{adjacent}}{\text{hypotenuse}}$, $\tan\theta = \frac{\text{opposite}}{\text{adjacent}}$."#,
                  seconds: 35) { rng in
            let (a, b, c) = rng.pick([(3, 4, 5), (5, 12, 13), (8, 15, 17), (7, 24, 25), (4, 3, 5), (12, 5, 13)])
            let which = rng.int(0...2)
            let names = [#"\sin"#, #"\cos"#, #"\tan"#]
            let value = [Rational(a, c), Rational(b, c), Rational(a, b)][which]
            let rule = [#"\frac{\text{opposite}}{\text{hypotenuse}}"#, #"\frac{\text{adjacent}}{\text{hypotenuse}}"#,
                        #"\frac{\text{opposite}}{\text{adjacent}}"#][which]
            return .number(#"In a right-angled triangle, the side opposite angle $\theta$ is $\#(a)$, the side next to it is $\#(b)$ and the hypotenuse is $\#(c)$. Find $\#(names[which])\theta$."#,
                           value, steps: [#"$\#(names[which])\theta = \#(rule) = \#(value.tex)$."#])
        },
        MathTopic(id: "radians", title: "Radians", level: 6, prerequisites: ["circles", "fractions-multiply"],
                  lesson: #"A full turn is $2\pi$ radians, so $180° = \pi$. Multiply degrees by $\frac{\pi}{180}$: $135° = \frac{3\pi}{4}$."#,
                  seconds: 35) { rng in
            let degrees = rng.pick([30, 45, 60, 90, 120, 135, 150, 210, 225, 240, 270, 300, 315, 330])
            let k = Rational(degrees, 180)
            if rng.chance(0.5) {
                return .number(#"Write $\#(degrees)°$ in radians as $k\pi$. What is $k$?"#, k,
                               steps: [#"$\#(degrees) \times \frac{\pi}{180} = \#(k.tex)\pi$."#])
            }
            let written = k.denominator == 1 ? "\(k.numerator)\\pi" : "\\frac{\(k.numerator == 1 ? "" : "\(k.numerator)")\\pi}{\(k.denominator)}"
            return .number(#"How many degrees is $\#(written)$ radians?"#, degrees,
                           steps: [#"$\pi$ radians is $180°$: $\#(k.tex) \times 180 = \#(degrees)$."#])
        },
        MathTopic(id: "exact-trig", title: "Exact trig values", level: 7, prerequisites: ["trig-ratios", "radians", "surds"],
                  lesson: #"Learn the special angles: $\sin 30° = \frac{1}{2}$, $\sin 45° = \frac{\sqrt{2}}{2}$, $\sin 60° = \frac{\sqrt{3}}{2}$ (cosine runs the other way). Around the circle, the sign follows the quadrant."#,
                  seconds: 30) { rng in
            let degrees = rng.pick([0, 30, 45, 60, 90, 120, 135, 150, 180, 210, 225, 240, 270, 300, 315, 330])
            var functions = [0, 1]
            if degrees % 180 != 90 { functions.append(2) }
            let which = rng.pick(functions)
            let radians = Double(degrees) * .pi / 180
            let value = [sin(radians), cos(radians), tan(radians)][which]
            let name = [#"\sin"#, #"\cos"#, #"\tan"#][which]
            let correct = exactTrig(value)
            let pool = (which == 2 ? tanValues : sinValues).map(\.tex).filter { $0 != correct }
            let flipped = exactTrig(-value)
            return .choice(#"What is $\#(name) \#(degrees)°$?"#, correct: "$\(correct)$",
                           wrong: ([flipped] + pool.shuffled(using: &rng)).filter { $0 != correct }.map { "$\($0)$" },
                           steps: [#"$\#(name) \#(degrees)° = \#(correct)$."#], rng: &rng)
        },
    ]

    static let sinValues: [(value: Double, tex: String)] = [
        (0, "0"), (0.5, #"\frac{1}{2}"#), (2.0.squareRoot() / 2, #"\frac{\sqrt{2}}{2}"#), (3.0.squareRoot() / 2, #"\frac{\sqrt{3}}{2}"#), (1, "1"),
        (-0.5, #"-\frac{1}{2}"#), (-(2.0.squareRoot()) / 2, #"-\frac{\sqrt{2}}{2}"#), (-(3.0.squareRoot()) / 2, #"-\frac{\sqrt{3}}{2}"#), (-1, "-1"),
    ]
    static let tanValues: [(value: Double, tex: String)] = [
        (0, "0"), (3.0.squareRoot() / 3, #"\frac{\sqrt{3}}{3}"#), (1, "1"), (3.0.squareRoot(), #"\sqrt{3}"#),
        (-(3.0.squareRoot()) / 3, #"-\frac{\sqrt{3}}{3}"#), (-1, "-1"), (-(3.0.squareRoot()), #"-\sqrt{3}"#),
    ]

    static func exactTrig(_ value: Double) -> String {
        (sinValues + tanValues).min { abs($0.value - value) < abs($1.value - value) }!.tex
    }
}

// MARK: - Data and probability

extension MathCurriculum {
    static let data: [MathTopic] = [
        MathTopic(id: "averages", title: "Mean and median", level: 2, prerequisites: ["fractions-add"],
                  lesson: #"The mean is the total divided by how many. The median is the middle value once they're in order; with an even count, it's halfway between the middle two."#,
                  seconds: 35) { rng in
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
        },
        MathTopic(id: "probability", title: "Probability", level: 4, prerequisites: ["fractions-multiply"],
                  lesson: #"Probability is favourable outcomes over all outcomes. For two things in a row, multiply; without replacement, the second fraction changes: two reds from 3 red and 2 blue is $\frac{3}{5} \times \frac{2}{4}$."#,
                  seconds: 45) { rng in
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
        MathTopic(id: "counting", title: "Permutations and combinations", level: 6, prerequisites: ["probability"],
                  lesson: #"Choosing $r$ from $n$ when order matters: $\frac{n!}{(n - r)!}$. When it doesn't: $\binom{n}{r} = \frac{n!}{r!(n - r)!}$. A team of 3 from 5 people is $\binom{5}{3} = 10$."#,
                  seconds: 45) { rng in
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
                  seconds: 50) { rng in
            let a = rng.int(5...12), b = rng.int(1...4), c = rng.int(1...3)
            let value = Rational(a + 2 * b - 3 * c, 6)
            return .number(#"Roll a fair die: a 6 wins $\#(a)$ points, a 4 or 5 wins $\#(b)$, and anything else loses $\#(c)$. What is the expected score per roll?"#,
                           value, steps: [#"$\frac{1}{6}(\#(a)) + \frac{2}{6}(\#(b)) + \frac{3}{6}(-\#(c))$."#, #"$= \#(value.tex)$."#])
        },
    ]
}

// MARK: - Calculus

extension MathCurriculum {
    static let calculus: [MathTopic] = [
        MathTopic(id: "limits", title: "Limits", level: 7, prerequisites: ["factorising", "functions"],
                  lesson: #"A limit is the value a function approaches. If putting the number in gives $\frac{0}{0}$, factorise and cancel first: $\frac{x^{2} - 9}{x - 3} = x + 3$, which approaches 6 as $x \to 3$."#,
                  seconds: 50) { rng in
            let r = rng.nonZero(-5...5)
            var s = rng.int(-6...6)
            if s == r { s = r + 2 }
            if rng.chance(0.5) {
                let numerator = TeX.poly([r * s, -(r + s), 1])
                return .number(#"Find $\lim_{x \to \#(r)} \frac{\#(numerator)}{x \#(TeX.signed(-r))}$."#, r - s,
                               steps: [#"$\#(numerator) = \#(TeX.factor(-r))\#(TeX.factor(-s))$; cancel $\#(TeX.factor(-r))$."#,
                                       #"Left with $x \#(TeX.signed(-s))$, which is $\#(r - s)$ at $x = \#(r)$."#])
            }
            let a = rng.nonZero(-3...3), b = rng.int(-5...5), c = rng.int(-9...9), k = rng.int(-3...3)
            return .number(#"Find $\lim_{x \to \#(k)} (\#(TeX.poly([c, b, a])))$."#, a * k * k + b * k + c,
                           steps: [#"A polynomial is continuous, so put $x = \#(k)$ in: $\#(a * k * k + b * k + c)$."#])
        },
        MathTopic(id: "limits-infinity", title: "Limits at infinity", level: 8, prerequisites: ["limits"],
                  lesson: #"As $x \to \infty$, only the highest powers matter. With equal top and bottom degrees, the limit is the ratio of their leading coefficients; with a higher bottom degree, it's 0."#,
                  seconds: 40) { rng in
            let a = rng.nonZero(-6...6), d = rng.nonZero(-6...6), b = rng.int(-9...9), c = rng.int(-9...9), e = rng.int(-9...9), f = rng.int(-9...9)
            if rng.chance(0.65) {
                return .number(#"Find $\lim_{x \to \infty} \frac{\#(TeX.poly([c, b, a]))}{\#(TeX.poly([f, e, d]))}$."#, Rational(a, d),
                               steps: [#"Same degree on top and bottom: the leading coefficients, $\frac{\#(a)}{\#(d)} = \#(Rational(a, d).tex)$."#])
            }
            return .number(#"Find $\lim_{x \to \infty} \frac{\#(TeX.linear(a, b))}{\#(TeX.poly([f, e, d]))}$."#, 0,
                           steps: [#"The bottom has the higher power, so the fraction shrinks to $0$."#])
        },
        MathTopic(id: "derivatives", title: "Derivatives: the power rule", level: 7, prerequisites: ["functions", "index-laws"],
                  lesson: #"The derivative of $x^{n}$ is $nx^{n - 1}$: bring the power down and reduce it by one. Constants vanish. $\frac{d}{dx}(3x^{2} + 5x - 7) = 6x + 5$."#,
                  seconds: 45) { rng in
            let a = rng.nonZero(-3...3), b = rng.int(-6...6), c = rng.int(-6...6), d = rng.int(-9...9)
            let f = TeX.poly([d, c, b, a])
            let derivative = [c, 2 * b, 3 * a]
            if rng.chance(0.5) {
                let k = rng.int(-3...3)
                let value = 3 * a * k * k + 2 * b * k + c
                return .number(#"If $f(x) = \#(f)$, find $f'(\#(k))$."#, value,
                               steps: [#"$f'(x) = \#(TeX.poly(derivative))$."#, #"$f'(\#(k)) = \#(value)$."#])
            }
            return .choice(#"Differentiate $\#(f)$."#, correct: "$\(TeX.poly(derivative))$",
                           wrong: ["$\(TeX.poly([d, c, 2 * b, 3 * a]))$", "$\(TeX.poly([c, b, a]))$", "$\(TeX.poly([0, c, 2 * b, 3 * a]))$",
                                   "$\(TeX.poly([c + d, 2 * b, 3 * a]))$", "$\(TeX.poly([c, 2 * b, a]))$"],
                           steps: [#"Each term $ax^{n}$ becomes $anx^{n - 1}$, and the constant goes."#,
                                   #"$\#(TeX.poly(derivative))$."#], rng: &rng)
        },
        MathTopic(id: "product-quotient", title: "Product and quotient rules", level: 8, prerequisites: ["derivatives"],
                  lesson: #"Product: $(uv)' = u'v + uv'$. Quotient: $\left(\frac{u}{v}\right)' = \frac{u'v - uv'}{v^{2}}$."#,
                  seconds: 75) { rng in
            let a = rng.nonZero(-4...4), b = rng.int(-5...5), c = rng.nonZero(-3...3), d = rng.int(-5...5), k = rng.int(-2...2)
            if rng.chance(0.5) {
                let value = a * (c * k * k + d) + (a * k + b) * (2 * c * k)
                return .number(#"If $f(x) = (\#(TeX.linear(a, b)))(\#(TeX.poly([d, 0, c])))$, find $f'(\#(k))$."#, value,
                               steps: [#"$u = \#(TeX.linear(a, b))$, $v = \#(TeX.poly([d, 0, c]))$; $u' = \#(a)$, $v' = \#(TeX.linear(2 * c, 0))$."#,
                                       #"$f'(\#(k)) = \#(a)(\#(c * k * k + d)) + (\#(a * k + b))(\#(2 * c * k)) = \#(value)$."#])
            }
            // A constant quotient (ad = bc) has nothing to differentiate; and the bottom can't be zero at the point.
            let top = a * d - b * c == 0 ? b + 1 : b
            var kk = k
            while c * kk + d == 0 { kk += 1 }
            let bottom = c * kk + d
            let value = Rational(a * d - top * c, bottom * bottom)
            return .number(#"If $f(x) = \frac{\#(TeX.linear(a, top))}{\#(TeX.linear(c, d))}$, find $f'(\#(kk))$."#, value,
                           steps: [#"$f'(x) = \frac{\#(a)(\#(TeX.linear(c, d))) - \#(TeX.paren(c))(\#(TeX.linear(a, top)))}{(\#(TeX.linear(c, d)))^{2}} = \frac{\#(a * d - top * c)}{(\#(TeX.linear(c, d)))^{2}}$."#,
                                   #"At $x = \#(kk)$: $\frac{\#(a * d - top * c)}{\#(bottom * bottom)} = \#(value.tex)$."#])
        },
        MathTopic(id: "chain-rule", title: "The chain rule", level: 8, prerequisites: ["derivatives", "composition"],
                  lesson: #"For a function inside a function, differentiate the outside, keep the inside, then multiply by the inside's derivative: $\frac{d}{dx}(3x + 1)^{4} = 4(3x + 1)^{3} \times 3$."#,
                  seconds: 60) { rng in
            let n = rng.int(2...5), c = rng.nonZero(-5...5)
            if rng.chance(0.5) {
                let a = rng.pick([-2, -1, 1, 2, 3]), b = rng.int(-3...3)
                var k = rng.int(-2...2)
                while abs(a * k + b) > 3 { k = k > 0 ? k - 1 : k + 1 }
                let inner = a * k + b
                let value = n * a * Int(Rational(inner).power(n - 1).numerator)
                return .number(#"If $f(x) = (\#(TeX.linear(a, b)))^{\#(n)}$, find $f'(\#(k))$."#, value,
                               steps: [#"$f'(x) = \#(n)(\#(TeX.linear(a, b)))^{\#(n - 1)} \times \#(TeX.paren(a))$."#,
                                       #"At $x = \#(k)$: $\#(n) \times \#(TeX.paren(inner))^{\#(n - 1)} \times \#(TeX.paren(a)) = \#(value)$."#])
            }
            let inside = TeX.poly([c, 0, 1])
            let power = n - 1 == 1 ? "" : "^{\(n - 1)}"
            return .choice(#"Differentiate $(\#(inside))^{\#(n)}$."#, correct: "$\(2 * n)x(\(inside))\(power)$",
                           wrong: ["$\(n)(\(inside))\(power)$", "$\(n)x(\(inside))\(power)$", "$\(2 * n)x(\(inside))^{\(n)}$", "$2x(\(inside))\(power)$"],
                           steps: [#"Outside: $\#(n)(\#(inside))^{\#(n - 1)}$. Inside's derivative: $2x$."#,
                                   #"Multiply: $\#(2 * n)x(\#(inside))\#(power)$."#], rng: &rng)
        },
        MathTopic(id: "derivatives-functions", title: "Derivatives of eˣ, ln x, sin and cos", level: 8, prerequisites: ["derivatives", "logarithms", "exact-trig"],
                  lesson: #"$\frac{d}{dx}e^{x} = e^{x}$, $\frac{d}{dx}\ln x = \frac{1}{x}$, $\frac{d}{dx}\sin x = \cos x$ and $\frac{d}{dx}\cos x = -\sin x$."#,
                  seconds: 45) { rng in
            let a = rng.int(2...6), b = rng.int(2...6), c = rng.int(2...6)
            let useCos = rng.chance(0.5)
            let f = useCos ? #"\#(a)e^{x} + \#(b)\ln x + \#(c)\cos x"# : #"\#(a)e^{x} + \#(b)\ln x + \#(c)\sin x"#
            let correct = useCos ? #"\#(a)e^{x} + \frac{\#(b)}{x} - \#(c)\sin x"# : #"\#(a)e^{x} + \frac{\#(b)}{x} + \#(c)\cos x"#
            let wrong = useCos
                ? [#"\#(a)e^{x} + \frac{\#(b)}{x} + \#(c)\sin x"#, #"\#(a)xe^{x - 1} + \frac{\#(b)}{x} - \#(c)\sin x"#, #"\#(a)e^{x} + \#(b)\ln x - \#(c)\sin x"#]
                : [#"\#(a)e^{x} + \frac{\#(b)}{x} - \#(c)\cos x"#, #"\#(a)xe^{x - 1} + \frac{\#(b)}{x} + \#(c)\cos x"#, #"\#(a)e^{x} + \#(b)\ln x + \#(c)\cos x"#]
            return .choice(#"Differentiate $\#(f)$."#, correct: "$\(correct)$", wrong: wrong.map { "$\($0)$" },
                           steps: [#"Term by term: $e^{x}$ stays, $\ln x$ becomes $\frac{1}{x}$, \#(useCos ? #"$\cos x$ becomes $-\sin x$"# : #"$\sin x$ becomes $\cos x$"#)."#],
                           rng: &rng)
        },
        MathTopic(id: "tangent-lines", title: "Tangent lines", level: 8, prerequisites: ["derivatives", "line-equation"],
                  lesson: #"The tangent at $x = k$ has gradient $f'(k)$ and passes through $(k, f(k))$. Put both into $y = mx + c$ to find $c$."#,
                  seconds: 75) { rng in
            let b = rng.int(-5...5), c = rng.int(-6...6), k = rng.nonZero(-3...3)
            let y = k * k + b * k + c, m = 2 * k + b, intercept = y - m * k
            func line(_ m: Int, _ c: Int) -> String { "$y = \(TeX.linear(m, c))$" }
            return .choice(#"Find the tangent to $y = \#(TeX.poly([c, b, 1]))$ at $x = \#(k)$."#,
                           correct: line(m, intercept), wrong: [line(m, y), line(b, intercept), line(m, -intercept), line(2 * k, y - 2 * k * k)],
                           steps: [#"Gradient: $2x \#(TeX.signed(b))$ at $x = \#(k)$ is $\#(m)$. Point: $(\#(k), \#(y))$."#,
                                   #"$\#(y) = \#(m)(\#(k)) + c$, so $c = \#(intercept)$."#], rng: &rng)
        },
        MathTopic(id: "stationary-points", title: "Stationary points", level: 9, prerequisites: ["derivatives", "quadratic-equations"],
                  lesson: #"Stationary points are where $f'(x) = 0$. For a cubic starting $+x^{3}$, the left one is a local maximum and the right one a local minimum; check with $f''(x)$: negative means maximum."#,
                  seconds: 90) { rng in
            let p = rng.int(-4...2)
            let q = p + 2 * rng.int(1...3)
            let d = rng.int(-9...9)
            // f'(x) = 3(x - p)(x - q) = 3x² - 3(p + q)x + 3pq.
            let f = TeX.poly([Rational(d), Rational(3 * p * q), Rational(-3 * (p + q), 2), Rational(1)])
            let wantMin = rng.chance(0.5)
            return .number(#"$f(x) = \#(f)$. At what $x$ is its local \#(wantMin ? "minimum" : "maximum")?"#, wantMin ? q : p,
                           steps: [#"$f'(x) = \#(TeX.poly([3 * p * q, -3 * (p + q), 3])) = 3\#(TeX.factor(-p))\#(TeX.factor(-q))$, zero at $x = \#(p)$ and $x = \#(q)$."#,
                                   #"$f''(x) = 6x \#(TeX.signed(-3 * (p + q)))$: negative at $\#(p)$ (maximum), positive at $\#(q)$ (minimum)."#])
        },
        MathTopic(id: "integration", title: "Integration: the power rule", level: 8, prerequisites: ["derivatives"],
                  lesson: #"Integration undoes differentiation: $\int x^{n} \, dx = \frac{x^{n + 1}}{n + 1} + C$. Raise the power by one, divide by the new power, and add $C$."#,
                  seconds: 50) { rng in
            let a = rng.pick([3, 6, 9, -3, -6]), b = rng.pick([2, 4, 6, -2, -4]), c = rng.nonZero(-7...7)
            let f = TeX.poly([c, b, a])
            let correct = TeX.poly([0, c, b / 2, a / 3]) + " + C"
            return .choice(#"Find $\int (\#(f)) \, dx$."#, correct: "$\(correct)$",
                           wrong: ["$\(TeX.poly([0, c, b, a])) + C$", "$\(TeX.poly([b, 2 * a]))$", "$\(TeX.poly([0, c, b / 2, a])) + C$",
                                   "$\(TeX.poly([0, c, b * 2, a * 3])) + C$"],
                           steps: [#"Each $x^{n}$ becomes $\frac{x^{n + 1}}{n + 1}$: $\#(TeX.poly([0, c, b / 2, a / 3]))$."#, #"Plus the constant $C$."#],
                           rng: &rng)
        },
        MathTopic(id: "definite-integrals", title: "Definite integrals", level: 9, prerequisites: ["integration"],
                  lesson: #"$\int_{a}^{b} f(x) \, dx = F(b) - F(a)$, where $F$ is any antiderivative. It's the signed area under the curve between $a$ and $b$."#,
                  seconds: 75) { rng in
            let p = rng.nonZero(-3...3), q = rng.int(-4...4), r = rng.int(-5...5)
            let a = rng.int(-2...1), b = a + rng.int(1...3)
            func antiderivative(_ x: Int) -> Rational { Rational(p * x * x * x, 3) + Rational(q * x * x, 2) + Rational(r * x) }
            let value = antiderivative(b) - antiderivative(a)
            return .number(#"Work out $\int_{\#(a)}^{\#(b)} (\#(TeX.poly([r, q, p]))) \, dx$."#, value,
                           steps: [#"Antiderivative: $F(x) = \#(TeX.poly([Rational(0), Rational(r), Rational(q, 2), Rational(p, 3)]))$."#,
                                   #"$F(\#(b)) - F(\#(a)) = \#(antiderivative(b).tex) - \#(TeX.paren(antiderivative(a))) = \#(value.tex)$."#])
        },
        MathTopic(id: "substitution", title: "Integration by substitution", level: 10, prerequisites: ["integration", "chain-rule"],
                  lesson: #"When the derivative of an inner function is sitting outside, substitute $u$ for the inside: $\int 2x(x^{2} + 1)^{3} \, dx = \int u^{3} \, du = \frac{(x^{2} + 1)^{4}}{4} + C$."#,
                  seconds: 75) { rng in
            let n = rng.int(1...4), m = rng.int(1...3), b = rng.nonZero(-5...5)
            let k = 2 * (n + 1) * m
            let inside = TeX.poly([b, 0, 1])
            func term(_ coefficient: String, _ power: Int) -> String { "$\(coefficient)(\(inside))^{\(power)} + C$" }
            return .choice(#"Find $\int \#(k)x(\#(inside))^{\#(n)} \, dx$."#, correct: term(m == 1 ? "" : "\(m)", n + 1),
                           wrong: [term("\(k)", n + 1), term("\(2 * m)", n + 1), term(m == 1 ? "" : "\(m)", n), term("\(k / 2)", n + 1)],
                           steps: [#"Let $u = \#(inside)$, so $du = 2x \, dx$ and the integral is $\int \#(k / 2)u^{\#(n)} \, du$."#,
                                   #"$= \frac{\#(k / 2)}{\#(n + 1)}u^{\#(n + 1)} + C = \#(m == 1 ? "" : "\(m)")(\#(inside))^{\#(n + 1)} + C$."#], rng: &rng)
        },
        MathTopic(id: "integration-by-parts", title: "Integration by parts", level: 10, prerequisites: ["integration", "derivatives-functions"],
                  lesson: #"$\int u \, dv = uv - \int v \, du$. Pick $u$ to be the part that gets simpler when differentiated (usually the $x$)."#,
                  seconds: 90) { rng in
            let cases: [(String, String, [String], String)] = [
                (#"xe^{x}"#, #"xe^{x} - e^{x} + C"#, [#"xe^{x} + e^{x} + C"#, #"\frac{x^{2}}{2}e^{x} + C"#, #"e^{x} - xe^{x} + C"#], #"$u = x$, $dv = e^{x} \, dx$: $xe^{x} - \int e^{x} \, dx$."#),
                (#"x\cos x"#, #"x\sin x + \cos x + C"#, [#"x\sin x - \cos x + C"#, #"-x\sin x + \cos x + C"#, #"\frac{x^{2}}{2}\sin x + C"#], #"$u = x$, $dv = \cos x \, dx$: $x\sin x - \int \sin x \, dx$."#),
                (#"x\sin x"#, #"-x\cos x + \sin x + C"#, [#"x\cos x - \sin x + C"#, #"-x\cos x - \sin x + C"#, #"\frac{x^{2}}{2}\cos x + C"#], #"$u = x$, $dv = \sin x \, dx$: $-x\cos x + \int \cos x \, dx$."#),
                (#"\ln x"#, #"x\ln x - x + C"#, [#"\frac{1}{x} + C"#, #"x\ln x + x + C"#, #"\ln x - x + C"#], #"$u = \ln x$, $dv = dx$: $x\ln x - \int x \cdot \frac{1}{x} \, dx$."#),
                (#"xe^{2x}"#, #"\frac{x}{2}e^{2x} - \frac{1}{4}e^{2x} + C"#, [#"\frac{x}{2}e^{2x} + \frac{1}{4}e^{2x} + C"#, #"2xe^{2x} - 4e^{2x} + C"#, #"xe^{2x} - e^{2x} + C"#], #"$u = x$, $dv = e^{2x} \, dx$: $\frac{x}{2}e^{2x} - \int \frac{1}{2}e^{2x} \, dx$."#),
            ]
            let (integrand, correct, wrong, step) = rng.pick(cases)
            return .choice(#"Find $\int \#(integrand) \, dx$."#, correct: "$\(correct)$", wrong: wrong.map { "$\($0)$" },
                           steps: [step, #"$= \#(correct)$."#], rng: &rng)
        },
    ]
}
