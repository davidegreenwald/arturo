import Foundation

/// Turns a folder into an ordered list of photographs.
///
/// Deliberately shallow and read-only: Arturo never copies, imports, or
/// moves a file, so a folder's organisation is the slideshow's order. The
/// extension allow-list is the contract for what "a photograph" means here.
enum FolderScanner {
    /// Formats macOS can decode through ImageIO. RAW is left out on purpose:
    /// it decodes on some machines and not others, and a slideshow that
    /// silently skips half a folder is worse than one that never claimed it.
    nonisolated static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp", "avif", "gif", "bmp",
    ]

    /// Non-recursive, hidden files skipped, sorted the way Finder sorts
    /// (`localizedStandardCompare`: IMG_2 before IMG_10).
    nonisolated static func imageURLs(in folder: URL) throws -> [URL] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        let photographs = contents
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .filter { url in
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }

        // Sort keys are derived once per file, not inside the comparator.
        // `lastPathComponent` inside the comparator bridges to NSString and
        // allocates a String on every comparison — about 850k times for a
        // 50,000-photo folder — and that re-derivation was ~85% of the total
        // scan time (976 ms -> 243 ms on an M-series Mac; see
        // docs/performance-baseline.md). The comparator itself is unchanged,
        // so the resulting order is identical.
        return photographs
            .map { (name: $0.lastPathComponent, url: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map(\.url)
    }
}
