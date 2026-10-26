import DesignSystem
import SwiftUI

/// First run: no folder, no photographs, one action worth taking and the four
/// keys worth knowing. Deliberately not a controls skeleton — the pill appears
/// once there is something to control.
struct EmptyStageView: View {
    let onOpenFolder: () -> Void

    var body: some View {
        VStack(spacing: DS.Space.md) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(DS.Color.textTertiary)
                .accessibilityHidden(true)

            VStack(spacing: DS.Space.xxs) {
                Text("No folder open")
                    .font(DS.Font.title)
                    .foregroundStyle(DS.Color.textPrimary)

                Text(
                    "Choose a folder of photographs. Arturo reads them in place — "
                        + "nothing is copied, imported, or moved."
                )
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            }

            Button("Open a Folder…", action: onOpenFolder)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityHint("Choose a folder of photographs to show")

            Text("⌘O open · ← → skip · space pause · F full screen")
                .font(DS.Font.counter)
                .foregroundStyle(DS.Color.textTertiary)
                .padding(.top, DS.Space.xs)
        }
        .padding(DS.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
