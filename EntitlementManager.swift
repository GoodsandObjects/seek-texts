import Foundation
import Combine

final class EntitlementManager: ObservableObject {
    static let shared = EntitlementManager()

    @Published private(set) var state: SubscriptionState

    private init() {
        state = SubscriptionStore.load()
        applySandboxOverrideIfNeeded()
    }

    var isPremium: Bool {
        state.isPremium
    }

    func setPremium(_ value: Bool, source: String, expirationDate: Date? = nil) {
        state.isPremium = value
        state.source = source
        state.expirationDate = expirationDate
        SubscriptionStore.save(state)
        applySandboxOverrideIfNeeded()
    }

    func applyStoreKitEntitlement(isPremium: Bool, expirationDate: Date?) {
        setPremium(isPremium, source: "storekit", expirationDate: expirationDate)
    }

    func applySandboxOverrideIfNeeded() {
        let stored = SubscriptionStore.load()
        state = stored

        #if DEBUG
        if AppSettings.shared.isSandboxModeEnabled {
            state.isPremium = true
            state.source = "sandbox"
        }
        #endif
    }
}
