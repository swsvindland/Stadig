import ImageIO
import UIKit

/// Photos made ready for the models and OCR: upright and at most a size on their long side, made
/// off the main thread. A 12–48 MP photo decoded and redrawn there stalls the screen for a moment
/// right as the camera or picker closes.
nonisolated enum PhotoInput {
    /// A picked photo, straight from its bytes, never decoded at full size.
    static func prepare(_ data: Data, maxDimension: Int) async -> CGImage? {
        await Task.detached(priority: .userInitiated) { image(from: data, maxDimension: maxDimension) }.value
    }

    /// A photo from the camera, redrawn upright at the size.
    static func prepare(_ photo: UIImage, maxDimension: CGFloat) async -> CGImage? {
        await Task.detached(priority: .userInitiated) { image(from: photo, maxDimension: maxDimension) }.value
    }

    static func image(from data: Data, maxDimension: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Upright: without it the photo's EXIF orientation is ignored and a portrait label
            // reaches OCR sideways.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func image(from photo: UIImage, maxDimension: CGFloat) -> CGImage? {
        let longest = max(photo.size.width, photo.size.height)
        guard longest > 0 else { return nil }
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: (photo.size.width * scale).rounded(), height: (photo.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        // UIImage draws itself upright; the renderer is safe off the main thread.
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in photo.draw(in: CGRect(origin: .zero, size: target)) }.cgImage
    }
}
