import Foundation

/// Reusable page metadata never needs HTTP authentication userinfo. Queries,
/// fragments, ports and paths remain part of the destination.
public enum MetadataPrivacy {
    public static func address(_ text: String) -> String {
        guard var parts = URLComponents(string: text),
              parts.percentEncodedUser != nil || parts.percentEncodedPassword != nil else { return text }
        parts.user = nil
        parts.password = nil
        return parts.string ?? "about:blank"
    }
    public static func address(_ url: URL) -> URL {
        URL(string: address(url.absoluteString)) ?? URL(string: "about:blank")!
    }
    /// Covers nested window rows, session homes, pins and legacy bookmark trees.
    /// Unchanged data keeps its original bytes and serialization order.
    public static func json(_ data: Data) -> Data {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return data }
        var changed = false
        func clean(_ value: Any) -> Any {
            if let text = value as? String {
                let safe = address(text)
                if safe != text { changed = true }
                return safe
            }
            if let list = value as? [Any] { return list.map(clean) }
            if let dictionary = value as? [String: Any] { return dictionary.mapValues(clean) }
            return value
        }
        let safe = clean(object)
        guard changed else { return data }
        return (try? JSONSerialization.data(withJSONObject: safe, options: [.fragmentsAllowed, .sortedKeys])) ?? data
    }
}
