import Foundation
import Testing
@testable import RetailApp

struct SystemDesignTests {
    @Test func demoSearchReturnsMatchesAndPopularFallback() async throws {
        let client = SearchSuggestionsClient.demo()
        let matches = try await client.suggestions(for: "wire")
        let fallback = try await client.suggestions(for: "does-not-exist")

        #expect(matches.map(\.text) == ["Wireless headphones"])
        #expect(!fallback.isEmpty)
    }

    @Test @MainActor func routerOwnsTypedPushAndSheetState() {
        let router = AppRouter()
        let first = Destination.product(id: "one")
        let second = Destination.search(query: "shoes")

        router.navigate(to: first)
        router.navigate(to: second)
        #expect(router.path == [first, second])

        router.navigateBack()
        #expect(router.path == [first])
        router.navigateToRoot()
        router.navigateBack()
        #expect(router.path.isEmpty)

        router.present(.cart)
        #expect(router.presentedSheet == .cart)
        router.dismissSheet()
        #expect(router.presentedSheet == nil)
    }

    @Test func freshnessUsesExplicitClock() {
        let deadline = Date(timeIntervalSince1970: 100)
        let page = makePage(freshUntil: deadline)
        #expect(page.isFresh(at: Date(timeIntervalSince1970: 99)))
        #expect(!page.isFresh(at: deadline))
    }

    @Test func cacheSeparatesContextsAndPersists() async {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "home.plist")
        let firstKey = key(accountID: "one")
        let secondKey = key(accountID: "two")
        let page = makePage()
        let firstCache = HomeCache(persistentURL: url)
        await firstCache.save(page, for: firstKey)
        #expect(await firstCache.value(for: secondKey) == nil)
        await firstCache.flushPersistence()
        let restoredCache = HomeCache(persistentURL: url)
        #expect(await restoredCache.value(for: firstKey) == page)
    }

    @Test func concurrentRefreshIsSingleFlight() async throws {
        let counter = RequestCounter()
        let response = try decodeResponse()
        let client = HomeAPIClient { _ in
            await counter.increment()
            try await Task.sleep(for: .milliseconds(50))
            return response
        }
        let coordinator = HomeRefreshCoordinator()
        let cache = HomeCache(persistentURL: nil)
        async let first = coordinator.refresh(api: client, cache: cache, context: .demo, now: { .distantPast }, observeContractIssues: { _ in })
        async let second = coordinator.refresh(api: client, cache: cache, context: .demo, now: { .distantPast }, observeContractIssues: { _ in })
        _ = try await (first, second)
        #expect(await counter.value == 1)
        #expect(await cache.value(for: .demo) != nil)
    }

    @Test func unknownSectionUsesConstrainedFallback() throws {
        let mapping = try decodeResponse().toDomain(now: .distantPast)
        #expect(mapping.page.sections.count == 1)
        guard case .fallback(let fallback) = mapping.page.sections[0] else {
            Issue.record("Expected fallback section")
            return
        }
        #expect(fallback.sourceType == "future_carousel")
        #expect(mapping.issues == [.unsupported(type: "future_carousel")])
    }

    @Test @MainActor func lostCartResponseResolvesWithSameOperationID() async {
        let operationIDs = OperationIDRecorder()
        let client = CartClient(
            add: { _, id in
                await operationIDs.record(id)
                throw CancellationError()
            },
            resolve: { _, id in
                await operationIDs.record(id)
                return CartSummary(itemCount: 1, revision: 1)
            }
        )
        let store = CartStore(
            addProductToCart: AddProductToCart(client: client),
            analytics: AnalyticsTracker()
        )
        store.add(makeProduct())
        for _ in 0..<100 where !store.pendingProductIDs.isEmpty {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(store.pendingProductIDs.isEmpty)
        #expect(store.itemCount == 1)
        let ids = await operationIDs.values
        #expect(ids.count == 2)
        #expect(Set(ids).count == 1)
    }

    @Test func cacheEvictsLeastRecentlyUsedContext() async {
        let cache = HomeCache(persistentURL: nil, maximumContextCount: 2)
        let first = key(accountID: "one")
        let second = key(accountID: "two")
        let third = key(accountID: "three")
        await cache.save(makePage(), for: first)
        await cache.save(makePage(), for: second)
        _ = await cache.value(for: first)
        await cache.save(makePage(), for: third)
        #expect(await cache.value(for: second) == nil)
        #expect(await cache.value(for: first) != nil)
        #expect(await cache.value(for: third) != nil)
    }

    private func key(accountID: String) -> HomeCacheKey {
        HomeCacheKey(accountID: accountID, localeIdentifier: "en_US", market: "US", experiments: [], capabilities: [])
    }

    private func makePage(freshUntil: Date = Date(timeIntervalSince1970: 20)) -> HomePage {
        HomePage(sections: [], nextCursor: nil, schemaVersion: "test", fetchedAt: Date(timeIntervalSince1970: 10), freshUntil: freshUntil)
    }

    private func makeProduct() -> ProductCard {
        ProductCard(
            id: "product", title: "Product", imageURL: nil,
            price: Money(amount: 1, currencyCode: "USD"), availability: .available,
            destination: .product(id: "product"),
            tracking: TrackingContext(requestID: "request", sectionID: "section", itemID: "product", position: 0)
        )
    }

    private func decodeResponse() throws -> HomeResponseDTO {
        try JSONDecoder().decode(HomeResponseDTO.self, from: Data(Self.responseJSON.utf8))
    }

    private static let responseJSON = #"""
    {"schemaVersion":"home.v1","ttl":300,"nextCursor":null,"requestID":"test-request","sections":[
      {"id":"future","type":"future_carousel","fallback":{"id":"future-fallback","title":"Available","subtitle":null,"destination":{"type":"campaign","id":"preview"}}}
    ]}
    """#
}

private actor RequestCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private actor OperationIDRecorder {
    private(set) var values: [UUID] = []
    func record(_ id: UUID) { values.append(id) }
}
