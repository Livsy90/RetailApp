import SwiftUI

/// Owns one Home navigation stack and its router lifetime.
struct HomeFlowCoordinator: View {
    @State private var router = AppRouter()
    let viewModel: HomeViewModel
    let imagePipeline: ImagePipeline

    var body: some View {
        NavigationStack(path: $router.path) {
            HomeFeatureCoordinator(
                viewModel: viewModel,
                imagePipeline: imagePipeline
            )
        }
        .environment(router)
    }
}

/// Maps Home routes and presentations to concrete feature views.
private struct HomeFeatureCoordinator: View {
    @Environment(AppRouter.self) private var router
    let viewModel: HomeViewModel
    let imagePipeline: ImagePipeline

    var body: some View {
        @Bindable var router = router

        HomeView(viewModel: viewModel, imagePipeline: imagePipeline)
            .navigationDestination(for: Destination.self) { destination in
                DestinationView(destination: destination)
            }
            .sheet(item: $router.presentedSheet) { sheet in
                switch sheet {
                case .cart:
                    CartSheet(cart: viewModel.cart)
                }
            }
    }
}

private struct CartSheet: View {
    @Environment(AppRouter.self) private var router
    let cart: CartStore

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Cart",
                systemImage: "cart",
                description: Text("\(cart.itemCount) items in your cart")
            )
            .navigationTitle("Cart")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { router.dismissSheet() }
                }
            }
        }
    }
}
