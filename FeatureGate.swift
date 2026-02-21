import Foundation

enum FeatureGate {
    static func canUseUnlimitedStudy() -> Bool {
        EntitlementManager.shared.isPremium
    }
}

