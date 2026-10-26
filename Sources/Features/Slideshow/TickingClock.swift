import Foundation

/// Injectable time source (house rule, see CONTRIBUTING.md): views
/// own the cadence, the clock stays swappable so a test never sleeps.
protocol TickingClock: Sendable {
    func sleep(for duration: Duration) async throws
}

struct SystemTickingClock: TickingClock {
    func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }
}
