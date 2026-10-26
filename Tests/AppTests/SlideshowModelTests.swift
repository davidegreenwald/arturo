@testable import Arturo
import Foundation
import Testing

/// Unit suite for the rotation contract: which photographs are on screen, what
/// a skip does, and what survives a relaunch. No window, no AppKit, no timers.
@Suite("Slideshow rotation")
@MainActor
struct SlideshowModelTests {
    private func makeDefaults() throws -> UserDefaults {
        let name = "arturo.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// Photographs are never decoded by the model, so empty files are enough.
    private func makeFolder(count: Int) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "slideshow-model-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        for index in 1 ... max(count, 1) where count > 0 {
            try Data().write(to: root.appending(path: String(format: "photo-%03d.jpg", index)))
        }
        return root
    }

    @Test("opening a folder lists its photographs and starts on the first page")
    func openingFolder() throws {
        let model = try SlideshowModel(defaults: makeDefaults())
        try model.open(makeFolder(count: 7))

        #expect(model.images.count == 7)
        #expect(model.pageStart == 0)
        #expect(model.errorMessage == nil)
        #expect(model.visibleImages.count == 3)
        #expect(model.visibleImages.first?.lastPathComponent == "photo-001.jpg")
    }

    @Test("columns never exceed the photographs a folder holds")
    func columnsCappedByFolderSize() throws {
        let model = try SlideshowModel(defaults: makeDefaults())
        model.preferredColumns = 3
        try model.open(makeFolder(count: 2))

        #expect(model.columnCount == 2)
        #expect(model.visibleImages.count == 2)

        model.preferredColumns = 1
        #expect(model.columnCount == 1)
    }

    @Test("a one-column page is a single photograph")
    func singleColumnPage() throws {
        let model = try SlideshowModel(defaults: makeDefaults())
        try model.open(makeFolder(count: 4))
        model.preferredColumns = 1

        #expect(model.visibleImages == [model.images[0]])
    }

    @Test("pages advance and wrap forever in both directions")
    func wrapping() throws {
        let model = try SlideshowModel(defaults: makeDefaults())
        model.preferredColumns = 3
        try model.open(makeFolder(count: 5))

        var starts = [model.pageStart]
        for _ in 0 ..< 5 {
            model.advanceAutomatically()
            starts.append(model.pageStart)
        }

        #expect(starts == [0, 3, 1, 4, 2, 0])

        // Backwards from the first page lands on the last full page.
        model.previousPage()
        #expect(model.pageStart == 2)
    }

    @Test("only a manual skip restarts the rotation clock")
    func skipGeneration() throws {
        let model = try SlideshowModel(defaults: makeDefaults())
        try model.open(makeFolder(count: 5))

        #expect(model.skipGeneration == 0)

        model.advanceAutomatically()
        #expect(model.skipGeneration == 0)

        model.nextPage()
        #expect(model.skipGeneration == 1)

        model.previousPage()
        #expect(model.skipGeneration == 2)
    }

    @Test("the position label tells the truth when a page wraps")
    func rangeLabels() throws {
        let model = try SlideshowModel(defaults: makeDefaults())
        model.preferredColumns = 3
        try model.open(makeFolder(count: 5))

        #expect(model.rangeLabel == "1–3 / 5")

        model.nextPage()
        // Photographs 4 and 5, then back to the top of the folder.
        #expect(model.rangeLabel == "4·5·1 / 5")

        model.preferredColumns = 1
        #expect(model.rangeLabel == "4 / 5")
    }

    @Test("advancing with no photographs is a no-op")
    func advanceWithoutPhotographs() throws {
        let model = try SlideshowModel(defaults: makeDefaults())

        model.advanceAutomatically()
        model.nextPage()

        #expect(model.pageStart == 0)
        #expect(model.visibleImages.isEmpty)
    }

    @Test("an empty folder reports instead of showing a silent blank canvas")
    func emptyFolderMessage() throws {
        let model = try SlideshowModel(defaults: makeDefaults())
        try model.open(makeFolder(count: 0))

        #expect(model.images.isEmpty)
        #expect(model.columnCount == 0)
        #expect(model.rangeLabel == "— / —")
        #expect(model.errorMessage != nil)
    }

    @Test("hold time is clamped when used, not silently stored out of range")
    func holdClamping() throws {
        let model = try SlideshowModel(defaults: makeDefaults())

        model.holdSeconds = 900
        #expect(model.holdDuration == .seconds(30))

        // The floor is half a second: fast skimming is allowed, a hold of zero
        // would be a flicker.
        model.holdSeconds = 0
        #expect(model.holdDuration == .seconds(0.5))

        model.holdSeconds = 1
        #expect(model.holdDuration == .seconds(1))
    }

    private struct HoldLabelCase {
        let seconds: Double
        let label: String
        let spoken: String
    }

    @Test("half-second holds read correctly in the pill and to VoiceOver")
    func holdLabels() throws {
        let model = try SlideshowModel(defaults: makeDefaults())

        let cases: [HoldLabelCase] = [
            HoldLabelCase(seconds: 0.5, label: "0.5s", spoken: "half a second"),
            HoldLabelCase(seconds: 1, label: "1s", spoken: "1 second"),
            HoldLabelCase(seconds: 1.5, label: "1.5s", spoken: "1.5 seconds"),
            HoldLabelCase(seconds: 6, label: "6s", spoken: "6 seconds"),
            HoldLabelCase(seconds: 30, label: "30s", spoken: "30 seconds"),
        ]

        for testCase in cases {
            model.holdSeconds = testCase.seconds
            #expect(model.holdLabel == testCase.label, "label for \(testCase.seconds)s")
            #expect(model.holdSpokenLabel == testCase.spoken, "spoken label for \(testCase.seconds)s")
        }
    }

    @Test("view preferences survive a relaunch")
    func preferencesSurviveRelaunch() throws {
        let defaults = try makeDefaults()
        let folder = try makeFolder(count: 4)

        let first = SlideshowModel(defaults: defaults)
        first.holdSeconds = 12
        first.preferredColumns = 2
        first.open(folder)

        let second = SlideshowModel(defaults: defaults)

        #expect(second.holdSeconds == 12)
        #expect(second.preferredColumns == 2)
    }

    @Test("the app always launches blank, however the last session ended")
    func launchesBlank() throws {
        let defaults = try makeDefaults()

        let first = SlideshowModel(defaults: defaults)
        try first.open(makeFolder(count: 4))
        #expect(first.images.count == 4)

        let second = SlideshowModel(defaults: defaults)

        #expect(second.images.isEmpty, "a previous folder must not come back")
        #expect(second.folder == nil)
        #expect(second.errorMessage == nil, "blank is not an error state")
    }

    @Test("--folder opens a folder for this launch only")
    func folderLaunchArgument() throws {
        let defaults = try makeDefaults()
        let folder = try makeFolder(count: 3)

        let withArgument = SlideshowModel(
            defaults: defaults,
            arguments: ["Arturo", "--folder", folder.path]
        )
        #expect(withArgument.images.count == 3)

        let withoutArgument = SlideshowModel(defaults: defaults, arguments: ["Arturo"])
        #expect(withoutArgument.images.isEmpty, "the argument is not remembered either")
    }

    @Test("a dangling --folder is ignored instead of crashing")
    func danglingFolderArgument() throws {
        let model = try SlideshowModel(defaults: makeDefaults(), arguments: ["Arturo", "--folder"])

        #expect(model.images.isEmpty)
    }

    @Test("playback defaults to running and toggles")
    func playbackToggle() throws {
        let model = try SlideshowModel(defaults: makeDefaults())

        #expect(model.isPlaying)

        model.togglePlayback()
        #expect(!model.isPlaying)

        model.togglePlayback()
        #expect(model.isPlaying)
    }

    @Test("fit is the default, and a switch to fill survives a relaunch")
    func fillsFramesPreference() throws {
        let defaults = try makeDefaults()

        let first = SlideshowModel(defaults: defaults)
        #expect(!first.fillsFrames, "a viewer must not crop a photograph unasked")

        first.fillsFrames = true
        let second = SlideshowModel(defaults: defaults)
        #expect(second.fillsFrames)
    }

    @Test("a tile's spoken label carries its position and filename")
    func positionLabel() throws {
        let model = try SlideshowModel(defaults: makeDefaults())
        try model.open(makeFolder(count: 3))

        #expect(model.positionLabel(for: model.images[1]) == "Photograph 2 of 3, photo-002.jpg")
    }
}
