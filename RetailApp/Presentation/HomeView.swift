import SwiftUI

struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @State private var viewModel: HomeViewModel
    private let imagePipeline: ImagePipeline

    init(viewModel: HomeViewModel, imagePipeline: ImagePipeline) {
        self.viewModel = viewModel
        self.imagePipeline = imagePipeline
    }

    var body: some View {
        Group {
            if viewModel.sections.isEmpty {
                initialContent
            } else {
                homeContent
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Discover")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                CartBadgeView(cart: viewModel.cart)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .searchable(
            text: $viewModel.searchQuery,
            prompt: "Search products and campaigns"
        )
        .searchSuggestions {
            SearchSuggestionsView(viewModel: viewModel)
        }
        .onSubmit(of: .search) {
            if let destination = viewModel.submitSearch() {
                router.navigate(to: destination)
            }
        }
        .onChange(of: viewModel.searchQuery) { _, query in
            viewModel.searchQueryChanged(query)
        }
        .task { await viewModel.load() }
        .onDisappear { viewModel.cancelSearch() }
    }

    @ViewBuilder
    private var initialContent: some View {
        switch viewModel.loadState {
        case .empty:
            ContentUnavailableView("Nothing to show", systemImage: "rectangle.stack", description: Text("New offers will appear here soon."))
        case .failed(let message):
            ContentUnavailableView("Unable to load", systemImage: "wifi.exclamationmark", description: Text(message))
                .overlay(alignment: .bottom) {
                    Button("Try again") {
                        Task { await viewModel.load(forceRefresh: true) }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                }
        default:
            ProgressView("Loading your offers…")
        }
    }

    private var homeContent: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                if let message = viewModel.refreshError {
                    Text(message)
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                }

                CartStatusMessage(cart: viewModel.cart)

                ForEach(viewModel.sections) { section in
                    HomeSectionView(
                        section: section,
                        cart: viewModel.cart,
                        actions: sectionActions,
                        imagePipeline: imagePipeline
                    )
                }
            }
            .padding(.vertical)
        }
        .refreshable { await viewModel.load(forceRefresh: true) }
    }

    private var sectionActions: HomeSectionActions {
        HomeSectionActions { [viewModel, router] action in
            switch action {
            case .select(let destination, let tracking):
                viewModel.trackSelection(tracking)
                router.navigate(to: destination)
            case .becameVisible(let tracking):
                viewModel.itemBecameVisible(tracking)
            }
        }
    }
}

private enum HomeSectionAction {
    case select(Destination, TrackingContext)
    case becameVisible(TrackingContext)
}

private struct HomeSectionActions {
    let send: (HomeSectionAction) -> Void
}

private struct SearchSuggestionsView: View {
    @Environment(AppRouter.self) private var router
    let viewModel: HomeViewModel

    var body: some View {
        if viewModel.isSearching {
            Label {
                Text("Searching…")
            } icon: {
                ProgressView()
            }
        }

        ForEach(viewModel.suggestions) { suggestion in
            Button {
                if let destination = viewModel.submitSearch(suggestion.text) {
                    router.navigate(to: destination)
                }
            } label: {
                Label(suggestion.text, systemImage: "magnifyingglass")
            }
        }
    }
}

private struct CartBadgeView: View {
    @Environment(AppRouter.self) private var router
    let cart: CartStore

    var body: some View {
        Button {
            router.present(.cart)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cart")
                if cart.itemCount > 0 {
                    Text("\(cart.itemCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(.red, in: .circle)
                }
            }
        }
        .accessibilityLabel("Cart, \(cart.itemCount) items")
    }
}

private struct CartStatusMessage: View {
    let cart: CartStore

    var body: some View {
        if let message = cart.message {
            Text(message)
                .font(.footnote)
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
        }
    }
}

private struct AddToCartButton: View {
    enum Style {
        case standard, prominent
    }

    let product: ProductCard
    let cart: CartStore
    let state: CartProductState
    let style: Style

    init(
        product: ProductCard,
        cart: CartStore,
        style: Style
    ) {
        self.product = product
        self.cart = cart
        self.style = style
        state = cart.state(for: product.id)
    }

    @ViewBuilder
    var body: some View {
        switch style {
        case .standard:
            button.buttonStyle(.bordered)
        case .prominent:
            button.buttonStyle(.borderedProminent)
        }
    }
    
    private var button: some View {
        Button {
            cart.add(product)
        } label: {
            if state.isPending {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Added")
                    ProgressView().controlSize(.mini)
                }
                .frame(maxWidth: .infinity)
            } else {
                Text(product.availability == .available ? "Add to cart" : "Unavailable")
                    .frame(maxWidth: .infinity)
            }
        }
        .disabled(product.availability == .unavailable || state.isPending)
    }
}

