import Foundation

enum SubscriptionPlan: String, CaseIterable {
    case monthly
    case annual

    var title: String {
        switch self {
        case .monthly:
            return "Monthly"
        case .annual:
            return "Annual"
        }
    }
}

protocol PurchaseService {
    func purchase(plan: SubscriptionPlan) async throws
    func restore() async throws
}

enum PurchaseServiceError: LocalizedError {
    case noActiveSubscriptionToRestore

    var errorDescription: String? {
        switch self {
        case .noActiveSubscriptionToRestore:
            return "No active subscription found to restore."
        }
    }
}

struct DefaultPurchaseService: PurchaseService {
    func purchase(plan: SubscriptionPlan) async throws {
        try await StoreManager.shared.purchase(plan: plan)
    }

    func restore() async throws {
        try await StoreManager.shared.restorePurchases()
        if !EntitlementManager.shared.isPremium {
            throw PurchaseServiceError.noActiveSubscriptionToRestore
        }
    }
}
