import Foundation

public enum ResourcePolicy: Sendable {
    case chromePackage
    case sameOrigin(URL)
    public func allows(_ url: URL) -> Bool {
        guard url.user == nil, url.password == nil, let host = url.host?.lowercased() else { return false }
        switch self {
        case .chromePackage:
            guard url.scheme == "https", url.port == nil || url.port == 443 else { return false }
            return host == "clients2.google.com" || ["googleusercontent.com", "gvt1.com", "gvt2.com"].contains { host == $0 || host.hasSuffix("." + $0) }
        case .sameOrigin(let source):
            func port(_ url: URL) -> Int? { url.port ?? (url.scheme == "https" ? 443 : url.scheme == "http" ? 80 : nil) }
            return ["http", "https"].contains(url.scheme) && url.scheme == source.scheme && host == source.host?.lowercased() && port(url) == port(source)
        }
    }
}
