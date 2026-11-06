import CoreGraphics
import FoodDatabase
import FoodIntelligence
import Foundation
import Observation
import SystemCore

/// Photo, description and label logging through Apple's models: on device first, Private Cloud
/// Compute when allowed. The models name foods and amounts; nutrients always come from the catalog.
@MainActor @Observable
final class MealAIService {
    /// Whether the photo and description features can run, and why not.
    private(set) var availability = MealAIAvailability(onDevice: false, onDeviceVision: false, privateCloud: false, reason: "Checking…")
    private(set) var allowCloud = true

    @ObservationIgnored private var engine: AnyObject?
    @ObservationIgnored private var engineAllowsCloud: Bool?
    @ObservationIgnored private var completer: AnyObject?

    var canDescribe: Bool { availability.descriptions }
    var canSeePhotos: Bool { availability.photos }

    /// Re-checks availability and builds the engine for the current setting. Cheap; call on launch
    /// and when the setting changes.
    func configure(catalog: FoodCatalog, allowCloud: Bool) {
        self.allowCloud = allowCloud
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else {
            availability = MealAIAvailability(
                onDevice: false, onDeviceVision: false, privateCloud: false,
                reason: "Photo and description logging needs iOS 27.")
            return
        }
        availability = MealAI.availability(allowCloud: allowCloud)
        completer = availability.onDevice ? (completer ?? SearchCompletionAI()) : nil
        if engineAllowsCloud != allowCloud || engine == nil {
            engine = MealAI(catalog: catalog, allowCloud: allowCloud)
            engineAllowsCloud = allowCloud
        }
    }

    /// Loads the model ahead of a likely request (the logger opening), so the answer comes faster.
    func prewarm() {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *), let ai = engine as? MealAI else { return }
        let completer = completer as? SearchCompletionAI
        Task {
            await completer?.prewarm()
            await ai.prewarm()
        }
    }

    /// Whether the device's own model can order a search's suggestions.
    var canRankCompletions: Bool { completer != nil }

    /// A search's suggestions in the order this person likely wants, or nil without the device's
    /// model. Private Cloud Compute is never asked: this runs as someone types.
    func rankCompletions(_ options: [String], typed: String, past: [String]) async -> [String]? {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *), let ai = completer as? SearchCompletionAI else { return nil }
        return await ai.rank(typed: typed, options: options, past: past, at: Date())
    }

    func recognize(photo: CGImage, note: String?, personal: [PersonalFood]) async throws -> MealGuess {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *), let ai = engine as? MealAI else {
            throw MealAIError.unavailable(availability.reason ?? "Unavailable")
        }
        return try await ai.recognize(photo: photo, note: note, personal: personal)
    }

    func recognize(description: String, personal: [PersonalFood]) async throws -> MealGuess {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *), let ai = engine as? MealAI else {
            throw MealAIError.unavailable(availability.reason ?? "Unavailable")
        }
        return try await ai.recognize(description: description, personal: personal)
    }

    /// A label photo read into a food. Works without the language model too: OCR and the parser
    /// do the reading; the model only helps with a name.
    /// A Supplement Facts photo: OCR and the parser, with the model naming the product when it can.
    func readSupplementLabel(photo: CGImage) async throws -> SupplementLabelResult {
        if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *), let ai = engine as? MealAI {
            return try await ai.readSupplementLabel(photo: photo)
        }
        let lines = try await LabelOCR.lines(in: photo)
        return SupplementLabelResult(facts: SupplementLabel.parse(lines: lines), lines: lines, suggestedName: nil, brand: nil)
    }

    /// A live scan's text checked by the model: values copied from the panel and the product's name.
    /// Nil without a model (on the device alone when `onDeviceOnly`).
    func checkLabel(panel: [String], other: [String], onDeviceOnly: Bool) async throws -> LabelCheck? {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *), let ai = engine as? MealAI else { return nil }
        return try await ai.checkLabel(panel: panel, other: other, onDeviceOnly: onDeviceOnly)
    }

    func checkSupplement(panel: [String], other: [String], onDeviceOnly: Bool) async throws -> SupplementCheck? {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *), let ai = engine as? MealAI else { return nil }
        return try await ai.checkSupplement(panel: panel, other: other, onDeviceOnly: onDeviceOnly)
    }

    /// Loads the on-device model for a scan's checks as the scanner opens.
    func prewarmCheck(supplement: Bool) {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *), let ai = engine as? MealAI else { return }
        Task { await ai.prewarmCheck(supplement: supplement) }
    }

    func readLabel(photo: CGImage) async throws -> LabelResult {
        if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *), let ai = engine as? MealAI {
            return try await ai.readLabel(photo: photo)
        }
        // One Vision pass gives both the positions (for two-column panels) and the lines.
        return try await LabelOCR.label(in: photo)
    }
}
