import Foundation

/// The one place a folder gets chosen. Shared by the toolbar button, the
/// empty state, ⌘O, and the `o` key, so all four paths behave identically.
@MainActor
enum ViewerActions {
    /// Presents the folder panel, loads what it contains, and starts the show.
    /// Entering full screen here — and nowhere else — is what keeps a restored
    /// session from stealing the screen at launch.
    static func openFolder(into model: SlideshowModel) {
        let startingPoint = model.folder?.deletingLastPathComponent()
        guard let folder = FolderPanelBridge.chooseFolder(startingAt: startingPoint) else { return }

        model.open(folder)
        guard !model.images.isEmpty else { return }

        model.isPlaying = true
        FullScreenBridge.enter()
    }
}
