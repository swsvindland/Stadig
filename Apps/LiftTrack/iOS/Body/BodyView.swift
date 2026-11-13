import Charts
import LiftEngine
import OSLog
import PhotosUI
import SwiftUI
import SystemCore
import UniformTypeIdentifiers

/// Physique on a mesocycle cadence: tape measurements, the ratios that matter, gaps and what
/// the program does about them, and progress photos for your own comparison. Trends and next
/// steps, never appearance.
struct BodyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var measuring = false
    @State private var editing: BodyMeasurements?
    @State private var pickerItem: PhotosPickerItem?
    @State private var pose: ProgressPhoto.Pose = .front
    @State private var importFailed = false
    /// The phone's progress photos, opened from the header's camera.
    @State private var showPhotos = false
    #if DEBUG
    /// `-proportions`: Proportions opened at launch, as its row does.
    @State private var showProportions = false
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                if sizeClass.isWide {
                    wide
                } else {
                    column
                }
            }
            .accessibilityIdentifier("body.screen")
            .background(.pageBackground)
            .safeAreaInset(edge: .bottom) {
                if !sizeClass.isWide { addCheckIn }
            }
            .navigationDestination(isPresented: $showPhotos) { photosPage }
            #if DEBUG
            // `-photos` opens the phone's progress photos, as the header's camera does.
            .onAppear {
                if !sizeClass.isWide, LaunchOptions.current.has("-photos") { showPhotos = true }
                if LaunchOptions.current.has("-proportions") { showProportions = true }
            }
            .navigationDestination(isPresented: $showProportions) {
                if let physique = model.analysis?.physique { proportionsPage(physique) }
            }
            #endif
            .navigationTitle("Body")
            .ownHeader()
            #if os(iOS)
            // Every width draws its own header: the last check-in over a large title.
            .toolbarVisibility(.hidden, for: .navigationBar)
            #endif
            .sessionResumeToolbar()
            #if os(macOS)
            // Continuity Camera: File ▸ Import from iPhone or iPad takes a photo with the phone.
            .importsItemProviders([.image]) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadDataRepresentation(for: .image) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in await importPhoto(data: data) }
                }
                return true
            }
            #endif
            .sheet(isPresented: $measuring) { MeasurementEditor(measurements: BodyMeasurements(day: .today)) }
            .sheet(item: $editing) { m in MeasurementEditor(measurements: m) }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await importPhoto(item) }
            }
            .alert("Couldn't add that photo", isPresented: $importFailed) {
                Button("OK") {}
            } message: {
                Text("It couldn't be read. Try it again, or another photo.")
            }
        }
    }

    // MARK: The phone

    /// The phone's Body, as the design has it: Physique and waist to height, the waist over the
    /// weeks, the latest tape in a row, and the rest (proportions, photos, every check-in) as rows,
    /// with Add check-in at the foot.
    private var column: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let physique = model.analysis?.physique, physique.score != nil || physique.waistToHeight != nil {
                VStack(alignment: .leading, spacing: 11) { hero(physique) }
                    .card(padding: 16)
            }
            waistTrend
            latestTape
            RowCard {
                if let physique = model.analysis?.physique {
                    NavigationLink {
                        proportionsPage(physique)
                    } label: {
                        LinkRowLabel(title: "Proportions", caption: proportionsLine(physique))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("body.proportions")
                }
                Button {
                    showPhotos = true
                } label: {
                    LinkRowLabel(title: "Progress photos", caption: photosLine)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("body.photos")
            }
            history
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .readableWidth()
    }

    /// The phone's Body laid out for width: Physique and the waist over the weeks on the left; the
    /// latest tape, proportions, photos and every check-in beside them, with Add check-in.
    private var wide: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    if let physique = model.analysis?.physique, physique.score != nil || physique.waistToHeight != nil {
                        VStack(alignment: .leading, spacing: 11) { hero(physique) }
                            .card(padding: 16)
                    }
                    waistTrend
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 12) {
                    latestTape
                    RowCard {
                        if let physique = model.analysis?.physique {
                            NavigationLink {
                                proportionsPage(physique)
                            } label: {
                                LinkRowLabel(title: "Proportions", caption: proportionsLine(physique))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("body.proportions")
                        }
                        Button {
                            showPhotos = true
                        } label: {
                            LinkRowLabel(title: "Progress photos", caption: photosLine)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("body.photos")
                    }
                    history
                    Button {
                        measuring = true
                    } label: {
                        Label("Add check-in", systemImage: "plus").frame(maxWidth: .infinity)
                    }
                    .primaryAction()
                    .controlSize(.large)
                    .help("Add tape measurements")
                    .accessibilityIdentifier("body.addMeasurements")
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: 1180)
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        PageHeader(eyebrow: model.measurements.map(\.day).max().map { "Last check-in \(Self.when($0, today: model.today))" }, title: "Body") {
            CircleIconButton(symbol: "camera", label: "Progress photos", identifier: "body.openPhotos") { showPhotos = true }
        }
    }

    /// "Saturday" within the week, "10 Nov" before it.
    private static func when(_ day: Day, today: Day) -> String {
        let days = day.days(until: today)
        if days == 0 { return "today" }
        return days < 7 ? Format.day(day, style: .dateTime.weekday(.wide)) : Format.day(day, style: .dateTime.day().month(.abbreviated))
    }

    /// The one action, over the tab bar: a check-in with the tape.
    private var addCheckIn: some View {
        Button {
            measuring = true
        } label: {
            Label("Add check-in", systemImage: "plus").frame(maxWidth: .infinity)
        }
        .primaryAction()
        .controlSize(.large)
        .shadow(color: .black.opacity(0.3), radius: 15, y: 10)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .readableWidth()
        .accessibilityIdentifier("body.addMeasurements")
    }

    /// The latest tape, five numbers in a row, each with its change since the first check-in.
    @ViewBuilder
    private var latestTape: some View {
        let fields: [(String, (BodyMeasurements) -> Double?)] = [
            ("Chest", { $0.chestCm }), ("Waist", { $0.waistCm }), ("Hips", { $0.hipsCm }), ("Arm", { $0.size(.arm) }), ("Thigh", { $0.size(.thigh) }),
        ]
        let length = model.units.length
        let readings = fields.compactMap { name, read -> (name: String, value: Double, change: Double?)? in
            let values = model.measurements.sorted { $0.day < $1.day }.compactMap(read)
            guard let last = values.last else { return nil }
            return (name, last, values.count > 1 ? last - values[0] : nil)
        }
        if !readings.isEmpty {
            HStack(alignment: .top) {
                ForEach(Array(readings.enumerated()), id: \.offset) { index, reading in
                    if index > 0 { Spacer(minLength: 4) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(reading.name).font(.caption).foregroundStyle(Ink.text3)
                        Text(Format.number(length.fromCentimetres(reading.value))).numeral(18).foregroundStyle(Ink.text)
                        if let change = reading.change {
                            let shown = length.fromCentimetres(change)
                            Text(shown == 0 ? "0" : "\(shown > 0 ? "+" : "−")\(Format.number(abs(shown)))")
                                .font(.caption.monospacedDigit())
                                // A smaller waist is the change that's good news; the rest just are.
                                .foregroundStyle(reading.name == "Waist" && change < 0 ? Ink.good : Ink.text3)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.cardBackground, in: .rect(cornerRadius: 18, style: .continuous))
            .accessibilityIdentifier("body.latest")
        }
    }

    private func proportionsLine(_ p: PhysiqueAnalysis) -> String {
        if p.latest == nil { return "Measure once a block, at the deload check-in" }
        var parts = [p.targets == .off ? "Targets off" : "\(p.targets.label) targets"]
        if !p.asymmetries.isEmpty { parts.append("a side lagging") }
        if !p.gaps.isEmpty { parts.append("\(p.gaps.count) to work on") }
        return parts.joined(separator: " · ")
    }

    private var photosLine: String {
        let count = model.photos.count
        return count == 0 ? "For your own comparison, never analysed" : "\(count) \(count == 1 ? "photo" : "photos")"
    }

    /// Proportions, left against right and what the program does about them: Body's detail.
    private func proportionsPage(_ p: PhysiqueAnalysis) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                DetailHeader(eyebrow: "Body", title: "Proportions")
                proportions(p).card()
                sides(p)
                if !p.gaps.isEmpty || p.proportions.contains(where: { $0.cause == .fat }) { gaps(p) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .readableWidth()
        }
        .background(.pageBackground)
        .detailPage(title: "Proportions", wide: sizeClass.isWide)
    }

    private var photosPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if sizeClass.isWide {
                    // Two of a pose side by side, large; drop an image on it to add one.
                    PhotoComparison(pose: $pose, pickerItem: $pickerItem) { data in await importPhoto(data: data) }
                } else {
                    DetailHeader(eyebrow: "Body", title: "Progress photos")
                    photos
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .readableWidth(sizeClass.isWide ? 1100 : 720)
        }
        .background(.pageBackground)
        .safeAreaInset(edge: .bottom) {
            if !sizeClass.isWide { addPhoto }
        }
        .detailPage(title: "Progress photos", wide: sizeClass.isWide)
    }

    /// The phone's one action on its photos, at the foot as Body's Add check-in is: a photo of the
    /// pose shown.
    private var addPhoto: some View {
        let title = "Add a \(pose.rawValue) photo"
        return PhotosPicker(selection: $pickerItem, matching: .images) {
            Label(title, systemImage: "plus").frame(maxWidth: .infinity)
        }
        .primaryAction()
        .controlSize(.large)
        .shadow(color: .black.opacity(0.3), radius: 15, y: 10)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .readableWidth()
        .accessibilityLabel("Add a progress photo")
        .accessibilityIdentifier("body.addPhoto")
    }

    /// Physique's score on a ruler, and waist to height against the healthy line.
    @ViewBuilder
    private func hero(_ p: PhysiqueAnalysis) -> some View {
        if let score = p.score {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Physique").eyebrow()
                        Text("\(Int(score.rounded()))").numeral(60, weight: .heavy).foregroundStyle(Ink.text)
                    }
                    Spacer(minLength: 8)
                    if let trend = model.stats.first(where: { $0.stat == .physique }).flatMap({ TrendWord($0.trend) }) {
                        TrendChip(trend: trend).padding(.bottom, 4)
                    }
                }
                Ruler(value: score / 100)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Physique \(Int(score.rounded())) of 100")
            if p.waistToHeight != nil { Rectangle().fill(Ink.hairline).frame(height: 1) }
        }
        if let wth = p.waistToHeight {
            let healthy = wth < 0.5
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Waist to height").font(.body.weight(.semibold)).foregroundStyle(Ink.text)
                        Text("Under 0.50 is healthy").font(.caption).foregroundStyle(Ink.text2)
                    }
                    Spacer()
                    Text(Format.number(wth, digits: 2)).numeral(30).foregroundStyle(healthy ? Ink.good : Ink.ok)
                }
                Ruler(value: (wth - 0.4) / 0.2, color: healthy ? Ink.good : Ink.ok, marker: 0.5)
                HStack {
                    Text("0.40")
                    Spacer()
                    Text("0.50").foregroundStyle(Ink.text)
                    Spacer()
                    Text("0.60")
                }
                .font(.caption2.weight(.semibold).monospacedDigit()).foregroundStyle(Ink.text3)
                .accessibilityHidden(true)
            }
            .padding(.top, 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Waist to height \(Format.number(wth, digits: 2)). Under 0.50 is healthy.")
        }
    }

    /// The ratios against their targets, body fat, FFMI and the waist, or how to start measuring.
    private func proportions(_ p: PhysiqueAnalysis) -> some View {
        let length = model.units.length
        let sex = model.profile?.sex ?? .unspecified
        return VStack(alignment: .leading, spacing: 12) {
            // Under the page's own title: the card says what's in it, not the page's name again.
            SectionEyebrow("Ratios", detail: p.targets == .off ? "Proportion targets off" : "\(p.targets.label) targets")
            if p.latest == nil {
                Text("Measure once a block, at the deload check-in. It takes a few minutes with a tape.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button {
                    measuring = true
                } label: {
                    Label("Add measurements", systemImage: "ruler").frame(maxWidth: .infinity)
                }.primaryAction()
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    ForEach(p.proportions) { reading in
                        GridRow {
                            Text(reading.rule.label).foregroundStyle(.secondary)
                            Text(Format.number(reading.value, digits: 2)).monospacedDigit()
                            Text(caption(reading, sex: sex)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let bf = p.bodyFatPercent {
                        let source =
                            switch p.bodyFatSource {
                            case .health: "from Health"
                            case .entered: "entered"
                            case .tape, nil: "tape estimate, a soft signal"
                            }
                        GridRow {
                            Text("Body fat").foregroundStyle(.secondary)
                            Text("\(Format.number(bf))%").monospacedDigit()
                            Text(source).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let ffmi = p.normalizedFFMI, let band = p.ffmiBand {
                        GridRow {
                            Text("FFMI").foregroundStyle(.secondary)
                            Text(Format.number(ffmi, digits: 1)).monospacedDigit()
                            Text(band.label.lowercased() + (p.bodyFatEstimated ? ", about ±1" : "")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let latest = p.latest {
                        GridRow {
                            Text("Waist").foregroundStyle(.secondary)
                            Text(Format.length(latest.waistCm, unit: length))
                            Text(p.waistTrend.map { "\($0 > 0 ? "+" : "")\(Format.length($0, unit: length)) since first" } ?? "").font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.subheadline)
            }
        }
    }

    /// Left against right for each limb measured on both sides, and any side that's lagging.
    @ViewBuilder
    private func sides(_ p: PhysiqueAnalysis) -> some View {
        let limbs = Limb.allCases.compactMap { limb in p.latest?.sides(limb).map { (limb, $0) } }
        if !limbs.isEmpty {
            let length = model.units.length
            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow("Left and right")
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("")
                        Text("Left").font(.caption).foregroundStyle(.secondary)
                        Text("Right").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(limbs, id: \.0) { item in
                        let lagging = p.asymmetries.first { $0.limb == item.0 }?.smaller
                        GridRow {
                            Text(item.0.label).foregroundStyle(.secondary)
                            Text(Format.length(item.1.left, unit: length)).monospacedDigit().fontWeight(lagging == .left ? .semibold : nil)
                            Text(Format.length(item.1.right, unit: length)).monospacedDigit().fontWeight(lagging == .right ? .semibold : nil)
                        }
                    }
                }
                .font(.subheadline)
                if p.asymmetries.isEmpty {
                    Text("Even enough: a centimetre or so either way is normal, and tape readings vary that much.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(p.asymmetries) { asymmetry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(asymmetry.finding).font(.caption).foregroundStyle(.secondary)
                        Label(asymmetry.action, systemImage: "arrow.right.circle").font(.caption)
                    }
                }
            }
            .card()
        }
    }

    private func caption(_ reading: ProportionReading, sex: BiologicalSex) -> String {
        switch reading.cause {
        case .fat: "fat loss closes it"
        case .build: "target \(reading.rule.targetText(sex: sex))"
        case nil: reading.magnitude == 0 ? "on target" : "target \(reading.rule.targetText(sex: sex))"
        }
    }

    private func gaps(_ p: PhysiqueAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow("What the program does about it")
            ForEach(p.gaps) { gap in
                VStack(alignment: .leading, spacing: 2) {
                    Text(gap.region.label).font(.subheadline.weight(.semibold))
                    Text(gap.finding).font(.caption).foregroundStyle(.secondary)
                    Label(gap.action, systemImage: "arrow.right.circle").font(.caption)
                }
            }
            // Gaps the waist drives: the nutrition phase closes them, not extra volume.
            ForEach(p.proportions.filter { $0.cause == .fat }) { reading in
                VStack(alignment: .leading, spacing: 2) {
                    Text(reading.rule.label).font(.subheadline.weight(.semibold))
                    Text(reading.finding).font(.caption).foregroundStyle(.secondary)
                    if let action = reading.action { Label(action, systemImage: "arrow.right.circle").font(.caption) }
                }
            }
            if model.settings.autoPrioritise == false {
                Text("Auto-prioritisation is off, so the next block won't act on these.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    /// The waist over the weeks: the latest large, its line from the first check-in, and a sentence
    /// on how fast it's moving.
    @ViewBuilder
    private var waistTrend: some View {
        let length = model.units.length
        let points = model.measurements.sorted { $0.day < $1.day }.compactMap { m in m.waistCm.map { (day: m.day, value: length.fromCentimetres($0)) }
        }
        if points.count >= 2, let first = points.first, let last = points.last {
            let weeks = max(1, Int((Double(first.day.days(until: last.day)) / 7).rounded()))
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Waist").font(.callout.weight(.semibold)).foregroundStyle(Ink.text)
                        Text("\(weeks) \(weeks == 1 ? "week" : "weeks")").font(.caption).foregroundStyle(Ink.text3)
                    }
                    Spacer()
                    Measure(value: Format.number(last.value), unit: length.symbol, size: 30)
                }
                Chart {
                    ForEach(points, id: \.day) { point in
                        LineMark(x: .value("Day", point.day.date()), y: .value("Waist", point.value))
                            .foregroundStyle(Color.accentColor)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    }
                    PointMark(x: .value("Day", first.day.date()), y: .value("Waist", first.value))
                        .symbol { Circle().strokeBorder(Ink.text3, lineWidth: 2).background(Circle().fill(Ink.surface)).frame(width: 8, height: 8) }
                    PointMark(x: .value("Day", last.day.date()), y: .value("Waist", last.value))
                        .symbol {
                            Circle().fill(Color.accentColor).overlay { Circle().stroke(Ink.surface, lineWidth: 2) }.frame(width: 10, height: 10)
                        }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(Ink.hairline)
                        AxisValueLabel().font(.system(size: 10, weight: .semibold)).foregroundStyle(Ink.text3)
                    }
                }
                .frame(height: sizeClass.isWide ? 240 : 96)
                .accessibilityLabel("Waist over \(weeks) weeks")
                .accessibilityValue("From \(Format.number(first.value)) to \(Format.number(last.value)) \(length.symbol)")
                HStack {
                    Text(Format.day(first.day, style: .dateTime.day().month(.abbreviated)))
                    Spacer()
                    Text(last.day == model.today ? "Today" : Format.day(last.day, style: .dateTime.day().month(.abbreviated)))
                }
                .font(.system(size: 10, weight: .semibold)).textCase(.uppercase).tracking(0.6).foregroundStyle(Ink.text3)
                .padding(.trailing, 28)
                .accessibilityHidden(true)
                waistSentence(change: last.value - first.value, weeks: weeks, unit: length.symbol)
                    .padding(.top, 2)
            }
            .card(padding: 16)
        }
    }

    /// "Down 3.5 cm in 12 weeks, about 0.3 a week."
    private func waistSentence(change: Double, weeks: Int, unit: String) -> some View {
        let size = Format.number(abs(change))
        let lead =
            change == 0
            ? "Level over \(weeks) \(weeks == 1 ? "week" : "weeks")."
            : "\(change < 0 ? "Down" : "Up") \(size) \(unit) in \(weeks) \(weeks == 1 ? "week" : "weeks"),"
        let rate = change == 0 ? "" : " about \(Format.number(abs(change) / Double(weeks))) a week."
        let first = Text(lead).foregroundStyle(Ink.text).fontWeight(.semibold)
        let second = Text(rate).foregroundStyle(Ink.text2)
        return Text("\(first)\(second)")
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The phone's photos: the pose to show, the first and the latest of it side by side, and every
    /// one of it in a strip. For the person's own comparison; nothing reads them.
    private var photos: some View {
        let shown = model.photos.filter { $0.pose == pose }
        return VStack(alignment: .leading, spacing: 12) {
            InkSegmented(options: ProgressPhoto.Pose.allCases.map { (value: $0, label: $0.rawValue.capitalized) }, selection: $pose)
                .accessibilityLabel("Pose")
            if shown.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No \(pose.rawValue) photos yet").font(.callout.weight(.semibold)).foregroundStyle(Ink.text)
                    Text(
                        "Same light, same spot, same time of day, once a block. They're for your own comparison: never analysed or used as a measure."
                    )
                    .font(.subheadline).foregroundStyle(Ink.text2).fixedSize(horizontal: false, vertical: true)
                }
                .card()
            } else {
                if let first = shown.first, let last = shown.last, first.id != last.id {
                    HStack(alignment: .top, spacing: 8) {
                        photo(first, title: "First", maxPixel: 720)
                        photo(last, title: "Latest", maxPixel: 720)
                    }
                    .card(padding: 12)
                }
                VStack(alignment: .leading, spacing: 8) {
                    SectionEyebrow("Every \(pose.rawValue) photo", detail: "\(shown.count)")
                        .padding(.horizontal, 4)
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 8) {
                            ForEach(shown.reversed()) { p in
                                photo(p, title: nil, maxPixel: 360).frame(width: 90)
                                    .contextMenu { Button("Delete", systemImage: "trash", role: .destructive) { model.delete(photo: p.id) } }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                }
                Text("Touch and hold a photo to delete it. They're never analysed or used as a measure.")
                    .font(.caption).foregroundStyle(Ink.text3).padding(.horizontal, 4)
            }
        }
    }

    /// A photo with its day under it, and what it is ("First", "Latest") over the day when it says.
    private func photo(_ p: ProgressPhoto, title: String?, maxPixel: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressPhotoImage(photo: p, maxPixel: maxPixel)
                .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 240).clipped()
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("Progress photo, \(Format.day(p.day))")
            HStack(spacing: 4) {
                if let title { Text(title).eyebrow() }
                Text(Format.day(p.day, style: .dateTime.month(.abbreviated).day().year())).font(.caption2).foregroundStyle(Ink.text3)
            }
            .lineLimit(1)
        }
    }

    /// Every check-in, newest first, each opening to correct it.
    private var history: some View {
        RowCard(title: "Check-ins", minHeight: 48) {
            ForEach(model.measurements.reversed()) { m in
                Button {
                    editing = m
                } label: {
                    LinkRowLabel(
                        title: Format.day(m.day, style: .dateTime.month(.abbreviated).day().year()),
                        caption: [
                            m.waistCm.map { "waist \(Format.length($0, unit: model.units.length))" },
                            m.shouldersCm.map { "shoulders \(Format.length($0, unit: model.units.length))" },
                            m.weightKg.map { Format.weight($0, unit: model.units.weight) },
                        ].compactMap { $0 }.joined(separator: " · "))
                }
                .buttonStyle(.plain)
                .hoverHighlight()
                .contextMenu {
                    Button("Edit…", systemImage: "pencil") { editing = m }
                    Button("Delete", systemImage: "trash", role: .destructive) { model.delete(measurement: m.id) }
                }
                .accessibilityIdentifier("body.measurement")
            }
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        // The pose it was picked for, even if the person changes it while iCloud downloads it.
        let pose = pose
        // Cleared whatever happens, so picking the same photo again tries again.
        defer { pickerItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let jpeg = await ProgressPhotos.jpeg(from: data) else {
                importFailed = true
                return
            }
            model.save(photo: ProgressPhoto(day: .today, pose: pose, jpeg: jpeg))
        } catch {
            appLog.error("Couldn't load a progress photo: \(error.localizedDescription)")
            importFailed = true
        }
    }

    /// A photo dropped on the window, or taken with the iPhone through Continuity Camera.
    private func importPhoto(data: Data) async {
        let pose = pose
        guard let jpeg = await ProgressPhotos.jpeg(from: data) else {
            importFailed = true
            return
        }
        model.save(photo: ProgressPhoto(day: .today, pose: pose, jpeg: jpeg))
    }
}

/// An image dropped from Finder, Photos or another app.
struct DroppedImage: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { DroppedImage(data: $0) }
    }
}

/// Progress photos on a wide screen: two of one pose side by side, large, chosen by date (the
/// first and the latest to start with), above every photo of it. Drop an image to add one.
private struct PhotoComparison: View {
    @Environment(AppModel.self) private var model
    @Binding var pose: ProgressPhoto.Pose
    @Binding var pickerItem: PhotosPickerItem?
    let add: (Data) async -> Void
    @State private var before: UUID?
    @State private var after: UUID?
    @State private var dropping = false

    var body: some View {
        let shown = model.photos.filter { $0.pose == pose }
        let left = shown.first { $0.id == before } ?? shown.first
        let right = shown.first { $0.id == after } ?? shown.last
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                CardTitle("Progress photos")
                Spacer()
                InkSegmented(options: ProgressPhoto.Pose.allCases.map { (value: $0, label: $0.rawValue.capitalized) }, selection: $pose)
                    .frame(width: 240)
                    .accessibilityLabel("Pose")
                PhotosPicker(selection: $pickerItem, matching: .images) { Label("Add Photo", systemImage: "plus") }
                    .secondaryAction()
                    .controlSize(.small)
                    .accessibilityIdentifier("body.addPhoto")
            }
            if shown.isEmpty {
                Text(
                    "For your own comparison only. Photos are never analysed or used as a measure. Add one, or drop an image here\(Platform.isMac ? "; File ▸ Import from iPhone takes one with your phone" : "")."
                )
                .font(.subheadline).foregroundStyle(Ink.text2)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    if let left { side(left, selection: $before, in: shown, title: "Before") }
                    if let right, right.id != left?.id { side(right, selection: $after, in: shown, title: "After") }
                }
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 8) {
                        ForEach(shown) { p in
                            ProgressPhotoImage(photo: p, maxPixel: 360)
                                .frame(width: 90, height: 120).clipShape(.rect(cornerRadius: 10))
                                .accessibilityLabel("Progress photo, \(Format.day(p.day))")
                                .contextMenu {
                                    Button("Compare as Before") { before = p.id }
                                    Button("Compare as After") { after = p.id }
                                    Divider()
                                    Button("Delete", systemImage: "trash", role: .destructive) { model.delete(photo: p.id) }
                                }
                        }
                    }
                }
            }
        }
        .card()
        .overlay {
            if dropping { RoundedRectangle(cornerRadius: 22).strokeBorder(Color.accentColor, lineWidth: 3) }
        }
        .dropDestination(for: DroppedImage.self) { items, _ in
            guard let item = items.first else { return false }
            Task { await add(item.data) }
            return true
        } isTargeted: {
            dropping = $0
        }
        .onChange(of: pose) {
            before = nil
            after = nil
        }
    }

    private func side(_ photo: ProgressPhoto, selection: Binding<UUID?>, in shown: [ProgressPhoto], title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(title, selection: Binding(get: { selection.wrappedValue ?? photo.id }, set: { selection.wrappedValue = $0 })) {
                ForEach(shown) { Text(Format.day($0.day, style: .dateTime.month(.abbreviated).day().year())).tag($0.id) }
            }
            .pickerStyle(.menu)
            .valueTint()
            ProgressPhotoImage(photo: photo, maxPixel: 1400)
                .frame(maxWidth: .infinity).frame(height: 440).clipped()
                .clipShape(.rect(cornerRadius: 14))
                .accessibilityLabel("\(title): progress photo, \(Format.day(photo.day))")
        }
        .frame(maxWidth: .infinity)
    }
}

