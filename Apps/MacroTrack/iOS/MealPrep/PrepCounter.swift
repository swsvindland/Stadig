import MealPlanner
import NutritionEngine
import SwiftUI
import SystemCore

/// Prep day at the counter, like a line cook's ticket rail, for an iPad propped up by the stove and
/// hands too wet for small targets: the steps across the top, the one being done in enormous type,
/// what's on the heat as draining rulers, the scale's reading against the recipe, a huge Next, and
/// the containers filling as the steps are done. Sized from the screen rather than the text size:
/// it's read from across the kitchen.
struct PrepCounter: View {
    @Environment(AppModel.self) private var model
    let run: PrepRun
    @State private var showSteps = false

    var body: some View {
        GeometryReader { proxy in
            // The design is drawn for an 11-inch iPad on its side; everything scales with the window.
            // Upright, what's on the heat goes under the step, two timers to a row.
            let upright = proxy.size.height > proxy.size.width * 1.1
            let s =
                upright
                ? min(max(min(proxy.size.width / 834, proxy.size.height / 1194), 0.6), 1.3)
                : min(max(min(proxy.size.width / 1194, proxy.size.height / 834), 0.6), 1.3)
            VStack(alignment: .leading, spacing: 16 * s) {
                header(s).layoutPriority(1)
                StepRail(run: run, scale: s).layoutPriority(1)
                if upright {
                    VStack(alignment: .leading, spacing: 22 * s) {
                        now(s)
                        OnTheHeat(run: run, scale: s, columns: 2)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    HStack(alignment: .top, spacing: 36 * s) {
                        now(s).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        OnTheHeat(run: run, scale: s, columns: 1)
                            .frame(width: proxy.size.width * 0.34)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
                // The rail, Next and the containers keep their size; the step and the timers fit what's left.
                UpNext(run: run, scale: s, next: next).layoutPriority(1)
                Containers(run: run, scale: s).layoutPriority(1)
            }
            .padding(.horizontal, 28 * s)
            .padding(.vertical, 18 * s)
        }
        .inkGround()
        .keepsScreenAwake()
        .sheet(isPresented: $showSteps) { steps.macSheetSize(width: 520, height: 700) }
        // Closed with a reading set and no Next since: it's kept all the same.
        .onDisappear { model.saveReadings(run) }
    }

    /// The step being done, and its batch on the scale.
    func now(_ s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 20 * s) {
            CurrentStep(run: run, step: run.step, scale: s)
            if let weigh = run.step.weigh {
                ScaleStrip(run: run, step: run.step, weigh: weigh, scale: s).id(run.step.id)
            }
        }
    }

    func header(_ s: CGFloat) -> some View {
        HStack(spacing: 14) {
            Button {
                model.saveReadings(run)
                model.showPrepCounter = false
            } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundStyle(Ink.text)
                    .frame(width: 44, height: 44).background(Ink.raised, in: .circle).contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close counter mode")
            .accessibilityIdentifier("prep.close")
            Text("\(Format.day(model.today, style: .dateTime.weekday(.wide))) prep · step \(run.index + 1) of \(run.guide.steps.count)")
                .eyebrow()
            Spacer(minLength: 12)
            TimelineView(.everyMinute) { context in
                Text(Self.progress(run, now: context.date))
                    .font(.subheadline.weight(.medium).monospacedDigit()).foregroundStyle(Ink.text2).lineLimit(1)
            }
            Button {
                showSteps = true
            } label: {
                Label("All steps", systemImage: "list.bullet").font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
                    .padding(.horizontal, 14).frame(height: 44).background(Ink.raised, in: .capsule).contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("prep.steps")
        }
    }

    /// "17 min of 1 h 57 min · done by 5:40 PM".
    static func progress(_ run: PrepRun, now: Date) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(run.started) / 60))
        return "\(Format.duration(elapsed)) of \(Format.duration(run.guide.minutes)) · done by \(Format.time(run.doneBy(now)))"
    }

    /// The step after this one, done or not: the run carries on, or ends on the last.
    func next() {
        if run.isLast {
            model.finishPrep()
        } else {
            run.advance(at: Date())
            model.saveReadings(run)
        }
    }

