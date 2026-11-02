import Foundation
import Testing
@testable import MoonCore

@Test func suggestionsPreferOpenTabsAndDeduplicateStoredPages() {
    let url = URL(string: "https://webkit.org/")!
    let id = UUID()
    let stored = PageRecord(title: "WebKit", url: url)
    let offers = SearchOffers.make(query: "webkit", engine: .google,
                                   tabs: [SearchTab(id: id, title: "WebKit", url: url)],
                                   bookmarks: [stored], history: [stored], privateMode: false)
    #expect(offers.map(\.kind) == [.search, .tab])
    #expect(offers.last?.tabID == id)
    #expect(offers.first?.url == SearchEngine.google.search("webkit"))
}

@Test func privateSuggestionsExcludePersonalRecords() {
    let url = URL(string: "https://example.com/private")!
    let offers = SearchOffers.make(query: "example", engine: .duckDuckGo,
                                   tabs: [SearchTab(id: UUID(), title: "Example", url: url)],
                                   bookmarks: [PageRecord(title: "Example", url: url)],
                                   history: [PageRecord(title: "Example", url: url)], privateMode: true)
    #expect(offers.count == 1)
    #expect(offers.first?.kind == .search)
}

@Test func addressOffersUseTheDestinationAndHonorLimits() {
    let records = (0..<20).map { PageRecord(title: "Web \($0)", url: URL(string: "https://example.com/\($0)")!) }
    let offers = SearchOffers.make(query: "example.com", engine: .bing, tabs: [],
                                   bookmarks: records, history: records, privateMode: false, limit: 4)
    #expect(offers.count == 4)
    #expect(offers.first?.kind == .address)
    #expect(offers.first?.url.host == "example.com")
    #expect(SearchOffers.make(query: "  ", engine: .bing, tabs: [], bookmarks: records, history: [], privateMode: false).isEmpty)
    #expect(SearchOffers.make(query: "example", engine: .bing, tabs: [], bookmarks: records, history: [], privateMode: false, limit: 0).isEmpty)
}
