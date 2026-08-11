import Foundation
import StoreKit

/// SPEC.md §11.1 — a single non-consumable, not a subscription. Free tier is
/// enforced by item count (§6.2), checked against `isPro` here.
@MainActor
final class StoreManager: ObservableObject {
    static let proProductID = "com.serhansari.LifeVars.pro"
    static let freeItemLimit = 3

    @Published private(set) var isPro = false
    @Published private(set) var product: Product?
    @Published var purchaseError: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            await self?.observeTransactionUpdates()
        }
        Task { [weak self] in
            await self?.loadProduct()
            await self?.refreshEntitlement()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.proProductID])
            product = products.first
            if product == nil {
                // Not an error StoreKit throws — an empty match is a valid
                // response. Surface it anyway so the paywall doesn't spin
                // forever with no explanation.
                purchaseError = "Pro isn't available right now. Try again later."
            }
        } catch {
            purchaseError = "Couldn't load Pro pricing. Check your connection and try again."
        }
    }

    func purchase() async {
        guard let product else { return }
        purchaseError = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlement()
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = "Purchase failed. Try again."
        }
    }

    func restore() async {
        purchaseError = nil
        do {
            try await AppStore.sync()
            await refreshEntitlement()
        } catch {
            purchaseError = "Couldn't restore purchases."
        }
    }

    private func refreshEntitlement() async {
        #if DEBUG
        // Any build compiled locally (Xcode Run, not TestFlight/App Store)
        // is unlimited with no purchase involved — this block is stripped
        // entirely from Release builds, so it has no effect on what ships.
        isPro = true
        return
        #else
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == Self.proProductID {
                isPro = true
                return
            }
        }
        isPro = false
        #endif
    }

    private func observeTransactionUpdates() async {
        for await update in Transaction.updates {
            if case .verified(let transaction) = update {
                await transaction.finish()
                await refreshEntitlement()
            }
        }
    }
}
