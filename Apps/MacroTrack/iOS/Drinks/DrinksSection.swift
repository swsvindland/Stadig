import FoodDatabase
import NutritionEngine
import SwiftUI
import SystemCore

/// Water and caffeine on Today, for people who turned drinks on: a tap for a glass, a tap for a
/// coffee, today's caffeine against its limit and what will still be active at bedtime.
struct DrinksSection: View {
    @Environment(AppModel.self) private var model
    let day: Day
    @State private var cuttingBack = false

    var body: some View {
        if model.tracksDrinks, let analysis = model.analysis {
            let hydration = day == model.today ? analysis.hydration : hydrationOn(day)
            let caffeine = day == model.today ? analysis.caffeine : nil
            Section {
                if let hydration { waterRow(hydration) }
                if let caffeine, day == model.today { caffeineRow(caffeine) } else { pastCaffeine }
                drinkChips
                if let caffeine, day == model.today, let advice = advice(caffeine) {
                    Label(advice, systemImage: "lightbulb").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                HStack {
                    Text("Drinks")
                    Spacer()
                    Button {
                        cuttingBack = true
                    } label: {
                        Text(analysis.caffeine?.cutBack == nil ? "Cut back" : "Cutting back").font(.subheadline)
                    }
                    .accessibilityIdentifier("drinks.cutBack")
                }
                .sheet(isPresented: $cuttingBack) { CaffeineCutBackSheet().macSheetSize(width: 460, height: 480) }
            }
        }
    }

    func hydrationOn(_ day: Day) -> HydrationDay? {
        guard let profile = model.profile else { return nil }
        return Hydration.day(
            day, water: model.water, entries: model.entries,
            target: model.settings.waterTarget ?? Hydration.target(sex: profile.sex))
    }

    func waterRow(_ h: HydrationDay) -> some View {
        let ounces = model.fluidOunces
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "drop.fill").foregroundStyle(.cyan).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Format.volume(h.total, ounces: ounces)).font(.subheadline.weight(.semibold).monospacedDigit())
                    Text(
                        "of \(Format.volume(h.target, ounces: ounces))\(h.drinks > 0 ? " · \(Format.volume(h.drinks, ounces: ounces)) from drinks" : "")"
                    )
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                .layoutPriority(1)
                Spacer(minLength: 4)
                ForEach(model.waterSizes, id: \.ml) { size in
                    Button {
                        model.addWater(ml: size.ml)
                    } label: {
                        Text("+ \(size.label)").font(.caption.weight(.semibold)).lineLimit(1).fixedSize()
                    }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(.cyan)
                    .accessibilityLabel("Add \(Format.volume(size.ml, ounces: ounces)) of water")
                }
            }
            Bar(fraction: h.fraction, color: .cyan)
        }
    }

    func caffeineRow(_ c: CaffeineReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "bolt.fill").foregroundStyle(.brown).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Format.mg(c.total)) caffeine of \(Format.mg(c.limit))").font(.subheadline.weight(.semibold).monospacedDigit())
                    Text(caffeineDetail(c)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Bar(fraction: c.limit > 0 ? c.total / c.limit : 0, color: c.over ? .orange : .brown)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    var pastCaffeine: some View {
        let doses = Caffeine.doses(on: day, entries: model.entries, supplements: model.supplementLogs)
        if !doses.isEmpty {
            Label("\(Format.mg(doses.map(\.mg).reduce(0, +))) caffeine", systemImage: "bolt.fill").font(.subheadline)
        }
    }

    func caffeineDetail(_ c: CaffeineReport) -> String {
        guard let last = c.last else { return c.cutBack != nil ? "This week's limit while cutting back" : "Nothing yet today" }
        var parts = ["Last \(Format.time(last.date))"]
        if c.atBedtime >= 10 { parts.append("≈ \(Format.mg(c.atBedtime)) left at bedtime") }
        return parts.joined(separator: " · ")
    }

    /// One thing to do about today's caffeine, when there's something.
    func advice(_ c: CaffeineReport) -> String? {
        let bedtime = Format.time(c.bedtime)
        if c.over {
            return "Over today's \(Format.mg(c.limit))\(c.cutBack != nil ? " step" : ""). Decaf, or half-caf, for anything else today."
        }
        if c.atBedtime >= Caffeine.bedtimeConcern {
            return
                "About \(Format.mg(c.atBedtime)) will still be active at \(bedtime). Caffeine before \(Format.time(c.cutoff)) leaves less in the way of deep sleep."
        }
        if let cut = c.cutBack, c.limit > cut.goal {
            return "Cutting back: up to \(Format.mg(c.limit)) this week, \(Format.mg(cut.goal)) from \(Format.day(cut.reachesGoal))."
        }
        if c.cutBack == nil, let average = c.weekAverage, average > Caffeine.defaultLimit {
            return "You've averaged \(Format.mg(average)) a day this week. Cut back a step a week to keep the headaches away."
        }
        return nil
    }

    var drinkChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(QuickDrink.standard) { drink in
                    chip(drink.name, symbol: drink.symbol) { model.log(drink) }
                }
                ForEach(model.usualDrinks) { entry in
                    chip(Format.shortName(entry.name), symbol: nil, detail: entry.amountLabel) { model.logAgain(drink: entry) }
                }
                chip("Other", symbol: "magnifyingglass") { model.openLogger(.search) }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
    }

    func chip(_ title: String, symbol: String?, detail: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.caption) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.subheadline.weight(.medium)).lineLimit(1)
                    if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                }
            }
            .frame(maxWidth: 160, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.insetBackground, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log \(title)\(detail.map { ", \($0)" } ?? "")")
    }
}

