import SwiftUI

struct AppComposition {
    let homeRepository: HomeRepository
    let cart: CartStore
    let analytics: AnalyticsTracker
    let searchSuggestions: SearchSuggestionsClient
    let imagePipeline: ImagePipeline

    @MainActor
    static func demo() -> AppComposition {
        let cache = HomeCache()
        let homeAPI = HomeAPIClient.demo()
        let cartClient = CartClient.demo()
        let analytics = AnalyticsTracker()
        let searchSuggestions = SearchSuggestionsClient.demo()
        let imagePipeline = ImagePipeline()

        let addProductToCart = AddProductToCart(client: cartClient)
        let cart = CartStore(addProductToCart: addProductToCart, analytics: analytics)

        return AppComposition(
            homeRepository: HomeRepository(
                api: homeAPI,
                cache: cache,
                context: .demo,
                observeContractIssues: { issues in
                    analytics.enqueueContractIssues(issues)
                }
            ),
            cart: cart,
            analytics: analytics,
            searchSuggestions: searchSuggestions,
            imagePipeline: imagePipeline
        )
    }

    @MainActor
    func makeRootView() -> some View {
        HomeFlowCoordinator(
            viewModel: HomeViewModel(
                repository: homeRepository,
                cart: cart,
                analytics: analytics,
                searchSuggestions: searchSuggestions
            ),
            imagePipeline: imagePipeline
        )
    }
}