private struct HomeSectionView: View {
    let section: HomeSection
    let cart: CartStore
    let actions: HomeSectionActions
    let imagePipeline: ImagePipeline

    var body: some View {
        switch section {
        case .hero(let value):
            HeroSectionView(
                section: value,
                actions: actions,
                imagePipeline: imagePipeline
            )
        case .campaignCarousel(let value):
            CampaignCarouselSectionView(
                section: value,
                actions: actions,
                imagePipeline: imagePipeline
            )
        case .categories(let value):
            CategorySectionView(
                section: value,
                actions: actions
            )
        case .products(let value):
            ProductSectionView(
                section: value,
                cart: cart,
                actions: actions,
                imagePipeline: imagePipeline
            )
        case .recommendations(let value):
            RecommendationSectionView(
                section: value,
                cart: cart,
                actions: actions,
                imagePipeline: imagePipeline
            )
        case .editorial(let value):
            EditorialSectionView(
                section: value,
                actions: actions,
                imagePipeline: imagePipeline
            )
        case .promo(let value):
            PromoSectionView(
                section: value,
                actions: actions
            )
        case .fallback(let value):
            FallbackSectionView(
                section: value,
                actions: actions
            )
        }
    }
}

private struct HeroSectionView: View {
    let section: HeroSection
    let actions: HomeSectionActions
    let imagePipeline: ImagePipeline

    var body: some View {
        ForEach(section.items) { item in
            Button {
                actions.send(.select(item.destination, item.tracking))
            } label: {
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(
                        url: item.imageURL,
                        targetSize: CGSize(width: 400, height: 230),
                        pipeline: imagePipeline,
                        placeholder: .hero
                    )
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.75)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.title.bold())
                        if let subtitle = item.subtitle {
                            Text(subtitle).font(.headline)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(20)
                }
                .frame(height: 230)
                .clipShape(.rect(cornerRadius: 24))
                .padding(.horizontal)
            }
            .buttonStyle(.plain)
            .onScrollVisibilityChange(threshold: 0.5) { isVisible in
                if isVisible {
                    actions.send(.becameVisible(item.tracking))
                }
            }
        }
    }
}

