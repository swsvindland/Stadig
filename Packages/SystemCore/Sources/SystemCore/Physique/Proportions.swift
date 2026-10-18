import Foundation

/// Which proportions the program works toward. The default follows "Standards for"; the person
/// can pick another or turn them off.
public enum ProportionTargets: String, CaseIterable, Codable, Sendable, Identifiable {
    case vTaper, hourglass, leannessOnly, off

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .vTaper: "V-taper"
        case .hourglass: "Hourglass"
        case .leannessOnly: "Leanness only"
        case .off: "Off"
        }
    }

    public var detail: String {
        switch self {
        case .vTaper: "Shoulders, chest and arms against the waist, with thigh to calf."
        case .hourglass: "Waist against the glutes, shoulders balanced with them, and thigh to calf."
        case .leannessOnly: "No torso ratios: just thigh to calf, with leanness guiding the nutrition phase."
        case .off: "No ratio targets. Leanness still guides the nutrition phase."
        }
    }

    public static func standard(for sex: BiologicalSex) -> ProportionTargets {
        switch sex {
        case .male: .vTaper
        case .female: .hourglass
        case .unspecified: .leannessOnly
        }
    }

    /// The rules each set checks, most telling first.
    public func rules(sex: BiologicalSex) -> [ProportionRule] {
        switch self {
        // Chest measures muscle against the waist only where there's no breast tissue in it.
        case .vTaper: [.shoulderToWaist, .chestToWaist, .armToNeck, .thighToCalf, .waistToHips].filter { sex != .female || $0 != .chestToWaist }
        case .hourglass: [.waistToGlutes, .shoulderToGlutes, .thighToCalf]
        case .leannessOnly: [.thighToCalf]
        case .off: []
        }
    }
}

/// One proportion, the sites it compares and its target. Rules only ever bring an area up.
public enum ProportionRule: String, CaseIterable, Codable, Sendable, Identifiable {
    case shoulderToWaist, waistToGlutes, shoulderToGlutes, armToNeck, thighToCalf, chestToWaist, waistToHips

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .shoulderToWaist: "Shoulders to waist"
        case .waistToGlutes: "Waist to glutes"
        case .shoulderToGlutes: "Shoulders to glutes"
        case .armToNeck: "Arm to neck"
        case .thighToCalf: "Thigh to calf"
        case .chestToWaist: "Chest to waist"
        case .waistToHips: "Waist to hips"
        }
    }

    /// Rules with the waist in them, which fat loss changes as much as training does.
    public var waistSensitive: Bool { [.shoulderToWaist, .waistToGlutes, .shoulderToGlutes, .chestToWaist, .waistToHips].contains(self) }

    /// A health signal only: it can ask for fat loss, never for more training.
    public var fatOnly: Bool { self == .waistToHips }

    public func value(_ m: BodyMeasurements) -> Double? {
        func ratio(_ a: Double?, _ b: Double?) -> Double? {
            guard let a, let b, b > 0 else { return nil }
            return a / b
        }
        return switch self {
        case .shoulderToWaist: ratio(m.shouldersCm, m.waistCm)
        case .waistToGlutes: ratio(m.naturalWaistCm ?? m.waistCm, m.glutesCm)
        case .shoulderToGlutes: ratio(m.shouldersCm, m.glutesCm)
        case .armToNeck: ratio(m.size(.arm), m.neckCm)
        case .thighToCalf: ratio(m.size(.thigh), m.size(.calf))
        case .chestToWaist: ratio(m.chestCm, m.waistCm)
        case .waistToHips: ratio(m.waistCm, m.glutesCm)
        }
    }

    /// The target, said plainly.
    public func targetText(sex: BiologicalSex) -> String {
        switch self {
        case .shoulderToWaist: "\(Self.format(Physique.shoulderToWaistTarget(sex))) or more"
        case .waistToGlutes: "0.72 or under"
        case .shoulderToGlutes, .armToNeck: "1.00 or more"
        case .thighToCalf: "1.45 to 1.75"
        case .chestToWaist: "1.30 or more"
        case .waistToHips: "\(Self.format(Self.healthyWaistToHips(sex))) or under"
        }
    }

    /// The WHO's thresholds for a raised health risk.
    static func healthyWaistToHips(_ sex: BiologicalSex) -> Double {
        switch sex {
        case .male: 0.90
        case .female: 0.85
        case .unspecified: 0.875
        }
    }

    static func format(_ value: Double) -> String { String(format: "%.2f", value) }

    /// Whether a value is far enough off to act on, how far it is from the target (0–1), and the
    /// area that would close it.
    public func assess(_ v: Double, sex: BiologicalSex) -> (flagged: Bool, magnitude: Double, region: PhysiqueRegion?) {
        func short(of target: Double, flagBelow: Double, span: Double, _ region: PhysiqueRegion?) -> (Bool, Double, PhysiqueRegion?) {
            (v < flagBelow, clamp((target - v) / span, 0, 1), region)
        }
        func over(_ target: Double, flagAbove: Double, span: Double, _ region: PhysiqueRegion?) -> (Bool, Double, PhysiqueRegion?) {
            (v > flagAbove, clamp((v - target) / span, 0, 1), region)
        }
        switch self {
        case .shoulderToWaist:
            let target = Physique.shoulderToWaistTarget(sex)
            return short(of: target, flagBelow: target - 0.04, span: 0.25, .shoulders)
        case .waistToGlutes: return over(0.72, flagAbove: 0.77, span: 0.10, .glutes)
        case .shoulderToGlutes: return short(of: 1.00, flagBelow: 0.95, span: 0.10, .shoulders)
        case .armToNeck: return (v < 0.95, clamp((1 - v) * 3, 0, 1), .arms)
        case .thighToCalf:
            if v < 1.45 { return (true, clamp((1.45 - v) / 0.25, 0, 1), .thighs) }
            if v > 1.75 { return (true, clamp((v - 1.75) / 0.25, 0, 1), .calves) }
            return (false, 0, nil)
        case .chestToWaist: return short(of: 1.30, flagBelow: 1.25, span: 0.15, .chest)
        case .waistToHips:
            let healthy = Self.healthyWaistToHips(sex)
            return over(healthy, flagAbove: healthy, span: 0.10, nil)
        }
    }

    func finding(_ v: Double, sex: BiologicalSex, region: PhysiqueRegion?) -> String {
        switch self {
        case .armToNeck: return "Upper arms measure smaller than the neck."
        case .thighToCalf: return region == .calves ? "Calves are small relative to thighs." : "Thighs are small relative to calves."
        default: return "\(label) is \(Self.format(v)); the target is \(targetText(sex: sex))."
        }
    }

    static func buildAction(_ region: PhysiqueRegion) -> String {
        switch region {
        case .shoulders: "Add side-delt and lat volume this block."
        case .chest: "Add chest volume this block."
        case .back: "Add rows and pulldowns this block."
        case .arms: "Add direct biceps and triceps work; it costs little recovery."
        case .core: "Add direct ab work."
        case .glutes: "Add glute volume this block."
        case .thighs: "Add quad and hamstring volume."
        case .calves: "Add calf work; it costs little recovery."
        }
    }
}

