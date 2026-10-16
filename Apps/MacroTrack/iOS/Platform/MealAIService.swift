import CoreGraphics
import Foundation
import Observation
import FoodDatabase
import FoodIntelligence

/// Photo, description and label logging through Apple's models: on device first, Private Cloud
/// Compute when allowed. The models name foods and amounts; nutrients always come from the catalog.
@MainActor @Observable
final class MealAIService {
    /// Whether the photo and description features can run, and why not.
    private(set) var availability = MealAIAvailability(onDevice: false, onDeviceVision: false, privateCloud: false, reason: "Checking…")
    private(set) var allowCloud = true

    @ObservationIgnored private var engine: AnyObject?
    @ObservationIgnored private var engineAllowsCloud: Bool?

    var canDescribe: Bool { availability.descriptions }
    var canSeePhotos: Bool { availability.photos }

    /// Re-checks availability and builds the engine for the current setting. Cheap; call on launch
    /// and when the setting changes.
    func configure(catalog: FoodCatalog, allowCloud: Bool) {
        self.allowCloud = allowCloud
        guard #available(iOS 27.0, *) else {
            availability = MealAIAvailability(onDevice: false, onDeviceVision: false, privateCloud: false,
                                              reason: "Photo and description logging needs iOS 27.")
            return
        }
        availability = MealAI.availability(allowCloud: allowCloud)
        if engineAllowsCloud != allowCloud || engine == nil {
            engine = MealAI(catalog: catalog, allowCloud: allowCloud)
            engineAllowsCloud = allowCloud
        }
    }

    /// Loads the model ahead of a likely request (the logger opening), so the answer comes faster.
    func prewarm() {
        guard #available(iOS 27.0, *), let ai = engine as? MealAI else { return }
        Task { await ai.prewarm() }
    }

    func recognize(photo: CGImage, note: String?, personal: [PersonalFood]) async throws -> MealGuess {
        guard #available(iOS 27.0, *), let ai = engine as? MealAI else { throw MealAIError.unavailable(availability.reason ?? "Unavailable") }
        return try await ai.recognize(photo: photo, note: note, personal: personal)
    }

    func recognize(description: String, personal: [PersonalFood]) async throws -> MealGuess {
        guard #available(iOS 27.0, *), let ai = engine as? MealAI else { throw MealAIError.unavailable(availability.reason ?? "Unavailable") }
        return try await ai.recognize(description: description, personal: personal)
    }

    /// A label photo read into a food. Works without the language model too: OCR and the parser
    /// do the reading; the model only helps with a name.
    func readLabel(photo: CGImage) async throws -> LabelResult {
        if #available(iOS 27.0, *), let ai = engine as? MealAI {
            return try await ai.readLabel(photo: photo)
        }
        // Positions let the parser read two-column panels; lines are the fallback.
        let boxes = try await LabelOCR.boxes(in: photo)
        let lines = try await LabelOCR.lines(in: photo)
        return LabelResult(reading: NutritionLabel.parse(boxes: boxes) ?? NutritionLabel.parse(lines: lines), lines: lines,
                           suggestedName: nil, brand: nil)
    }
}
