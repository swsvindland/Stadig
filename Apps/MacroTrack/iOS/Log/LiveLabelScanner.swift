import FoodDatabase
import FoodIntelligence
import NutritionEngine
import SwiftUI
import Synchronization
import SystemCore

/// What a live scan ended in.
enum LiveScanOutcome {
    /// The barcode is a food the catalogs (or the person) know.
    case food(Food)
    /// The barcode is a supplement already in the stack, or one the NIH labels know.
    case supplement(Supplement)
    /// A nutrition panel read live, named, with the barcode when one was seen.
    case label(LabelResult, barcode: String?)
    /// A Supplement Facts panel read live, named.
    case supplementLabel(SupplementFacts, barcode: String?)
}

/// Lets one frame through to the reader at a time, at most five a second; the rest are dropped.
nonisolated final class FrameGate: Sendable {
    private let state = Mutex((busy: false, last: Date.distantPast))
    private let interval: TimeInterval

    init(interval: TimeInterval = 0.2) { self.interval = interval }

    func enter() -> Bool {
        state.withLock { s in
            guard !s.busy, Date().timeIntervalSince(s.last) >= interval else { return false }
            s = (true, Date())
            return true
        }
    }

    func leave() { state.withLock { $0.busy = false } }
}

/// A camera frame on its way to the reader, which holds it until it's read.
nonisolated struct FrameBox: @unchecked Sendable {
    let buffer: CVPixelBuffer
}

/// A scan in progress: every frame's text merged into one panel, the barcode if one was seen, and
/// the package's name from its front.
@MainActor @Observable
final class LiveScan {
    nonisolated enum Kind: Sendable { case food, supplement }

    /// What one frame's text says, parsed off the main thread before it's merged: a panel is a
    /// couple of dozen patterns over every box, five times a second.
    nonisolated enum Parsed: Sendable {
        case food(LabelFrame)
        case supplement(SupplementFacts?)

        static func read(_ text: FrameText, as kind: Kind) -> Parsed {
            switch kind {
            case .food: .food(NutritionLabel.frame(boxes: text.boxes))
            case .supplement: .supplement(SupplementLabel.parse(lines: text.lines))
            }
        }
    }

    let kind: Kind
    private(set) var label = LiveLabel()
    private(set) var supplementLabel = LiveSupplementLabel()
    /// A barcode seen that the catalogs don't know; its food is being made from the label.
    private(set) var newBarcode: String?
    /// The latest frame's text, 0–1 of the frame, and the frame's width over height.
    private(set) var regions: [CGRect] = []
    private(set) var frameAspect = 9.0 / 16
    /// Every printed row seen, once, in the order seen: the panel's, and the rest of the package's
    /// (for the name). Apple's model checks them while scanning.
    private(set) var panelLines: [String] = []
    private(set) var otherLines: [String] = []
    private(set) var finished = false
    /// The model's name and brand for the product, once it has checked the text.
    private(set) var modelName: String?
    private(set) var modelBrand: String?
    private(set) var checking = false
    /// Debug builds replay frames instead of using the camera.
    var still: CGImage?

    @ObservationIgnored private var seen = Set<String>()
    @ObservationIgnored private var headlines: [String: Int] = [:]
    @ObservationIgnored private var checkedLines = 0
    @ObservationIgnored private var checkTask: Task<Void, Never>?
    @ObservationIgnored let lookup: (String, Barcode.Symbology?) -> LiveScanOutcome?
    @ObservationIgnored let finish: (LiveScanOutcome) -> Void

    init(kind: Kind, lookup: @escaping (String, Barcode.Symbology?) -> LiveScanOutcome?, finish: @escaping (LiveScanOutcome) -> Void) {
        self.kind = kind
        self.lookup = lookup
        self.finish = finish
    }

    func add(_ text: FrameText, parsed: Parsed, aspect: Double) {
        guard !finished else { return }
        regions = text.regions
        frameAspect = aspect
        if let headline = text.headline { headlines[headline, default: 0] += 1 }
        let panel: Bool
        switch parsed {
        case .food(let frame):
            panel = frame.isPanel
            label.add(frame)
        case .supplement(let facts):
            panel = facts != nil
            supplementLabel.add(facts)
        }
        for line in text.lines where seen.insert(line.lowercased()).inserted {
            if panel {
                if panelLines.count < 200 { panelLines.append(line) }
            } else if otherLines.count < 60 {
                otherLines.append(line)
            }
        }
    }

    // MARK: Apple's model

