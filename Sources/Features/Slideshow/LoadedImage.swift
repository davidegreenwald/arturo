import CoreGraphics

/// Sendable carrier for a decoded frame. `CGImage` is immutable once created,
/// so handing the same instance to the main actor is safe; the wrapper exists
/// only because Core Graphics types are not annotated `Sendable`.
///
/// The initializer is `nonisolated` because decoding finishes off the main
/// actor — that is the whole point of the decoder.
final class LoadedImage: @unchecked Sendable {
    let cgImage: CGImage

    nonisolated init(cgImage: CGImage) {
        self.cgImage = cgImage
    }
}
