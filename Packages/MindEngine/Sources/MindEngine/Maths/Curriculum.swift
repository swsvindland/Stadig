import Foundation

/// The maths skill graphs: the classic ladder from arithmetic to integration, and statistics and
/// logic from reading a chart to least squares. Each topic lists what it builds on, within its
/// strand, so a placement that finds a topic known can assume the ones beneath it, and a new topic
/// is only offered once everything under it is in place. Numeracy has no graph: it's drilled.
public enum MathCurriculum {
    public static let topics: [MathTopic] = foundations + algebra + functions + geometry + calculus + discrete

    /// One strand's topics, in curriculum order.
    public static func topics(_ strand: MathsStrand) -> [MathTopic] { topics.filter { $0.strand == strand } }

    public static let byID: [String: MathTopic] = Dictionary(topics.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    public static func topic(_ id: String) -> MathTopic? { byID[id] }

    /// Everything a topic builds on, directly or not.
    public static func ancestors(of id: String) -> Set<String> {
        var out: Set<String> = []
        var stack = byID[id]?.prerequisites ?? []
        while let next = stack.popLast() {
            if out.insert(next).inserted { stack += byID[next]?.prerequisites ?? [] }
        }
        return out
    }

    /// Topics that build on this one, directly or not.
    public static func descendants(of id: String) -> Set<String> {
        Set(topics.filter { ancestors(of: $0.id).contains(id) }.map(\.id))
    }

    public static let maxLevel = 10
}

// MARK: - Arithmetic

extension MathCurriculum {
    static let foundations: [MathTopic] = [
        MathTopic(id: "order-of-operations", title: "Order of operations", level: 1, prerequisites: [],
                  lesson: #"Brackets first, then powers, then multiplication and division left to right, then addition and subtraction left to right. $2 + 3 \times 4 = 14$, not $20$."#,
                  seconds: 20) { rng in
            let a = rng.int(2...12), b = rng.int(2...9), c = rng.int(2...9), d = rng.int(1...6)
            switch rng.int(0...2) {
            case 0:
                let value = a + b * c - d
                return .number(#"Work out $\#(a) + \#(b) \times \#(c) - \#(d)$."#, value,
                               steps: [#"Multiply first: $\#(b) \times \#(c) = \#(b * c)$."#,
                                       #"Then left to right: $\#(a) + \#(b * c) - \#(d) = \#(value)$."#])
            case 1:
                let value = (a + b) * c - d * d
                return .number(#"Work out $(\#(a) + \#(b)) \times \#(c) - \#(d)^{2}$."#, value,
                               steps: [#"Brackets: $\#(a) + \#(b) = \#(a + b)$. Power: $\#(d)^{2} = \#(d * d)$."#,
                                       #"Multiply, then subtract: $\#(a + b) \times \#(c) - \#(d * d) = \#(value)$."#])
            default:
                let value = a + b * c
                return .number(#"Work out $\#(a * d) \div \#(d) + \#(b) \times \#(c)$."#, value,
                               steps: [#"Divide and multiply first: $\#(a * d) \div \#(d) = \#(a)$ and $\#(b) \times \#(c) = \#(b * c)$."#,
                                       #"Then add: $\#(a) + \#(b * c) = \#(value)$."#])
            }
        },
        MathTopic(id: "negative-numbers", title: "Negative numbers", level: 1, prerequisites: [],
                  lesson: #"Subtracting a negative adds: $5 - (-3) = 8$. Multiplying or dividing two numbers with the same sign gives a positive; different signs give a negative: $(-4) \times 3 = -12$, $(-4) \times (-3) = 12$."#,
                  seconds: 20) { rng in
            let a = rng.int(2...9), b = rng.int(2...9), c = rng.int(2...9), d = rng.int(2...9)
            if rng.chance(0.5) {
                let value = -a + b - c * d
                return .number(#"Work out $-\#(a) - (-\#(b)) + \#(c) \times (-\#(d))$."#, value,
                               steps: [#"Subtracting $-\#(b)$ adds $\#(b)$: $-\#(a) + \#(b) = \#(b - a)$."#,
                                       #"$\#(c) \times (-\#(d)) = -\#(c * d)$, so the total is $\#(b - a) - \#(c * d) = \#(value)$."#])
            }
            let value = a * b - c
            return .number(#"Work out $(-\#(a)) \times (-\#(b)) - \#(c)$."#, value,
                           steps: [#"Two negatives multiply to a positive: $(-\#(a)) \times (-\#(b)) = \#(a * b)$."#,
                                   #"$\#(a * b) - \#(c) = \#(value)$."#])
        },
        MathTopic(id: "fractions-add", title: "Adding and subtracting fractions", level: 1, prerequisites: [],
                  lesson: #"Write both fractions over a common denominator, then add or subtract the tops. $\frac{1}{4} + \frac{1}{6} = \frac{3}{12} + \frac{2}{12} = \frac{5}{12}$."#,
                  seconds: 30) { rng in
            let b = rng.int(2...12)
            var d = rng.int(2...12)
            if d == b { d = b == 12 ? 5 : b + 1 }
            let a = rng.int(1...(b - 1)), c = rng.int(1...(d - 1))
            let add = rng.chance(0.6)
            let x = Rational(a, b), y = Rational(c, d)
            let value = add ? x + y : x - y
            let common = lcm(b, d)
            let top1 = a * common / b, top2 = c * common / d
            let op = add ? "+" : "-"
            return .number(#"Work out $\frac{\#(a)}{\#(b)} \#(op) \frac{\#(c)}{\#(d)}$."#, value,
                           steps: [#"Common denominator $\#(common)$: $\frac{\#(top1)}{\#(common)} \#(op) \frac{\#(top2)}{\#(common)}$."#,
                                   #"$= \frac{\#(add ? top1 + top2 : top1 - top2)}{\#(common)} = \#(value.tex)$."#])
        },
        MathTopic(id: "fractions-multiply", title: "Multiplying and dividing fractions", level: 2, prerequisites: ["fractions-add"],
                  lesson: #"Multiply tops and bottoms: $\frac{2}{3} \times \frac{3}{4} = \frac{6}{12} = \frac{1}{2}$. To divide, flip the second fraction and multiply: $\frac{2}{3} \div \frac{4}{5} = \frac{2}{3} \times \frac{5}{4}$."#,
                  seconds: 30) { rng in
            let a = rng.int(1...9), b = rng.int(2...9), c = rng.int(1...9), d = rng.int(2...9)
            let x = Rational(a, b), y = Rational(c, d)
            if rng.chance(0.5) {
                let value = x * y
                return .number(#"Work out $\frac{\#(a)}{\#(b)} \times \frac{\#(c)}{\#(d)}$."#, value,
                               steps: [#"Tops times tops, bottoms times bottoms: $\frac{\#(a * c)}{\#(b * d)}$."#, #"Simplified: $\#(value.tex)$."#])
            }
            let value = x / y
            return .number(#"Work out $\frac{\#(a)}{\#(b)} \div \frac{\#(c)}{\#(d)}$."#, value,
                           steps: [#"Flip the second and multiply: $\frac{\#(a)}{\#(b)} \times \frac{\#(d)}{\#(c)} = \frac{\#(a * d)}{\#(b * c)}$."#,
                                   #"Simplified: $\#(value.tex)$."#])
        },
        MathTopic(id: "percentages", title: "Percentages", level: 2, prerequisites: ["fractions-multiply"],
                  lesson: #"$p\%$ of a number is $\frac{p}{100}$ times it. Percentage change is $\frac{\text{new} - \text{old}}{\text{old}} \times 100$: from 80 to 100 is $\frac{20}{80} \times 100 = 25\%$."#,
                  seconds: 35) { rng in
            if rng.chance(0.5) {
                let p = rng.pick([5, 10, 15, 20, 25, 30, 40, 60, 75]), n = 20 * rng.int(1...20)
                let value = Rational(p * n, 100)
                return .number(#"What is $\#(p)\%$ of $\#(n)$?"#, value,
                               steps: [#"$\frac{\#(p)}{100} \times \#(n) = \#(value.tex)$."#])
            }
            let old = rng.pick([20, 40, 50, 80, 120, 200, 250, 400]), change = rng.pick([-50, -40, -25, -20, -10, 10, 15, 20, 25, 30, 50, 75, 100])
            let new = Rational(old * (100 + change), 100)
            return .number(#"A price goes from $\#(old)$ to $\#(new.tex)$. What is the percentage change? (A fall is negative.)"#, change,
                           steps: [#"Change: $\#(new.tex) - \#(old) = \#((new - Rational(old)).tex)$."#,
                                   #"$\frac{\#((new - Rational(old)).tex)}{\#(old)} \times 100 = \#(change)\%$."#])
        },
        MathTopic(id: "powers", title: "Powers and roots", level: 2, prerequisites: ["negative-numbers", "fractions-multiply"],
                  lesson: #"$a^{n}$ multiplies $a$ by itself $n$ times. A negative power is a reciprocal, $2^{-3} = \frac{1}{8}$, and a fractional power is a root, $27^{\frac{1}{3}} = 3$ and $8^{\frac{2}{3}} = 4$."#,
                  seconds: 30) { rng in
            switch rng.int(0...3) {
            case 0:
                let a = rng.int(2...5), n = rng.int(2...(a <= 3 ? 5 : 4)), sign = rng.chance(0.4) ? -1 : 1
                let value = Rational(sign * a).power(n)
                return .number(#"Work out $\#(TeX.paren(sign * a))^{\#(n)}$."#, value,
                               steps: [#"Multiply $\#(TeX.paren(sign * a))$ by itself $\#(n)$ times: $\#(value.tex)$."#])
            case 1:
                let a = rng.int(2...5), n = rng.int(1...3)
                let value = Rational(a).power(-n)
                return .number(#"Work out $\#(a)^{-\#(n)}$."#, value,
                               steps: [#"A negative power is a reciprocal: $\frac{1}{\#(a)^{\#(n)}} = \#(value.tex)$."#])
            case 2:
                let r = rng.int(2...5), root = rng.pick([2, 3]), power = rng.int(1...2)
                let base = Int(Rational(r).power(root).numerator)
                let value = Rational(r).power(power)
                return .number(#"Work out $\#(base)^{\frac{\#(power)}{\#(root)}}$."#, value,
                               steps: [#"The \#(root == 2 ? "square" : "cube") root of $\#(base)$ is $\#(r)$."#,
                                       #"Then to the power $\#(power)$: $\#(value.tex)$."#])
            default:
                let r = rng.int(4...15)
                return .number(#"Work out $\sqrt{\#(r * r)}$."#, r, steps: [#"$\#(r) \times \#(r) = \#(r * r)$, so $\sqrt{\#(r * r)} = \#(r)$."#])
            }
        },
        MathTopic(id: "ratios", title: "Ratio and proportion", level: 2, prerequisites: ["fractions-multiply"],
                  lesson: #"Quantities in proportion scale together. If 3 tins cost 4.50, one costs 1.50 and 5 cost 7.50. Find one unit's worth first, then scale."#,
                  seconds: 35) { rng in
            let people = rng.pick([2, 3, 4, 5, 6]), grams = people * rng.pick([25, 40, 50, 60, 75]), target = rng.int(2...12)
            let value = Rational(grams * target, people)
            return .number(#"A recipe for $\#(people)$ people uses $\#(grams)$ g of flour. How many grams for $\#(target)$ people?"#, value,
                           steps: [#"Per person: $\#(grams) \div \#(people) = \#(Rational(grams, people).tex)$ g."#,
                                   #"For $\#(target)$: $\#(Rational(grams, people).tex) \times \#(target) = \#(value.tex)$ g."#])
        },
    ]
}

// MARK: - Algebra

extension MathCurriculum {
    static let algebra: [MathTopic] = [
        MathTopic(id: "linear-equations", title: "Solving linear equations", level: 3, prerequisites: ["order-of-operations", "negative-numbers"],
                  lesson: #"Undo what's been done to $x$, in reverse order, doing the same to both sides. For $3x + 5 = 20$: subtract 5 to get $3x = 15$, then divide by 3: $x = 5$."#,
                  seconds: 35) { rng in
            let x = rng.int(-9...9), a = rng.nonZero(-9...9), b = rng.nonZero(-20...20)
            let c = a * x + b
            return .number(#"Solve $\#(TeX.linear(a, b)) = \#(c)$."#, x,
                           steps: [#"Move the constant: $\#(TeX.linear(a, 0)) = \#(c) \#(TeX.signed(-b)) = \#(c - b)$."#,
                                   #"Divide by $\#(a)$: $x = \#(x)$."#])
        },
        MathTopic(id: "expanding", title: "Expanding brackets", level: 3, prerequisites: ["negative-numbers"],
                  lesson: #"Multiply everything inside a bracket by what's outside, keeping signs: $-2(3x - 4) = -6x + 8$. Then collect like terms."#,
                  seconds: 40) { rng in
            let a = rng.int(2...6), b = rng.int(1...5), c = rng.nonZero(-7...7), d = rng.nonZero(-5...5), e = rng.int(1...5), f = rng.nonZero(-7...7)
            let p = a * b + d * e, q = a * c + d * f
            let inner2 = TeX.linear(e, f)
            let outside2 = d < 0 ? "- \(-d)" : "+ \(d)"
            return .choice(#"Expand and simplify $\#(a)(\#(TeX.linear(b, c))) \#(outside2)(\#(inner2))$."#,
                           correct: "$\(TeX.linear(p, q))$",
                           wrong: ["$\(TeX.linear(a * b - d * e, a * c - d * f))$", "$\(TeX.linear(p, a * c + f))$",
                                   "$\(TeX.linear(p, c + d * f))$", "$\(TeX.linear(p + 1, q))$", "$\(TeX.linear(p, q - 2))$"],
                           steps: [#"$\#(a)(\#(TeX.linear(b, c))) = \#(TeX.linear(a * b, a * c))$ and $\#(d)(\#(inner2)) = \#(TeX.linear(d * e, d * f))$."#,
                                   #"Collect: $\#(TeX.linear(p, q))$."#], rng: &rng)
        },
        MathTopic(id: "equations-both-sides", title: "Unknowns on both sides", level: 4, prerequisites: ["linear-equations", "expanding"],
                  lesson: #"Gather the $x$ terms on one side and the numbers on the other. $5x + 2 = 2x + 14$ becomes $3x = 12$, so $x = 4$."#,
                  seconds: 45) { rng in
            let x = rng.int(-8...8), a = rng.int(2...9)
            var c = rng.int(1...9)
            if c == a { c = a - 1 }
            let b = rng.nonZero(-15...15), d = (a - c) * x + b
            return .number(#"Solve $\#(TeX.linear(a, b)) = \#(TeX.linear(c, d))$."#, x,
                           steps: [#"Subtract $\#(c)x$ and $\#(TeX.paren(b))$ from both sides: $\#(TeX.linear(a - c, 0)) = \#(d - b)$."#,
                                   #"Divide by $\#(a - c)$: $x = \#(x)$."#])
        },
        MathTopic(id: "inequalities", title: "Linear inequalities", level: 4, prerequisites: ["linear-equations"],
                  lesson: #"Solve like an equation, but multiplying or dividing by a negative flips the sign: $-2x < 6$ becomes $x > -3$."#,
                  seconds: 40) { rng in
            let a = rng.pick([-6, -5, -4, -3, -2, 2, 3, 4, 5, 6]), x0 = rng.nonZero(-6...6), b = rng.int(-10...10)
            let c = a * x0 + b
            let flips = a < 0
            return .choice(#"Solve $\#(TeX.linear(a, b)) < \#(c)$."#,
                           correct: flips ? "$x > \(x0)$" : "$x < \(x0)$",
                           wrong: [flips ? "$x < \(x0)$" : "$x > \(x0)$", "$x < \(-x0)$", "$x > \(-x0)$"],
                           steps: [#"Move the constant: $\#(TeX.linear(a, 0)) < \#(c - b)$."#,
                                   flips ? #"Divide by $\#(a)$, a negative, so the sign flips: $x > \#(x0)$."#
                                         : #"Divide by $\#(a)$: $x < \#(x0)$."#], rng: &rng)
        },
        MathTopic(id: "slope", title: "Gradient of a line", level: 4, prerequisites: ["negative-numbers", "fractions-add"],
                  lesson: #"Gradient (slope) is rise over run: $m = \frac{y_{2} - y_{1}}{x_{2} - x_{1}}$. Through $(1, 2)$ and $(3, 8)$ it's $\frac{6}{2} = 3$."#,
                  seconds: 35) { rng in
            let x1 = rng.int(-6...6), y1 = rng.int(-9...9), y2 = rng.int(-9...9)
            var x2 = rng.int(-6...6)
            if x2 == x1 { x2 = x1 + rng.pick([-3, 2, 4]) }
            let value = Rational(y2 - y1, x2 - x1)
            return .number(#"Find the gradient of the line through $(\#(x1), \#(y1))$ and $(\#(x2), \#(y2))$."#, value,
                           steps: [#"$m = \frac{\#(y2) - \#(TeX.paren(y1))}{\#(x2) - \#(TeX.paren(x1))} = \frac{\#(y2 - y1)}{\#(x2 - x1)} = \#(value.tex)$."#])
        },
        MathTopic(id: "line-equation", title: "Equation of a line", level: 5, prerequisites: ["slope", "linear-equations"],
                  lesson: #"A straight line is $y = mx + c$: $m$ is the gradient and $c$ is where it crosses the $y$-axis. Find $m$ from two points, then put one point in to find $c$."#,
                  seconds: 50) { rng in
            let m = rng.nonZero(-4...4), c = rng.int(-8...8), x1 = rng.int(-4...1), x2 = x1 + rng.int(1...4)
            let y1 = m * x1 + c, y2 = m * x2 + c
            func line(_ m: Int, _ c: Int) -> String { "$y = \(TeX.linear(m, c))$" }
            return .choice(#"Which line passes through $(\#(x1), \#(y1))$ and $(\#(x2), \#(y2))$?"#,
                           correct: line(m, c), wrong: [line(m, -c), line(-m, c), line(m, y1), line(m, c + m), line(m + 1, c - x1)],
                           steps: [#"$m = \frac{\#(y2 - y1)}{\#(x2 - x1)} = \#(m)$."#,
                                   #"Put in $(\#(x1), \#(y1))$: $\#(y1) = \#(m) \times \#(TeX.paren(x1)) + c$, so $c = \#(c)$."#], rng: &rng)
        },
        MathTopic(id: "simultaneous", title: "Simultaneous equations", level: 5, prerequisites: ["equations-both-sides"],
                  lesson: #"Make one variable's coefficients match, then add or subtract the equations to eliminate it. Solve for the other, then substitute back."#,
                  seconds: 75) { rng in
            let x = rng.int(-6...6), y = rng.int(-6...6)
            var a1 = 0, b1 = 0, a2 = 0, b2 = 0
            repeat {
                a1 = rng.nonZero(-5...5); b1 = rng.nonZero(-5...5); a2 = rng.nonZero(-5...5); b2 = rng.nonZero(-5...5)
            } while a1 * b2 - a2 * b1 == 0
            let c1 = a1 * x + b1 * y, c2 = a2 * x + b2 * y
            func pair(_ x: Int, _ y: Int) -> String { "$x = \(x),\\ y = \(y)$" }
            return .choice(#"Solve $\#(TeX.twoVariable(a1, b1)) = \#(c1)$ and $\#(TeX.twoVariable(a2, b2)) = \#(c2)$."#,
                           correct: pair(x, y),
                           wrong: [pair(y, x), pair(x, -y), pair(-x, y), pair(x + 1, y - 1), pair(-x, -y), pair(x + 2, y), pair(x, y + 2)],
                           steps: [#"Eliminate one variable by scaling and adding the equations."#,
                                   #"Check: $\#(a1)(\#(x)) + \#(b1)(\#(y)) = \#(c1)$ and $\#(a2)(\#(x)) + \#(b2)(\#(y)) = \#(c2)$."#], rng: &rng)
        },
        MathTopic(id: "index-laws", title: "Laws of indices", level: 4, prerequisites: ["powers"],
                  lesson: #"Multiplying adds powers, $x^{a} \times x^{b} = x^{a + b}$; dividing subtracts them; a power of a power multiplies them, $(x^{a})^{b} = x^{ab}$."#,
                  seconds: 30) { rng in
            let a = rng.int(2...9), b = rng.int(2...9), c = rng.int(2...6), d = rng.int(2...4)
            switch rng.int(0...2) {
            case 0:
                return .number(#"$x^{\#(a)} \times x^{\#(b)} \div x^{\#(c)} = x^{n}$. What is $n$?"#, a + b - c,
                               steps: [#"Add, then subtract the powers: $\#(a) + \#(b) - \#(c) = \#(a + b - c)$."#])
            case 1:
                return .number(#"$(x^{\#(c)})^{\#(d)} \times x^{\#(a)} = x^{n}$. What is $n$?"#, c * d + a,
                               steps: [#"A power of a power multiplies: $(x^{\#(c)})^{\#(d)} = x^{\#(c * d)}$."#,
                                       #"Then add: $\#(c * d) + \#(a) = \#(c * d + a)$."#])
            default:
                return .number(#"$\frac{x^{\#(a)} \times x^{\#(b)}}{(x^{\#(c)})^{\#(d)}} = x^{n}$. What is $n$?"#, a + b - c * d,
                               steps: [#"Top: $x^{\#(a + b)}$. Bottom: $x^{\#(c * d)}$."#, #"Divide: $\#(a + b) - \#(c * d) = \#(a + b - c * d)$."#])
            }
        },
        MathTopic(id: "surds", title: "Simplifying square roots", level: 5, prerequisites: ["powers"],
                  lesson: #"Take out the largest square factor: $\sqrt{72} = \sqrt{36 \times 2} = 6\sqrt{2}$."#,
                  seconds: 35) { rng in
            let k = rng.int(2...9), m = rng.pick([2, 3, 5, 6, 7, 10])
            return .choice(#"Simplify $\sqrt{\#(k * k * m)}$."#,
                           correct: "$\(k)\\sqrt{\(m)}$", wrong: ["$\(m)\\sqrt{\(k)}$", "$\(k * k)\\sqrt{\(m)}$", "$\(k)\\sqrt{\(2 * m)}$", "$\(k + 1)\\sqrt{\(m)}$"],
                           steps: [#"$\#(k * k * m) = \#(k * k) \times \#(m)$, and $\sqrt{\#(k * k)} = \#(k)$."#, #"So $\#(k)\sqrt{\#(m)}$."#], rng: &rng)
        },
        MathTopic(id: "factorising", title: "Factorising quadratics", level: 5, prerequisites: ["expanding"],
                  lesson: #"For $x^{2} + bx + c$, find two numbers that multiply to $c$ and add to $b$. $x^{2} + 5x + 6 = (x + 2)(x + 3)$."#,
                  seconds: 45) { rng in
            let p = rng.nonZero(-9...9), q = rng.nonZero(-9...9)
            let quad = TeX.poly([p * q, p + q, 1])
            return .choice(#"Factorise $\#(quad)$."#,
                           correct: "$\(TeX.factor(p))\(TeX.factor(q))$",
                           wrong: ["$\(TeX.factor(-p))\(TeX.factor(-q))$", "$\(TeX.factor(p))\(TeX.factor(-q))$", "$\(TeX.factor(-p))\(TeX.factor(q))$",
                                   "$\(TeX.factor(p * q))\(TeX.factor(1))$"],
                           steps: [#"Two numbers that multiply to $\#(p * q)$ and add to $\#(p + q)$: $\#(p)$ and $\#(q)$."#], rng: &rng)
        },
        MathTopic(id: "quadratic-equations", title: "Solving quadratics by factorising", level: 6, prerequisites: ["factorising"],
                  lesson: #"Factorise, then each bracket can be zero: $(x - 2)(x + 5) = 0$ gives $x = 2$ or $x = -5$. Watch the signs flip."#,
                  seconds: 50) { rng in
            let r1 = rng.int(-9...9)
            var r2 = rng.int(-9...9)
            if r2 == r1 { r2 = r1 == 9 ? -4 : r1 + 1 }
            let lo = min(r1, r2), hi = max(r1, r2)
            func roots(_ a: Int, _ b: Int) -> String { "$x = \(min(a, b))$ or $x = \(max(a, b))$" }
            return .choice(#"Solve $\#(TeX.poly([r1 * r2, -(r1 + r2), 1])) = 0$."#,
                           correct: roots(lo, hi),
                           wrong: [roots(-lo, -hi), roots(lo, -hi), roots(-lo, hi), roots(lo + 1, hi + 1), roots(lo - 1, hi - 1), roots(lo - 2, hi + 2)],
                           steps: [#"Factorise: $\#(TeX.factor(-r1))\#(TeX.factor(-r2)) = 0$."#, #"So $x = \#(lo)$ or $x = \#(hi)$."#], rng: &rng)
        },
        MathTopic(id: "quadratic-formula", title: "The quadratic formula", level: 6, prerequisites: ["quadratic-equations", "surds"],
                  lesson: #"$ax^{2} + bx + c = 0$ has solutions $x = \frac{-b \pm \sqrt{b^{2} - 4ac}}{2a}$. The discriminant $b^{2} - 4ac$ says how many: positive two, zero one, negative none."#,
                  seconds: 75) { rng in
            var a = 1, b = 0, c = 0, disc = 0
            repeat {
                a = rng.int(1...3); b = rng.int(-9...9); c = rng.int(-9...9)
                disc = b * b - 4 * a * c
            } while disc <= 0 || Int(Double(disc).squareRoot()) * Int(Double(disc).squareRoot()) == disc
            let larger = (Double(-b) + Double(disc).squareRoot()) / Double(2 * a)
            let rounded = (larger * 100).rounded() / 100
            return .number(#"Solve $\#(TeX.poly([c, b, a])) = 0$. Give the larger solution to 2 decimal places."#,
                           Rational(Int((rounded * 100).rounded()), 100),
                           steps: [#"$b^{2} - 4ac = \#(TeX.paren(b))^{2} - 4(\#(a))(\#(TeX.paren(c))) = \#(disc)$."#,
                                   #"$x = \frac{\#(-b) + \sqrt{\#(disc)}}{\#(2 * a)} \approx \#(String(format: "%.2f", larger))$."#],
                           tolerance: 0.011)
        },
    ]
}

// MARK: - Functions, sequences and logarithms

extension MathCurriculum {
    static let functions: [MathTopic] = [
        MathTopic(id: "functions", title: "Evaluating functions", level: 5, prerequisites: ["order-of-operations", "powers"],
                  lesson: #"$f(3)$ means put 3 in place of every $x$. If $f(x) = x^{2} - 2x$, then $f(3) = 9 - 6 = 3$. Bracket negative inputs: $f(-2) = (-2)^{2} - 2(-2) = 8$."#,
                  seconds: 35) { rng in
            let a = rng.nonZero(-3...3), b = rng.int(-6...6), c = rng.int(-9...9), k = rng.int(-4...4)
            let value = a * k * k + b * k + c
            return .number(#"If $f(x) = \#(TeX.poly([c, b, a]))$, find $f(\#(k))$."#, value,
                           steps: [#"Put in $\#(TeX.paren(k))$: $\#(a)(\#(TeX.paren(k)))^{2} + \#(TeX.paren(b))(\#(TeX.paren(k))) + \#(TeX.paren(c))$."#,
                                   #"$= \#(a * k * k) + \#(TeX.paren(b * k)) + \#(TeX.paren(c)) = \#(value)$."#])
        },
        MathTopic(id: "composition", title: "Composite functions", level: 6, prerequisites: ["functions"],
                  lesson: #"$f(g(x))$ means do $g$ first, then $f$ to the result. Work from the inside out."#,
                  seconds: 45) { rng in
            let a = rng.nonZero(-4...4), b = rng.int(-6...6), c = rng.int(-5...5), k = rng.int(-3...3)
            let f = TeX.linear(a, b), g = TeX.poly([c, 0, 1])
            if rng.chance(0.5) {
                let inner = k * k + c, value = a * inner + b
                return .number(#"$f(x) = \#(f)$ and $g(x) = \#(g)$. Find $f(g(\#(k)))$."#, value,
                               steps: [#"Inside first: $g(\#(k)) = \#(inner)$."#, #"Then $f(\#(inner)) = \#(value)$."#])
            }
            let inner = a * k + b, value = inner * inner + c
            return .number(#"$f(x) = \#(f)$ and $g(x) = \#(g)$. Find $g(f(\#(k)))$."#, value,
                           steps: [#"Inside first: $f(\#(k)) = \#(inner)$."#, #"Then $g(\#(inner)) = \#(value)$."#])
        },
        MathTopic(id: "inverse-functions", title: "Inverse functions", level: 6, prerequisites: ["composition", "linear-equations"],
                  lesson: #"$f^{-1}$ undoes $f$. To find $f^{-1}(k)$, solve $f(x) = k$. For $f(x) = 2x + 3$, $f^{-1}(11) = 4$ because $f(4) = 11$."#,
                  seconds: 45) { rng in
            let a = rng.pick([-7, -5, -4, -3, -2, 2, 3, 4, 5, 7]), b = rng.int(-9...9), k = rng.int(-12...12)
            let value = Rational(k - b, a)
            return .number(#"If $f(x) = \#(TeX.linear(a, b))$, find $f^{-1}(\#(k))$."#, value,
                           steps: [#"Solve $\#(TeX.linear(a, b)) = \#(k)$: $\#(a)x = \#(k - b)$."#, #"$x = \#(value.tex)$."#])
        },
        MathTopic(id: "sequences", title: "Arithmetic sequences", level: 5, prerequisites: ["linear-equations"],
                  lesson: #"Each term adds the same difference $d$. The $n$th term is $a + (n - 1)d$, and the first $n$ terms add to $\frac{n}{2}(2a + (n - 1)d)$."#,
                  seconds: 45) { rng in
            let a = rng.int(-10...20), d = rng.nonZero(-5...7), n = rng.int(8...30)
            let terms = (0..<4).map { "\(a + $0 * d)" }.joined(separator: ", ")
            if rng.chance(0.5) {
                let value = a + (n - 1) * d
                return .number(#"The sequence $\#(terms), \ldots$ continues the same way. What is term $\#(n)$?"#, value,
                               steps: [#"$a = \#(a)$, $d = \#(d)$."#, #"$\#(a) + (\#(n) - 1)(\#(d)) = \#(value)$."#])
            }
            let value = n * (2 * a + (n - 1) * d) / 2
            return .number(#"Add the first $\#(n)$ terms of $\#(terms), \ldots$"#, value,
                           steps: [#"$a = \#(a)$, $d = \#(d)$."#, #"$\frac{\#(n)}{2}(2 \times \#(TeX.paren(a)) + \#(n - 1) \times \#(TeX.paren(d))) = \#(value)$."#])
        },
        MathTopic(id: "geometric-sequences", title: "Geometric sequences", level: 6, prerequisites: ["sequences", "powers"],
                  lesson: #"Each term multiplies by the same ratio $r$. The $n$th term is $ar^{n - 1}$; the first $n$ terms add to $\frac{a(r^{n} - 1)}{r - 1}$."#,
                  seconds: 50) { rng in
            let a = rng.int(1...5), r = rng.pick([2, 3, -2]), n = rng.int(4...7)
            let terms = (0..<4).map { "\(a * Int(Rational(r).power($0).numerator))" }.joined(separator: ", ")
            if rng.chance(0.5) {
                let value = Rational(a) * Rational(r).power(n - 1)
                return .number(#"The sequence $\#(terms), \ldots$ continues the same way. What is term $\#(n)$?"#, value,
                               steps: [#"$a = \#(a)$, $r = \#(r)$."#, #"$\#(a) \times \#(TeX.paren(r))^{\#(n - 1)} = \#(value.tex)$."#])
            }
            let value = Rational(a) * (Rational(r).power(n) - 1) / Rational(r - 1)
            return .number(#"Add the first $\#(n)$ terms of $\#(terms), \ldots$"#, value,
                           steps: [#"$a = \#(a)$, $r = \#(r)$."#, #"$\frac{\#(a)(\#(TeX.paren(r))^{\#(n)} - 1)}{\#(r) - 1} = \#(value.tex)$."#])
        },
        MathTopic(id: "exponential-growth", title: "Exponential growth and decay", level: 6, prerequisites: ["percentages", "powers"],
                  lesson: #"Growing by $r\%$ a year multiplies by $1 + \frac{r}{100}$ each year: after $t$ years, $P(1 + \frac{r}{100})^{t}$. Falling by $r\%$ multiplies by $1 - \frac{r}{100}$."#,
                  seconds: 60) { rng in
            let p = rng.pick([100, 200, 500, 1000, 2500]), r = rng.pick([2, 3, 4, 5, 8, 10, 12]), t = rng.int(2...10)
            let grow = rng.chance(0.6)
            let factor = grow ? 1 + Double(r) / 100 : 1 - Double(r) / 100
            let value = Double(p) * pow(factor, Double(t))
            let rounded = value.rounded()
            let prompt = grow
                ? #"An investment of $\#(p)$ grows by $\#(r)\%$ a year. What is it worth after $\#(t)$ years, to the nearest whole number?"#
                : #"A population of $\#(p)$ falls by $\#(r)\%$ a year. What is it after $\#(t)$ years, to the nearest whole number?"#
            return .number(prompt, Rational(Int(rounded)),
                           steps: [#"Multiply by $\#(String(format: "%g", factor))$ each year: $\#(p) \times \#(String(format: "%g", factor))^{\#(t)}$."#,
                                   #"$\approx \#(String(format: "%.2f", value))$, so $\#(Int(rounded))$."#], tolerance: 1.01)
        },
        MathTopic(id: "logarithms", title: "Logarithms", level: 7, prerequisites: ["index-laws"],
                  lesson: #"$\log_{b} x$ asks: what power of $b$ gives $x$? $\log_{2} 8 = 3$. Logs add when numbers multiply: $\log_{b} m + \log_{b} n = \log_{b} mn$."#,
                  seconds: 40) { rng in
            let b = rng.pick([2, 3, 5, 10]), i = rng.int(1...3), j = rng.int(1...3)
            let m = Int(Rational(b).power(i).numerator), n = Int(Rational(b).power(j).numerator)
            switch rng.int(0...2) {
            case 0:
                let k = rng.int(-2...5)
                let x = Rational(b).power(k)
                return .number(#"Work out $\log_{\#(b)} \#(x.tex)$."#, k, steps: [#"$\#(b)^{\#(k)} = \#(x.tex)$, so the answer is $\#(k)$."#])
            case 1:
                return .number(#"Work out $\log_{\#(b)} \#(m) + \log_{\#(b)} \#(n)$."#, i + j,
                               steps: [#"$\log_{\#(b)} \#(m) = \#(i)$ and $\log_{\#(b)} \#(n) = \#(j)$."#, #"Total $\#(i + j)$."#])
            default:
                let big = m * n
                return .number(#"Work out $\log_{\#(b)} \#(big) - \log_{\#(b)} \#(n)$."#, i,
                               steps: [#"Logs subtract when numbers divide: $\log_{\#(b)} \frac{\#(big)}{\#(n)} = \log_{\#(b)} \#(m) = \#(i)$."#])
            }
        },
        MathTopic(id: "exponential-equations", title: "Exponential equations", level: 7, prerequisites: ["logarithms"],
                  lesson: #"Write both sides as powers of the same base, then the powers must be equal: $2^{x + 1} = 32 = 2^{5}$, so $x + 1 = 5$ and $x = 4$."#,
                  seconds: 50) { rng in
            if rng.chance(0.5) {
                let b = rng.pick([2, 3, 5]), n = rng.int(2...(b == 2 ? 7 : 4)), a = rng.int(-3...3)
                let c = Int(Rational(b).power(n).numerator)
                return .number(#"Solve $\#(b)^{\#(TeX.linear(1, a))} = \#(c)$."#, n - a,
                               steps: [#"$\#(c) = \#(b)^{\#(n)}$, so $\#(TeX.linear(1, a)) = \#(n)$."#, #"$x = \#(n - a)$."#])
            }
            // 4^x = 8: both powers of 2.
            let p = rng.pick([2, 3, 4]), q = rng.pick([1, 3, 5])
            let left = 1 << p, right = 1 << q
            let value = Rational(q, p)
            return .number(#"Solve $\#(left)^{x} = \#(right)$."#, value,
                           steps: [#"Both are powers of 2: $2^{\#(p)x} = 2^{\#(q)}$."#, #"$\#(p)x = \#(q)$, so $x = \#(value.tex)$."#])
        },
    ]
}
