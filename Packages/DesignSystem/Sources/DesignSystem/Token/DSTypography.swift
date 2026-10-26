import SwiftUI

/// Typography tokens. Type styles resolve to Dynamic-Type-capable fonts so
/// text scales with user settings; fixed sizes exist only for the numeric
/// "value" style that gives cards their glanceable hierarchy.
public extension DS {
    enum Font {
        /// Card headline — Dynamic Type text style.
        public static let title = SwiftUI.Font.system(.headline)

        /// Supporting labels and captions.
        public static let caption = SwiftUI.Font.system(.caption)

        /// The large numeric value on a metric card (direction 11's 76px
        /// number, scaled down for a two-column grid). Rounded design pairs
        /// with the native-baseline look (D7).
        public static func value(size: CGFloat = 28) -> SwiftUI.Font {
            .system(size: size, weight: .semibold, design: .rounded)
        }

        /// Counters and position readouts. Monospaced so a number that changes
        /// every six seconds does not shift the controls around it.
        public static let counter = SwiftUI.Font.system(.caption, design: .monospaced)
    }
}
