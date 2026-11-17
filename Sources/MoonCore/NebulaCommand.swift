import Foundation

/// Voice input selects a bounded browser action. It never becomes executable code.
public enum NebulaCommand: Equatable, Sendable {
    case newTab, newPrivateTab, closeTab, back, forward, reload, nextTab, previousTab
    case bookmarks, downloads, translate, orbit, bookmark, mute, zoomIn, zoomOut, resetZoom
    case scroll(up: Bool)
    case search(String), open(URL), switchTab(String), switchSpace(String), closeMatching(String)
    case summarize, tidy

    public static func parse(_ transcript: String) -> Self? {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 2_000 else { return nil }
        let normalized = text.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?¿¡"))
        let spanish: [String: Self] = [
            "nueva pestana": .newTab, "abre una nueva pestana": .newTab,
            "nueva pestana privada": .newPrivateTab, "nueva pestana fantasma": .newPrivateTab,
            "cierra esta pestana": .closeTab, "cerrar pestana": .closeTab, "cierra la pestana": .closeTab,
            "atras": .back, "vuelve atras": .back, "adelante": .forward,
            "recarga": .reload, "recarga la pagina": .reload, "actualiza la pagina": .reload,
            "siguiente pestana": .nextTab, "pestana anterior": .previousTab,
            "muestra los marcadores": .bookmarks, "muestra las descargas": .downloads,
            "traduce esta pagina": .translate, "abre orbit": .orbit,
            "guarda esta pagina": .bookmark, "silencia esta pestana": .mute,
            "aumenta el zoom": .zoomIn, "reduce el zoom": .zoomOut, "restablece el zoom": .resetZoom,
            "baja": .scroll(up: false), "sube": .scroll(up: true),
            "resume esta pagina": .summarize, "resume esto": .summarize,
            "organiza mis pestanas": .tidy, "ordena mis pestanas": .tidy
        ]
        if let action = spanish[normalized] { return action }
        for prefix in ["busca en google ", "busca ", "buscar "] where normalized.hasPrefix(prefix) {
            let query = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return query.isEmpty ? nil : .search(query)
        }
        for prefix in ["cambia al espacio ", "cambia de espacio a "] where normalized.hasPrefix(prefix) {
            return .switchSpace(String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        for prefix in ["cambia a ", "ve a la pestana "] where normalized.hasPrefix(prefix) {
            return .switchTab(String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        for prefix in ["abre ", "abrir ", "ve a ", "llevame a "] where normalized.hasPrefix(prefix) {
            let address = String(text.dropFirst(prefix.count))
                .replacingOccurrences(of: " punto ", with: ".", options: .caseInsensitive)
            return parse("open " + address)
        }
        if normalized.hasPrefix("cierra todas las pestanas de ") || normalized.hasPrefix("cierra mis pestanas de ") {
            let prefix = normalized.hasPrefix("cierra todas") ? "cierra todas las pestanas de " : "cierra mis pestanas de "
            let name = String(normalized.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : .closeMatching(name)
        }
        for prefix in ["close all of my ", "close all my ", "close all ", "close my "] where normalized.hasPrefix(prefix) && normalized.hasSuffix(" tabs") {
            let name = String(normalized.dropFirst(prefix.count).dropLast(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : .closeMatching(name)
        }
        for prefix in ["switch to space ", "switch space to "] where normalized.hasPrefix(prefix) {
            let name = String(normalized.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : .switchSpace(name)
        }
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
            "scroll down": .scroll(up: false), "scroll up": .scroll(up: true),
            "summarize this page": .summarize, "summarize this": .summarize,
            "summarize page": .summarize, "summarise this page": .summarize,
            "tidy my tabs": .tidy, "tidy tabs": .tidy, "organize my tabs": .tidy,
            "organise my tabs": .tidy
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
            let site = address.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!?")))
            let sites = ["youtube": "https://www.youtube.com", "you tube": "https://www.youtube.com",
                         "gmail": "https://mail.google.com", "x": "https://x.com",
                         "google": "https://www.google.com", "github": "https://github.com",
                         "chatgpt": "https://chatgpt.com"]
            if let destination = sites[site], let url = URL(string: destination) { return .open(url) }
            if !address.contains("://") { address = "https://" + address }
            guard var parts = URLComponents(string: address), ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
                  let originalHost = parts.host, parts.user == nil, parts.password == nil,
                  !address.contains(where: { $0.isWhitespace }) else { return nil }
            // Speech recognition adds sentence punctuation. A trailing DNS dot
            // must not turn a spoken site name into a different destination.
            // Normalize the host only; paths, queries and fragments stay literal.
            var host = originalHost
            while host.hasSuffix(".") { host.removeLast() }
            guard host.contains("."), !host.split(separator: ".", omittingEmptySubsequences: false).contains(where: { $0.isEmpty }) else { return nil }
            parts.host = host
            guard let url = parts.url else { return nil }
            return .open(url)
        }
        return nil
    }
}