/// Progress photo pixels, off the main actor. ImageIO decodes straight to the size asked for, so
/// a 24 MP original is never held in full; the same on every platform (`ImageData`).
enum ProgressPhotos {
    /// What's stored: at most 1400 pixels on the long side, enough to compare and light to sync.
    @concurrent nonisolated static func jpeg(from data: Data) async -> Data? {
        ImageData.resizedJPEG(data, maxPixels: 1400, quality: 0.7)
    }

    /// For the screen, at about the pixels it's shown at.
    @concurrent nonisolated static func image(from data: Data, maxPixel: Int) async -> CGImage? {
        ImageData.downsampled(data, maxPixels: maxPixel)
    }

    /// Decoded once per photo and size: the Body tab re-renders on every reload.
    static let cache = NSCache<NSString, CGImage>()

    static func key(_ photo: ProgressPhoto, maxPixel: Int) -> NSString { "\(photo.id.uuidString)-\(maxPixel)" as NSString }
}

/// One progress photo, decoded off the main actor at the size it's shown and kept in the cache.
struct ProgressPhotoImage: View {
    let photo: ProgressPhoto
    let maxPixel: Int
    @State private var image: CGImage?

    init(photo: ProgressPhoto, maxPixel: Int) {
        self.photo = photo
        self.maxPixel = maxPixel
        _image = State(initialValue: ProgressPhotos.cache.object(forKey: ProgressPhotos.key(photo, maxPixel: maxPixel)))
    }

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                Rectangle().fill(.secondary.opacity(0.12))
            }
        }
        .task(id: photo.id) {
            guard image == nil, let decoded = await ProgressPhotos.image(from: photo.jpeg, maxPixel: maxPixel) else { return }
            ProgressPhotos.cache.setObject(decoded, forKey: ProgressPhotos.key(photo, maxPixel: maxPixel))
            image = decoded
        }
    }
}