    /// Has the on-device model check what's been read every couple of seconds while the panel is in
    /// view: its reading of the text counts as two votes on each value, and it names the product.
    func startChecking(_ ai: MealAIService) {
        guard checkTask == nil else { return }
        ai.prewarmCheck(supplement: kind == .supplement)
        checkTask = Task { [weak self] in
            while !Task.isCancelled {
                // A cancelled sleep ends the loop: one more check here would take `checking` and
                // turn away the final check that review is about to start.
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard let self, !self.finished, !Task.isCancelled else { return }
                await self.check(ai, onDeviceOnly: true, minimumNew: 3)
            }
        }
    }

    func stopChecking() {
        checkTask?.cancel()
        checkTask = nil
    }

    /// One check of the text so far, when enough new panel text has come in since the last.
    func check(_ ai: MealAIService, onDeviceOnly: Bool, minimumNew: Int = 1) async {
        let panel = panelLines
        guard !checking, !panel.isEmpty, panel.count >= checkedLines + minimumNew || checkedLines == 0 else { return }
        checking = true
        defer { checking = false }
        let other = Array(otherLines.prefix(20))
        switch kind {
        case .food:
            guard let check = try? await ai.checkLabel(panel: panel, other: other, onDeviceOnly: onDeviceOnly) else { return }
            label.check(values: check.values, servingGrams: check.servingGrams, servingLabel: check.servingLabel)
            modelName = check.name
            modelBrand = check.brand
        case .supplement:
            guard let check = try? await ai.checkSupplement(panel: panel, other: other, onDeviceOnly: onDeviceOnly) else { return }
            supplementLabel.check(check.facts)
            modelName = check.name
            modelBrand = check.brand
        }
        checkedLines = panel.count
    }

    /// Before review: waits for a check under way, then checks whatever came in after it (with
    /// Private Cloud Compute too, when allowed), for at most a few seconds.
    func finalCheck(_ ai: MealAIService) async {
        stopChecking()
        let deadline = Date().addingTimeInterval(10)
        while checking, Date() < deadline { try? await Task.sleep(for: .milliseconds(150)) }
        guard panelLines.count > checkedLines, Date() < deadline else { return }
        _ = await withTimeout(seconds: deadline.timeIntervalSinceNow) { [weak self] in
            await self?.check(ai, onDeviceOnly: false)
            return true
        }
    }

    /// Everything seen, for naming when no check has run.
    var lines: [String] { panelLines + otherLines }

    /// A barcode the camera read: known ones end the scan; a new one is kept for the food the
    /// label makes.
    func barcodeSeen(_ code: String, _ symbology: Barcode.Symbology?) {
        let digits = code.filter(\.isNumber)
        guard !finished, !digits.isEmpty, digits != newBarcode, Barcode.isValid(digits) else { return }
        if let outcome = lookup(digits, symbology) {
            end(outcome)
        } else {
            newBarcode = digits
        }
    }

    func end(_ outcome: LiveScanOutcome) {
        guard !finished else { return }
        finished = true
        stopChecking()
        finish(outcome)
    }

    /// The model's name for the product, else the largest words seen on more than one frame.
    var name: String? {
        modelName ?? headlines.filter { $0.value >= 2 }.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
    }

    var isChecked: Bool { kind == .food ? label.isChecked : supplementLabel.isChecked }

    var ready: Bool { kind == .food ? label.ready : supplementLabel.ready }
    var lockedCount: Int { kind == .food ? label.lockedCount : supplementLabel.lockedCount }
    var panelSeen: Bool { kind == .food ? label.panelFrames > 0 : supplementLabel.panelFrames > 0 }
    var frames: Int { kind == .food ? label.frames : supplementLabel.frames }

    /// The one thing to do next.
    var hint: String {
        let panel = kind == .food ? "Nutrition Facts" : "Supplement Facts"
        if !panelSeen {
            if newBarcode != nil { return "New to the database. Now the \(panel) panel." }
            if frames > 12 { return "Get closer to the \(panel), hold steady and fill the frame with it." }
            return "Point at the barcode or the \(panel)."
        }
        if ready {
            guard kind == .food else { return "Got it. Review, or keep going for the rest of the lines." }
            let more = LiveLabel.secondary.filter { !label.value($0).isLocked }.map(Self.word)
            return more.isEmpty
                ? "Got it. Review when you're ready." : "Got it. Review, or keep going for \(ListFormatter.localizedString(byJoining: more))."
        }
        if kind == .food {
            let missing = label.missingCore.map(Self.word)
            return missing.isEmpty ? "Hold steady on the panel." : "Keep going: still reading \(ListFormatter.localizedString(byJoining: missing))."
        }
        return "Move slowly down the panel, line by line."
    }

