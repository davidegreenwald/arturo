import CoreGraphics

/// The namespace every token lives under: `DS.Space.md`, `DS.Radius.card`, …
/// One namespace keeps component call sites greppable for token usage.
public enum DS {}

public extension DS {
    /// Spacing scale (4-point base).
    enum Space {
        public static let xxs: CGFloat = 4
        public static let xs: CGFloat = 8
        public static let sm: CGFloat = 12
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 24
    }

    /// Corner radii. `pill` is a shape intent, not a measurement — it means
    /// "fully rounded", so a future radius token change cannot break it.
    enum Radius {
        public static let card: CGFloat = 10
        public static let control: CGFloat = 6
        public static let pill: CGFloat = .infinity

        /// A photograph's own corners. Deliberately almost square: rounding a
        /// picture is a crop, and this viewer does not crop.
        public static let tile: CGFloat = 2
    }
}
