import Foundation

public struct SearchTab: Sendable {
    public let id: UUID
    public let title: String
    public let url: URL
    public init(id: UUID, title: String, url: URL) { self.id = id; self.title = title; self.url = url }
}

public struct SearchOffer: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case search, suggested, address, tab, bookmark, history }
    public let id: String
    public let kind: Kind
    public let title: String
    public let detail: String
    public let url: URL
    public let tabID: UUID?
}

public enum SearchOffers {
    /// Local records only. Keystrokes never trigger a request to an engine or favicon service.
    public static func make(query: String, engine: SearchEngine, tabs: [SearchTab], bookmarks: [PageRecord], history: [PageRecord], privateMode: Bool, limit: Int = 7) -> [SearchOffer] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 0, let destination = Address.resolve(query, engine: engine) else { return [] }
        let search = destination == engine.search(query)
        var offers = [SearchOffer(id: "input", kind: search ? .search : .address,
                                  title: search ? query : readable(destination),
                                  detail: search ? engine.title : "",
                                  url: destination, tabID: nil)]
        guard !privateMode, offers.count < limit else { return offers }
        let matches: (String, URL) -> Bool = { title, url in
            title.localizedCaseInsensitiveContains(query) || url.absoluteString.localizedCaseInsensitiveContains(query)
        }
        var seen = Set<URL>()
        for tab in tabs where matches(tab.title, tab.url) && seen.insert(tab.url).inserted {
            offers.append(SearchOffer(id: "tab:\(tab.id)", kind: .tab, title: readable(tab.url),
                                      detail: tab.title, url: tab.url, tabID: tab.id))
            if offers.count == limit { return offers }
        }
        var examined = 0
        for (records, kind) in [(bookmarks, SearchOffer.Kind.bookmark), (history, .history)] {
            for record in records {
                examined += 1
                if examined.isMultiple(of: 256), Task.isCancelled { return offers }
                guard matches(record.title, record.url), seen.insert(record.url).inserted else { continue }
                offers.append(SearchOffer(id: "\(kind.rawValue):\(record.url.absoluteString)", kind: kind,
                                          title: readable(record.url), detail: record.title, url: record.url, tabID: nil))
                if offers.count == limit { return offers }
            }
        }
        return Array(offers.prefix(limit))
    }

    public static func remote(_ query: String, engine: SearchEngine) -> SearchOffer {
        SearchOffer(id: "suggested:" + query, kind: .suggested, title: query, detail: engine.title, url: engine.search(query), tabID: nil)
    }
    private static func readable(_ url: URL) -> String {
        guard let host = url.host else { return url.isFileURL ? url.lastPathComponent : url.absoluteString }
        return (host.hasPrefix("www.") ? String(host.dropFirst(4)) : host) + (url.path == "/" ? "" : url.path)
    }
}