    static func word(_ key: String) -> String {
        switch key {
        case "kcal": "calories"
        case "carbs": "carbs"
        case "saturatedFat": "saturated fat"
        default: key
        }
    }
}

/// What a barcode field says where there's no live scanner.
enum ScanWords {
    static var typeTheBarcode: String {
        Platform.isPhoneOrPad
            ? "The camera scanner isn't available here, so type the digits under the barcode."
            : "Type the digits under the barcode."
    }
}

/// Waits at most `seconds` for an answer; nil when it takes longer.
func withTimeout<T: Sendable>(seconds: Double, _ work: @escaping @Sendable () async -> T?) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await work() }
        group.addTask {
            try? await Task.sleep(for: .seconds(seconds))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}

#if os(iOS)
/// Live scanning, like filming the package: the barcode, the front and the panel in one go, with
/// each value filling in as it's read. A tall label is read a slice at a time; a value is trusted
/// once two frames agree on it. Laid out as the design's camera: what's been read as chips over
/// the finder (the camera in a rounded frame, with a reticle until a panel's in view), the label's
/// values on a card under it, and the host's foot (a found food, the shutter) below that.
struct LiveLabelScanner<MenuItems: View, Foot: View>: View {
    @Environment(AppModel.self) private var model
    @State private var scan: LiveScan
    @State private var camera = LiveCamera()
    @State private var torch = false
    @State private var denied = false
    @State private var naming = false
    private let menu: MenuItems
    /// Under the card: given whether the label's card is up, so a host can keep out of its way.
    private let foot: (Bool) -> Foot

    init(
        kind: LiveScan.Kind, lookup: @escaping (String, Barcode.Symbology?) -> LiveScanOutcome?, finish: @escaping (LiveScanOutcome) -> Void,
        @ViewBuilder menu: () -> MenuItems, @ViewBuilder foot: @escaping (_ reading: Bool) -> Foot
    ) {
        _scan = State(initialValue: LiveScan(kind: kind, lookup: lookup, finish: finish))
        self.menu = menu()
        self.foot = foot
    }

    /// The label's card: once a panel or a new barcode is in view, until the scan has ended.
    var reading: Bool { !scan.finished && (scan.panelSeen || scan.newBarcode != nil) }

    var body: some View {
        VStack(spacing: 12) {
            chips
            finder
            if reading { card.transition(.move(edge: .bottom).combined(with: .opacity)) }
            foot(reading)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .animation(.snappy, value: reading)
        .navigationTitle(scan.kind == .food ? "Scan" : "Scan a supplement")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.impact(weight: .light), trigger: scan.lockedCount)
        .sensoryFeedback(.success, trigger: scan.ready) { _, ready in ready }
        .task { await start() }
        .onDisappear {
            camera.stop()
            scan.stopChecking()
        }
    }