/// What a proportion reads, and whether fat loss or building would close it.
public struct ProportionReading: Hashable, Codable, Sendable, Identifiable {
    public enum Cause: String, Codable, Sendable {
        /// At a lean waist it would reach its target: fat loss closes it.
        case fat
        /// Still short at a lean waist: training closes it.
        case build
    }

    public var rule: ProportionRule
    public var value: Double
    public var flagged: Bool
    public var cause: Cause?
    /// The area that training would bring up, for a build gap.
    public var region: PhysiqueRegion?
    /// 0–1. A build gap's is measured at a lean waist, so it's the gap muscle would close.
    public var magnitude: Double
    /// 0–1: how much of the gap fat loss would close.
    public var fatShare: Double
    public var finding: String
    public var action: String?

    public var id: ProportionRule { rule }
}

/// Lift Track's read on whether fat loss or building would do more for proportions, published for
/// Macro Track's phase planner. It never asks for a cut at or below the floors.
public struct PhysiqueDirection: Hashable, Codable, Sendable {
    public var targets: ProportionTargets
    /// 0–1: how much fat loss would close the gaps.
    public var fatLoss: Double
    /// 0–1: how much building would.
    public var build: Double
    public var buildRegions: [PhysiqueRegion]
    /// Lean enough that no cut should be recommended, whatever a ratio says.
    public var atLeanFloor: Bool
    public var waistToHeight: Double?
    public var bodyFatPercent: Double?
    public var normalizedFFMI: Double?
    public var ffmiBand: FFMIBand?
    /// Each ratio fat loss would close, with what it reads and its target.
    public var fatLossReasons: [String]
    /// Each ratio training would close.
    public var buildReasons: [String]

    public init(
        targets: ProportionTargets, fatLoss: Double, build: Double, buildRegions: [PhysiqueRegion], atLeanFloor: Bool,
        waistToHeight: Double?, bodyFatPercent: Double?, normalizedFFMI: Double?, ffmiBand: FFMIBand?,
        fatLossReasons: [String] = [], buildReasons: [String] = []
    ) {
        self.targets = targets
        self.fatLoss = fatLoss
        self.build = build
        self.buildRegions = buildRegions
        self.atLeanFloor = atLeanFloor
        self.waistToHeight = waistToHeight
        self.bodyFatPercent = bodyFatPercent
        self.normalizedFFMI = normalizedFFMI
        self.ffmiBand = ffmiBand
        self.fatLossReasons = fatLossReasons
        self.buildReasons = buildReasons
    }

