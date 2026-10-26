import AppKit

/// AppKit seam: an `NSOpenPanel` is the only system-vetted way to pick a
/// folder, and SwiftUI has no equivalent (ADR-001 §D2 allows panels).
///
/// Modal by design: choosing a folder is the app's single blocking intent and
/// the viewer has nothing to animate behind the panel.
@MainActor
enum FolderPanelBridge {
    static func chooseFolder(startingAt directory: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        // A Photos library or an app bundle is a single item, not a photo
        // folder — refuse to treat it as a directory to walk.
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = "Show"
        panel.message = "Choose a folder of photographs"
        if let directory {
            panel.directoryURL = directory
        }
        return panel.runModal() == .OK ? panel.url : nil
    }
}
