import Foundation

enum Freshness: Equatable {
    case none
    case cached(Date)
    case fresh(Date)
}

enum LoadState: Equatable {
    case idle
    case loading
    case empty
    case failed(String)
}

@MainActor
@Observable
final class HomeViewModel {

    var sections: [HomeSection] = []
    var freshness: Freshness = .none
    var loadState: LoadState = .idle
    var refreshError: String?
    var searchQuery = ""
    var suggestions: [SearchSuggestion] = []
    var isSearching = false
    let cart: CartStore
    
    private let repository: HomeRepository
    private let analytics: AnalyticsTracker
    private let searchSuggestions: SearchSuggestionsClient
    private let impressionLimit = 500
    private var searchTask: Task<Void, Never>?
    private var recordedImpressions = Set<String>()
    private var impressionOrder: [String] = []

    init(
        repository: HomeRepository,
        cart: CartStore,
        analytics: AnalyticsTracker,
        searchSuggestions: SearchSuggestionsClient
    ) {
        self.repository = repository
        self.cart = cart
        self.analytics = analytics
        self.searchSuggestions = searchSuggestions
    }

    func load(forceRefresh: Bool = false) async {
        refreshError = nil
        loadState = .loading
        do {
            for try await update in repository.updates(forceRefresh: forceRefresh) {
                try Task.checkCancellation()
                switch update {
                case .cached(let page):
                    sections = page.sections
                    freshness = .cached(page.fetchedAt)
                case .fresh(let page):
                    sections = page.sections
                    freshness = .fresh(page.fetchedAt)
                }
            }
            loadState = sections.isEmpty ? .empty : .idle
        } catch is CancellationError {
            loadState = .idle
        } catch {
            if sections.isEmpty {
                loadState = .failed("We couldn't load the home page.")
            } else {
                loadState = .idle
                refreshError = "Couldn't refresh. Showing saved content."
            }
        }
    }

    func trackSelection(_ tracking: TrackingContext) {
        Task {
            await analytics.track(.tap(tracking))
        }
    }

    func itemBecameVisible(_ tracking: TrackingContext) {
        let key = [tracking.requestID, tracking.sectionID, tracking.itemID ?? "section"].joined(separator: ":")
        
        guard recordedImpressions.insert(key).inserted else { return }
        
        impressionOrder.append(key)
        
        if impressionOrder.count > impressionLimit {
            let overflow = impressionOrder.count - impressionLimit
            recordedImpressions.subtract(impressionOrder.prefix(overflow))
            impressionOrder.removeFirst(overflow)
        }
        
        Task {
            await analytics.track(.impression(tracking))
        }
    }

    func searchQueryChanged(_ query: String) {
        searchTask?.cancel()
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.count >= 2 else {
            suggestions = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task { [weak self, searchSuggestions] in
            do {
                try await Task.sleep(for: .milliseconds(150))
                let loaded = try await searchSuggestions.suggestions(for: normalized)
                try Task.checkCancellation()
                guard let self, searchQuery == query else { return }
                suggestions = loaded
                isSearching = false
            } catch is CancellationError {
                return
            } catch {
                guard let self, searchQuery == query else { return }
                suggestions = []
                isSearching = false
            }
        }
    }

    func submitSearch(_ text: String? = nil) -> Destination? {
        let query = (text ?? searchQuery).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        searchQuery = query
        suggestions = []
        searchTask?.cancel()
        return .search(query: query)
    }

    func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
    }
}