    /// The Prep page as it is on the plan, every step and what goes in each container.
    @ViewBuilder
    var steps: some View {
        NavigationStack {
            if let plan = model.mealPlans.first(where: { $0.id == run.planID }) {
                List { PrepPage(plan: plan) }
                    .insetGroupedList()
                    .navigationTitle("Prep day")
                    .inlineTitle()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showSteps = false } }
                    }
            }
        }
    }
}

/// The steps as a rail across the top: done ones filled, the current one half, the rest to come.
private struct StepRail: View {
    let run: PrepRun
    let scale: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(Array(run.guide.steps.enumerated()), id: \.element.id) { index, step in
                VStack(alignment: .leading, spacing: 6 * scale) {
                    HStack(spacing: 0) {
                        Rectangle().fill(index <= run.index ? Color.accentColor : Ink.track)
                        Rectangle().fill(index < run.index ? Color.accentColor : Ink.track)
                    }
                    .frame(height: 6)
                    .clipShape(.capsule)
                    Text(step.label)
                        .font(.system(size: 13 * scale, weight: index == run.index ? .bold : .medium))
                        .foregroundStyle(index == run.index ? Ink.text : Ink.text3)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(run.index + 1) of \(run.guide.steps.count)")
        .accessibilityValue(run.step.title)
    }
}

/// The step being done: its few words huge, what to weigh or how long, and the whole instruction.
private struct CurrentStep: View {
    let run: PrepRun
    let step: PrepStep
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            Text("\(step.label).")
                .font(.system(size: 84 * scale, weight: .bold))
                .tracking(-2.5 * scale)
                .foregroundStyle(Ink.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityLabel(step.title)
                .accessibilityIdentifier("prep.step")
            if let weigh = step.weigh {
                // The recipe's amount; the water for what's actually in the pot.
                amount(Format.whole(weigh.grams), "g \(weigh.form)")
                if let water = weigh.water(for: run.reading(for: step)) { amount(water.formatted(), "ml water") }
            } else if let timer = step.timer {
                amount("\(step.minutes)", "min · \(timer.place)")
            }
            Text(step.detail)
                .font(.system(size: 21 * scale))
                .foregroundStyle(Ink.text2)
                .lineLimit(4)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4 * scale)
        }
    }

    /// "400 g dry": the number white, the words grey, both big.
    func amount(_ value: String, _ words: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12 * scale) {
            Text(value).foregroundStyle(Ink.text).monospacedDigit()
            Text(words).foregroundStyle(Ink.text3)
        }
        .font(.system(size: 56 * scale, weight: .bold))
        .tracking(-1.5 * scale)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .accessibilityElement(children: .combine)
    }
}

/// The batch on the scale against the recipe: set what it reads with − and + or by typing, and
/// every container it goes in follows.
private struct ScaleStrip: View {
    let run: PrepRun
    let step: PrepStep
    let weigh: PrepWeigh
    let scale: CGFloat
    @FocusState private var typing: Bool
    /// What's typed. Emptied as the field is tapped, so a reading is typed over the old one (shown
    /// faintly meanwhile) rather than into it.
    @State private var text = ""

