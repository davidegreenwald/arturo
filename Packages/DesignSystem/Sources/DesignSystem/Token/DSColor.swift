import AppKit
import SwiftUI

/// Semantic color tokens (ADR-001, D7 native baseline).
///
/// Components reference these — literal colors appear here and nowhere else
/// (see CONTRIBUTING.md). Light/dark resolution comes free from
/// the system semantics wrapped below; a theme overrides tokens, never call
/// sites (theme adoption requires an ADR).
public extension DS {
    enum Color {
        /// The family accent. Placeholder until Q1 (house accent) is decided
        /// against the M2 gallery comparison; resolves to the host app's
        /// asset-catalog accent.
        public static let accent = SwiftUI.Color.accentColor

        public static let surface = SwiftUI.Color(nsColor: .windowBackgroundColor)
        public static let surfaceRaised = SwiftUI.Color(nsColor: .controlBackgroundColor)

        /// The stage behind photographs: a dark room in both system appearances.
        /// Fixed rather than adaptive — a photograph is judged against a stable
        /// surround, and a light surround washes out low-key images.
        public static let canvas = SwiftUI.Color(nsColor: NSColor(white: 0.043, alpha: 1))

        /// One-pixel separators and outlines — decorative, never a boundary by
        /// itself.
        public static let hairline = SwiftUI.Color.primary.opacity(0.14)

        public static let textPrimary = SwiftUI.Color.primary
        public static let textSecondary = SwiftUI.Color.secondary
        public static let textTertiary = SwiftUI.Color(nsColor: .tertiaryLabelColor)

        public static let positive = SwiftUI.Color(nsColor: .systemGreen)
        public static let negative = SwiftUI.Color(nsColor: .systemRed)
        public static let neutral = SwiftUI.Color(nsColor: .secondaryLabelColor)
    }
}
