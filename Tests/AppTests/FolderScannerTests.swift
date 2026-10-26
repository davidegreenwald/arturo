@testable import Arturo
import Foundation
import Testing

/// Unit suite for the folder contract: what counts as a photograph, in what
/// order, and what gets ignored. Written against the acceptance criteria, not
/// against the implementation (see CONTRIBUTING.md).
@Suite("Folder scanning")
struct FolderScannerTests {
    private func makeFolder(_ fileNames: [String], directories: [String] = []) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "slideshow-scan-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        for name in fileNames {
            try Data().write(to: root.appending(path: name))
        }
        for name in directories {
            try FileManager.default.createDirectory(
                at: root.appending(path: name),
                withIntermediateDirectories: true
            )
        }
        return root
    }

    @Test("keeps decodable photographs, drops everything else")
    func filtersByExtension() throws {
        let folder = try makeFolder(["a.jpg", "b.png", "notes.txt", ".hidden.jpg", "scan.dng"])

        let names = try FolderScanner.imageURLs(in: folder).map(\.lastPathComponent)

        #expect(names == ["a.jpg", "b.png"])
    }

    @Test("sorts the way Finder sorts: numbers compare numerically")
    func naturalOrder() throws {
        let folder = try makeFolder(["frame10.heic", "frame2.heic", "frame1.heic"])

        let names = try FolderScanner.imageURLs(in: folder).map(\.lastPathComponent)

        #expect(names == ["frame1.heic", "frame2.heic", "frame10.heic"])
    }

    @Test("numeric ordering holds across a wider range")
    func wideNumericOrder() throws {
        let folder = try makeFolder([
            "IMG_100.jpg", "IMG_9.jpg", "IMG_10.jpg", "IMG_2.jpg", "IMG_1.jpg",
        ])

        let names = try FolderScanner.imageURLs(in: folder).map(\.lastPathComponent)

        #expect(names == ["IMG_1.jpg", "IMG_2.jpg", "IMG_9.jpg", "IMG_10.jpg", "IMG_100.jpg"])
    }

    /// Guards the sort-key optimization: deriving the key once per file and
    /// sorting on it must not drop, duplicate, or rewrite entries.
    @Test("sorting preserves every file exactly once")
    func sortingIsLossless() throws {
        let fileNames = (1 ... 50).map { "photo-\($0).jpg" }
        let folder = try makeFolder(fileNames.shuffled())

        let scanned = try FolderScanner.imageURLs(in: folder).map(\.lastPathComponent)

        #expect(scanned.count == fileNames.count)
        #expect(Set(scanned) == Set(fileNames))
    }

    @Test("a directory named like a photograph is not a photograph")
    func skipsDirectories() throws {
        let folder = try makeFolder(["real.jpg"], directories: ["album.jpg"])

        let names = try FolderScanner.imageURLs(in: folder).map(\.lastPathComponent)

        #expect(names == ["real.jpg"])
    }

    @Test("an empty folder is an empty list, not an error")
    func emptyFolder() throws {
        let folder = try makeFolder([])

        #expect(try FolderScanner.imageURLs(in: folder).isEmpty)
    }

    @Test("extension matching is case-insensitive")
    func caseInsensitiveExtensions() throws {
        let folder = try makeFolder(["SHOUT.JPG", "MiXeD.PnG"])

        let names = try FolderScanner.imageURLs(in: folder).map(\.lastPathComponent)

        #expect(names == ["MiXeD.PnG", "SHOUT.JPG"])
    }
}
