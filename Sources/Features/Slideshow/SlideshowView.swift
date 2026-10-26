import DesignSystem
import SwiftUI

/// The show: a canvas, the current page of up to three photographs, and a
/// transport pill that gets out of the way once playback settles.
///
/// Cadence lives here, not in the model (house pattern): `task(id:)` is the
/// rotation, so pausing cancels it, a manual skip restarts it, and changing the
/// hold time applies to the next sleep rather than interrupting the current one.
struct SlideshowView: View {
    private struct PlaybackKey: Hashable {
        let isPlaying: Bool
        let skipGeneration: Int
        let imageCount: Int
    }

    private struct PageKey: Hashable {
        let pageStart: Int
        let columns: Int
        let pixelTarget: Int
    }

    let model: SlideshowModel
    private let clock: any TickingClock

    @State private var store = ImageStore()
    @State private var keyboard = KeyboardMonitorBridge()
    @State private var controlsVisible = true
    @State private var idleTicks = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    init(model: SlideshowModel, clock: any TickingClock = SystemTickingClock()) {
        self.model = model
        self.clock = clock
    }

    var body: some View {
        ZStack {
            DS.Color.canvas.ignoresSafeArea()

            if model.images.isEmpty {
                EmptyStageView(onOpenFolder: openFolder)
            } else {
                stage
            }

            overlay
        }
        // The transport pill is ~610 pt wide and never wraps; a window narrower
        // than this would clip its right-hand controls.
        // A dark room in both system appearances: the materials, the pill, and
        // the empty state all resolve against the canvas instead of against a
        // white window that would wash the photographs out.
        .preferredColorScheme(.dark)
        .frame(minWidth: 720, minHeight: 420)
        .onContinuousHover { phase in
            if case .active = phase {
                revealControls()
            }
        }
        .task(id: playbackKey) { await runRotation() }
        .task { await runIdleCountdown() }
        .onAppear { keyboard.start(handler: handle) }
        .onDisappear { keyboard.stop() }
    }

    // MARK: - Stage

    private var stage: some View {
        GeometryReader { proxy in
            let columns = max(model.columnCount, 1)
            let gutter = DS.Space.xs
            let target = pixelTarget(for: proxy.size, columns: columns)
            // Full bleed: no margin between the photographs and the window edge.
            // Gutters exist only BETWEEN tiles, so the outer edges sit flush.
            // Explicit, equal tile geometry: a filled image will otherwise
            // negotiate its own width and break the grid.
            let gaps = CGFloat(max(columns - 1, 0)) * gutter
            let tileWidth = max((proxy.size.width - gaps) / CGFloat(columns), 1)
            let tileHeight = max(proxy.size.height, 1)

            HStack(spacing: gutter) {
                ForEach(model.visibleImages, id: \.self) { url in
                    ImageTile(
                        url: url,
                        store: store,
                        label: model.positionLabel(for: url),
                        fillsFrame: model.fillsFrames,
                        tileSize: CGSize(width: tileWidth, height: tileHeight)
                    )
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(pageChangeAnimation, value: model.pageStart)
            .onAppear { store.setMaxPixelSize(target) }
            .onChange(of: target) { _, newValue in store.setMaxPixelSize(newValue) }
            .task(id: PageKey(pageStart: model.pageStart, columns: columns, pixelTarget: target)) {
                // Size first: the loader must decode for this layout, not the
                // previous one. Then the visible page, then the page after it,
                // so a manual skip lands on a decoded frame.
                store.setMaxPixelSize(target)
                store.ensureLoaded(model.visibleImages + model.nextPageImages)
            }
        }
    }

    private var pageChangeAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.45)
    }

    /// Decode for the larger of the two axes a tile can occupy, in pixels.
    /// The store clamps the result; this only has to be honest about layout.
    private func pixelTarget(for size: CGSize, columns: Int) -> Int {
        let columnWidth = size.width / CGFloat(max(columns, 1))
        return Int((max(size.height, columnWidth) * displayScale).rounded())
    }

    // MARK: - Overlay

    private var overlay: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            if let message = model.errorMessage {
                errorBanner(message)
            }

            if !model.images.isEmpty {
                ViewerControls(
                    model: model,
                    onOpenFolder: openFolder,
                    onToggleFullScreen: FullScreenBridge.toggle
                )
                .padding(.horizontal, DS.Space.lg)
                .padding(.bottom, DS.Space.lg)
            }
        }
        .opacity(controlsVisible ? 1 : 0)
        .allowsHitTesting(controlsVisible)
        // A pill the user cannot see must not be in the VoiceOver order either.
        .accessibilityHidden(!controlsVisible)
        .animation(.easeInOut(duration: 0.25), value: controlsVisible)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DS.Color.negative)
            Text(message)
                .foregroundStyle(DS.Color.textPrimary)
            Button("Dismiss") { model.dismissError() }
                .buttonStyle(.plain)
                .foregroundStyle(DS.Color.accent)
        }
        .font(DS.Font.caption)
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.xs)
        .background(.regularMaterial, in: .capsule)
        .padding(.bottom, DS.Space.sm)
    }

    // MARK: - Cadence

    private var playbackKey: PlaybackKey {
        PlaybackKey(
            isPlaying: model.isPlaying,
            skipGeneration: model.skipGeneration,
            imageCount: model.images.count
        )
    }

    private func runRotation() async {
        // A one-photograph folder has nothing to rotate to; the loop would
        // redraw the same frame forever.
        guard model.isPlaying, model.images.count > 1 else { return }

        await runRotationLoop(
            clock: clock,
            holdDuration: { model.holdDuration },
            advance: { model.advanceAutomatically() }
        )
    }

    /// Counts idle ticks rather than comparing wall-clock dates, so the reveal
    /// and the countdown share one time source and stay testable.
    private func runIdleCountdown() async {
        while !Task.isCancelled {
            try? await clock.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }

            guard controlsVisible, model.isPlaying else {
                idleTicks = 0
                continue
            }

            idleTicks += 1
            if idleTicks >= 6 {
                withAnimation(.easeInOut(duration: 0.3)) {
                    controlsVisible = false
                }
            }
        }
    }

    private func revealControls() {
        idleTicks = 0
        guard !controlsVisible else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible = true
        }
    }

    // MARK: - Intents

    private func handle(_ key: ViewerKey) {
        revealControls()
        switch key {
        case .previous:
            model.previousPage()
        case .next:
            model.nextPage()
        case .togglePlayback:
            model.togglePlayback()
        case .toggleFullScreen:
            FullScreenBridge.toggle()
        case .openFolder:
            // Off the event callback: the panel runs its own modal loop, and
            // starting that inside a local event monitor is not safe.
            Task { openFolder() }
        }
    }

    private func openFolder() {
        ViewerActions.openFolder(into: model)
        revealControls()
    }
}

#Preview("Viewer") {
    SlideshowView(model: SlideshowModel(defaults: .standard))
        .frame(width: 1200, height: 760)
}