struct MeasurementEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var measurements: BodyMeasurements

    var body: some View {
        let unit = model.units.length
        NavigationStack {
            Form {
                FormHeading(
                    eyebrow: isStored ? "Body · \(Format.day(measurements.day))" : "Body · check-in", title: "Measurements",
                    detail: "In the morning, before eating or training, the tape snug but not pressing in. Skip any you like.")
                Group {
                    DatePicker(
                        "Day", selection: Binding(get: { measurements.day.date() }, set: { measurements.day = Day($0) }), in: ...Date(),
                        displayedComponents: .date)
                    Section {
                        NavigationLink("Where the tape goes") { MeasuringGuide() }
                    }
                    Section {
                        MeasureField(label: "Neck", value: $measurements.neckCm, unit: unit)
                        MeasureField(label: "Shoulders", value: $measurements.shouldersCm, unit: unit)
                        MeasureField(label: "Chest", value: $measurements.chestCm, unit: unit)
                        MeasureField(label: "Waist at the navel", value: $measurements.waistCm, unit: unit, identifier: "measurements.waist")
                        MeasureField(label: "Waist at its narrowest", value: $measurements.naturalWaistCm, unit: unit)
                        MeasureField(label: "Hips, at the hip bones", value: $measurements.hipsCm, unit: unit)
                        MeasureField(label: "Glutes, at the widest", value: $measurements.glutesCm, unit: unit)
                    } header: {
                        Text("Torso").eyebrow()
                    } footer: {
                        Text("The waist at the navel matters most: leanness and the nutrition phase come from it.")
                    }
                    Section {
                        ForEach(Limb.allCases) { limb in
                            let keys = BodyMeasurements.sides(limb)
                            SidesField(
                                label: limb == .arm ? "Upper arm, flexed" : limb.label, left: $measurements[dynamicMember: keys.left],
                                right: $measurements[dynamicMember: keys.right], unit: unit)
                        }
                    } header: {
                        Text("Arms and legs").eyebrow()
                    } footer: {
                        Text("Both sides, so a side that's lagging shows up.")
                    }
                    let unsided = Limb.allCases.filter { measurements[keyPath: BodyMeasurements.unsided($0)] != nil }
                    if !unsided.isEmpty {
                        Section {
                            ForEach(unsided) { limb in
                                MeasureField(label: limb.label, value: $measurements[dynamicMember: BodyMeasurements.unsided(limb)], unit: unit)
                            }
                        } header: {
                            Text("Before sides were measured").eyebrow()
                        }
                    }
                    Section {
                        WeightField(label: "Body weight", kg: $measurements.weightKg, unit: model.units.weight)
                        HStack {
                            Text("Body fat")
                            Spacer()
                            TextField("—", value: $measurements.bodyFatPercent, format: .number.precision(.fractionLength(0...1)))
                                .fieldKeyboard(.decimal).multilineTextAlignment(.trailing).frame(width: 80)
                            Text("%").foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("Weight usually comes from Apple Health or Stadig Macro.")
                    }
                }
                .inkRows()
                if isStored {
                    Section {
                        FormActionRow("Delete", destructive: true, identifier: "measurements.delete") {
                            model.delete(measurement: measurements.id)
                            dismiss()
                        }
                    }
                }
            }
            .inkList()
            .inkSheet {
                SheetBar(label: "Cancel", identifier: "measurements.cancel") { dismiss() }
            } foot: {
                SheetFoot {
                    Button {
                        model.save(measurements: measurements)
                        dismiss()
                    } label: {
                        Text("Save").frame(maxWidth: .infinity)
                    }
                    .primaryAction()
                    .keyboardShortcut(.defaultAction)
                    .disabled(measurements.isEmpty)
                    .accessibilityIdentifier("measurements.save")
                }
            }
        }
        .sheetFrame()
    }

    /// A check-in already kept, opened to change: it can be deleted.
    private var isStored: Bool { model.measurements.contains { $0.id == measurements.id } }
}

