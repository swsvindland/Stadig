import SwiftUI
import Synchronization
import FoodDatabase
import FoodIntelligence
import NutritionEngine
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
    enum Kind { case food, supplement }

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

    func add(_ text: FrameText, aspect: Double) {
        guard !finished else { return }
        regions = text.regions
        frameAspect = aspect
        if let headline = text.headline { headlines[headline, default: 0] += 1 }
        let panel: Bool
        switch kind {
        case .food:
            let frame = NutritionLabel.frame(boxes: text.boxes)
            panel = frame.isPanel
            label.add(frame)
        case .supplement:
            let facts = SupplementLabel.parse(lines: text.lines)
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
                try? await Task.sleep(for: .seconds(2))
                guard let self, !self.finished else { return }
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
            return more.isEmpty ? "Got it. Review when you're ready." : "Got it. Review, or keep going for \(ListFormatter.localizedString(byJoining: more))."
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

/// Live scanning, like filming the package: the barcode, the front and the panel in one go, with
/// each value filling in as it's read. A tall label is read a slice at a time; a value is trusted
/// once two frames agree on it.
struct LiveLabelScanner: View {
    @Environment(AppModel.self) private var model
    @State private var scan: LiveScan
    @State private var camera = LiveCamera()
    @State private var torch = false
    @State private var denied = false
    @State private var naming = false

    init(kind: LiveScan.Kind, lookup: @escaping (String, Barcode.Symbology?) -> LiveScanOutcome?, finish: @escaping (LiveScanOutcome) -> Void) {
        _scan = State(initialValue: LiveScan(kind: kind, lookup: lookup, finish: finish))
    }

    static var isAvailable: Bool {
        #if DEBUG
        if LiveScanDemo.enabled { return true }
        #endif
        return LiveCamera.isAvailable
    }

    var body: some View {
        ZStack {
            preview.ignoresSafeArea()
            ReadingOverlay(regions: scan.regions, aspect: scan.frameAspect).ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing: 10) {
                Text(scan.hint)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .floatingGlass(in: Capsule(), interactive: false)
                    .contentTransition(.opacity)
                    .animation(.snappy, value: scan.hint)
                if let code = scan.newBarcode {
                    Label("Barcode \(code) · new", systemImage: "barcode").font(.caption.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .floatingGlass(in: Capsule(), interactive: false)
                }
                Spacer()
                card
            }
            .padding()
            if denied {
                ContentUnavailableView("Camera access is off", systemImage: "camera",
                                       description: Text("Allow the camera for Macro Track in Settings to scan labels."))
                    .background(.background)
            }
        }
        .navigationTitle(scan.kind == .food ? "Scan" : "Scan a supplement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if LiveCamera.isAvailable {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        torch.toggle()
                        camera.setTorch(torch)
                    } label: {
                        Image(systemName: torch ? "flashlight.on.fill" : "flashlight.off.fill")
                    }
                    .accessibilityLabel(torch ? "Turn the light off" : "Turn the light on")
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: scan.lockedCount)
        .sensoryFeedback(.success, trigger: scan.ready) { _, ready in ready }
        .task { await start() }
        .onDisappear {
            camera.stop()
            scan.stopChecking()
        }
    }

    @ViewBuilder
    var preview: some View {
        if let still = scan.still {
            // Filling the screen without widening the layout, centred like the camera's preview.
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
            if let name = scan.name {
                HStack(spacing: 6) {
                    Text(name).font(.headline).lineLimit(1)
                    if scan.checking { ProgressView().controlSize(.mini) }
                }
            }
            if scan.isChecked {
                Label("Checked by Apple Intelligence", systemImage: "sparkles").font(.caption2).foregroundStyle(.secondary)
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
                    Text(naming ? "Checking…" : "Review").font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(scan.ready ? .accentColor : .secondary)
            .disabled(naming || !canReview)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    var canReview: Bool {
        scan.kind == .food ? scan.label.reading != nil : scan.supplementLabel.facts != nil
    }

    @ViewBuilder
    var foodFields: some View {
        let label = scan.label
        let serving = label.serving
        if serving.label != nil || serving.grams != nil || serving.milliliters != nil {
            Text("Per serving: \([serving.label, serving.grams.map { "\(Format.number($0)) g" } ?? serving.milliliters.map { "\(Format.number($0)) ml" }].compactMap { $0 }.joined(separator: ", "))")
                .font(.caption).foregroundStyle(.secondary)
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
            Text((others + (extras > 0 ? ["+\(extras) more"] : [])).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    var supplementLines: some View {
        let lines = scan.supplementLabel.readLines
        if lines.isEmpty {
            Text("Each line appears here as it's read.").font(.subheadline).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(lines.suffix(6).enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 8) {
                        Image(systemName: line.locked ? "checkmark.circle.fill" : "circle.dotted")
                            .foregroundStyle(line.locked ? Color.green : Color.secondary)
                        Text(line.ingredient.name).font(.subheadline).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(line.ingredient.amountLabel ?? "").font(.subheadline.monospacedDigit())
                            .foregroundStyle(line.locked ? .primary : .secondary)
                    }
                }
                if lines.count > 6 { Text("+\(lines.count - 6) more above").font(.caption).foregroundStyle(.secondary) }
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
        let started = await camera.start(frame: { buffer in
            guard gate.enter() else { return }
            let box = FrameBox(buffer: buffer)
            Task.detached(priority: .userInitiated) {
                defer { gate.leave() }
                guard let text = try? await LabelOCR.frame(box.buffer) else { return }
                let aspect = Double(CVPixelBufferGetWidth(box.buffer)) / Double(max(1, CVPixelBufferGetHeight(box.buffer)))
                await scan.add(text, aspect: aspect)
            }
        }, barcode: { code, symbology in
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

/// One of the four core values: read, trusted, or not yet seen.
private struct FieldCell: View {
    let title: String
    let value: LiveValue
    let unit: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: value.isLocked ? "checkmark.circle.fill" : (value.value == nil ? "circle" : "circle.dotted"))
                .foregroundStyle(value.isLocked ? Color.green : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value.value.map { "\(Format.number($0))\(unit.isEmpty ? "" : " \(unit)")" } ?? "—")
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(value.isLocked ? .primary : .secondary)
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
