import Foundation

public enum SearchEngine: String, Codable, CaseIterable, Sendable {
    case duckDuckGo, google, bing, ecosia, startpage, kagi, brave, qwant
    public var title: String {
        switch self {
        case .duckDuckGo: "DuckDuckGo"
        case .google: "Google"
        case .bing: "Bing"
        case .ecosia: "Ecosia"
        case .startpage: "Startpage"
        case .kagi: "Kagi"
        case .brave: "Brave Search"
        case .qwant: "Qwant"
        }
    }
    public func search(_ query: String) -> URL {
        let base: String = switch self {
        case .duckDuckGo: "https://duckduckgo.com/"
        case .google: "https://www.google.com/search"
        case .bing: "https://www.bing.com/search"
        case .ecosia: "https://www.ecosia.org/search"
        case .startpage: "https://www.startpage.com/sp/search"
        case .kagi: "https://kagi.com/search"
        case .brave: "https://search.brave.com/search"
        case .qwant: "https://www.qwant.com/"
        }
        var components = URLComponents(string: base)!
        components.queryItems = [URLQueryItem(name: caseParameter, value: query)]
        return components.url!
    }
    private var caseParameter: String { self == .startpage ? "query" : "q" }
}

public enum Address {
    /// Only browser-owned schemes. Other app schemes require a separate user prompt.
    public static func resolve(_ input: String, engine: SearchEngine = .duckDuckGo) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value == "about:blank" { return URL(string: value) }
        if value.hasPrefix("/") || value.hasPrefix("~/") {
            return URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
        }
        if let url = URL(string: value), let scheme = url.scheme?.lowercased(),
           ["http", "https", "file"].contains(scheme),
           scheme == "file" || url.host?.isEmpty == false { return url }
        if !value.contains(where: { $0.isWhitespace }),
           let parts = URLComponents(string: "https://" + value),
           let host = parts.host, parts.user == nil, parts.password == nil,
           (host.contains(".") || host == "localhost" || host.contains(":")),
           !host.contains("@") {
            var result = parts
            result.scheme = isLocalHost(host) ? "http" : "https"
            return result.url
        }
        return engine.search(value)
    }

    public static func isLocalHost(_ host: String) -> Bool {
        if ["localhost", "[::1]", "::1"].contains(host.lowercased()) || host.hasSuffix(".localhost") { return true }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }
        return octets[0] == 127 || octets[0] == 10 ||
            (octets[0] == 192 && octets[1] == 168) ||
            (octets[0] == 172 && (16...31).contains(octets[1]))
    }

    public static func clean(_ url: URL) -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        parts.queryItems = parts.queryItems?.filter {
            !$0.name.lowercased().hasPrefix("utm_") && !["fbclid", "gclid", "msclkid"].contains($0.name.lowercased())
        }
        if parts.queryItems?.isEmpty == true { parts.queryItems = nil }
        return parts.url ?? url
    }
}
