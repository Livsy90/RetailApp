import Foundation

enum HomeUpdate: Sendable {
    case cached(HomePage)
    case fresh(HomePage)
}

struct HomeRepository: Sendable {
    let api: HomeAPIClient
    let cache: HomeCache
    let context: HomeCacheKey
    let refreshCoordinator: HomeRefreshCoordinator
    let now: @Sendable () -> Date
    let observeContractIssues: @Sendable ([HomeContractIssue]) -> Void

    init(
        api: HomeAPIClient,
        cache: HomeCache,
        context: HomeCacheKey,
        refreshCoordinator: HomeRefreshCoordinator = HomeRefreshCoordinator(),
        now: @escaping @Sendable () -> Date = { Date() },
        observeContractIssues: @escaping @Sendable ([HomeContractIssue]) -> Void = { _ in }
    ) {
        self.api = api
        self.cache = cache
        self.context = context
        self.refreshCoordinator = refreshCoordinator
        self.now = now
        self.observeContractIssues = observeContractIssues
    }

    func updates(forceRefresh: Bool = false) -> AsyncThrowingStream<HomeUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                if !forceRefresh, let cached = await cache.value(for: context) {
                    continuation.yield(.cached(cached))
                    if cached.isFresh(at: now()) {
                        continuation.finish()
                        return
                    }
                }

                do {
                    let mapping = try await refreshCoordinator.refresh(
                        api: api,
                        cache: cache,
                        context: context,
                        now: now,
                        observeContractIssues: observeContractIssues
                    )
                    continuation.yield(.fresh(mapping.page))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

actor HomeRefreshCoordinator {
    private var inFlight: [HomeCacheKey: Task<HomeMappingResult, Error>] = [:]

    func refresh(
        api: HomeAPIClient,
        cache: HomeCache,
        context: HomeCacheKey,
        now: @escaping @Sendable () -> Date,
        observeContractIssues: @escaping @Sendable ([HomeContractIssue]) -> Void
    ) async throws -> HomeMappingResult {
        if let existing = inFlight[context] {
            return try await existing.value
        }

        let task = Task<HomeMappingResult, Error> {
            let response = try await api.home()
            let mapping = response.toDomain(now: now())
            // The app-scoped coordinator commits successful work even if the
            // initiating screen stops consuming the stream.
            await cache.save(mapping.page, for: context)
            observeContractIssues(mapping.issues)
            return mapping
        }
        inFlight[context] = task

        do {
            let result = try await task.value
            inFlight[context] = nil
            return result
        } catch {
            inFlight[context] = nil
            throw error
        }
    }
}
