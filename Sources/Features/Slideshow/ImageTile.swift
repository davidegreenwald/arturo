import DesignSystem
import SwiftUI

/// One photograph in its column.
///
/// Fitted (default) keeps the picture's own shape and letterboxes it against the
/// canvas; filled crops the overflow so the column is covered edge to edge. The
/// two are the entire difference between a gallery and a contact sheet, so the
/// choice is explicit, persisted, and visible in the transport pill.
///
/// The tile takes an explicit size rather than `maxWidth: .infinity` because a
/// filled image has an unbounded ideal size: left to negotiate, the three tiles
/// resolve unequal widths and the last one lands off-screen.
struct ImageTile: View {
    let url: URL
    let store: ImageStore
    let label: String
    let fillsFrame: Bool
    let tileSize: CGSize

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            if let frame = store.frame(for: url) {
                picture(frame)
                    .transition(.opacity)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .opacity(0.5)
            }
        }
        .frame(width: tileSize.width, height: tileSize.height)
        // A filled picture is larger than its column by definition; without
        // this it would paint over its neighbours.
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func picture(_ frame: LoadedImage) -> some View {
        let image = Image(decorative: frame.cgImage, scale: displayScale)
            .resizable()

        if fillsFrame {
            image
                .scaledToFill()
                .clipShape(.rect(cornerRadius: DS.Radius.tile))
        } else {
            image
                .scaledToFit()
                .clipShape(.rect(cornerRadius: DS.Radius.tile))
        }
    }
}
