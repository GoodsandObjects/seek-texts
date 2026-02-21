import Foundation

struct StreakStore {
    private let defaults: UserDefaults
    private let key = "seek_streak_state_v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> StreakState? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(StreakState.self, from: data)
    }

    func save(_ state: StreakState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
        Task { @MainActor in
            StreakManager.shared.applyLegacyDebugState(state)
        }
    }

    func reset() {
        defaults.removeObject(forKey: key)
        Task { @MainActor in
            StreakManager.shared.debugResetAll()
        }
    }
}
