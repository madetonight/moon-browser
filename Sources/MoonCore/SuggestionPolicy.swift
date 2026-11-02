import Foundation

public enum SuggestionPolicy {
    /// Only explicitly enabled, nonprivate, ordinary search words can leave the Mac.
    public static func permits(_ text: String, enabled: Bool, privateMode: Bool) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard enabled, !privateMode, !text.isEmpty, text.count <= 160,
              !text.contains(where: \.isNewline), !text.contains("\\") else { return false }
        let tokens = text.split(whereSeparator: \.isWhitespace)
        guard let first = tokens.first,
              !first.hasPrefix("/"), !first.hasPrefix("~"), !first.hasPrefix("./"), !first.hasPrefix("../"),
              !first.contains(":") else { return false }
        for token in tokens {
            if tokens.count == 1 && (token.contains(".") || token.contains("/")) { return false }
            if token.contains("@") { return false }
            if token.count >= 12 && token.contains(where: \.isLetter) && token.contains(where: \.isNumber) { return false }
            if token.count >= 9 && token.allSatisfy({ $0.isNumber || $0 == "-" }) { return false }
            if token.count >= 24 && !token.contains(where: \.isWhitespace) { return false }
        }
        return true
    }
    public static func endpoint(query: String, engine: SearchEngine) -> URL? {
        let template: String
        switch engine {
        case .google: template = "https://suggestqueries.google.com/complete/search?client=firefox&q="
        case .duckDuckGo: template = "https://duckduckgo.com/ac/?type=list&q="
        case .bing: template = "https://www.bing.com/osjson.aspx?query="
        case .ecosia: template = "https://ac.ecosia.org/autocomplete?type=list&q="
        case .startpage: template = "https://www.startpage.com/osuggestions?q="
        case .kagi: template = "https://kagi.com/api/autosuggest?q="
        case .brave: template = "https://search.brave.com/api/suggest?q="
        case .qwant: template = "https://api.qwant.com/api/suggest/?client=opensearch&q="
        }
        var parts = URLComponents(string: template)
        var items = parts?.queryItems ?? []
        items[items.count - 1].value = query
        parts?.queryItems = items
        return parts?.url
    }
    public static func parse(_ data: Data, query: String) -> [String] {
        guard let result = try? JSONSerialization.jsonObject(with: data) as? [Any],
              result.count >= 2, let strings = result[1] as? [String] else { return [] }
        var seen = Set([query.lowercased()])
        return Array(strings.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter {
            !$0.isEmpty && $0.count <= 200 && !$0.contains(where: \.isNewline) && seen.insert($0.lowercased()).inserted
        }.prefix(4))
    }
}
