import Foundation

struct HomePage: Sendable, Equatable, Codable {
    let sections: [HomeSection]
    let nextCursor: String?
    let schemaVersion: String
    let fetchedAt: Date
    let freshUntil: Date

    func isFresh(at date: Date) -> Bool { freshUntil > date }
}

enum HomeSection: Sendable, Equatable, Identifiable, Codable {
    case hero(HeroSection)
    case campaignCarousel(CampaignCarouselSection)
    case categories(CategorySection)
    case products(ProductSection)
    case recommendations(RecommendationSection)
    case editorial(EditorialSection)
    case promo(PromoSection)
    case fallback(FallbackSection)

    var id: String {
        switch self {
        case .hero(let section): section.id
        case .campaignCarousel(let section): section.id
        case .categories(let section): section.id
        case .products(let section): section.id
        case .recommendations(let section): section.id
        case .editorial(let section): section.id
        case .promo(let section): section.id
        case .fallback(let section): section.id
        }
    }

    var tracking: TrackingContext {
        switch self {
        case .hero(let section): section.tracking
        case .campaignCarousel(let section): section.tracking
        case .categories(let section): section.tracking
        case .products(let section): section.tracking
        case .recommendations(let section): section.tracking
        case .editorial(let section): section.tracking
        case .promo(let section): section.tracking
        case .fallback(let section): section.tracking
        }
    }
}

struct HeroSection: Sendable, Equatable, Codable {
    let id: String
    let items: [CampaignCard]
    let tracking: TrackingContext
}

struct CampaignCarouselSection: Sendable, Equatable, Codable {
    let id: String
    let title: String
    let items: [CampaignCard]
    let tracking: TrackingContext
}

struct CategorySection: Sendable, Equatable, Codable {
    let id: String
    let title: String
    let items: [CategoryCard]
    let tracking: TrackingContext
}

struct ProductSection: Sendable, Equatable, Codable {
    let id: String
    let title: String
    let items: [ProductCard]
    let tracking: TrackingContext
}

struct RecommendationSection: Sendable, Equatable, Codable {
    let id: String
    let title: String
    let items: [ProductCard]
    let tracking: TrackingContext
}

struct EditorialSection: Sendable, Equatable, Codable {
    let id: String
    let title: String
    let items: [CampaignCard]
    let tracking: TrackingContext
}

struct PromoSection: Sendable, Equatable, Codable {
    let id: String
    let title: String
    let subtitle: String?
    let destination: Destination?
    let tracking: TrackingContext
}

struct FallbackSection: Sendable, Equatable, Codable {
    let id: String
    let sourceType: String
    let title: String
    let subtitle: String?
    let destination: Destination?
    let tracking: TrackingContext
}

struct CampaignCard: Sendable, Equatable, Identifiable, Codable {
    let id: String
    let title: String
    let subtitle: String?
    let imageURL: URL?
    let destination: Destination
    let tracking: TrackingContext
}

struct CategoryCard: Sendable, Equatable, Identifiable, Codable {
    let id: String
    let title: String
    let symbol: String
    let destination: Destination
    let tracking: TrackingContext
}

struct ProductCard: Sendable, Equatable, Identifiable, Codable {
    let id: String
    let title: String
    let imageURL: URL?
    let price: Money
    let availability: Availability
    let destination: Destination
    let tracking: TrackingContext
}

struct Money: Sendable, Equatable, Codable {
    let amount: Decimal
    let currencyCode: String
}

enum Availability: String, Sendable, Equatable, Codable {
    case available
    case unavailable
}

enum Destination: Sendable, Hashable, Codable {
    case campaign(id: String)
    case category(id: String)
    case product(id: String)
    case search(query: String)
}

struct TrackingContext: Sendable, Equatable, Codable {
    let requestID: String
    let sectionID: String
    let itemID: String?
    let position: Int?
}
