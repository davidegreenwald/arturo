import DesignSystem
import SwiftUI

/// The transport pill: play/pause, page skips, column count, dwell time, and
/// where the current page sits in the folder.
///
/// It is the only chrome the viewer owns, so it stays a single row and never
/// wraps — the width is fixed by construction (`fixedSize`) rather than pushed
/// around by the window.
struct ViewerControls: View {
    @Bindable var model: SlideshowModel
    let onOpenFolder: () -> Void
    let onToggleFullScreen: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.xxs) {
            transport
            rule
            columns
            rule
            frameStyle
            rule
            hold
            rule
            Text(model.rangeLabel)
                .font(DS.Font.counter)
                .monospacedDigit()
                .foregroundStyle(DS.Color.textPrimary.opacity(0.85))
                .padding(.horizontal, DS.Space.xxs)
                .accessibilityIdentifier("position-label")
            rule
            utilities
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.xs)
        .background(.regularMaterial, in: .capsule)
        .overlay(Capsule().strokeBorder(DS.Color.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
        .fixedSize()
    }

    private var transport: some View {
        HStack(spacing: 2) {
            iconButton("backward.end.fill", label: "Previous page", action: model.previousPage)

            Button(action: model.togglePlayback) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Color.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(DS.Color.textPrimary.opacity(0.1), in: .circle)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
            .help(model.isPlaying ? "Pause" : "Play")

            iconButton("forward.end.fill", label: "Next page", action: model.nextPage)
        }
    }

    private var columns: some View {
        HStack(spacing: DS.Space.xs) {
            Text("Across")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textPrimary.opacity(0.75))

            HStack(spacing: 0) {
                ForEach(SlideshowModel.columnRange, id: \.self) { count in
                    let isSelected = model.preferredColumns == count
                    Button {
                        model.preferredColumns = count
                    } label: {
                        Text("\(count)")
                            .font(DS.Font.counter)
                            .foregroundStyle(isSelected ? DS.Color.textPrimary : DS.Color.textSecondary)
                            .frame(width: 22, height: 22)
                            .background(
                                isSelected ? DS.Color.textPrimary.opacity(0.14) : .clear,
                                in: .capsule
                            )
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show \(count) across")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(2)
            .background(DS.Color.textPrimary.opacity(0.06), in: .capsule)
        }
    }

    /// One chip, not a segmented control: the two states are "how it ships" and
    /// "a deliberate crop", so the control reads as a toggle rather than a
    /// choice of equals.
    private var frameStyle: some View {
        Button {
            model.fillsFrames.toggle()
        } label: {
            HStack(spacing: DS.Space.xxs) {
                Image(systemName: model.fillsFrames ? "square.fill" : "square.dashed")
                    .font(.system(size: 10, weight: .semibold))
                Text("Fill")
                    .font(DS.Font.caption)
            }
            .foregroundStyle(model.fillsFrames ? DS.Color.textPrimary : DS.Color.textPrimary.opacity(0.75))
            .padding(.horizontal, DS.Space.xs)
            .frame(height: 22)
            .background(
                model.fillsFrames ? DS.Color.textPrimary.opacity(0.14) : .clear,
                in: .capsule
            )
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Fill frame")
        .accessibilityValue(model.fillsFrames ? "On" : "Off")
        .accessibilityAddTraits(model.fillsFrames ? .isSelected : [])
        .help(model.fillsFrames ? "Fit each photograph to its frame" : "Fill each frame, cropping the overflow")
    }

    private var hold: some View {
        HStack(spacing: DS.Space.xs) {
            Text("Hold")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textPrimary.opacity(0.75))

            Slider(value: $model.holdSeconds, in: SlideshowModel.holdRange, step: SlideshowModel.holdStep)
                .labelsHidden()
                .controlSize(.mini)
                .tint(DS.Color.accent)
                .frame(width: 84)
                .accessibilityLabel("Hold each page")
                .accessibilityValue(model.holdSpokenLabel)

            Text(model.holdLabel)
                .font(DS.Font.counter)
                .monospacedDigit()
                .foregroundStyle(DS.Color.textPrimary)
                .frame(width: 32, alignment: .trailing)
        }
    }

    private var utilities: some View {
        HStack(spacing: 2) {
            iconButton("folder", label: "Open folder", action: onOpenFolder)
            iconButton("arrow.up.left.and.arrow.down.right", label: "Full screen", action: onToggleFullScreen)
        }
    }

    private var rule: some View {
        Rectangle()
            .fill(DS.Color.hairline)
            .frame(width: 1, height: 18)
            .padding(.horizontal, DS.Space.xxs)
            .accessibilityHidden(true)
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Color.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}
