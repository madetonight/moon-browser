import Foundation

/// Voice input selects a bounded browser action. It never becomes executable code.
public enum NebulaCommand: Equatable, Sendable {
    case newTab, newPrivateTab, closeTab, back, forward, reload, nextTab, previousTab
    case bookmarks, downloads, translate, orbit, bookmark, mute, zoomIn, zoomOut, resetZoom
    case scroll(up: Bool)
    case search(String), open(URL), switchTab(String)

    public static func parse(_ transcript: String) -> Self? {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 2_000 else { return nil }
        let normalized = text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
        let commands: [String: Self] = [
            "new tab": .newTab, "open a new tab": .newTab, "open new tab": .newTab,
            "new private tab": .newPrivateTab, "open a private tab": .newPrivateTab,
            "close tab": .closeTab, "close this tab": .closeTab,
            "go back": .back, "back": .back, "go forward": .forward,
            "reload": .reload, "reload page": .reload, "refresh page": .reload,
            "next tab": .nextTab, "previous tab": .previousTab,
            "show bookmarks": .bookmarks, "show downloads": .downloads,
            "translate this page": .translate, "open orbit": .orbit,
            "bookmark this page": .bookmark, "mute this tab": .mute,
            "zoom in": .zoomIn, "zoom out": .zoomOut, "reset zoom": .resetZoom,
            "scroll down": .scroll(up: false), "scroll up": .scroll(up: true)
        ]
        if let command = commands[normalized] { return command }
        for prefix in ["search for ", "search "] where normalized.hasPrefix(prefix) {
            let query = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return query.isEmpty ? nil : .search(query)
        }
        if normalized.hasPrefix("switch to ") {
            let name = String(normalized.dropFirst(10)).trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : .switchTab(name)
        }
        if normalized.hasPrefix("open ") {
            var address = String(text.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !address.contains("://") { address = "https://" + address }
            guard let url = URL(string: address), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                  let host = url.host, host.contains("."), url.user == nil, url.password == nil,
                  !address.contains(where: { $0.isWhitespace }) else { return nil }
            return .open(url)
        }
        return nil
    }
}
