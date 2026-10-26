import AppKit

/// The keys the viewer answers to, independent of which control holds focus.
enum ViewerKey: Sendable {
    case previous
    case next
    case togglePlayback
    case toggleFullScreen
    case openFolder
}

/// AppKit seam: a local event monitor taps the responder chain before SwiftUI
/// resolves focus (ADR-001 §D2 "responder-chain interactions"). Arrow keys must
/// work while a slider or a button holds focus, and `.onKeyPress` cannot
/// promise that.
///
/// Only unmodified keys are claimed; anything with ⌘/⌃/⌥ continues to its menu
/// equivalent. Keys are dropped while a modal panel is up, so typing a folder
/// name never pages the slideshow behind it.
@MainActor
final class KeyboardMonitorBridge {
    /// The monitor's handler is `@Sendable` and `NSEvent` is explicitly not, so
    /// the event is reduced to these plain values before crossing isolation.
    private struct KeyStroke: Sendable {
        let keyCode: UInt16
        let characters: String?
        let modifiers: UInt
    }

    private enum KeyCode {
        static let leftArrow: UInt16 = 123
        static let rightArrow: UInt16 = 124
    }

    private var token: Any?

    func start(handler: @escaping @MainActor (ViewerKey) -> Void) {
        guard token == nil else { return }

        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let stroke = KeyStroke(
                keyCode: event.keyCode,
                characters: event.charactersIgnoringModifiers,
                modifiers: event.modifierFlags.rawValue
            )
            let claimed = MainActor.assumeIsolated { Self.claim(stroke, handler: handler) }
            return claimed ? nil : event
        }
    }

    func stop() {
        if let token {
            NSEvent.removeMonitor(token)
        }
        token = nil
    }

    /// Returns true when the app should swallow the event.
    private static func claim(_ stroke: KeyStroke, handler: (ViewerKey) -> Void) -> Bool {
        let blocking: NSEvent.ModifierFlags = [.command, .control, .option]
        guard NSEvent.ModifierFlags(rawValue: stroke.modifiers).isDisjoint(with: blocking),
              NSApplication.shared.modalWindow == nil,
              NSApplication.shared.keyWindow?.attachedSheet == nil,
              let key = viewerKey(for: stroke) else { return false }
        handler(key)
        return true
    }

    private static func viewerKey(for stroke: KeyStroke) -> ViewerKey? {
        switch stroke.keyCode {
        case KeyCode.leftArrow:
            return .previous
        case KeyCode.rightArrow:
            return .next
        default:
            break
        }

        switch stroke.characters?.lowercased() {
        case " ":
            return .togglePlayback
        case "f":
            return .toggleFullScreen
        case "o":
            return .openFolder
        default:
            return nil
        }
    }
}
