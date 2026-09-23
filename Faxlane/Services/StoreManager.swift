import Foundation
import RevenueCat

/// Purchases through RevenueCat. Plans and page packs are RevenueCat packages
/// (product IDs from PlanTier.productID and PagePack.productID).
/// The RevenueCat App User ID is the Faxlane account ID, so the server can read the same customer.
@MainActor
@Observable
final class StoreManager {
    private(set) var packages: [String: Package] = [:]      // by product ID
    private(set) var products: [String: StoreProduct] = [:]  // products that aren't in an offering
    private(set) var activePlan: (tier: PlanTier, period: BillingPeriod)?
    private(set) var isPurchasing = false
    var lastError: String?
    /// Called after a purchase, restore or redeemed code, so the server can re-read the account.
    var onPurchasesChanged: (@MainActor () async -> Void)?

    /// Public Apple SDK key (appl_...) from Info.plist. Empty = purchases are off (sample-data mode).
    static let apiKey: String? = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "FaxlaneRevenueCatAPIKey") as? String, !key.isEmpty else { return nil }
        return key
    }()

    private var listener: Task<Void, Never>?

    /// Call once at launch. With no account ID yet, RevenueCat starts anonymous and
    /// moves the purchases over when `logIn` is called.
    func configure(appUserID: String?) {
        guard let key = Self.apiKey, !Purchases.isConfigured else { return }
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: key, appUserID: appUserID)
        listener = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream { self?.update(info) }
        }
    }

    /// Links RevenueCat to the Faxlane account (after registering or signing in with Apple).
    func logIn(_ appUserID: String) async {
        guard Purchases.isConfigured else { return configure(appUserID: appUserID) }
        guard Purchases.shared.appUserID != appUserID else { return }
        if let result = try? await Purchases.shared.logIn(appUserID) { update(result.customerInfo) }
    }

    var allProductIDs: [String] {
        PlanTier.allCases.flatMap { tier in tier.periods.map { tier.productID($0) } } + PagePack.all.map(\.productID)
    }

    func loadProducts() async {
        guard Purchases.isConfigured else { return }
        do {
            let offerings = try await Purchases.shared.offerings()
            var found: [String: Package] = [:]
            for offering in offerings.all.values {
                for package in offering.availablePackages { found[package.storeProduct.productIdentifier] = package }
            }
            packages = found
            let missing = allProductIDs.filter { found[$0] == nil }
            if !missing.isEmpty {
                let loaded = await Purchases.shared.products(missing)
                products = Dictionary(loaded.map { ($0.productIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
            }
        } catch {
            lastError = error.localizedDescription
        }
        await refreshEntitlements()
    }

    func price(for id: String, fallback: String) -> String {
        packages[id]?.storeProduct.localizedPriceString ?? products[id]?.localizedPriceString ?? fallback
    }

    @discardableResult
    func purchase(_ id: String) async -> Bool {
        guard Purchases.isConfigured else {
            #if DEBUG
            return true // sample-data mode: lets the design be tried without a store
            #else
            lastError = String(localized: "This item isn’t available yet. Try again in a moment.")
            return false
            #endif
        }
        isPurchasing = true
        defer { isPurchasing = false }
        lastError = nil
        do {
            let result: PurchaseResultData
            if let package = packages[id] {
                result = try await Purchases.shared.purchase(package: package)
            } else if let product = products[id] {
                result = try await Purchases.shared.purchase(product: product)
            } else {
                lastError = String(localized: "This item isn’t available yet. Try again in a moment.")
                return false
            }
            if result.userCancelled { return false }
            update(result.customerInfo)
            await onPurchasesChanged?()
            return true
        } catch {
            if (error as? ErrorCode) != .purchaseCancelledError { lastError = error.localizedDescription }
            return false
        }
    }

    func restore() async {
        guard Purchases.isConfigured else { return }
        do {
            update(try await Purchases.shared.restorePurchases())
            await onPurchasesChanged?()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// After an offer code is redeemed in Apple's sheet: sync quietly, without a sign-in prompt.
    func syncAfterRedeem() async {
        guard Purchases.isConfigured else { return }
        if let info = try? await Purchases.shared.syncPurchases() { update(info) }
        await onPurchasesChanged?()
    }

    func refreshEntitlements() async {
        guard Purchases.isConfigured else { return }
        if let info = try? await Purchases.shared.customerInfo() { update(info) }
    }

    private func update(_ info: CustomerInfo) {
        var found: (tier: PlanTier, period: BillingPeriod)?
        for tier in PlanTier.allCases {           // ordered basic → enterprise, so the highest plan wins
            for period in tier.periods where info.activeSubscriptions.contains(tier.productID(period)) {
                found = (tier, period)
            }
        }
        activePlan = found
    }
}