private struct CampaignCarouselSectionView: View {
    let section: CampaignCarouselSection
    let actions: HomeSectionActions
    let imagePipeline: ImagePipeline

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(section.title)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(section.items) { item in
                        Button {
                            actions.send(.select(item.destination, item.tracking))
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                RemoteImage(
                                    url: item.imageURL,
                                    targetSize: CGSize(width: 270, height: 160),
                                    pipeline: imagePipeline,
                                    placeholder: .campaign
                                )
                                LinearGradient(
                                    colors: [.clear, .black.opacity(0.7)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.headline)
                                    if let subtitle = item.subtitle {
                                        Text(subtitle).font(.caption)
                                    }
                                }
                                .foregroundStyle(.white)
                                .padding()
                            }
                            .frame(width: 270, height: 160)
                            .clipShape(.rect(cornerRadius: 20))
                        }
                        .buttonStyle(.plain)
                        .onScrollVisibilityChange(threshold: 0.5) { isVisible in
                            if isVisible {
                                actions.send(.becameVisible(item.tracking))
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

private struct CategorySectionView: View {
    let section: CategorySection
    let actions: HomeSectionActions
    private let columns = Array(repeating: GridItem(.flexible()), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(section.title)
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(section.items) { item in
                    Button {
                        actions.send(.select(item.destination, item.tracking))
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: item.symbol)
                                .font(.title2)
                                .frame(width: 56, height: 56)
                                .background(Color(.secondarySystemGroupedBackground), in: .circle)
                            Text(item.title)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .onScrollVisibilityChange(threshold: 0.5) { isVisible in
                        if isVisible {
                            actions.send(.becameVisible(item.tracking))
                        }
                    }
                }
            }.padding(.horizontal)
        }
    }
}

private struct ProductSectionView: View {
    let section: ProductSection
    let cart: CartStore
    let actions: HomeSectionActions
    let imagePipeline: ImagePipeline

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(section.title)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(section.items) { product in
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                actions.send(.select(product.destination, product.tracking))
                            } label: {
                                RemoteImage(
                                    url: product.imageURL,
                                    targetSize: CGSize(width: 170, height: 170),
                                    pipeline: imagePipeline,
                                    placeholder: .product
                                )
                                .frame(width: 170, height: 170)
                                .clipShape(.rect(cornerRadius: 18))
                            }
                            .buttonStyle(.plain)
                            Text(product.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)
                                .frame(width: 170, alignment: .leading)
                            Text(
                                product.price.amount,
                                format: .currency(code: product.price.currencyCode)
                            )
                            .font(.headline)
                            AddToCartButton(
                                product: product,
                                cart: cart,
                                style: .prominent
                            )
                        }
                        .onScrollVisibilityChange(threshold: 0.5) { isVisible in
                            if isVisible {
                                actions.send(.becameVisible(product.tracking))
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

private struct RecommendationSectionView: View {
    let section: RecommendationSection
    let cart: CartStore
    let actions: HomeSectionActions
    let imagePipeline: ImagePipeline

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(section.title)
                Spacer()
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(.purple).padding(.trailing)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(section.items) { product in
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                actions.send(.select(product.destination, product.tracking))
                            } label: {
                                RemoteImage(url: product.imageURL, targetSize: CGSize(width: 190, height: 150), pipeline: imagePipeline, placeholder: .recommendation)
                                .frame(width: 190, height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                            }
                            .buttonStyle(.plain)
                            Text(product.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(
                                product.price.amount,
                                format: .currency(code: product.price.currencyCode)
                            )
                            .font(.headline)
                            AddToCartButton(
                                product: product,
                                cart: cart,
                                style: .standard
                            )
                        }
                        .frame(width: 190, alignment: .leading)
                        .onScrollVisibilityChange(threshold: 0.5) { isVisible in
                            if isVisible {
                                actions.send(.becameVisible(product.tracking))
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

private struct EditorialSectionView: View {
    let section: EditorialSection
    let actions: HomeSectionActions
    let imagePipeline: ImagePipeline

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(section.title)
            ForEach(section.items) { item in
                Button {
                    actions.send(.select(item.destination, item.tracking))
                } label: {
                    HStack(spacing: 14) {
                        RemoteImage(url: item.imageURL, targetSize: CGSize(width: 110, height: 90), pipeline: imagePipeline, placeholder: .editorial)
                        .frame(width: 110, height: 90)
                        .clipShape(.rect(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title).font(.headline)
                            if let subtitle = item.subtitle {
                                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .padding(12)
                    .background(
                        Color(.secondarySystemGroupedBackground),
                        in: .rect(cornerRadius: 18)
                    )
                    .padding(.horizontal)
                }
                .buttonStyle(.plain)
                .onScrollVisibilityChange(threshold: 0.5) { isVisible in
                    if isVisible { actions.send(.becameVisible(item.tracking)) }
                }
            }
        }
    }
}

private struct PromoSectionView: View {
    let section: PromoSection
    let actions: HomeSectionActions

    var body: some View {
        Button {
            if let destination = section.destination {
                actions.send(.select(destination, section.tracking))
            }
        } label: {
            HStack {
                Image(systemName: "shippingbox.fill").font(.title)
                VStack(alignment: .leading) {
                    Text(section.title).font(.headline)
                    if let subtitle = section.subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding()
            .background(
                Color(.secondarySystemGroupedBackground),
                in: .rect(cornerRadius: 18)
            )
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
        .onScrollVisibilityChange(threshold: 0.5) { isVisible in
            if isVisible { actions.send(.becameVisible(section.tracking)) }
        }
    }
}

private struct FallbackSectionView: View {
    let section: FallbackSection
    let actions: HomeSectionActions

    var body: some View {
        Button {
            if let destination = section.destination {
                actions.send(.select(destination, section.tracking))
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .frame(width: 48, height: 48)
                    .background(.orange.opacity(0.12), in: .circle)
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title).font(.headline)
                    if let subtitle = section.subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("Fallback for \(section.sourceType)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if section.destination != nil { Image(systemName: "chevron.right") }
            }
            .padding()
            .background(.orange.opacity(0.08), in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.orange.opacity(0.25))
            }
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
        .onScrollVisibilityChange(threshold: 0.5) { isVisible in
            if isVisible {
                actions.send(.becameVisible(section.tracking))
            }
        }
    }
}

private struct SectionTitle: View {
    let value: String
    
    init(_ value: String) { self.value = value }
    
    var body: some View {
        Text(value)
        .font(.title2.bold())
        .padding(.horizontal)
    }
}

struct DestinationView: View {
    let destination: Destination
    
    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text("This screen is an explicit boundary of the Home feature."))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
    
    private var title: String {
        switch destination {
        case .campaign: "Campaign"
        case .category: "Category"
        case .product: "Product"
        case .search: "Search"
        }
    }
    
    private var symbol: String {
        switch destination {
        case .campaign: "megaphone"
        case .category: "square.grid.2x2"
        case .product: "bag"
        case .search: "magnifyingglass"
        }
    }
}

#Preview {
    AppComposition.demo().makeRootView()
}
