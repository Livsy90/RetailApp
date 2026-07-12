import Foundation

struct HomeAPIClient: Sendable {
    var fetch: @Sendable (_ cursor: String?) async throws -> HomeResponseDTO

    func home(cursor: String? = nil) async throws -> HomeResponseDTO {
        try await fetch(cursor)
    }
}

extension HomeAPIClient {
    static func demo() -> HomeAPIClient {
        HomeAPIClient { _ in
            try await Task.sleep(for: .milliseconds(700))
            try Task.checkCancellation()
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(HomeResponseDTO.self, from: Data(Self.demoJSON.utf8))
        }
    }

    private static let demoJSON = #"""
    {
      "schemaVersion": "home.v1", "ttl": 300, "nextCursor": null, "requestID": "demo-request",
      "sections": [
        {"id":"hero","type":"hero_campaign","items":[
          {"id":"summer","title":"Summer essentials","subtitle":"Up to 40% off","imageURL":"https://images.unsplash.com/photo-1441986300917-64674bd600d8?auto=format&fit=crop&w=900&q=75","destination":{"type":"campaign","id":"summer"}}
        ]},
        {"id":"campaigns","type":"campaign_carousel","title":"Trending campaigns","items":[
          {"id":"weekend","title":"Weekend getaway","subtitle":"Travel-ready picks","imageURL":"https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=700&q=75","destination":{"type":"campaign","id":"weekend"}},
          {"id":"workspace","title":"Refresh your workspace","subtitle":"Comfort meets focus","imageURL":"https://images.unsplash.com/photo-1497366754035-f200968a6e72?auto=format&fit=crop&w=700&q=75","destination":{"type":"campaign","id":"workspace"}}
        ]},
        {"id":"categories","type":"category_grid","title":"Shop by category","items":[
          {"id":"fashion","title":"Fashion","symbol":"tshirt","destination":{"type":"category","id":"fashion"}},
          {"id":"home","title":"Home","symbol":"house","destination":{"type":"category","id":"home"}},
          {"id":"tech","title":"Tech","symbol":"headphones","destination":{"type":"category","id":"tech"}},
          {"id":"beauty","title":"Beauty","symbol":"sparkles","destination":{"type":"category","id":"beauty"}}
        ]},
        {"id":"recommended","type":"product_carousel","title":"Recommended for you","items":[
          {"id":"p1","title":"Everyday sneakers","imageURL":"https://images.unsplash.com/photo-1542291026-7eec264c27ff?auto=format&fit=crop&w=500&q=75","priceAmount":89.00,"currencyCode":"USD","availability":"available","destination":{"type":"product","id":"p1"}},
          {"id":"p2","title":"Wireless headphones","imageURL":"https://images.unsplash.com/photo-1505740420928-5e560c06d30e?auto=format&fit=crop&w=500&q=75","priceAmount":129.00,"currencyCode":"USD","availability":"available","destination":{"type":"product","id":"p2"}},
          {"id":"p3","title":"Minimal watch","imageURL":"https://images.unsplash.com/photo-1523275335684-37898b6baf30?auto=format&fit=crop&w=500&q=75","priceAmount":149.00,"currencyCode":"USD","availability":"unavailable","destination":{"type":"product","id":"p3"}}
        ]},
        {"id":"personalized","type":"recommendations","title":"Because you like design","items":[
          {"id":"p4","title":"Portable speaker","imageURL":"https://images.unsplash.com/photo-1608043152269-423dbba4e7e1?auto=format&fit=crop&w=500&q=75","priceAmount":79.00,"currencyCode":"USD","availability":"available","destination":{"type":"product","id":"p4"}},
          {"id":"p5","title":"Modern table lamp","imageURL":"https://images.unsplash.com/photo-1507473885765-e6ed057f782c?auto=format&fit=crop&w=500&q=75","priceAmount":64.00,"currencyCode":"USD","availability":"available","destination":{"type":"product","id":"p5"}}
        ]},
        {"id":"stories","type":"editorial","title":"Stories & inspiration","items":[
          {"id":"slow_living","title":"A calmer home","subtitle":"Simple ideas for everyday spaces","imageURL":"https://images.unsplash.com/photo-1600566753086-00f18fb6b3ea?auto=format&fit=crop&w=500&q=75","destination":{"type":"campaign","id":"slow_living"}},
          {"id":"city_style","title":"City style edit","subtitle":"The season's versatile essentials","imageURL":"https://images.unsplash.com/photo-1483985988355-763728e1935b?auto=format&fit=crop&w=500&q=75","destination":{"type":"campaign","id":"city_style"}}
        ]},
        {"id":"future","type":"live_shopping_carousel","items":[],"fallback":{"id":"live_fallback","title":"Live shopping is coming","subtitle":"Update the app later for the interactive experience","destination":{"type":"campaign","id":"live_preview"}}},
        {"id":"promo","type":"promo","title":"Members get free delivery","subtitle":"Join today and enjoy more benefits","destination":{"type":"campaign","id":"membership"}}
      ]
    }
    """#
}