    var body: some View {
        let read = run.reading(for: step)
        VStack(alignment: .leading, spacing: 10 * scale) {
            HStack(spacing: 18 * scale) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("On the scale").eyebrow()
                    Text("\(weigh.name), \(weigh.form)").font(.system(size: 26 * scale, weight: .bold)).foregroundStyle(Ink.text)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("Recipe \(Format.whole(weigh.grams)) g").font(.system(size: 16 * scale, weight: .medium)).foregroundStyle(Ink.text3)
                }
                Spacer(minLength: 8)
                HStack(spacing: 4 * scale) {
                    button("Less", "minus", -increment)
                    HStack(alignment: .firstTextBaseline, spacing: 4 * scale) {
                        TextField(Self.plain(read), text: $text)
                            .font(.system(size: 52 * scale, weight: .bold).monospacedDigit())
                            .multilineTextAlignment(.trailing)
                            .fieldKeyboard(.number)
                            .focused($typing)
                            .onSubmit { typing = false }
                            .frame(width: 136 * scale)
                            .accessibilityLabel("Grams on the scale")
                            .accessibilityIdentifier("prep.scale.value")
                        Text("g").font(.system(size: 24 * scale, weight: .semibold)).foregroundStyle(Ink.text3)
                    }
                    button("More", "plus", increment)
                }
                // The reading keeps its room; the batch's name shrinks first.
                .fixedSize()
                .padding(6 * scale)
                .background(Ink.raised, in: .rect(cornerRadius: 22 * scale, style: .continuous))
            }
            Text(Self.feedback(weigh, read: read, changes: run.changes(for: step)))
                .font(.system(size: 18 * scale))
                .foregroundStyle(Ink.text2)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .accessibilityIdentifier("prep.scale.change")
        }
        .inkCard(padding: 18 * scale, radius: 26 * scale)
        .sensoryFeedback(.selection, trigger: read)
        .onAppear { text = Self.plain(read) }
        // Next tapped mid-typing: what was typed counts.
        .onDisappear { if typing { commit() } }
        .onChange(of: typing) { _, typing in
            if typing { text = "" } else { commit() }
        }
        .onChange(of: read) { _, read in
            if !typing { text = Self.plain(read) }
        }
    }

    /// What was typed, if it's a reading the batch could be: otherwise the reading stays as it was.
    func commit() {
        if let grams = Format.parse(text) { run.read(grams, for: step) }
        text = Self.plain(run.reading(for: step))
    }

    /// "412": a reading as typed.
    static func plain(_ grams: Double) -> String { "\(Int(grams.rounded()))" }

    /// A step of the reading: 5 g on a big batch, a gram on a small one.
    var increment: Double { weigh.grams >= 100 ? 5 : 1 }

    func button(_ label: String, _ symbol: String, _ by: Double) -> some View {
        Button {
            typing = false
            run.read(run.reading(for: step) + by, for: step)
        } label: {
            Image(systemName: symbol).font(.system(size: 26 * scale, weight: .semibold)).foregroundStyle(Ink.text)
                .frame(width: 72 * scale, height: 72 * scale).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier("prep.scale.\(symbol)")
    }

    /// "12 g over: +9 kcal in each of 7 containers." or, for a pot two dishes share, each dish's.
    static func feedback(_ weigh: PrepWeigh, read: Double, changes: [PrepChange]) -> AttributedString {
        let off = read - weigh.grams
        guard abs(off) >= 0.5, !changes.isEmpty else {
            return AttributedString("On the recipe: every container as planned. Set what the scale reads and they follow it.")
        }
        func signed(_ value: Double) -> String {
            let whole = Int(value.rounded())
            return whole >= 0 ? "+\(whole)" : "−\(-whole)"
        }
        var text = AttributedString("\(Int(abs(off).rounded())) g \(off > 0 ? "over" : "under"): ")
        let containers = changes.map(\.servings).reduce(0, +)
        let kcal = changes.map { signed($0.kcal) }
        for (index, value) in kcal.enumerated() {
            if index > 0 { text += AttributedString(" and ") }
            var part = AttributedString("\(value) kcal")
            part.foregroundColor = .accentColor
            text += part
        }
        if let protein = changes.first?.protein, abs(protein) >= 0.5 {
            var part = AttributedString(", \(signed(protein)) g protein")
            part.foregroundColor = Ink.protein
            text += part
        }
        text += AttributedString(kcal.count == 1 ? " in each of \(containers) containers." : " a container, by dish, in \(containers) containers.")
        return text
    }
}

/// Everything cooking by itself, as big countdowns over rulers that drain; one that's done rings
/// once and stays until it's cleared.
private struct OnTheHeat: View {
    let run: PrepRun
    let scale: CGFloat
    let columns: Int

