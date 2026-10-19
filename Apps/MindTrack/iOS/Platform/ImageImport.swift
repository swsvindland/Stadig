import CoreGraphics
import Foundation
import OSLog
import UniformTypeIdentifiers

/// Pages and pictures brought in from outside the app: a photo or a scanned PDF from the file
/// importer, an image dropped on the window, or what an iPhone's camera sends the Mac through
/// Continuity Camera (a photo, or a document scan as a PDF). Decoded off the main actor, upright and
/// no bigger than text recognition needs.
enum ImageImport {
    nonisolated private static let log = Logger(subsystem: "dev.svindland.stadig.mind", category: "import")

    /// What the importers and drops accept: pictures, and scans saved as PDFs.
    static let pageTypes: [UTType] = [.image, .pdf]

    /// The pages in a file's bytes: each page of a PDF, or the one picture.
    @concurrent nonisolated static func pages(_ data: Data, maxPixels: Int = 3000) async -> [CGImage] {
        if isPDF(data) { return pdfPages(data, maxPixels: maxPixels) }
        return ImageData.downsampled(data, maxPixels: maxPixels).map { [$0] } ?? []
    }

    /// A file chosen in the file importer, read while the sandbox allows it.
    nonisolated static func data(at url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    /// The bytes an item provider holds: a PDF if it has one (a document scan), else a picture.
    nonisolated static func data(from provider: NSItemProvider) async -> Data? {
        let types = provider.registeredContentTypes
        guard let type = types.first(where: { $0.conforms(to: .pdf) }) ?? types.first(where: { $0.conforms(to: .image) }) else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: type) { data, error in
                if let error { log.error("Couldn't load an imported page: \(error.localizedDescription)") }
                continuation.resume(returning: data)
            }
        }
    }

    nonisolated static func isPDF(_ data: Data) -> Bool { data.prefix(5) == Data("%PDF-".utf8) }

    /// Each page drawn white behind black, at most `maxPixels` on its long side.
    nonisolated private static func pdfPages(_ data: Data, maxPixels: Int) -> [CGImage] {
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider) else { return [] }
        return (1...max(1, document.numberOfPages)).compactMap { number in
            guard let page = document.page(at: number) else { return nil }
            let box = page.getBoxRect(.cropBox)
            let scale = Double(maxPixels) / max(1, max(box.width, box.height))
            let width = Int((box.width * scale).rounded())
            let height = Int((box.height * scale).rounded())
            guard width > 0, height > 0,
                let context = CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return nil }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -box.minX, y: -box.minY)
            context.drawPDFPage(page)
            return context.makeImage()
        }
    }
}
