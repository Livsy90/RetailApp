import Foundation

struct HomeResponseDTO: Decodable, Sendable {
    let schemaVersion: String
    let ttl: TimeInterval
    let nextCursor: String?
    let requestID: String
    let sections: [LossyHomeSectionDTO]
}

/// Keeps one new or malformed section from failing the entire home response.
struct LossyHomeSectionDTO: Decodable, Sendable {
    let value: HomeSectionDTO?
    let rawType: String?
    let issue: HomeContractIssue?
    let fallback: FallbackSectionDTO?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try? container.decode(RawSectionTypeDTO.self)
        rawType = raw?.type

        do {
            value = try container.decode(HomeSectionDTO.self)
            issue = nil
            fallback = nil
        } catch {
            value = nil
            fallback = try? container.decode(UnknownSectionDTO.self).fallback
            if let rawType, HomeSectionDTO.supportedTypes.contains(rawType) {
                issue = .invalid(type: rawType)
            } else {
                issue = .unsupported(type: rawType ?? "<missing>")
            }
        }
    }
}

enum HomeContractIssue: Sendable, Equatable {
    case unsupported(type: String)
    case invalid(type: String)
    case invalidItem(sectionID: String, itemID: String)
}

private struct RawSectionTypeDTO: Decodable {
    let type: String
}

private struct UnknownSectionDTO: Decodable {
    let fallback: FallbackSectionDTO?
}

struct FallbackSectionDTO: Decodable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let destination: DestinationDTO?
}

enum HomeSectionDTO: Decodable, Sendable {
    case hero(SectionPayloadDTO)
    case campaignCarousel(SectionPayloadDTO)
    case categories(SectionPayloadDTO)
    case products(SectionPayloadDTO)
    case recommendations(SectionPayloadDTO)
    case editorial(SectionPayloadDTO)
    case promo(SectionPayloadDTO)

    private enum CodingKeys: String, CodingKey { case type }
    static let supportedTypes = Set(["hero_campaign", "campaign_carousel", "category_grid", "product_carousel", "recommendations", "editorial", "promo"])

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "hero_campaign": self = .hero(try SectionPayloadDTO(from: decoder))
        case "campaign_carousel": self = .campaignCarousel(try SectionPayloadDTO(from: decoder))
        case "category_grid": self = .categories(try SectionPayloadDTO(from: decoder))
        case "product_carousel": self = .products(try SectionPayloadDTO(from: decoder))
        case "recommendations": self = .recommendations(try SectionPayloadDTO(from: decoder))
        case "editorial": self = .editorial(try SectionPayloadDTO(from: decoder))
        case "promo": self = .promo(try SectionPayloadDTO(from: decoder))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unsupported section: \(type)")
        }
    }
}

struct SectionPayloadDTO: Decodable, Sendable {
    let id: String
    let title: String?
    let subtitle: String?
    let expiresAt: Date?
    let items: [HomeItemDTO]?
    let destination: DestinationDTO?
}

struct HomeItemDTO: Decodable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let imageURL: URL?
    let symbol: String?
    let priceAmount: Decimal?
    let currencyCode: String?
    let availability: String?
    let destination: DestinationDTO?
}

struct DestinationDTO: Decodable, Sendable {
    let type: String
    let id: String?
    let query: String?
}

struct HomeMappingResult: Sendable {
    let page: HomePage
    let issues: [HomeContractIssue]
}

extension HomeResponseDTO {
    func toDomain(now: Date = Date()) -> HomeMappingResult {
        let mapped = sections.compactMap { section -> SectionMappingResult? in
            if let value = section.value {
                return value.toDomain(requestID: requestID, now: now)
            }
            if let fallback = section.fallback {
                return fallback.toDomain(requestID: requestID, sourceType: section.rawType ?? "unknown")
            }
            return nil
        }

        return HomeMappingResult(
            page: HomePage(
                sections: mapped.compactMap(\.section),
                nextCursor: nextCursor,
                schemaVersion: schemaVersion,
                fetchedAt: now,
                freshUntil: now.addingTimeInterval(ttl)
            ),
            issues: sections.compactMap(\.issue) + mapped.flatMap(\.issues)
        )
    }
}

private struct SectionMappingResult {
    let section: HomeSection?
    let issues: [HomeContractIssue]
}

