import Foundation
import Observation

/// The viewer's whole state: which folder, which photographs, where the window
/// of up to three sits, and how the rotation is paced.
///
/// Pure model — no AppKit, no timers. The view owns cadence (`task(id:)` runs
/// the loop), the keys call `nextPage()`/`previousPage()`, and AppKit seams
/// live behind the bridges. That split is what lets the rotation rules be
/// tested without a window.
@Observable
@MainActor
final class SlideshowModel {
    /// Persistence rung 1 (ADR-001 §D5): flat view preferences, no file store.
    /// The folder is deliberately absent — the viewer always launches blank
    /// (adr-102), so there is nothing about a previous session to restore.
    private enum Keys {
        static let holdSeconds = "arturo.holdSeconds"
        static let columns = "arturo.columns"
        static let fillsFrames = "arturo.fillsFrames"
    }

    /// Half-second steps from 0.5 s: fast enough to skim a folder, slow enough
    /// to look at something. The floor is not 0 — a hold of nothing is a flicker.
    static let holdRange: ClosedRange<Double> = 0.5 ... 30
    static let holdStep: Double = 0.5
    static let columnRange: ClosedRange<Int> = 1 ... 3

    private let defaults: UserDefaults

    private(set) var folder: URL?
    private(set) var images: [URL] = []
    /// Index in `images` of the leftmost photograph on screen.
    private(set) var pageStart = 0
    /// Bumped only by a manual skip, so the rotation timer restarts then and
    /// not on every automatic advance.
    private(set) var skipGeneration = 0
    private(set) var errorMessage: String?

    var isPlaying = true

    /// The photographs are fitted inside their columns by default. Filling them
    /// is opt-in because a fill is a crop: it silently discards whatever does
    /// not fit, which is the one thing a viewer must never do unasked.
    var fillsFrames: Bool {
        didSet { defaults.set(fillsFrames, forKey: Keys.fillsFrames) }
    }

    /// How many photographs side by side the user asked for. The effective
    /// count is `columnCount`, which cannot exceed the folder size.
    var preferredColumns: Int {
        didSet { defaults.set(clamped(preferredColumns), forKey: Keys.columns) }
    }

    /// Dwell time per page, in seconds. The effective value is `holdDuration`.
    var holdSeconds: Double {
        didSet { defaults.set(clamped(holdSeconds), forKey: Keys.holdSeconds) }
    }

    /// `arguments` is injectable so the launch-argument path is testable without
    /// spawning a process.
    init(defaults: UserDefaults = .standard, arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.defaults = defaults

        let storedColumns = defaults.integer(forKey: Keys.columns)
        preferredColumns = Self.columnRange.contains(storedColumns) ? storedColumns : 3

        let storedHold = defaults.double(forKey: Keys.holdSeconds)
        holdSeconds = Self.holdRange.contains(storedHold) ? storedHold : 6

        fillsFrames = defaults.bool(forKey: Keys.fillsFrames)

        // No session restore: the app opens blank every time. A folder named on
        // the command line ("--folder <path>") opens the show for this launch
        // only — that is how scripts and the UI tests start without the panel.
        if let flag = arguments.firstIndex(of: "--folder"), arguments.indices.contains(flag + 1) {
            open(URL(filePath: arguments[flag + 1], directoryHint: .isDirectory))
        }
    }

    // MARK: - Derived state

    /// Photographs actually shown side by side: never more than the folder
    /// holds, so a two-file folder renders two full-width columns rather than
    /// three with a hole in it.
    var columnCount: Int {
        guard !images.isEmpty else { return 0 }
        return min(clamped(preferredColumns), images.count)
    }

    /// The window of URLs on screen right now, wrapping past the end of the
    /// folder. Distinct by construction: `columnCount <= images.count`.
    var visibleImages: [URL] {
        guard !images.isEmpty else { return [] }
        return (0 ..< columnCount).map { images[(pageStart + $0) % images.count] }
    }