    var body: some View {
        let timers = run.timers
        VStack(alignment: .leading, spacing: 16 * scale) {
            Text("On the heat").eyebrow()
            if timers.isEmpty {
                Text("Nothing on yet. A pot or a tray starts its timer when you tap Next.")
                    .font(.system(size: 18 * scale)).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
            } else {
                let shown = columns == 1 ? 3 : 4
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 32 * scale, alignment: .top), count: columns),
                        alignment: .leading, spacing: 22 * scale
                    ) {
                        // Three down one column: smaller, so they fit beside the step.
                        let size = columns == 1 && timers.count >= 3 ? scale * 0.72 : scale
                        ForEach(timers.prefix(shown)) { timer in
                            TimerRow(timer: timer, now: context.date, scale: size) { run.clear(timer.id) }
                        }
                    }
                }
                if timers.count > shown {
                    Text("and \(timers.count - shown) more").font(.system(size: 16 * scale)).foregroundStyle(Ink.text3)
                }
            }
        }
        .task(id: run.nextAlarm?.id) { await ring() }
    }

    /// Waits for the next timer to run out, then rings it.
    func ring() async {
        guard let timer = run.nextAlarm else { return }
        let wait = timer.ends.timeIntervalSinceNow
        if wait > 0 {
            do { try await Task.sleep(for: .seconds(wait)) } catch { return }
        }
        Platform.chime()
        run.ring(timer.id)
    }
}

private struct TimerRow: View {
    let timer: PrepRun.Timer
    let now: Date
    let scale: CGFloat
    let clear: () -> Void

    var body: some View {
        let left = timer.ends.timeIntervalSince(now)
        VStack(alignment: .leading, spacing: 8 * scale) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(timer.name).font(.system(size: 30 * scale, weight: .bold)).foregroundStyle(Ink.text)
                    .lineLimit(2).minimumScaleFactor(0.6)
                Spacer(minLength: 8)
                Text(left > 0 ? Self.clock(left) : "Done")
                    .font(.system(size: 92 * scale, weight: .bold)).monospacedDigit().tracking(-3 * scale)
                    .foregroundStyle(left > 0 ? Ink.text : Color.accentColor)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .layoutPriority(1)
            }
            Ruler(value: max(0, left) / timer.seconds, height: 40 * scale)
            HStack(spacing: 8) {
                Text(left > 0 ? timer.place : "Take it off · \(Self.clock(-left)) over")
                    .foregroundStyle(left > 0 ? Ink.text3 : Color.accentColor)
                Spacer(minLength: 8)
                if left > 0 {
                    Text("of \(Self.clock(timer.seconds))").foregroundStyle(Ink.text3)
                } else {
                    Button("Clear", action: clear).fontWeight(.semibold).buttonStyle(.borderless).accessibilityIdentifier("prep.timer.clear")
                }
            }
            .font(.system(size: 17 * scale, weight: .medium).monospacedDigit())
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("prep.timer")
    }

    /// "12:40", "1:05:00".
    static func clock(_ seconds: TimeInterval) -> String {
        Duration.seconds(Int(seconds.rounded(.up))).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}

/// What's after this step, and the one big button to get there (Done on the last).
private struct UpNext: View {
    let run: PrepRun
    let scale: CGFloat
    let next: () -> Void

    var body: some View {
        HStack(spacing: 18 * scale) {
            VStack(alignment: .leading, spacing: 4 * scale) {
                Text(run.isLast ? "Last step" : "Up next").eyebrow()
                Text(run.next.map(Self.line) ?? "That's prep day done.")
                    .font(.system(size: 34 * scale, weight: .bold)).foregroundStyle(Ink.text)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if run.index > 0 {
                Button(action: run.back) {
                    Image(systemName: "chevron.left").font(.system(size: 26 * scale, weight: .bold)).foregroundStyle(Ink.text)
                        .frame(width: 84 * scale, height: 84 * scale)
                        .background(Ink.raised, in: .rect(cornerRadius: 22 * scale, style: .continuous))
                        .contentShape(.rect(cornerRadius: 22 * scale))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back a step")
                .accessibilityIdentifier("prep.back")
            }
            Button(action: next) {
                HStack(spacing: 10 * scale) {
                    Text(run.isLast ? "Done" : "Next")
                    Image(systemName: run.isLast ? "checkmark" : "chevron.right")
                }
                .font(.system(size: 36 * scale, weight: .bold))
                .foregroundStyle(Ink.ground)
                .frame(width: 236 * scale, height: 84 * scale)
                .background(Color.accentColor, in: .rect(cornerRadius: 22 * scale, style: .continuous))
                .contentShape(.rect(cornerRadius: 22 * scale))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("prep.next")
        }
        .inkCard(padding: 14 * scale, radius: 28 * scale)
    }

    /// "Prep broccoli. 1,166 g raw", "Chicken in. 22 min".
    static func line(_ step: PrepStep) -> String {
        if let weigh = step.weigh { return "\(step.label). \(Format.whole(weigh.grams)) g \(weigh.form)" }
        if step.timer != nil { return "\(step.label). \(step.minutes) min" }
        return "\(step.label)."
    }
}

/// The week's containers, dish by dish, filling as the steps put each part in, with what one holds
/// as weighed.
private struct Containers: View {
    let run: PrepRun
    let scale: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 26 * scale) {
            ForEach(run.dishes) { dish in
                let planned = run.planned.first { $0.id == dish.id }?.nutrients ?? dish.nutrients
                DishTubs(dish: dish, parts: run.parts(of: dish.id), change: dish.nutrients.kcal - planned.kcal, scale: scale)
            }
        }
    }
}

private struct DishTubs: View {
    let dish: PlannedRecipe
    let parts: (done: Int, of: Int)
    let change: Double
    let scale: CGFloat

