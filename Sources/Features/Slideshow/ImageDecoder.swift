import CoreGraphics
import Foundation
import ImageIO

/// Decodes a photograph straight to display size, off the main actor.
///
/// Why not `NSImage(contentsOf:)`: a 24 MP JPEG decodes to ~96 MB of pixels and
/// stalls the main actor while it does it. ImageIO's thumbnail path applies the
/// EXIF orientation and never materialises the full bitmap, so three tiles and
/// a prefetch cost a fraction of that.
enum ImageDecoder {
    nonisolated static func downsample(url: URL, maxPixelSize: Int) async -> LoadedImage? {
        await Task.detached(priority: .userInitiated) {
            decode(url: url, maxPixelSize: maxPixelSize)
        }.value
    }

    private nonisolated static func decode(url: URL, maxPixelSize: Int) -> LoadedImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }
        return LoadedImage(cgImage: cgImage)
    }
}
