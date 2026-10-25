import MindEngine
import SwiftUI
import SystemCore

/// A minute of setup, then the first session finds the level: the onboarding is the first session.
/// Each subject asks its own questions on its own page (the files beside this one).
struct OnboardingView: View {
    enum Page: String, Hashable { case welcome, courses, schedule, languages, maths, writing, reading, ready }

    @Environment(AppModel.self) private var model
    @State private var page = Page.welcome
    @State private var settings = MindSettings(onboardedAt: nil)
    @State private var books: [Book] = []

    var pages: [Page] { Self.pages(for: settings) }

    /// The pages a setup shows: a subject's own page only while it learns (Main or Secondary).
    static func pages(for settings: MindSettings) -> [Page] {
        var pages: [Page] = [.welcome, .courses, .schedule]
        let studied = settings.studied
        if studied.contains(where: \.isLanguage) { pages.append(.languages) }
        if studied.contains(.maths) { pages.append(.maths) }
        if studied.contains(.writing) { pages.append(.writing) }
        if studied.contains(.reading) { pages.append(.reading) }
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
                            .accessibilityIdentifier("onboarding.back")
                        }
                        Button {
                            if page == .ready { finish() } else { withAnimation { move(1) } }
                        } label: {
                            Text(page == .ready ? "Start" : page == .welcome ? "Set up" : "Next").font(.headline).frame(maxWidth: .infinity)
                        }
                        .primaryAction()
                        .controlSize(.large)
                        .disabled(page == .courses && settings.focus.isEmpty)
                        .accessibilityIdentifier("onboarding.next")
                    }
                }
            }
            .background(.pageBackground)
        }
        #if DEBUG
        .onAppear {
            // -onboardingPage courses|schedule|languages|maths|writing|reading|ready opens on that page.
            if let start = LaunchOptions.current.value(after: "-onboardingPage").flatMap(Page.init(rawValue:)) { page = start }
        }
        #endif
    }

    func move(_ by: Int) { page = Self.page(from: page, moving: by, in: pages) }

    /// The page `by` pages on, staying within the setup. A page that's gone (its course turned off)
    /// counts as the first.
    static func page(from page: Page, moving by: Int, in pages: [Page]) -> Page {
        let index = pages.firstIndex(of: page) ?? 0
        return pages[clamp(index + by, 0, pages.count - 1)]
    }

    var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "brain.head.profile").font(.system(size: 56)).foregroundStyle(.tint)
            Text("Stadig Mind").font(.largeTitle.bold())
                .accessibilityIdentifier("onboarding.welcomeTitle")
            Text("Focused 25-minute sessions that find your level, then train it, the way Stadig Lift trains the body.").font(.title3)
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
                .accessibilityIdentifier("onboarding.coursesTitle")
            Text(
                "Main courses get days of their own. Secondary courses take turns at a short block in each session, so they keep moving, more slowly. Maintenance keeps what you know with a few minutes of reviews. Two or three Main courses at once is plenty."
            )
            .foregroundStyle(.secondary)
            CoursePicker(settings: $settings)
            LoadWarning(settings: settings)
        }
    }

    var schedule: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("When do you study?").font(.title.bold())
                .accessibilityIdentifier("onboarding.scheduleTitle")
            Text(
                "Main courses rotate across the week like a training split. Reviews from every course open each session, and a Secondary course's block closes it."
            )
            .foregroundStyle(.secondary)
            ScheduleEditor(settings: $settings)
            LoadWarning(settings: settings)
            WeekPreview(settings: settings)
        }
    }

    var ready: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your first session").font(.largeTitle.bold())
                .accessibilityIdentifier("onboarding.readyTitle")
            Text(
                "About \(settings.schedule.minutes) minutes to find your level, then the first new material. Answer honestly: “Don't know” is always better than a guess."
            )
            .font(.title3)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(settings.studied) { domain in
                    if let line = firstSession(domain) { Label(line, systemImage: domain.symbol) }
                }
                if !settings.maintenance.isEmpty {
                    Label(
                        "Maintenance: \(ListFormatter.localizedString(byJoining: settings.maintenance.map(\.label))), reviews of what you know",
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

/// Every course as Main, Secondary, Maintenance or Off.
struct CoursePicker: View {
    enum Choice: Hashable { case focus, secondary, maintenance, off }

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
                        Text(CourseMode.focus.label).tag(Choice.focus)
                        Text(CourseMode.secondary.label).tag(Choice.secondary)
                        Text(CourseMode.maintenance.label).tag(Choice.maintenance)
                        Text("Off").tag(Choice.off)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("onboarding.course.\(domain.rawValue)")
                }
                .card()
            }
        }
    }

    func binding(_ domain: Domain) -> Binding<Choice> {
        Binding {
            switch settings.mode(domain) {
            case .focus: .focus
            case .secondary: .secondary
            case .maintenance: .maintenance
            case nil: .off
            }
        } set: { choice in
            switch choice {
            case .focus: settings.courses[domain] = .focus
            case .secondary: settings.courses[domain] = .secondary
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
            Stepper(
                value: Binding(
                    get: { settings.schedule.daysPerWeek },
                    set: { settings.schedule = StudySchedule(daysPerWeek: $0, minutes: settings.schedule.minutes) }),
                in: 1...7
            ) {
                LabeledContent("Days a week", value: "\(settings.schedule.daysPerWeek)")
            }
            .accessibilityIdentifier("onboarding.daysPerWeek")
            Picker("Session length", selection: Binding(get: { settings.schedule.minutes }, set: { settings.schedule.minutes = $0 })) {
                ForEach(StudySchedule.sessionOptions, id: \.self) { Text("\($0) min").tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("onboarding.sessionLength")
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
        .accessibilityLabel(
            Weekday.allCases.compactMap { weekday in
                let day = monday.adding(days: weekday.rawValue - 1)
                return week[day].map { "\(weekday.name): \($0.map(\.label).joined(separator: " and "))" }
            }.joined(separator: ". "))
    }
}
