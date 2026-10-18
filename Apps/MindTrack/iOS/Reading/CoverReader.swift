import SwiftUI
import UIKit
import Vision
import MindEngine
import SystemAI

/// A book from a photo of its cover: Vision reads the text on the device, Apple's model picks the
/// title and author out of it (a light job), and without the model the largest words and a
/// name-shaped line stand in. Either way the result is searched like anything typed.
enum CoverReader {
    /// Every line of text on the cover with its height, so the biggest words are known.
    static func lines(in image: CGImage) async throws -> [CoverText.Line] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: image)
        return observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else { return nil }
            return CoverText.Line(text: text, height: Double(observation.boundingBox.height))
        }
    }

    /// The title and author: the model's reading when it answers within a few seconds, the plain
    /// guess when it can't or doesn't.
    static func guess(_ lines: [CoverText.Line], ai: SystemAI) async -> CoverText.Guess? {
        guard !lines.isEmpty else { return nil }
        let prompt = CoverText.prompt(lines)
        let modelGuess = await withTaskGroup(of: CoverText.Guess?.self) { group in
            group.addTask {
                guard let reply = try? await ai.respond(instructions: CoverText.instructions, prompt: prompt, weight: .light, maxTokens: 80)
                else { return nil }
                return CoverText.parseReply(reply)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(6))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        return modelGuess ?? CoverText.guess(lines)
    }

    static func read(_ image: UIImage, ai: SystemAI) async -> CoverText.Guess? {
        guard let picture = image.bookCoverImage(), let lines = try? await lines(in: picture) else { return nil }
        return await guess(lines, ai: ai)
    }
}

/// The camera, for a photo of the cover.
struct CoverCamera: UIViewControllerRepresentable {
    let picked: (UIImage?) -> Void

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(picked: picked) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let picked: (UIImage?) -> Void
        init(picked: @escaping (UIImage?) -> Void) { self.picked = picked }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picked(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picked(nil) }
    }
}

extension UIImage {
    /// Upright and at most `maxDimension` on its long side, as text recognition wants it.
    func bookCoverImage(maxDimension: CGFloat = 2000) -> CGImage? {
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }.cgImage
    }
}