    var body: some View {
        let n = dish.nutrients
        let fill = parts.of > 0 ? Double(parts.done) / Double(parts.of) : 0
        VStack(alignment: .leading, spacing: 8 * scale) {
            HStack(spacing: 6) {
                Text(dish.title).font(.system(size: 15 * scale, weight: .semibold)).foregroundStyle(Ink.text).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(parts.done) of \(parts.of) in").font(.system(size: 13 * scale, weight: .medium)).foregroundStyle(Ink.text3)
                    .lineLimit(1).fixedSize()
            }
            HStack(spacing: 5 * scale) {
                ForEach(0..<dish.servings, id: \.self) { _ in Tub(fill: fill, bands: parts.of, scale: scale) }
            }
            .frame(height: 50 * scale)
            HStack(alignment: .firstTextBaseline, spacing: 5 * scale) {
                Text(Format.whole(n.kcal)).font(.system(size: 26 * scale, weight: .bold).monospacedDigit()).foregroundStyle(Ink.text)
                Text("kcal").font(.system(size: 13 * scale, weight: .medium)).foregroundStyle(Ink.text3)
                Text("\(Format.whole(n.protein)) g protein").font(.system(size: 13 * scale, weight: .semibold)).foregroundStyle(Ink.protein)
                if Int(change.rounded()) != 0 {
                    Text(change > 0 ? "+\(Int(change.rounded()))" : "−\(Int(-change.rounded()))")
                        .font(.system(size: 12 * scale, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.18), in: .capsule)
                }
                Text("each").font(.system(size: 13 * scale)).foregroundStyle(Ink.text3)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dish.title)
        .accessibilityValue(
            "\(parts.done) of \(parts.of) parts in, \(dish.servings) containers, \(Format.kcal(n.kcal)) and \(Format.whole(n.protein)) grams protein each"
        )
        .accessibilityIdentifier("prep.dish")
    }
}

/// A container: a lid once it's full, and its parts filling from the bottom.
private struct Tub: View {
    let fill: Double
    let bands: Int
    let scale: CGFloat

    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 3 * scale, bottomLeadingRadius: 10 * scale, bottomTrailingRadius: 10 * scale, topTrailingRadius: 3 * scale,
            style: .continuous)
        VStack(spacing: 3 * scale) {
            Capsule().fill(fill >= 1 ? Ink.text2 : Ink.track).frame(height: 4 * scale)
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    shape.fill(Ink.raised)
                    Rectangle().fill(Color.accentColor).frame(height: geometry.size.height * fill)
                    if bands > 1 {
                        Path { path in
                            for band in 1..<bands {
                                let y = (geometry.size.height * Double(band) / Double(bands)).rounded()
                                path.addRect(CGRect(x: 0, y: y - 0.75, width: geometry.size.width, height: 1.5))
                            }
                        }
                        .fill(Ink.tick)
                    }
                }
                .clipShape(shape)
            }
        }
        .frame(maxWidth: 90 * scale)
        .animation(.snappy, value: fill)
    }
}