    /// The first builds to publish this kept every reason in one list; reading one leaves these empty.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        targets = try c.decode(ProportionTargets.self, forKey: .targets)
        fatLoss = try c.decode(Double.self, forKey: .fatLoss)
        build = try c.decode(Double.self, forKey: .build)
        buildRegions = try c.decodeIfPresent([PhysiqueRegion].self, forKey: .buildRegions) ?? []
        atLeanFloor = try c.decodeIfPresent(Bool.self, forKey: .atLeanFloor) ?? false
        waistToHeight = try c.decodeIfPresent(Double.self, forKey: .waistToHeight)
        bodyFatPercent = try c.decodeIfPresent(Double.self, forKey: .bodyFatPercent)
        normalizedFFMI = try c.decodeIfPresent(Double.self, forKey: .normalizedFFMI)
        ffmiBand = try c.decodeIfPresent(FFMIBand.self, forKey: .ffmiBand)
        fatLossReasons = try c.decodeIfPresent([String].self, forKey: .fatLossReasons) ?? []
        buildReasons = try c.decodeIfPresent([String].self, forKey: .buildReasons) ?? []
    }
}

public enum Proportions {
    /// The waist-to-height where the projection stops: the "lean" band's edge.
    public static let leanWaistToHeight = 0.46

    /// How much each site shrinks for each unit the navel waist shrinks, on the way to a lean
    /// waist. Rough by nature.
    static func shrink(_ key: WritableKeyPath<BodyMeasurements, Double?>, sex: BiologicalSex) -> Double {
        switch key {
        case \.naturalWaistCm: 1
        case \.glutesCm, \.hipsCm: sex == .female ? 0.5 : 0.35
        case \.shouldersCm, \.chestCm: 0.15
        default: 0.2
        }
    }

    /// No cut below these, whatever a ratio says: body fat when it's known, waist-to-height when not.
    public static func atLeanFloor(bodyFatPercent: Double?, waistToHeight: Double?, sex: BiologicalSex) -> Bool {
        if let bodyFatPercent {
            let floor: Double =
                switch sex {
                case .male: 10
                case .female: 20
                case .unspecified: 15
                }
            return bodyFatPercent <= floor
        }
        return (waistToHeight ?? 1) <= 0.42
    }

    /// The same body at a lean waist: the navel waist at 0.46 of height and the other sites shrunk
    /// with it. Nil when the waist is already there.
    public static func atLeanWaist(_ m: BodyMeasurements, sex: BiologicalSex, heightCm: Double?) -> BodyMeasurements? {
        guard let h = heightCm, h > 0, let waist = m.waistCm, waist > leanWaistToHeight * h else { return nil }
        let r = (waist - leanWaistToHeight * h) / waist
        var lean = m
        lean.waistCm = leanWaistToHeight * h
        let others: [WritableKeyPath<BodyMeasurements, Double?>] = [
            \.naturalWaistCm, \.glutesCm, \.hipsCm, \.shouldersCm, \.chestCm, \.neckCm,
            \.armLeftCm, \.armRightCm, \.armCm, \.thighLeftCm, \.thighRightCm, \.thighCm,
            \.calfLeftCm, \.calfRightCm, \.calfCm,
        ]
        for key in others { lean[keyPath: key] = lean[keyPath: key].map { $0 * (1 - shrink(key, sex: sex) * r) } }
        return lean
    }

    /// Every rule in the set, read now and, for the waist rules, at a lean waist.
    public static func read(
        _ m: BodyMeasurements, targets: ProportionTargets, sex: BiologicalSex, heightCm: Double?,
        atLeanFloor: Bool
    ) -> [ProportionReading] {
        let lean = atLeanFloor ? nil : atLeanWaist(m, sex: sex, heightCm: heightCm)
        return targets.rules(sex: sex).compactMap { rule in
            guard let v = rule.value(m) else { return nil }
            let now = rule.assess(v, sex: sex)
            var reading = ProportionReading(
                rule: rule, value: v, flagged: now.flagged, magnitude: now.magnitude, fatShare: 0,
                finding: rule.finding(v, sex: sex, region: now.region))
            guard now.flagged else { return reading }
            if rule.fatOnly {
                // Only fat loss changes it; at the floor there's nothing to ask for.
                guard !atLeanFloor else { return reading }
                reading.cause = .fat
                reading.fatShare = now.magnitude
                reading.action = "Fat loss brings it down; the nutrition phase handles it."
                return reading
            }
            if rule.waistSensitive, let lean, let leanValue = rule.value(lean) {
                let then = rule.assess(leanValue, sex: sex)
                if !then.flagged {
                    reading.cause = .fat
                    reading.fatShare = now.magnitude
                    reading.action = "At a leaner waist it reaches the target, so fat loss closes it rather than extra volume."
                    return reading
                }
                reading.fatShare = max(0, now.magnitude - then.magnitude)
                reading.magnitude = then.magnitude
                reading.region = then.region
            } else {
                reading.region = now.region
            }
            reading.cause = .build
            reading.action = reading.region.map(ProportionRule.buildAction)
            return reading
        }
    }
}
