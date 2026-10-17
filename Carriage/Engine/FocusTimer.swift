import Foundation
import Observation

/// A kitchen-timer style focus session that rings the bell when it's done.
@Observable
final class FocusTimer {
    private(set) var endsAt: Date?
    private(set) var duration: TimeInterval = 0
    /// Words written today when the session began, to report the session's total.
    private(set) var wordsAtStart: Int?

    @ObservationIgnored var onFinish: (() -> Void)?
    @ObservationIgnored private var timer: Timer?

    var isRunning: Bool { endsAt != nil }

    func start(minutes: Int, wordsToday: Int) {
        duration = TimeInterval(minutes * 60)
        endsAt = Date().addingTimeInterval(duration)
        wordsAtStart = wordsToday
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        endsAt = nil
    }

    func remaining(at date: Date = .now) -> TimeInterval {
        guard let endsAt else { return 0 }
        return max(0, endsAt.timeIntervalSince(date))
    }

    /// Catches up after the app comes back from the background.
    func tick() {
        guard let endsAt, Date() >= endsAt else { return }
        stop()
        onFinish?()
    }
}