    /// What's been read, as the design's camera chips: the barcode, then the panel.
    var chips: some View {
        HStack(spacing: 6) {
            InkChip(title: scan.newBarcode != nil ? "New barcode" : "Barcode", selected: scan.newBarcode != nil || (scan.finished && !scan.panelSeen))
            InkChip(title: scan.kind == .food ? "Label" : "Supplement Facts", selected: scan.panelSeen)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// The camera in its frame, with what it's reading outlined, the reticle while it's looking for
    /// a barcode, the one thing to do next, and the light.
    var finder: some View {
        ZStack {
            preview
            ReadingOverlay(regions: scan.regions, aspect: scan.frameAspect).allowsHitTesting(false)
            if !scan.panelSeen {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(scan.finished ? Color.accentColor : Color.white.opacity(0.6), lineWidth: scan.finished ? 3 : 2)
                    .frame(width: 230, height: 136)
                    .allowsHitTesting(false)
            }
            VStack(spacing: 8) {
                HStack {
                    if MenuItems.self != EmptyView.self {
                        Menu {
                            menu
                        } label: {
                            overCamera("ellipsis")
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .accessibilityLabel("Other ways")
                    }
                    Spacer()
                    if LiveCamera.isAvailable {
                        Button {
                            torch.toggle()
                            camera.setTorch(torch)
                        } label: {
                            overCamera(torch ? "flashlight.on.fill" : "flashlight.off.fill")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(torch ? "Turn the light off" : "Turn the light on")
                    }
                }
                Spacer()
                if let code = scan.newBarcode {
                    Label("Barcode \(code) · new", systemImage: "barcode").font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.black.opacity(0.55), in: .capsule)
                }
                Text(scan.hint)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.55), in: .capsule)
                    .contentTransition(.opacity)
                    .animation(.snappy, value: scan.hint)
            }
            .padding(12)
            if denied {
                ContentUnavailableView(
                    "Camera access is off", systemImage: "camera",
                    description: Text("Allow the camera for Stadig Macro in Settings to scan labels.")
                )
                .background(Ink.surface)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.08))
        .clipShape(.rect(cornerRadius: 30, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scan.finder")
    }

    /// A round button over the camera, dark enough to read on whatever it's pointed at.
    func overCamera(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(.black.opacity(0.45), in: .circle)
            .contentShape(.circle)
    }

    @ViewBuilder
    var preview: some View {
        if let still = scan.still {
            // Filling the frame without widening the layout, centred like the camera's preview.
            Color.black.overlay { Image(decorative: still, scale: 1).resizable().scaledToFill() }.clipped()
        } else if LiveCamera.isAvailable {
            CameraPreview(session: camera.session)
        } else {
            Color.black
        }
    }

    // MARK: The card

    var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(scan.name ?? (scan.kind == .food ? "Reading the label" : "Reading the panel"))
                    .font(.headline).foregroundStyle(Ink.text).lineLimit(1)
                if scan.checking { ProgressView().controlSize(.mini) }
                Spacer(minLength: 4)
                if scan.isChecked {
                    Label("Checked by Apple Intelligence", systemImage: "sparkles").font(.caption2.weight(.medium)).foregroundStyle(Ink.text3)
                        .lineLimit(1)
                }
            }
            switch scan.kind {
            case .food: foodFields
            case .supplement: supplementLines
            }
            Button {
                Task { await review() }
            } label: {
                HStack {
                    if naming { ProgressView().controlSize(.small) }
                    Text(naming ? "Checking…" : "Review")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(InkButtonStyle(filled: scan.ready))
            .controlSize(.large)
            .disabled(naming || !canReview)
            .accessibilityIdentifier("scan.review")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground, in: .rect(cornerRadius: 26, style: .continuous))
    }

    var canReview: Bool {
        scan.kind == .food ? scan.label.reading != nil : scan.supplementLabel.facts != nil
    }

    @ViewBuilder
    var foodFields: some View {
        let label = scan.label
        let serving = label.serving
        if serving.label != nil || serving.grams != nil || serving.milliliters != nil {
            Text(
                "Per serving: \([serving.label, serving.grams.map { "\(Format.number($0)) g" } ?? serving.milliliters.map { "\(Format.number($0)) ml" }].compactMap { $0 }.joined(separator: ", "))"
            )
            .font(.caption).foregroundStyle(Ink.text3)
        }
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                FieldCell(title: "Calories", value: label.value("kcal"), unit: "")
                FieldCell(title: "Fat", value: label.value("fat"), unit: "g")
            }
            GridRow {
                FieldCell(title: "Carbs", value: label.value("carbs"), unit: "g")
                FieldCell(title: "Protein", value: label.value("protein"), unit: "g")
            }
        }
        let others = LiveLabel.secondary.compactMap { key -> String? in
            guard let value = label.value(key).value else { return nil }
            let word = LiveScan.word(key)
            return "\(word.prefix(1).uppercased() + word.dropFirst()) \(Format.number(value))\(key == "sodium" ? " mg" : " g")"
        }
        let extras = label.keys.filter { !LiveLabel.core.contains($0) && !LiveLabel.secondary.contains($0) }.count
        if !others.isEmpty || extras > 0 {
            Text((others + (extras > 0 ? ["+\(extras) more"] : [])).joined(separator: " · ")).font(.caption).foregroundStyle(Ink.text3)
        }
    }