    var holdDuration: Duration {
        .seconds(clamped(holdSeconds))
    }

    /// "0.5s", "1s", "6s" — halves are legal, and a whole second must not read
    /// "1.0s" in a control this narrow.
    var holdLabel: String {
        let seconds = clamped(holdSeconds)
        if seconds.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(seconds))s"
        }
        return String(format: "%.1fs", seconds)
    }

    /// Spoken form: "half a second" reads better than "0.5s" in VoiceOver.
    var holdSpokenLabel: String {
        let seconds = clamped(holdSeconds)
        if seconds == 0.5 {
            return "half a second"
        }
        if seconds.truncatingRemainder(dividingBy: 1) == 0 {
            let whole = Int(seconds)
            return whole == 1 ? "1 second" : "\(whole) seconds"
        }
        return String(format: "%.1f seconds", seconds)
    }

    /// The page after this one — prefetched so a skip lands on a decoded frame.
    var nextPageImages: [URL] {
        guard !images.isEmpty else { return [] }
        let start = (pageStart + columnCount) % images.count
        return (0 ..< columnCount).map { images[(start + $0) % images.count] }
    }

    /// "12–14 / 214" when the page is contiguous, "14·1·2 / 214" when it wraps
    /// — the wrap case is what stops the label from lying about position.
    var rangeLabel: String {
        guard !images.isEmpty else { return "— / —" }
        let count = images.count
        let positions = (0 ..< columnCount).map { (pageStart + $0) % count + 1 }
        guard let first = positions.first, let last = positions.last else { return "— / —" }
        if positions.count == 1 {
            return "\(first) / \(count)"
        }
        let contiguous = positions.enumerated().allSatisfy { offset, value in
            offset == 0 || value == positions[offset - 1] + 1
        }
        if contiguous {
            return "\(first)–\(last) / \(count)"
        }
        return positions.map(String.init).joined(separator: "·") + " / \(count)"
    }

    /// Spoken/visible identity for one tile: position in the folder plus the
    /// filename, which survives cover-cropping in a way the picture does not.
    func positionLabel(for url: URL) -> String {
        guard let index = images.firstIndex(of: url) else { return url.lastPathComponent }
        return "Photograph \(index + 1) of \(images.count), \(url.lastPathComponent)"
    }

    // MARK: - Intents

    /// Reads a folder and starts a new show from its first page. Nothing is
    /// written down: the next launch is blank again (adr-102).
    func open(_ folderURL: URL) {
        do {
            let found = try FolderScanner.imageURLs(in: folderURL)
            folder = folderURL
            images = found
            pageStart = 0
            errorMessage = found.isEmpty ? "No photographs in “\(folderURL.lastPathComponent)”." : nil
        } catch {
            errorMessage = "Could not read “\(folderURL.lastPathComponent)”."
        }
    }

    func togglePlayback() {
        isPlaying.toggle()
    }

    /// Manual skip: rotates, then tells the view to restart its timer.
    func nextPage() {
        advance(byPages: 1)
        skipGeneration += 1
    }

    func previousPage() {
        advance(byPages: -1)
        skipGeneration += 1
    }

    /// Timer-driven advance. Deliberately does not bump `skipGeneration`, so the
    /// running loop keeps its cadence instead of restarting itself each page.
    func advanceAutomatically() {
        advance(byPages: 1)
    }

    /// Moves the window by whole pages and wraps in both directions. Exposed
    /// for tests; the UI goes through the four intents above.
    func advance(byPages pages: Int) {
        guard !images.isEmpty else { return }
        let step = pages * columnCount
        pageStart = ((pageStart + step) % images.count + images.count) % images.count
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Clamping

    private func clamped(_ columns: Int) -> Int {
        min(max(columns, Self.columnRange.lowerBound), Self.columnRange.upperBound)
    }

    private func clamped(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return Self.holdRange.lowerBound }
        return min(max(seconds, Self.holdRange.lowerBound), Self.holdRange.upperBound)
    }
}
