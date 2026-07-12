import Foundation

struct SearchSuggestion: Sendable, Hashable, Identifiable {
    let text: String
    var id: String { text }
}

struct SearchSuggestionsClient: Sendable {
    var fetch: @Sendable (_ query: String) async throws -> [SearchSuggestion]

    func suggestions(for query: String) async throws -> [SearchSuggestion] {
        try await fetch(query)
    }
}

extension SearchSuggestionsClient {
    static func demo() -> SearchSuggestionsClient {
        let catalog = [
            "Sneakers", "Summer dresses", "Wireless headphones", "Smart watches",
            "Home office", "Skin care", "Travel bags", "Coffee makers"
        ]

        return SearchSuggestionsClient { query in
            try await Task.sleep(for: .milliseconds(100))
            try Task.checkCancellation()
            let matches = catalog
                .filter { $0.localizedCaseInsensitiveContains(query) }
            let values = matches.isEmpty ? Array(catalog.prefix(5)) : Array(matches.prefix(5))
            return values.map(SearchSuggestion.init(text:))
        }
    }
}
