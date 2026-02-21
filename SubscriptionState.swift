import Foundation

struct SubscriptionState: Codable {
    var isPremium: Bool
    var source: String?
    var expirationDate: Date?

    init(isPremium: Bool = false, source: String? = nil, expirationDate: Date? = nil) {
        self.isPremium = isPremium
        self.source = source
        self.expirationDate = expirationDate
    }
}