    @ViewBuilder
    var supplementLines: some View {
        let lines = scan.supplementLabel.readLines
        if lines.isEmpty {
            Text("Each line appears here as it's read.").font(.subheadline).foregroundStyle(Ink.text2)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(lines.suffix(6).enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 8) {
                        Image(systemName: line.locked ? "checkmark.circle.fill" : "circle.dotted")
                            .foregroundStyle(line.locked ? Ink.good : Ink.text3)
                        Text(line.ingredient.name).font(.subheadline).foregroundStyle(Ink.text).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(line.ingredient.amountLabel ?? "").font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(line.locked ? Ink.text : Ink.text2)
                    }
                }
                if lines.count > 6 { Text("+\(lines.count - 6) more above").font(.caption).foregroundStyle(Ink.text3) }
            }
        }
    }

    // MARK: Running

    func start() async {
        scan.startChecking(model.ai)
        #if DEBUG
        if LiveScanDemo.enabled {
            await LiveScanDemo.run(scan)
            return
        }
        #endif
        let gate = FrameGate()
        let scan = scan
        let kind = scan.kind
        let started = await camera.start(
            frame: { buffer in
                guard gate.enter() else { return }
                let box = FrameBox(buffer: buffer)
                Task.detached(priority: .userInitiated) {
                    defer { gate.leave() }
                    guard let text = try? await LabelOCR.frame(box.buffer) else { return }
                    let aspect = Double(CVPixelBufferGetWidth(box.buffer)) / Double(max(1, CVPixelBufferGetHeight(box.buffer)))
                    let parsed = LiveScan.Parsed.read(text, as: kind)
                    await scan.add(text, parsed: parsed, aspect: aspect)
                }
            },
            barcode: { code, symbology in
                Task { @MainActor in scan.barcodeSeen(code, symbology) }
            })
        denied = !started
    }

    /// Lets Apple's model check the last of what was read (it also names the product), then hands
    /// the panel on for checking by the person.
    func review() async {
        naming = true
        defer { naming = false }
        camera.stop()
        await scan.finalCheck(model.ai)
        switch scan.kind {
        case .food:
            let result = LabelResult(reading: scan.label.reading, lines: scan.lines, suggestedName: scan.name, brand: scan.modelBrand)
            scan.end(.label(result, barcode: scan.newBarcode))
        case .supplement:
            guard var facts = scan.supplementLabel.facts else { return }
            facts.name = scan.name ?? ""
            facts.brand = scan.modelBrand
            if let code = scan.newBarcode { facts.barcode = Barcode.keys(for: code).first }
            scan.end(.supplementLabel(facts, barcode: scan.newBarcode))
        }
    }
}
#else
/// The live scanner needs a camera the app can drive: iPhone and iPad. The Mac and Vision Pro type
/// the barcode and read a label from a photo instead, so this is never shown there.
struct LiveLabelScanner<MenuItems: View, Foot: View>: View {
    init(
        kind: LiveScan.Kind, lookup: @escaping (String, Barcode.Symbology?) -> LiveScanOutcome?, finish: @escaping (LiveScanOutcome) -> Void,
        @ViewBuilder menu: () -> MenuItems, @ViewBuilder foot: @escaping (_ reading: Bool) -> Foot
    ) {}

    var body: some View { EmptyView() }
}
#endif

extension LiveScan {
    /// Whether the live scanner can run: a camera the app can drive (iPhone and iPad), or the
    /// debug builds' stand-in for one.
    static var isAvailable: Bool {
        #if os(iOS)
        #if DEBUG
        if LiveScanDemo.enabled { return true }
        #endif
        return LiveCamera.isAvailable
        #else
        return false
        #endif
    }
}

#if os(iOS)
/// One of the four core values: read, trusted, or not yet seen.
private struct FieldCell: View {
    let title: String
    let value: LiveValue
    let unit: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: value.isLocked ? "checkmark.circle.fill" : (value.value == nil ? "circle" : "circle.dotted"))
                .foregroundStyle(value.isLocked ? Ink.good : Ink.text3)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(Ink.text3)
                Text(value.value.map { "\(Format.number($0))\(unit.isEmpty ? "" : " \(unit)")" } ?? "—")
                    .numeral(20)
                    .fixedSize()
                    .foregroundStyle(value.isLocked ? Ink.text : Ink.text2)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy, value: value)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value.value.map { Format.number($0) } ?? "not read yet")\(value.isLocked ? ", confirmed" : "")")
    }
}

/// Where text is being read in the latest frame, as faint outlines over the camera.
private struct ReadingOverlay: View {
    let regions: [CGRect]
    let aspect: Double

    var body: some View {
        GeometryReader { proxy in
            // The frame fills the view (aspect fill), so outlines scale and centre the same way.
            let size = proxy.size
            let scale = max(size.width / aspect, size.height)
            let offset = CGPoint(x: (size.width - aspect * scale) / 2, y: (size.height - scale) / 2)
            ForEach(Array(regions.prefix(80).enumerated()), id: \.offset) { _, r in
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.accentColor.opacity(0.7), lineWidth: 1.5)
                    .frame(width: r.width * aspect * scale, height: r.height * scale)
                    .position(x: offset.x + (r.midX) * aspect * scale, y: offset.y + r.midY * scale)
            }
        }
        .animation(.easeOut(duration: 0.2), value: regions)
    }
}
#endif
