import Foundation
import Observation

/// Holds decoded frames for the tiles that are visible or about to be.
///
/// Bounded on purpose: a folder of 2000 photographs must not become a folder of
/// 2000 decoded bitmaps. Nine frames is three pages — the visible page, the one
/// being prefetched, and slack for skipping back — and eviction is
/// first-in-first-out because skip direction is unpredictable.
@Observable
@MainActor
final class ImageStore {
    private(set) var frames: [URL: LoadedImage] = [:]
    private(set) var maxPixelSize = 2048

    private var arrivalOrder: [URL] = []
    private var pending: [URL: Task<Void, Never>] = [:]

    /// Bumped by every `clear()`. A decode that started before the bump belongs to
    /// a cache that no longer exists: it owns neither `pending` nor `frames` any
    /// more, because the request that replaced it owns both. Without this, a stale
    /// task resuming after a clear would untrack its successor and leave that
    /// successor uncancellable — the one way a cancelled decode resurrects a frame.
    private var generation = 0

    let capacity: Int

    /// The decode leaf. It is injected so a test can hold a decode in flight and
    /// count how many were started — neither is observable through the cache's
    /// own surface. Production passes `ImageDecoder.downsample`.
    typealias Decode = (URL, Int) async -> LoadedImage?

    private let decode: Decode

    /// `capacity` defaults to the nine frames the viewer needs for three pages;
    /// a test passes three so eviction is exercised in a handful of urls.
    init(capacity: Int = 9, decode: @escaping Decode = ImageDecoder.downsample) {
        precondition(capacity > 0, "a cache that holds nothing cannot serve a tile")
        self.capacity = capacity
        self.decode = decode
    }

    func frame(for url: URL) -> LoadedImage? {
        frames[url]
    }

    /// Adjusts the decode ceiling to the current layout. A change smaller than
    /// the slack is ignored so dragging a window does not re-decode the page;
    /// a real change (1-up to 3-up) drops the cache rather than displaying
    /// frames decoded for the wrong size.
    func setMaxPixelSize(_ proposed: Int) {
        let clamped = min(max(proposed, 512), 2600)
        guard abs(clamped - maxPixelSize) > 192 else { return }

        maxPixelSize = clamped
        clear()
    }

    func ensureLoaded(_ urls: [URL]) {
        let requestGeneration = generation
        for url in urls where frames[url] == nil && pending[url] == nil {
            let target = maxPixelSize
            let leaf = decode
            pending[url] = Task { [weak self] in
                let decoded = await leaf(url, target)
                guard let self else { return }
                // The cache may have been dropped or replaced while this was
                // decoding, so this task must not write on its behalf: a stale
                // generation owns nothing, and a task told to stop writes nothing.
                guard requestGeneration == self.generation, !Task.isCancelled else { return }
                self.pending[url] = nil
                guard let decoded else { return }
                self.retain(decoded, for: url)
            }
        }
    }

    func clear() {
        generation &+= 1
        for task in pending.values {
            task.cancel()
        }
        pending.removeAll()
        frames.removeAll()
        arrivalOrder.removeAll()
    }

    private func retain(_ image: LoadedImage, for url: URL) {
        // Arrival order mirrors the cache exactly, so an insert is always new. The
        // invariant is enforced by `pending` plus the generation check above; this
        // assertion is here because a duplicate entry would silently shrink the
        // effective cache by making a frame look older than it is.
        assert(arrivalOrder.count == frames.count, "arrival order drifted from the cache")
        assert(frames[url] == nil, "retain is only for a url the cache does not hold")

        frames[url] = image
        arrivalOrder.append(url)

        while arrivalOrder.count > capacity {
            frames[arrivalOrder.removeFirst()] = nil
        }
    }
}