private struct Bar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.16))
                Capsule().fill(color.gradient).frame(width: max(fraction > 0 ? 6 : 0, proxy.size.width * min(1, fraction)))
            }
        }
        .frame(height: 6)
        .animation(.snappy, value: fraction)
        .accessibilityHidden(true)
    }
}

/// A gradual cut: from the week's average to a goal, a step down each week.
struct CaffeineCutBackSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var from = 400.0
    @State private var goal = 200.0

    var body: some View {
        NavigationStack {
            Form {
                if let cut = model.settings.caffeineCutBack {
                    Section {
                        LabeledContent("Started", value: Format.day(cut.start))
                        LabeledContent("This week", value: Format.mg(cut.limit(on: model.today)))
                        LabeledContent("Goal", value: "\(Format.mg(cut.goal)) from \(Format.day(cut.reachesGoal))")
                        Button("Stop cutting back", role: .destructive) {
                            model.endCutBack()
                            dismiss()
                        }
                    } footer: {
                        Text("The goal stays as your daily limit once it's reached.")
                    }
                } else {
                    Section {
                        Stepper(value: $from, in: 50...1000, step: 10) {
                            LabeledContent("Now", value: "\(Format.mg(from)) a day")
                        }
                        Stepper(value: $goal, in: 0...max(0, from - 25), step: 25) {
                            LabeledContent("Goal", value: "\(Format.mg(goal)) a day")
                        }
                    } footer: {
                        Text(
                            average.map { "You've averaged \(Format.mg($0)) a day this past week." }
                                ?? "Log your coffee and energy drinks for a few days and this starts from your real average.")
                    }
                    Section("The plan") {
                        let plan = CaffeineCutBack(start: model.today, from: from, goal: goal)
                        ForEach(0..<plan.weeks, id: \.self) { week in
                            let day = model.today.adding(weeks: week)
                            LabeledContent(week == 0 ? "This week" : "From \(Format.day(day))", value: "up to \(Format.mg(plan.limit(on: day)))")
                        }
                        Text(
                            "A fifth less each week (at least 25 mg) keeps withdrawal headaches and fog mild. A coffee is about 95 mg, an energy drink 150–300 mg."
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Section {
                        Button("Start cutting back") {
                            model.startCutBack(from: from, goal: goal)
                            dismiss()
                        }
                        .disabled(goal >= from)
                    }
                }
                Section("Bedtime") {
                    DatePicker("Bedtime", selection: Binding(get: { bedtimeDate }, set: setBedtime), displayedComponents: .hourAndMinute)
                    Text("Caffeine left at bedtime is worked out at an average five-hour half-life.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Caffeine")
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear {
                if let average {
                    from = max(50, (average / 10).rounded() * 10)
                    goal = max(0, min(200, ((from * 0.5) / 25).rounded() * 25))
                }
            }
        }
        .presentationDetents([.large])
    }

    var average: Double? { model.analysis?.caffeine?.weekAverage }

    var bedtimeDate: Date { Day.today.at(minutes: model.settings.minutes(.bedtime)) }

    func setBedtime(_ date: Date) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        model.updateSettings { s in
            var times = s.doseTimes ?? [:]
            times[.bedtime] = (parts.hour ?? 22) * 60 + (parts.minute ?? 30)
            s.doseTimes = times
        }
    }
}
