import Foundation

/// Activity data and API credentials must never follow a redirect off this Mac.
public enum ActivityWatchEndpoint {
    public static let base = URL(string: "http://127.0.0.1:5600")!
    public static func allows(_ url: URL) -> Bool {
        url.scheme == "http" && url.host == "127.0.0.1" && url.port == 5600
            && url.user == nil && url.password == nil
    }
    public static func api(_ components: [String]) -> URL {
        components.reduce(base.appendingPathComponent("api/0")) { $0.appendingPathComponent($1) }
    }
    public static func workspace(_ path: String) -> URL {
        var parts = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        parts.path = "/"
        parts.fragment = path
        return parts.url!
    }
    /// Bucket ids are data in the query language, never executable query text.
    public static func literal(_ string: String) -> String {
        let encoded = try! JSONEncoder().encode(string)
        return String(decoding: encoded, as: UTF8.self)
    }
}
