import Foundation
import StoreKit

/// StoreKit 2 purchases. No third-party SDK, so there is no extra monthly cost.
/// Create the same product IDs in App Store Connect (see PlanTier.productID and PagePack.productID).
@MainActor
@Observable
final class StoreManager {
    private(set) var products: [String: Product] = [:]
    private(set) var activePlan: (tier: PlanTier, period: BillingPeriod)?
    private(set) var isPurchasing = false
    var lastError: String?
    /// Called with every verified transaction so the server can apply it (set by FaxlaneApp).
    var onVerifiedTransaction: (@MainActor (UInt64) async -> Void)?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await self?.onVerifiedTransaction?(transaction.id)
                    await transaction.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
    }

    var allProductIDs: [String] {
        PlanTier.allCases.flatMap { tier in tier.periods.map { tier.productID($0) } } + PagePack.all.map(\.productID)
    }

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: allProductIDs)
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        } catch {
            lastError = error.localizedDescription
        }
        await refreshEntitlements()
    }

    func price(for id: String, fallback: String) -> String { products[id]?.displayPrice ?? fallback }

    /// `accountToken` links the purchase to the Faxlane account (appAccountToken),
    /// so the server can find the account again after a reinstall.
    @discardableResult
    func purchase(_ id: String, accountToken: UUID) async -> Bool {
        guard let product = products[id] else {
            lastError = String(localized: "This item isn’t available yet. Try again in a moment.")
            return false
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase(options: [.appAccountToken(accountToken)])
            switch result {
            case .success(.verified(let transaction)):
                await onVerifiedTransaction?(transaction.id)
                await transaction.finish()
                await refreshEntitlements()
                return true
            case .success(.unverified):
                lastError = String(localized: "We couldn’t verify this purchase.")
            case .pending, .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
        return false
    }

    func restore() async {
        try? await AppStore.sync()
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement { await onVerifiedTransaction?(transaction.id) }
        }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var found: (PlanTier, BillingPeriod)?
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            for tier in PlanTier.allCases {
                for period in tier.periods where tier.productID(period) == transaction.productID {
                    found = (tier, period)
                }
            }
        }
        activePlan = found.map { (tier: $0.0, period: $0.1) }
    }
}
