import Foundation
import SwiftUI
import Combine

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults: UserDefaults
    private let sandboxKey = "seek_guided_sandbox"
    private let appearanceModeKey = "seek_appearance_mode"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedRaw = defaults.string(forKey: appearanceModeKey) ?? AppearanceMode.system.rawValue
        self.appearanceMode = AppearanceMode(rawValue: savedRaw) ?? .system
    }

    var isSandboxModeEnabled: Bool {
        defaults.bool(forKey: sandboxKey)
    }

    @Published var appearanceMode: AppearanceMode {
        didSet {
            defaults.set(appearanceMode.rawValue, forKey: appearanceModeKey)
        }
    }
}
