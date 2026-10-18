import SwiftUI
import MindEngine
import SystemCore

/// A minute of setup, then the first session finds the level: the onboarding is the first session.
/// Each subject asks its own questions on its own page (the files beside this one).
struct OnboardingView: View {
    enum Page: String, Hashable { case welcome, courses, schedule, languages, maths, writing, reading, ready }

    @Environment(AppModel.self) private var model
    @State private var page = Page.welcome
    @State private var settings = MindSettings(onboardedAt: nil)
    @State private var books: [Book] = []

    var pages: [Page] {
        var pages: [Page] = [.welcome, .courses, .schedule]
        if settings.focus.contains(where: \.isLanguage) { pages.append(.languages) }
        if settings.mode(.maths) == .focus { pages.append(.maths) }
        if settings.mode(.writing) == .focus { pages.append(.writing) }
        if settings.mode(.reading) == .focus { pages.append(.reading) }
        return pages + [.ready]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch page {
                        case .welcome: welcome
                        case .courses: courses
                        case .schedule: schedule
                        case .languages: LanguageOnboarding(settings: $settings)
                        case .maths: MathsOnboarding(settings: $settings)
                        case .writing: WritingOnboarding(settings: $settings)
                        case .reading: ReadingOnboarding(settings: $settings, books: $books)
                        case .ready: ready
                        }
                    }
                    .padding(24)
                    .readableWidth(600)
                }
                BottomBar {
                    HStack(spacing: 12) {
                        if page != .welcome {
                            Button {
                                withAnimation { move(-1) }
                            } label: {
                                Text("Back").frame(maxWidth: .infinity)
                            }
                            .secondaryAction()
                            .controlSize(.large)
                        }
                        Button {
                            if page == .ready { finish() } else { withAnimation { move(1) } }
                        } label: {
                            Text(page == .ready ? "Start" : page == .welcome ? "Set up" : "Next").font(.headline).frame(maxWidth: .infinity)
                        }
                        .primaryAction()
                        .controlSize(.large)
                        .disabled(page == .courses && settings.focus.isEmpty)
                    }
                }
            }
            .background(.pageBackground)
        }
        #if DEBUG
        .onAppear {
            // -onboardingPage courses|schedule|languages|maths|writing|reading|ready opens on that page.
            let arguments = ProcessInfo.processInfo.arguments
            if let i = arguments.firstIndex(of: "-onboardingPage"), arguments.indices.contains(i + 1),
               let start = Page(rawValue: arguments[i + 1]) { page = start }
        }
        #endif
    }

    func move(_ by: Int) {
        let index = pages.firstIndex(of: page) ?? 0
        page = pages[clamp(index + by, 0, pages.count - 1)]
    }

    var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "brain.head.profile").font(.system(size: 56)).foregroundStyle(.tint)
            Text("Mind Track").font(.largeTitle.bold())
            Text("Lift Track for the mind: focused 25-minute sessions that find your level, then train it.").font(.title3)
            VStack(alignment: .leading, spacing: 12) {
                Label("The first sessions find where you are in each subject", systemImage: "scope")
                Label("Something new only once the last thing has stuck", systemImage: "stairs")
                Label("Reviews come back just before you'd forget", systemImage: "arrow.triangle.2.circlepath")
                Label("Intelligence and Wisdom move only on real tests, never on time spent", systemImage: "gauge.with.dots.needle.67percent")
            }
            .font(.body)
            .padding(.top, 8)
        }
    }

    var courses: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What do you want to train?").font(.title.bold())
            Text("Focus courses get full sessions. Maintenance keeps what you know with a few minutes of reviews. Two or three Focus courses at once is plenty.")
                .foregroundStyle(.secondary)
            CoursePicker(settings: $settings)
            LoadWarning(settings: settings)
        }
    }

    var schedule: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("When do you study?").font(.title.bold())
            Text("Focus courses rotate across the week like a training split. Reviews from every course open each session.")
                .foregroundStyle(.secondary)
            ScheduleEditor(settings: $settings)
            LoadWarning(settings: settings)
            WeekPreview(settings: settings)
        }
    }

    var ready: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your first session").font(.largeTitle.bold())
            Text("About \(settings.schedule.minutes) minutes to find your level, then the first new material. Answer honestly: “Don't know” is always better than a guess.")
                .font(.title3)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(settings.focus) { domain in
                    if let line = firstSession(domain) { Label(line, systemImage: domain.symbol) }
                }
                if !settings.maintenance.isEmpty {
                    Label("Maintenance: \(ListFormatter.localizedString(byJoining: settings.maintenance.map(\.label))), reviews only",
                          systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .card()
        }
    }

    func firstSession(_ domain: Domain) -> String? {
        switch domain {
        case .japanese, .spanish: LanguageOnboarding.firstSession(domain, settings: settings)
        case .maths: MathsOnboarding.firstSession(settings)
        case .writing: WritingOnboarding.firstSession(settings)
        case .reading: ReadingOnboarding.firstSession(settings, books: books)
        }
    }

    func finish() {
        if !settings.has(.japanese) { settings.readsKana = nil }
        model.completeOnboarding(settings, booksRead: settings.has(.reading) ? books : [])
    }
}

