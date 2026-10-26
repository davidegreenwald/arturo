@testable import Arturo
import CoreGraphics
import Foundation
import ImageIO
import Testing

/// Proves the decode path against real bytes: ImageIO options are easy to get
/// subtly wrong (orientation, thumbnail fallbacks), and the model tests never
/// touch a pixel.
@Suite("Image decoding")
@MainActor
struct ImageDecoderTests {
    /// Writes a real image of the given ImageIO type. HEIC is encoded rather
    /// than stubbed so the decode path is exercised against the format an
    /// iPhone folder actually contains.
    private func makeImage(
        type: String,
        fileExtension: String,
        width: Int,
        height: Int
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "slideshow-source-\(UUID().uuidString).\(fileExtension)")

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let source = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL,
            type as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, source, nil)
        let finished = CGImageDestinationFinalize(destination)
        #expect(finished, "could not encode \(type) at \(width)x\(height)")
        return url
    }

    @Test("decodes down to the requested ceiling without upscaling the smaller axis")
    func downsamplesToCeiling() async throws {
        let url = try makeImage(type: "public.png", fileExtension: "png", width: 1200, height: 800)

        let loaded = try #require(await ImageDecoder.downsample(url: url, maxPixelSize: 400))
        let image = loaded.cgImage

        #expect(max(image.width, image.height) <= 400)
        #expect(image.width > image.height, "a landscape source must stay landscape")
    }

    @Test("decodes HEIC, the format an iPhone folder arrives in")
    func decodesHEIC() async throws {
        let url = try makeImage(type: "public.heic", fileExtension: "heic", width: 1200, height: 800)

        // The viewer special-cases nothing for HEIC: ImageIO reports the type
        // and applies the EXIF orientation on the same thumbnail path.
        let loaded = try #require(await ImageDecoder.downsample(url: url, maxPixelSize: 400))
        let image = loaded.cgImage

        #expect(max(image.width, image.height) <= 400)
        #expect(image.width > image.height, "a landscape HEIC must stay landscape")
    }

    @Test("a file that is not an image decodes to nothing rather than crashing")
    func rejectsNonImage() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "slideshow-broken-\(UUID().uuidString).jpg")
        try Data("not a photograph".utf8).write(to: url)

        #expect(await ImageDecoder.downsample(url: url, maxPixelSize: 400) == nil)
    }
}
