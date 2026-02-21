import Foundation

enum SubscriptionStore {
    private static let key = "seek.subscription.v1"

    static func load() -> SubscriptionState {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(SubscriptionState.self, from: data) else {
            return SubscriptionState()
        }
        return decoded
    }

    static func save(_ state: SubscriptionState) {
        guard let encoded = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(encoded, forKey: key)
    }
}

