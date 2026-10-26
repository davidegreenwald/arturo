@testable import Arturo
import CoreGraphics
import Foundation
import Testing

/// A stand-in frame whose pixel width encodes the decode that produced it, so a
/// test can prove the cache kept the frame it should have kept rather than a
/// same-shaped one from a decode it should have dropped.
private func makeFrame(seed: Int) -> LoadedImage? {
    let side = 8 + seed
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let image = context.makeImage() else {
        return nil
    }
    return LoadedImage(cgImage: image)
}

/// Yields until `condition` holds. Every decode in this suite is gated, so
/// nothing here waits out a decode duration — only out a main-actor turn, which
/// the bounded count tolerates without making the assertions time-dependent.
@MainActor
private func eventually(_ condition: () async -> Bool) async -> Bool {
    for turn in 0 ..< 500 {
        if await condition() {
            return true
        }
        if turn.isMultiple(of: 32) {
            try? await Task.sleep(for: .milliseconds(1))
        }
        await Task.yield()
    }
    return await condition()
}

/// Lets work that is already queued run, for the assertions that something did
/// not start. A duplicate decode would already be parked by the time this ends.
@MainActor
private func settle() async {
    for _ in 0 ..< 50 {
        await Task.yield()
    }
}

/// Suite for the frame cache — the one component holding real concurrency state:
/// in-flight dedup, bounded arrival-order eviction, and a cancellation path that
/// must not resurrect a frame decoded for a cache that no longer exists.
///
/// The decode leaf is injected rather than real: ImageIO gives no way to hold a
/// decode open, and a test that slept for one would be timing-dependent.
@Suite("Image cache")
@MainActor
struct ImageStoreTests {
    /// Decode leaf that parks every request until the test releases it by index,
    /// recording the ceiling each request asked for. Parking is what makes "in
    /// flight" a fact the test owns rather than a window it hopes to catch.
    private actor GatedDecoder {
        private var ceilings: [Int] = []
        private var parked: [Int: CheckedContinuation<Void, Never>] = [:]

        /// Decode requests started, whether still in flight or finished.
        var started: Int {
            ceilings.count
        }

        /// The ceiling each request asked for, in start order.
        var requestedCeilings: [Int] {
            ceilings
        }

        func decode(url _: URL, maxPixelSize: Int) async -> LoadedImage? {
            let index = ceilings.count
            ceilings.append(maxPixelSize)
            await withCheckedContinuation { continuation in
                parked[index] = continuation
            }
            return makeFrame(seed: index)
        }

        func release(_ index: Int) {
            parked.removeValue(forKey: index)?.resume()
        }
    }

    private func gatedStore(_ decoder: GatedDecoder, capacity: Int = 3) -> ImageStore {
        ImageStore(capacity: capacity, decode: { url, maxPixelSize in
            await decoder.decode(url: url, maxPixelSize: maxPixelSize)
        })
    }

    private func instantStore(capacity: Int = 3) -> ImageStore {
        ImageStore(capacity: capacity, decode: { _, _ in makeFrame(seed: 0) })
    }

    @Test("clamps the decode ceiling into the supported range")
    func clampsCeiling() {
        let store = instantStore()

        store.setMaxPixelSize(1)
        #expect(store.maxPixelSize == 512)

        store.setMaxPixelSize(99999)
        #expect(store.maxPixelSize == 2600)
    }

    @Test("ignores a ceiling change inside the hysteresis band, and clears on a real one")
    func hysteresisDecidesWhetherCacheIsDropped() async {
        let store = instantStore()
        let url = URL(filePath: "/photos/a.jpg")

        store.ensureLoaded([url])
        #expect(await eventually { store.frame(for: url) != nil })

        // A 100 px change is window-drag noise: re-decoding the page for it would
        // be the stutter the hysteresis exists to prevent.
        store.setMaxPixelSize(store.maxPixelSize - 100)
        #expect(store.maxPixelSize == 2048)
        #expect(store.frame(for: url) != nil, "a change inside the band must keep the cache")

        // 200 px is a real layout change, so frames decoded for the old ceiling go.
        store.setMaxPixelSize(store.maxPixelSize - 200)
        #expect(store.maxPixelSize == 1848)
        #expect(store.frames.isEmpty)
    }

