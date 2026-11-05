import HubEngine
import SwiftUI
import SystemCore

/// Work or school: a usual shape to start from, adjusted by hand, or said in your own words. Setup
/// and the Rhythm tab both use it.
struct ScheduleCard: View {
    @Binding var pattern: WorkPattern
    let monday: Day

    @State private var words = ""
    @State private var read: ScheduleReader.Draft?
    @State private var unread = false
    @State private var reading = false
    @State private var adjusting = false

    private static let commutes = [0, 15, 30, 45, 60, 90]
    private var selected: SchedulePreset? { SchedulePreset.matching(pattern) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeading("Work or school")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 124), spacing: 6)], spacing: 6) {
                ForEach(SchedulePreset.allCases) { preset in
                    Button {
                        pattern = preset.pattern(anchor: monday).withCommute(pattern.commuteMinutes)
                    } label: {
                        Text(preset.label)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(preset == selected ? AnyShapeStyle(Color.strongFill) : AnyShapeStyle(.insetBackground), in: .capsule)
                            .foregroundStyle(preset == selected ? AnyShapeStyle(Color.onStrongFill) : AnyShapeStyle(.primary))
                    }
                    .buttonStyle(.plain)
                    .hoverable(in: .capsule)
                    .accessibilityAddTraits(preset == selected ? .isSelected : [])
                    .accessibilityIdentifier("schedule.preset.\(preset.rawValue)")
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(ScheduleSummary.lines(pattern), id: \.self) { line in
                    Text(line).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("schedule.lines")
            if pattern.weeks.count > 1 { whichWeek }
            LabeledContent("Commute each way") {
                Picker("Commute each way", selection: commute) {
                    ForEach(Self.commutes, id: \.self) { minutes in
                        Text(minutes == 0 ? "None" : HubText.length(minutes)).tag(minutes)
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("schedule.commute")
            }
            Button("Adjust the days") { adjusting = true }
                .secondaryAction()
                .accessibilityIdentifier("schedule.adjust")
            Divider()
            ownWords
        }
        .card(padding: 14, radius: 18)
        .sheet(isPresented: $adjusting) {
            NavigationStack { WeekEditor(pattern: $pattern) }
                .sheetForm(width: 520, height: 640)
        }
    }

    /// Which week of the cycle this one is, which nothing but the person can say.
    private var whichWeek: some View {
        LabeledContent("This week is") {
            Picker("This week is", selection: Binding(get: { pattern.cycleWeek(of: monday) }, set: { pattern = pattern.settingWeek($0, of: monday) }))
            {
                ForEach(pattern.weeks.indices, id: \.self) { week in
                    Text("Week \(week + 1)").tag(week)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityIdentifier("schedule.whichWeek")
        }
    }

    private var commute: Binding<Int> {
        Binding(get: { pattern.commuteMinutes }, set: { pattern = pattern.withCommute($0) })
    }

    @ViewBuilder private var ownWords: some View {
        Text("Or say it in your own words").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
        TextField("9 hours Monday to Thursday, every other Friday off", text: $words, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("schedule.words")
        Button(reading ? "Reading…" : "Read it") {
            reading = true
            Task {
                read = await ScheduleAssistant().read(words, anchor: monday)
                unread = read == nil
                reading = false
            }
        }
        .secondaryAction()
        .disabled(reading || words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("schedule.read")
        if let read {
            VStack(alignment: .leading, spacing: 6) {
                Text("Here's what I read. Is that right?").font(.footnote.weight(.semibold))
                ForEach(ScheduleSummary.lines(read.pattern), id: \.self) { line in
                    Text(line).font(.subheadline)
                }
                Button("Use this") {
                    pattern = read.pattern.withCommute(pattern.commuteMinutes)
                    self.read = nil
                    words = ""
                }
                .primaryAction()
                .accessibilityIdentifier("schedule.use")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(HubItem.Kind.study.color.opacity(0.14), in: .rect(cornerRadius: 14))
        }
        if unread {
            Text("I couldn't read that one. Pick the closest above and adjust it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("schedule.unread")
        }
    }
}

/// The week by hand: each day's hours, any repeating weeks, and when it ends.
struct WeekEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var pattern: WorkPattern

    var body: some View {
        Form {
            ForEach(pattern.weeks.indices, id: \.self) { week in
                Section(pattern.weeks.count > 1 ? "Week \(week + 1)" : "Each week") {
                    ForEach(Weekday.allCases) { weekday in
                        DayEditor(weekday: weekday, spans: day(week, weekday))
                    }
                }
            }
            Section {
                Button("Add a week to the cycle") { pattern.weeks.append(pattern.weeks.last ?? []) }
                    .accessibilityIdentifier("editor.addWeek")
                if pattern.weeks.count > 1 {
                    Button("Remove the last week", role: .destructive) { pattern.weeks.removeLast() }
                        .accessibilityIdentifier("editor.removeWeek")
                }
            } footer: {
                Text("For a pattern that repeats over more than a week, such as alternate Fridays or rotating shifts.")
            }
            Section {
                Toggle("Ends on a date", isOn: ends)
                    .accessibilityIdentifier("editor.ends")
                if let endsOn = pattern.endsOn {
                    DatePicker(
                        "Last day", selection: Binding(get: { endsOn.date() }, set: { pattern.endsOn = Day($0) }), displayedComponents: .date)
                }
            } footer: {
                Text("The end of a term. After it the plan goes back to guessing until you set the next one.")
            }
        }
        .navigationTitle("Your days")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("editor.done")
            }
        }
    }

    /// A day without its commute, which follows whatever the day holds.
    private func day(_ week: Int, _ weekday: Weekday) -> Binding<[DaySpan]> {
        let index = weekday.rawValue - 1
        return Binding(
            get: { pattern.weeks[week][index].filter { $0.kind != .commute } },
            set: { spans in
                let commute = pattern.commuteMinutes
                pattern.weeks[week][index] = spans
                pattern = pattern.withCommute(commute)
            })
    }

    private var ends: Binding<Bool> {
        Binding(get: { pattern.endsOn != nil }, set: { pattern.endsOn = $0 ? Day(Date()).adding(weeks: 12) : nil })
    }
}

/// A day's hours: nothing, or a span or more of them.
struct DayEditor: View {
    let weekday: Weekday
    @Binding var spans: [DaySpan]

    var body: some View {
        DisclosureGroup {
            ForEach(spans.indices, id: \.self) { index in
                TextField("Name", text: $spans[index].label)
                    .accessibilityIdentifier("editor.\(weekday.short).\(index).name")
                ClockField(title: "From", minutes: $spans[index].start)
                // An end at or before the start is the next morning: a night shift.
                ClockField(
                    title: "To",
                    minutes: Binding(get: { spans[index].end }, set: { spans[index].end = $0 <= spans[index].start ? $0 + 1440 : $0 }))
                Button("Remove", role: .destructive) { spans.remove(at: index) }
            }
            Button(spans.isEmpty ? "Add hours" : "Add more hours") {
                let start = spans.last?.end ?? 9 * 60
                spans.append(DaySpan(.work, spans.last?.label ?? "Work", from: start, to: start + 60))
            }
            .accessibilityIdentifier("editor.\(weekday.short).add")
        } label: {
            LabeledContent(weekday.name, value: ScheduleSummary.describe(spans))
        }
    }
}
