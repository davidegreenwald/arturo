import Foundation

/// Drives the rotation: sleep one hold, advance one page, forever.
///
/// Extracted from the view so the cadence contract is testable without a window:
/// exactly one advance per hold, the hold read fresh on each iteration (so a
/// dwell-time change applies to the next rotation), and a throwing clock ending
/// the loop rather than being swallowed. The view owns the paused and
/// empty-folder guards, and cancellation.
@MainActor
func runRotationLoop(
    clock: any TickingClock,
    holdDuration: () -> Duration,
    advance: () -> Void
) async {
    while !Task.isCancelled {
        do {
            try await clock.sleep(for: holdDuration())
        } catch {
            return
        }

        guard !Task.isCancelled else { return }
        advance()
    }
}
