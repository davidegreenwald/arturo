import AppKit

/// AppKit seam: window chrome SwiftUI cannot express (ADR-001 §D2) — asking a
/// specific `NSWindow` to enter or leave macOS full screen. SwiftUI's
/// `Window` scene exposes no API for that transition.
@MainActor
enum FullScreenBridge {
    static func toggle() {
        window?.toggleFullScreen(nil)
    }

    /// Idempotent: entering while already full screen must not toggle back out.
    static func enter() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        window.toggleFullScreen(nil)
    }

    /// The open panel is its own window, so the viewer is not always `keyWindow`
    /// at the moment this is called; fall back to the first main-capable window.
    private static var window: NSWindow? {
        NSApplication.shared.keyWindow
            ?? NSApplication.shared.windows.first { $0.isVisible && $0.canBecomeMain }
    }
}
