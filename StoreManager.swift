import Foundation
import Combine
import StoreKit

@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()

    static let monthlyProductID = "com.seek.premium.monthly"
    static let annualProductID = "com.seek.premium.annual"
    static let productIDs = [monthlyProductID, annualProductID]

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPremium: Bool
    @Published private(set) var expirationDate: Date?

    private let defaults: UserDefaults
    private let premiumKey = "seek.storekit.isPremium"
    private let expirationKey = "seek.storekit.expirationDate"

    private var updatesTask: Task<Void, Never>?
    private var hasConfigured = false

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isPremium = defaults.bool(forKey: premiumKey)
        self.expirationDate = defaults.object(forKey: expirationKey) as? Date
    }

    deinit {
        updatesTask?.cancel()
    }

    func configure() async {
        if !hasConfigured {
            hasConfigured = true
            listenForTransactionUpdates()
        }
        await fetchProducts()
        await updateEntitlements()
    }

    func fetchProducts() async {
        do {
            let fetched = try await Product.products(for: Self.productIDs)
            products = fetched.sorted { $0.price < $1.price }
            #if DEBUG
            let ids = products.map(\.id).joined(separator: ", ")
            print("[StoreManager] Product fetch success: \(products.count) product(s): \(ids)")
            #endif
        } catch {
            products = []
            #if DEBUG
            print("[StoreManager] Product fetch failed: \(error.localizedDescription)")
            #endif
        }
    }

    func purchase(plan: SubscriptionPlan) async throws {
        if products.isEmpty {
            await fetchProducts()
        }

        guard let product = product(for: plan) else {
            throw StoreManagerError.productUnavailable
        }
        try await purchase(product: product)
    }

    func purchase(product: Product) async throws {
        #if DEBUG
        print("[StoreManager] Purchase started: \(product.id)")
        #endif

        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch {
            #if DEBUG
            print("[StoreManager] Purchase failed before completion: \(error.localizedDescription)")
            #endif
            throw error
        }

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await updateEntitlements()
            #if DEBUG
            print("[StoreManager] Purchase success: \(transaction.productID)")
            #endif
        case .pending:
            #if DEBUG
            print("[StoreManager] Purchase pending")
            #endif
            throw StoreManagerError.pending
        case .userCancelled:
            #if DEBUG
            print("[StoreManager] Purchase cancelled by user")
            #endif
            throw StoreManagerError.userCancelled
        @unknown default:
            throw StoreManagerError.unknown
        }
    }

    func restorePurchases() async throws {
        #if DEBUG
        print("[StoreManager] Restore purchases started")
        #endif
        try await AppStore.sync()
        await updateEntitlements()
        #if DEBUG
        print("[StoreManager] Restore purchases completed. isPremium=\(isPremium)")
        #endif
    }

    func updateEntitlements() async {
        var active = false
        var latestExpiration: Date?

        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            guard Self.productIDs.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }

            if let expires = transaction.expirationDate {
                if expires > Date() {
                    active = true
                    if latestExpiration == nil || expires > (latestExpiration ?? .distantPast) {
                        latestExpiration = expires
                    }
                }
            } else {
                active = true
            }
        }

        applyEntitlement(isPremium: active, expirationDate: latestExpiration)
        EntitlementManager.shared.applyStoreKitEntitlement(isPremium: active, expirationDate: latestExpiration)

        #if DEBUG
        let expirationText = latestExpiration?.description ?? "none"
        print("[StoreManager] Entitlement updated. isPremium=\(active), expiration=\(expirationText)")
        #endif
    }

    private func product(for plan: SubscriptionPlan) -> Product? {
        let id: String
        switch plan {
        case .monthly:
            id = Self.monthlyProductID
        case .annual:
            id = Self.annualProductID
        }
        return products.first(where: { $0.id == id })
    }

    private func listenForTransactionUpdates() {
        updatesTask?.cancel()
        updatesTask = Task(priority: .background) { [weak self] in
            guard let self else { return }
            for await update in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(update)
                    await transaction.finish()
                    #if DEBUG
                    print("[StoreManager] Transaction update received: \(transaction.productID)")
                    #endif
                } catch {
                    #if DEBUG
                    print("[StoreManager] Transaction verification failed: \(error.localizedDescription)")
                    #endif
                }
                await self.updateEntitlements()
            }
        }
    }

    private func applyEntitlement(isPremium: Bool, expirationDate: Date?) {
        self.isPremium = isPremium
        self.expirationDate = expirationDate
        defaults.set(isPremium, forKey: premiumKey)
        defaults.set(expirationDate, forKey: expirationKey)
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let signed):
            return signed
        case .unverified:
            throw StoreManagerError.verificationFailed
        }
    }
}

enum StoreManagerError: LocalizedError {
    case productUnavailable
    case verificationFailed
    case pending
    case userCancelled
    case unknown

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            return "Subscription product is currently unavailable."
        case .verificationFailed:
            return "Unable to verify the transaction."
        case .pending:
            return "Purchase is pending approval."
        case .userCancelled:
            return "Purchase was cancelled."
        case .unknown:
            return "Purchase could not be completed."
        }
    }
}
