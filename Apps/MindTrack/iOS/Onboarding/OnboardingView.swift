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
    @State private var week = WeekSettings.fresh(MindSettings(onboardedAt: nil).domains, since: .today, now: Date())
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
            Text("Focused 25-minute blocks, one subject at a time, that find your level and train it the way Stadig Lift trains the body.").font(
                .title3)
            VStack(alignment: .leading, spacing: 12) {
                Label("A subject's first block finds where you are", systemImage: "scope")
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
                "Each subject gets its own blocks a week. Four or five keeps a language moving; a block or two is enough to keep maths going. Reviews only keeps what you know."
            )
            .foregroundStyle(.secondary)
            CoursePicker(settings: $settings, week: $week)
            LoadWarning(warning: warning)
        }
    }

    var schedule: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("When do you study?").font(.title.bold())
                .accessibilityIdentifier("onboarding.scheduleTitle")
            Text(
                "Blocks go in the open parts of your week, around Stadig Lift's days and classes if you use it. Miss one and it moves to the next open part. Tap a part to open or close it."
            )
            .foregroundStyle(.secondary)
            Picker("Block length", selection: Binding(get: { settings.schedule.minutes }, set: { settings.schedule.minutes = $0 })) {
                ForEach(StudySchedule.sessionOptions, id: \.self) { Text("\($0) min").tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("onboarding.sessionLength")
            LoadWarning(warning: warning)
            WeekGrid(cells: previewCells) { week = WeekPlanner.toggling($0.weekday, $0.part, settings: week, commitments: model.commitments) }
        }
    }

    var warning: String? { CourseLoad.warning(settings, week: week, commitments: model.commitments) }

    /// The week these choices make.
    var previewCells: [WeekCell] { WeekPlanner.preview(settings, week: week, commitments: model.commitments, on: week.since) }

    var ready: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your first block").font(.largeTitle.bold())
                .accessibilityIdentifier("onboarding.readyTitle")
            Text(
                "Each subject's first block finds your level, then starts the new material. Answer honestly: “Don't know” is always better than a guess."
            )
            .font(.title3)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(settings.studied) { domain in
                    if let line = firstSession(domain) { Label(line, systemImage: domain.symbol) }
                }
                if !settings.maintenance.isEmpty {
                    Label(
                        "Reviews only: \(ListFormatter.localizedString(byJoining: settings.maintenance.map(\.label)))",
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
        model.completeOnboarding(settings, week: week, booksRead: settings.has(.reading) ? books : [])
    }
}

/// Every course, with how much of it there is in a week.
struct CoursePicker: View {
    @Binding var settings: MindSettings
    @Binding var week: WeekSettings

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
                    CourseAmount(domain: domain, amount: week.amount(domain, settings: settings), identifier: "onboarding.course.\(domain.rawValue)")
                    {
                        week.setAmount($0, for: domain, settings: &settings)
                    }
                }
                .card()
            }
        }
    }
}