/// Every course with Focus, Maintenance or Off.
struct CoursePicker: View {
    enum Choice: Hashable { case focus, maintenance, off }

    @Binding var settings: MindSettings

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Domain.allCases) { domain in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 14) {
                        DomainBadge(domain: domain, size: 38)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(domain.label).font(.headline)
                            Text(domain.pitch).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Picker(domain.label, selection: binding(domain)) {
                        Text("Focus").tag(Choice.focus)
                        Text("Maintenance").tag(Choice.maintenance)
                        Text("Off").tag(Choice.off)
                    }
                    .pickerStyle(.segmented)
                }
                .card()
            }
        }
    }

    func binding(_ domain: Domain) -> Binding<Choice> {
        Binding {
            switch settings.mode(domain) {
            case .focus: .focus
            case .maintenance: .maintenance
            case nil: .off
            }
        } set: { choice in
            switch choice {
            case .focus: settings.courses[domain] = .focus
            case .maintenance: settings.courses[domain] = .maintenance
            case .off: settings.courses[domain] = nil
            }
        }
    }
}

/// Days a week and session length.
struct ScheduleEditor: View {
    @Binding var settings: MindSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Stepper(value: Binding(get: { settings.schedule.daysPerWeek }, set: { settings.schedule = StudySchedule(daysPerWeek: $0, minutes: settings.schedule.minutes) }),
                    in: 1...7) {
                LabeledContent("Days a week", value: "\(settings.schedule.daysPerWeek)")
            }
            Picker("Session length", selection: Binding(get: { settings.schedule.minutes }, set: { settings.schedule.minutes = $0 })) {
                ForEach(StudySchedule.sessionOptions, id: \.self) { Text("\($0) min").tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .card()
    }
}

/// What to change when the courses won't fit the week. Nothing when they do.
struct LoadWarning: View {
    let settings: MindSettings

    var body: some View {
        if let warning = CourseLoad.check(settings).warning {
            Label(warning, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .symbolRenderingMode(.multicolor)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 14))
        }
    }
}

/// The week the split makes, previewed.
struct WeekPreview: View {
    let settings: MindSettings

    var body: some View {
        let monday = Day.today.startOfWeek
        let week = Split.week(starting: monday, settings: settings)
        HStack(alignment: .top, spacing: 6) {
            ForEach(0..<7, id: \.self) { offset in
                let day = monday.adding(days: offset)
                VStack(spacing: 6) {
                    Text(day.weekday.short).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    VStack(spacing: 3) {
                        ForEach(week[day] ?? [], id: \.self) { DomainBadge(domain: $0, size: 26) }
                        if (week[day] ?? []).isEmpty {
                            Circle().fill(Color.secondary.opacity(0.15)).frame(width: 26, height: 26)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .card(padding: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Weekday.allCases.compactMap { weekday in
            let day = monday.adding(days: weekday.rawValue - 1)
            return week[day].map { "\(weekday.name): \($0.map(\.label).joined(separator: " and "))" }
        }.joined(separator: ". "))
    }
}
