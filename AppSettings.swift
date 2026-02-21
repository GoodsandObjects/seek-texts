import Foundation

final class AppSettings {
    static let shared = AppSettings()

    private let defaults: UserDefaults
    private let sandboxKey = "seek_guided_sandbox"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isSandboxModeEnabled: Bool {
        defaults.bool(forKey: sandboxKey)
    }
}

