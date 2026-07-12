import Foundation

struct HomeCacheKey: Hashable, Codable, Sendable {
    let accountID: String
    let localeIdentifier: String
    let market: String
    let experiments: Set<String>
    let capabilities: Set<String>

    static let demo = HomeCacheKey(
        accountID: "demo-user",
        localeIdentifier: "en_US",
        market: "US",
        experiments: ["home-v1"],
        capabilities: ["fallback-v1"]
    )
}

private struct HomeCacheSnapshot: Codable, Sendable {
    var pages: [HomeCacheKey: HomePage]
    var accessOrder: [HomeCacheKey]
}

/// Owns blocking file APIs on one bounded, non-cooperative executor.
private final class HomeCacheDiskStore: @unchecked Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "com.retailapp.home-cache", qos: .utility)
    private var pendingSnapshot: HomeCacheSnapshot?
    private var pendingWrite: DispatchWorkItem?

    init(url: URL) {
        self.url = url
    }

    func load() async -> HomeCacheSnapshot? {
        await withCheckedContinuation { continuation in
            queue.async { [url] in
                guard let data = try? Data(contentsOf: url),
                      let snapshot = try? PropertyListDecoder().decode(HomeCacheSnapshot.self, from: data)
                else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: snapshot)
            }
        }
    }

    func scheduleSave(_ snapshot: HomeCacheSnapshot) {
        queue.async { [weak self] in
            guard let self else { return }
            pendingSnapshot = snapshot
            pendingWrite?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.writePendingSnapshot() }
            pendingWrite = work
            queue.asyncAfter(deadline: .now() + .milliseconds(100), execute: work)
        }
    }

    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                self?.pendingWrite?.cancel()
                self?.writePendingSnapshot()
                continuation.resume()
            }
        }
    }

    private func writePendingSnapshot() {
        guard let snapshot = pendingSnapshot else { return }
        pendingSnapshot = nil
        pendingWrite = nil

        guard let data = try? PropertyListEncoder().encode(snapshot) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            // Cache persistence is best effort; network remains authoritative.
        }
    }
}

actor HomeCache {
    private var pages: [HomeCacheKey: HomePage] = [:]
    private var accessOrder: [HomeCacheKey] = []
    private var didLoad = false
    private let maximumContextCount: Int
    private let diskStore: HomeCacheDiskStore?

    init(
        persistentURL: URL? = HomeCache.defaultPersistentURL(),
        maximumContextCount: Int = 4
    ) {
        self.maximumContextCount = max(1, maximumContextCount)
        diskStore = persistentURL.map(HomeCacheDiskStore.init)
    }

    func value(for key: HomeCacheKey) async -> HomePage? {
        await loadIfNeeded()
        guard let page = pages[key] else { return nil }
        touch(key)
        persist()
        return page
    }

    func save(_ page: HomePage, for key: HomeCacheKey) async {
        await loadIfNeeded()
        pages[key] = page
        touch(key)
        evictIfNeeded()
        persist()
    }

    func clear(for key: HomeCacheKey) async {
        await loadIfNeeded()
        pages[key] = nil
        accessOrder.removeAll { $0 == key }
        persist()
    }

    func clear(accountID: String) async {
        await loadIfNeeded()
        let keys = pages.keys.filter { $0.accountID == accountID }
        keys.forEach { pages[$0] = nil }
        accessOrder.removeAll { $0.accountID == accountID }
        persist()
    }

    func clearAll() async {
        await loadIfNeeded()
        pages.removeAll()
        accessOrder.removeAll()
        persist()
    }

    func flushPersistence() async {
        await diskStore?.flush()
    }

    private func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        guard let snapshot = await diskStore?.load() else { return }
        pages = snapshot.pages
        accessOrder = snapshot.accessOrder.filter { pages[$0] != nil }
        for key in pages.keys where !accessOrder.contains(key) {
            accessOrder.append(key)
        }
        evictIfNeeded()
    }

    private func touch(_ key: HomeCacheKey) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }

    private func evictIfNeeded() {
        while accessOrder.count > maximumContextCount {
            pages[accessOrder.removeFirst()] = nil
        }
    }

    private func persist() {
        diskStore?.scheduleSave(HomeCacheSnapshot(pages: pages, accessOrder: accessOrder))
    }

    private nonisolated static func defaultPersistentURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "RetailApp", directoryHint: .isDirectory)
            .appending(path: "home-cache.plist")
    }
}
