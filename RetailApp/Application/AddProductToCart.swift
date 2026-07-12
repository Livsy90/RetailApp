import Foundation

struct CartSummary: Sendable, Equatable {
    let itemCount: Int
    let revision: Int
}

struct CartClient: Sendable {
    var add: @Sendable (_ productID: String, _ idempotencyKey: UUID) async throws -> CartSummary
    var resolve: @Sendable (_ productID: String, _ idempotencyKey: UUID) async throws -> CartSummary
}

extension CartClient {
    static func demo() -> CartClient {
        let backend = DemoCartBackend()
        return CartClient(
            add: { productID, idempotencyKey in
                try await backend.add(productID: productID, idempotencyKey: idempotencyKey)
            },
            resolve: { productID, idempotencyKey in
                // The same key either returns the committed result or safely
                // completes the original operation exactly once.
                try await backend.add(productID: productID, idempotencyKey: idempotencyKey)
            }
        )
    }
}

private actor DemoCartBackend {
    private var itemCount = 0
    private var revision = 0
    private var appliedOperations: [UUID: CartSummary] = [:]

    func add(productID: String, idempotencyKey: UUID) async throws -> CartSummary {
        if let existing = appliedOperations[idempotencyKey] {
            return existing
        }

        try await Task.sleep(for: .milliseconds(450))
        try Task.checkCancellation()

        // The actor can be re-entered while sleeping. A concurrent retry may
        // have committed this operation in the meantime.
        if let existing = appliedOperations[idempotencyKey] {
            return existing
        }

        itemCount += 1
        revision += 1
        let summary = CartSummary(itemCount: itemCount, revision: revision)
        appliedOperations[idempotencyKey] = summary
        return summary
    }
}

enum AddToCartError: LocalizedError {
    case unavailable

    var errorDescription: String? { "This product is currently unavailable." }
}

struct AddProductToCart: Sendable {
    let client: CartClient

    func callAsFunction(_ product: ProductCard, operationID: UUID) async throws -> CartSummary {
        guard product.availability == .available else { throw AddToCartError.unavailable }
        return try await client.add(product.id, operationID)
    }

    func resolve(_ product: ProductCard, operationID: UUID) async throws -> CartSummary {
        try await client.resolve(product.id, operationID)
    }
}
