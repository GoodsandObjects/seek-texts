import Foundation
import Combine

@MainActor
final class PaywallViewModel: ObservableObject {
    @Published var selectedPlan: SubscriptionPlan = .annual
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let purchaseService: PurchaseService

    init(purchaseService: PurchaseService? = nil) {
        self.purchaseService = purchaseService ?? DefaultPurchaseService()
    }

    func purchaseSelectedPlan() async -> Bool {
        if EntitlementManager.shared.isPremium {
            return true
        }

        isLoading = true
        defer { isLoading = false }

        do {
            try await purchaseService.purchase(plan: selectedPlan)
            return EntitlementManager.shared.isPremium
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Unable to complete purchase right now."
            return false
        }
    }

    func restorePurchases() async -> Bool {
        if EntitlementManager.shared.isPremium {
            return true
        }

        isLoading = true
        defer { isLoading = false }

        do {
            try await purchaseService.restore()
            return EntitlementManager.shared.isPremium
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Unable to restore purchases right now."
            return false
        }
    }
}
