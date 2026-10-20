import Observation
import os
import StoreKit

/// How the app is sold. The spec leaves this open; flip `current` to match App Store Connect.
enum Monetization {
    /// Paid up front: everything is unlocked.
    case upfront
    /// Free to try: the first words written, then a one-time unlock. Counted from the writing history, so
    /// deleting never earns words back; imported text doesn't count.
    case freemium(freeWords: Int)

    static let current: Monetization = .freemium(freeWords: 5000)
}

enum ProductID {
    static let unlock = "com.carriage.app.unlock"

    static let all = [unlock]
}

/// StoreKit 2: one non-consumable unlock. Every paper, ribbon and machine is included from the first page;
/// the free version only limits how many words are written. No subscriptions, no ads.
@Observable
final class Store {
    private(set) var products: [String: Product] = [:]
    private(set) var purchased: Set<String> = []
    private(set) var isLoading = false
    /// True once the App Store has answered at least once, so a refund check can trust `purchased`.
    private(set) var entitlementsChecked = false
    var lastError: String?

    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "Carriage", category: "Store")

    init() {
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
    }

    var isUnlocked: Bool {
        if case .upfront = Monetization.current { return true }
        #if DEBUG
        // `-unlocked`: App Store screenshots of the machine, without the free-words note.
        if ProcessInfo.processInfo.arguments.contains("-unlocked") { return true }
        #endif
        return purchased.contains(ProductID.unlock)
    }

    var freeWordLimit: Int? {
        if case let .freemium(words) = Monetization.current, !isUnlocked { return words }
        return nil
    }

    func price(_ id: String) -> String? { products[id]?.displayPrice }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: ProductID.all)
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        } catch {
            log.error("Couldn't load products: \(error.localizedDescription)")
        }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var owned: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if case let .verified(transaction) = result, transaction.revocationDate == nil {
                owned.insert(transaction.productID)
            }
        }
        purchased = owned
        entitlementsChecked = true
    }

    /// Fetches the products if they aren't here yet (the first try at launch can fail on a slow network).
    func loadProductsIfNeeded() async {
        guard products.count < ProductID.all.count else { return }
        do {
            let loaded = try await Product.products(for: ProductID.all)
            for product in loaded { products[product.id] = product }
        } catch {
            log.error("Couldn't load products: \(error.localizedDescription)")
        }
    }

    /// Returns true if the purchase went through.
    @discardableResult
    func purchase(_ id: String) async -> Bool {
        lastError = nil
        if products[id] == nil { await loadProductsIfNeeded() }
        guard let product = products[id] else {
            lastError = "The App Store isn't reachable right now. Try again in a moment."
            return false
        }
        do {
            switch try await product.purchase() {
            case let .success(result):
                await handle(result)
                return purchased.contains(id)
            case .pending:
                lastError = "Your purchase is waiting for approval."
                return false
            case .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            lastError = error.localizedDescription
        }
        await refreshEntitlements()
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case let .verified(transaction) = result else { return }
        if transaction.revocationDate == nil {
            purchased.insert(transaction.productID)
        } else {
            purchased.remove(transaction.productID)
        }
        await transaction.finish()
    }
}
