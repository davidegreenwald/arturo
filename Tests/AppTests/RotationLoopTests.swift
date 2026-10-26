@testable import Arturo
import Foundation
import Testing

/// Suite for the rotation cadence. The clock is scripted, so the assertions are
/// about behaviour (one advance per hold, the hold read fresh, a throwing clock
/// ending the loop) and never about elapsed wall-clock time.
@Suite("Rotation loop")
@MainActor
struct RotationLoopTests {
    /// Records what the loop asked for, then throws once the script runs out —
    /// the same way a cancelled `ContinuousClock.sleep` ends it in the app.
    private actor ScriptedClock: TickingClock {
        private var requests: [Duration] = []
        private let limit: Int

        init(limit: Int) {
            self.limit = limit
        }

        func sleep(for duration: Duration) async throws {
            requests.append(duration)
            if requests.count > limit {
                throw CancellationError()
            }
        }

        func recorded() -> [Duration] {
            requests
        }
    }

    @Test("advances once per hold, then stops when the clock ends")
    func advancesPerHold() async {
        let clock = ScriptedClock(limit: 3)
        var advances = 0

        await runRotationLoop(
            clock: clock,
            holdDuration: { .seconds(6) },
            advance: { advances += 1 }
        )

        #expect(advances == 3)
        #expect(await clock.recorded() == Array(repeating: Duration.seconds(6), count: 4))
    }

    @Test("reads the hold fresh each rotation, so a change applies to the next one")
    func readsHoldEachIteration() async {
        let clock = ScriptedClock(limit: 3)
        var hold = Duration.seconds(6)

        await runRotationLoop(
            clock: clock,
            holdDuration: { hold },
            advance: {
                // Simulates the user dragging the slider while the show runs.
                hold = .seconds(9)
            }
        )

        #expect(await clock.recorded() == [.seconds(6), .seconds(9), .seconds(9), .seconds(9)])
    }

    @Test("a cancelled task advances nothing further")
    func cancellationStopsAdvancing() async {
        let clock = ScriptedClock(limit: 1000)
        var advances = 0

        let task = Task {
            await runRotationLoop(
                clock: clock,
                holdDuration: { .milliseconds(1) },
                advance: { advances += 1 }
            )
        }
        task.cancel()
        await task.value

        // Cancellation can land before the first sleep returns, so the count is
        // allowed to be zero or one — what matters is that the loop ended.
        #expect(advances <= 1)
    }
}
