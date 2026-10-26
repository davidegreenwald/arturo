import AppKit

/// App lifecycle seam. Arturo is a one-window app, so closing the window
/// must end the process — without this, a closed viewer keeps a Dock tile and
/// a menu bar with nothing to show.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }
}