    @Test("holds at most capacity frames and evicts the earliest arrival")
    func evictsEarliestArrival() async {
        let store = instantStore(capacity: 3)
        let urls = ["a", "b", "c", "d"].map { URL(filePath: "/photos/\($0).jpg") }

        // Loaded one at a time so arrival order is the test's, not the scheduler's.
        for url in urls {
            store.ensureLoaded([url])
            #expect(await eventually { store.frame(for: url) != nil })
        }

        #expect(store.frames.count == store.capacity)
        #expect(store.frame(for: urls[0]) == nil, "the earliest arrival is evicted first")
        #expect(store.frame(for: urls[3]) != nil)

        // A re-request appends, so the next eviction is the oldest survivor rather
        // than the frame that just arrived.
        store.ensureLoaded([urls[0]])
        #expect(await eventually { store.frame(for: urls[0]) != nil })
        #expect(store.frames.count == 3)
        #expect(store.frame(for: urls[1]) == nil)
    }

    @Test("starts one decode per url while that url is in flight, and none once cached")
    func dedupsInFlightRequests() async throws {
        let decoder = GatedDecoder()
        let store = gatedStore(decoder)
        let url = URL(filePath: "/photos/a.jpg")

        // Three requests in one turn, as a page change plus a prefetch would.
        store.ensureLoaded([url])
        store.ensureLoaded([url])
        store.ensureLoaded([url, url])
        await settle()
        #expect(await decoder.started == 1, "an in-flight url must not be decoded twice")

        await decoder.release(0)
        #expect(await eventually { store.frame(for: url) != nil })
        let frame = try #require(store.frame(for: url))
        #expect(frame.cgImage.width == 8, "the retained frame came from the only decode")

        store.ensureLoaded([url])
        await settle()
        #expect(await decoder.started == 1, "a cached url must not be decoded again")
    }

    @Test("a cancelled decode does not resurrect a frame, and does not dislodge its successor")
    func cancelledDecodeLeavesSuccessorInFlight() async throws {
        let decoder = GatedDecoder()
        let store = gatedStore(decoder)
        let url = URL(filePath: "/photos/a.jpg")

        store.ensureLoaded([url])
        #expect(await eventually { await decoder.started == 1 })

        // The resize path: clear for a new ceiling, then ask for the same url
        // again. `.task(id:)` does both in one main-actor turn.
        store.setMaxPixelSize(1600)
        store.ensureLoaded([url])
        #expect(await eventually { await decoder.started == 2 })
        #expect(await decoder.requestedCeilings == [2048, 1600])

        // The first decode lands now, decoded for a ceiling the cache has dropped.
        await decoder.release(0)
        await settle()
        #expect(store.frames.isEmpty, "a decode that outlived its cache must not retain a frame")

        // And it must not have untracked the request that replaced it: asking
        // again still finds one in flight rather than starting a third.
        store.ensureLoaded([url])
        await settle()
        #expect(await decoder.started == 2, "the replacement request was lost, so this url is decoded twice")

        await decoder.release(1)
        #expect(await eventually { store.frame(for: url) != nil })
        let frame = try #require(store.frame(for: url))
        #expect(frame.cgImage.width == 9, "the retained frame must be the one decoded at the current ceiling")
    }

    @Test("a second clear during an in-flight decode leaves the cache empty")
    func clearDuringFlightLeavesCacheEmpty() async {
        let decoder = GatedDecoder()
        let store = gatedStore(decoder)
        let url = URL(filePath: "/photos/a.jpg")

        store.ensureLoaded([url])
        #expect(await eventually { await decoder.started == 1 })

        store.setMaxPixelSize(1600)
        store.ensureLoaded([url])
        #expect(await eventually { await decoder.started == 2 })

        // The replaced decode lands first. It must not untrack its successor,
        // because the successor is the one the next clear has to cancel.
        await decoder.release(0)
        await settle()

        store.setMaxPixelSize(1000)
        await decoder.release(1)
        await settle()

        #expect(store.maxPixelSize == 1000)
        #expect(store.frames.isEmpty, "the successor was never cancelled, so a stale frame arrived after the clear")
    }
}