/// Left and right on one row, in the person's unit, stored in centimetres.
struct SidesField: View {
    let label: String
    @Binding var left: Double?
    @Binding var right: Double?
    let unit: LengthUnit

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
            Spacer()
            side("L", "Left", $left)
            side("R", "Right", $right)
            Text(unit.symbol).foregroundStyle(.secondary)
        }
    }

    private func side(_ short: String, _ name: String, _ value: Binding<Double?>) -> some View {
        HStack(spacing: 4) {
            Text(short).font(.caption).foregroundStyle(.secondary)
            TextField(
                "—",
                value: Binding(
                    get: { value.wrappedValue.map { (unit.fromCentimetres($0) * 10).rounded() / 10 } },
                    set: { value.wrappedValue = $0.map(unit.toCentimetres) }),
                format: .number.precision(.fractionLength(0...1))
            )
            .fieldKeyboard(.decimal)
            // Next to its letter, so each value reads as that side's.
            .multilineTextAlignment(.leading)
            .frame(width: 52)
            .accessibilityLabel("\(name) \(label.lowercased())")
        }
    }
}

/// Where each tape measurement goes, so every check-in is taken the same way.
struct MeasuringGuide: View {
    var body: some View {
        List {
            if !Platform.isMac { FormHeading(eyebrow: "Measurements", title: "Where the tape goes") }
            Section {
                Text(
                    "In the morning, before eating or training. Keep the tape level and snug on the skin without pressing in, and breathe out normally before reading it. The same way every time matters more than any one reading."
                )
                .font(.subheadline)
            }
            Section {
                site("Neck", "Just below the larynx, the tape sloping slightly down at the front.")
                site("Shoulders", "Around the widest point of the shoulders, arms relaxed at your sides.")
                site("Chest", "Level with the nipples.")
                site("Waist at the navel", "Level with the navel, relaxed, not sucked in.")
                site("Waist at its narrowest", "The narrowest point between the ribs and the hips.")
                site("Hips", "Around the top of the hip bones.")
                site("Glutes", "Around the widest point of the buttocks, feet together.")
            } header: {
                Text("Torso").eyebrow()
            }
            Section {
                site("Upper arm", "Flexed, at the peak of the biceps, with the arm raised to shoulder height.")
                site("Thigh", "Standing, just below the fold under the glutes.")
                site("Calf", "Standing, at the widest point.")
            } header: {
                Text("Arms and legs").eyebrow()
            }
            Section {
                Text(
                    "A centimetre between sides is normal, and a reading can vary that much. The program only acts on a difference that shows at two check-ins at least two weeks apart."
                )
                .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .inkRows()
        .inkList()
        .formPage("Where the tape goes")
    }

    private func site(_ name: String, _ how: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.subheadline.weight(.semibold))
            Text(how).font(.caption).foregroundStyle(.secondary)
        }
    }
}
