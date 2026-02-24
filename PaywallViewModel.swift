import Foundation
import Combine
import StoreKit

@MainActor
final class PaywallViewModel: ObservableObject {
    @Published var selectedPlan: SubscriptionPlan = .annual
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var isLoadingProducts = false

    private let purchaseService: PurchaseService
    private let storeManager: StoreManager
    private var productsByID: [String: Product]
    private var cancellables: Set<AnyCancellable> = []
    private var loggedMissingPlans: Set<SubscriptionPlan> = []

    init(purchaseService: PurchaseService? = nil, storeManager: StoreManager? = nil) {
        self.purchaseService = purchaseService ?? DefaultPurchaseService()
        self.storeManager = storeManager ?? StoreManager.shared
        self.productsByID = Dictionary(uniqueKeysWithValues: self.storeManager.products.map { ($0.id, $0) })
        observeProducts()
    }

    func loadProductsIfNeeded() async {
        guard missingProductIDs().isEmpty else {
            isLoadingProducts = true
            await storeManager.fetchProducts()
            isLoadingProducts = false

            let missing = missingProductIDs()
            if !missing.isEmpty {
                #if DEBUG
                print("[PaywallViewModel] Product loading incomplete. missing=[\(missing.joined(separator: ", "))] fallback=Price unavailable")
                #endif
            }
            return
        }

        isLoadingProducts = false
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

    func priceText(for plan: SubscriptionPlan) -> String {
        guard let product = product(for: plan) else {
            if isLoadingProducts {
                return "Loading..."
            }
            logPriceFallbackIfNeeded(for: plan)
            return "Price unavailable"
        }

        switch plan {
        case .annual:
            return "\(product.displayPrice) per year"
        case .monthly:
            return "\(product.displayPrice) per month"
        }
    }

    func priceDetailText(for plan: SubscriptionPlan) -> String {
        guard plan == .annual else { return "" }
        return product(for: plan) == nil ? "Billed annually" : "Auto-renews yearly"
    }

    private func product(for plan: SubscriptionPlan) -> Product? {
        let id = plan == .annual ? StoreManager.annualProductID : StoreManager.monthlyProductID
        return productsByID[id]
    }

    private func observeProducts() {
        storeManager.$products
            .sink { [weak self] products in
                guard let self else { return }
                self.productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
                if !products.isEmpty {
                    self.loggedMissingPlans.removeAll()
                }
            }
            .store(in: &cancellables)
    }

    private func missingProductIDs() -> [String] {
        let expectedIDs: Set<String> = [StoreManager.monthlyProductID, StoreManager.annualProductID]
        return expectedIDs.subtracting(Set(productsByID.keys)).sorted()
    }

    private func logPriceFallbackIfNeeded(for plan: SubscriptionPlan) {
        guard !loggedMissingPlans.contains(plan) else { return }
        loggedMissingPlans.insert(plan)
        #if DEBUG
        print("[PaywallViewModel] Missing product for \(plan.rawValue). Showing fallback=Price unavailable")
        #endif
    }
}