private extension HomeSectionDTO {
    func toDomain(requestID: String, now: Date) -> SectionMappingResult {
        let payload: SectionPayloadDTO
        switch self {
        case .hero(let value), .campaignCarousel(let value), .categories(let value), .products(let value), .recommendations(let value), .editorial(let value), .promo(let value): payload = value
        }

        guard payload.expiresAt.map({ $0 > now }) ?? true else {
            return SectionMappingResult(section: nil, issues: [])
        }
        let sectionTracking = TrackingContext(requestID: requestID, sectionID: payload.id, itemID: nil, position: nil)

        switch self {
        case .hero:
            var issues: [HomeContractIssue] = []
            let items = (payload.items ?? []).enumerated().compactMap { index, item -> CampaignCard? in
                guard let destination = item.destination?.toDomain() else {
                    issues.append(.invalidItem(sectionID: payload.id, itemID: item.id))
                    return nil
                }
                return CampaignCard(id: item.id, title: item.title, subtitle: item.subtitle, imageURL: item.imageURL, destination: destination, tracking: item.tracking(requestID: requestID, sectionID: payload.id, position: index))
            }
            let section = items.isEmpty ? nil : HomeSection.hero(HeroSection(id: payload.id, items: items, tracking: sectionTracking))
            return SectionMappingResult(section: section, issues: issues)

        case .campaignCarousel:
            let result = campaignItems(payload: payload, requestID: requestID)
            let section = result.items.isEmpty ? nil : HomeSection.campaignCarousel(CampaignCarouselSection(id: payload.id, title: payload.title ?? "Campaigns", items: result.items, tracking: sectionTracking))
            return SectionMappingResult(section: section, issues: result.issues)

        case .categories:
            var issues: [HomeContractIssue] = []
            let items = (payload.items ?? []).enumerated().compactMap { index, item -> CategoryCard? in
                guard let destination = item.destination?.toDomain() else {
                    issues.append(.invalidItem(sectionID: payload.id, itemID: item.id))
                    return nil
                }
                return CategoryCard(id: item.id, title: item.title, symbol: item.symbol ?? "square.grid.2x2", destination: destination, tracking: item.tracking(requestID: requestID, sectionID: payload.id, position: index))
            }
            let section = items.isEmpty ? nil : HomeSection.categories(CategorySection(id: payload.id, title: payload.title ?? "Categories", items: items, tracking: sectionTracking))
            return SectionMappingResult(section: section, issues: issues)

        case .products:
            var issues: [HomeContractIssue] = []
            let items = (payload.items ?? []).enumerated().compactMap { index, item -> ProductCard? in
                guard let amount = item.priceAmount,
                      let currency = item.currencyCode,
                      let availabilityRaw = item.availability,
                      let availability = Availability(rawValue: availabilityRaw),
                      let destination = item.destination?.toDomain()
                else {
                    issues.append(.invalidItem(sectionID: payload.id, itemID: item.id))
                    return nil
                }
                return ProductCard(id: item.id, title: item.title, imageURL: item.imageURL, price: Money(amount: amount, currencyCode: currency), availability: availability, destination: destination, tracking: item.tracking(requestID: requestID, sectionID: payload.id, position: index))
            }
            let section = items.isEmpty ? nil : HomeSection.products(ProductSection(id: payload.id, title: payload.title ?? "Products", items: items, tracking: sectionTracking))
            return SectionMappingResult(section: section, issues: issues)

        case .recommendations:
            let result = productItems(payload: payload, requestID: requestID)
            let section = result.items.isEmpty ? nil : HomeSection.recommendations(RecommendationSection(id: payload.id, title: payload.title ?? "Recommended for you", items: result.items, tracking: sectionTracking))
            return SectionMappingResult(section: section, issues: result.issues)

        case .editorial:
            let result = campaignItems(payload: payload, requestID: requestID)
            let section = result.items.isEmpty ? nil : HomeSection.editorial(EditorialSection(id: payload.id, title: payload.title ?? "Inspiration", items: result.items, tracking: sectionTracking))
            return SectionMappingResult(section: section, issues: result.issues)

        case .promo:
            return SectionMappingResult(
                section: .promo(PromoSection(id: payload.id, title: payload.title ?? "", subtitle: payload.subtitle, destination: payload.destination?.toDomain(), tracking: sectionTracking)),
                issues: []
            )
        }
    }

    func campaignItems(payload: SectionPayloadDTO, requestID: String) -> (items: [CampaignCard], issues: [HomeContractIssue]) {
        var issues: [HomeContractIssue] = []
        let items = (payload.items ?? []).enumerated().compactMap { index, item -> CampaignCard? in
            guard let destination = item.destination?.toDomain() else {
                issues.append(.invalidItem(sectionID: payload.id, itemID: item.id))
                return nil
            }
            return CampaignCard(id: item.id, title: item.title, subtitle: item.subtitle, imageURL: item.imageURL, destination: destination, tracking: item.tracking(requestID: requestID, sectionID: payload.id, position: index))
        }
        return (items, issues)
    }

    func productItems(payload: SectionPayloadDTO, requestID: String) -> (items: [ProductCard], issues: [HomeContractIssue]) {
        var issues: [HomeContractIssue] = []
        let items = (payload.items ?? []).enumerated().compactMap { index, item -> ProductCard? in
            guard let amount = item.priceAmount,
                  let currency = item.currencyCode,
                  let availabilityRaw = item.availability,
                  let availability = Availability(rawValue: availabilityRaw),
                  let destination = item.destination?.toDomain()
            else {
                issues.append(.invalidItem(sectionID: payload.id, itemID: item.id))
                return nil
            }
            return ProductCard(id: item.id, title: item.title, imageURL: item.imageURL, price: Money(amount: amount, currencyCode: currency), availability: availability, destination: destination, tracking: item.tracking(requestID: requestID, sectionID: payload.id, position: index))
        }
        return (items, issues)
    }
}

private extension FallbackSectionDTO {
    func toDomain(requestID: String, sourceType: String) -> SectionMappingResult {
        let tracking = TrackingContext(requestID: requestID, sectionID: id, itemID: nil, position: nil)
        return SectionMappingResult(
            section: .fallback(FallbackSection(id: id, sourceType: sourceType, title: title, subtitle: subtitle, destination: destination?.toDomain(), tracking: tracking)),
            issues: []
        )
    }
}

private extension HomeItemDTO {
    func tracking(requestID: String, sectionID: String, position: Int) -> TrackingContext {
        TrackingContext(requestID: requestID, sectionID: sectionID, itemID: id, position: position)
    }
}

private extension DestinationDTO {
    func toDomain() -> Destination? {
        switch type {
        case "campaign": id.map(Destination.campaign)
        case "category": id.map(Destination.category)
        case "product": id.map(Destination.product)
        case "search": query.map(Destination.search)
        default: nil
        }
    }
}
