import Foundation

enum StreakEngagementSource: String, Codable {
    case reader
    case study
}

extension Notification.Name {
    static let streakDidUpdate = Notification.Name("seek.streak.didUpdate")
}

final class StreakTracker {
    static let shared = StreakTracker()

    func markEngaged(source: StreakEngagementSource, at date: Date = Date()) {
        // Streaks are now qualification-based. This API remains for compatibility with
        // older call sites and performs no automatic streak increment.
        _ = source
        _ = date
        if source == .reader {
            StreakManager.shared.updateStreakIfQualified()
        }
    }

    #if DEBUG
    func debugState() -> StreakState? {
        StreakStore().load()
    }

    func debugReset() {
        StreakManager.shared.debugResetAll()
    }
    #endif
}
