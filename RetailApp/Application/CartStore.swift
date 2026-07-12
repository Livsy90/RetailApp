import Foundation
import Observation

@MainActor
@Observable
final class CartProductState {
    private(set) var isPending = false

    fileprivate func setPending(_ value: Bool) {
        isPending = value
    }
}

/// Session-scoped owner of optimistic cart state and server reconciliation.
@MainActor
@Observable
final class CartStore {
    private let addProductToCart: AddProductToCart
    private let analytics: AnalyticsTracker
    private var operations: [String: UUID] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
    private var latestRevision = 0
    private var latestSummary: CartSummary?
    @ObservationIgnored private var productStates: [String: CartProductState] = [:]

    private(set) var itemCount = 0
    private(set) var message: String?

    var pendingProductIDs: Set<String> { Set(operations.keys) }

    init(addProductToCart: AddProductToCart, analytics: AnalyticsTracker) {
        self.addProductToCart = addProductToCart
        self.analytics = analytics
    }

    func add(_ product: ProductCard) {
        guard operations[product.id] == nil else { return }

        let operationID = UUID()
        operations[product.id] = operationID
        state(for: product.id).setPending(true)
        message = nil
        itemCount += 1

        tasks[product.id] = Task { [weak self, addProductToCart, analytics] in
            let result: Result<CartSummary, Error>
            do {
                result = .success(try await addProductToCart(product, operationID: operationID))
            } catch {
                result = .failure(error)
            }

            guard let self, operations[product.id] == operationID else { return }

            switch result {
            case .success(let summary):
                apply(summary)
                finish(productID: product.id, operationID: operationID)
                await analytics.track(.addToCart(productID: product.id, requestID: product.tracking.requestID))

            case .failure(let error) where error is AddToCartError:
                rollbackOptimisticIncrement()
                message = error.localizedDescription
                finish(productID: product.id, operationID: operationID)

            case .failure:
                // A transport error is ambiguous: the server may have committed
                // the operation before the response was lost. Resolve using the
                // same idempotency key instead of guessing and rolling back.
                do {
                    let summary = try await addProductToCart.resolve(product, operationID: operationID)
                    guard operations[product.id] == operationID else { return }
                    apply(summary)
                    message = nil
                    finish(productID: product.id, operationID: operationID)
                    await analytics.track(.addToCart(productID: product.id, requestID: product.tracking.requestID))
                } catch {
                    guard operations[product.id] == operationID else { return }
                    message = "Confirming your cart update. It will retry with the same operation ID."
                    scheduleResolution(for: product, operationID: operationID)
                }
            }
        }
    }

    func state(for productID: String) -> CartProductState {
        if let state = productStates[productID] { return state }
        let state = CartProductState()
        productStates[productID] = state
        return state
    }

    /// Use on logout/account replacement before changing the session graph.
    func reset() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        operations.removeAll()
        productStates.values.forEach { $0.setPending(false) }
        productStates.removeAll()
        latestRevision = 0
        latestSummary = nil
        itemCount = 0
        message = nil
    }

    private func rollbackOptimisticIncrement() {
        itemCount = max(0, itemCount - 1)
    }

    private func apply(_ summary: CartSummary) {
        guard summary.revision >= latestRevision else { return }
        latestRevision = summary.revision
        latestSummary = summary
        itemCount = max(itemCount, summary.itemCount)
    }

    private func scheduleResolution(for product: ProductCard, operationID: UUID) {
        tasks[product.id] = Task { [weak self, addProductToCart, analytics] in
            var delay = Duration.milliseconds(500)
            while let self, operations[product.id] == operationID {
                do {
                    try await Task.sleep(for: delay)
                    let summary = try await addProductToCart.resolve(product, operationID: operationID)
                    guard operations[product.id] == operationID else { return }
                    apply(summary)
                    message = nil
                    finish(productID: product.id, operationID: operationID)
                    await analytics.track(.addToCart(productID: product.id, requestID: product.tracking.requestID))
                    return
                } catch is CancellationError {
                    return
                } catch {
                    delay = min(delay * 2, .seconds(5))
                }
            }
        }
    }

    private func finish(productID: String, operationID: UUID) {
        guard operations[productID] == operationID else { return }
        operations[productID] = nil
        tasks[productID] = nil
        productStates[productID]?.setPending(false)
        productStates[productID] = nil

        if operations.isEmpty, let latestSummary {
            itemCount = latestSummary.itemCount
        }
    }
}
