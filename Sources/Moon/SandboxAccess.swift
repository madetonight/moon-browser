import AppKit
import Security

/// Persist only grants obtained from the system's file/folder picker. A path
/// string by itself never expands the app's filesystem authority.
@MainActor enum SandboxAccess {
    nonisolated static var enabled: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil) as? Bool == true
    }
    private static var held: [String: URL] = [:]
    private static let key = "sandbox.fileBookmarks"

    @discardableResult static func remember(_ url: URL, persist: Bool = true) -> Bool {
        guard url.isFileURL else { return false }
        guard enabled else { return true }
        guard persist else { hold(url); return true }
        guard let data = try? url.bookmarkData(options: .withSecurityScope,
                    includingResourceValuesForKeys: nil, relativeTo: nil) else { return false }
        var bookmarks = Store.settings.dictionary(forKey: key) as? [String: Data] ?? [:]
        bookmarks[url.standardizedFileURL.path] = data
        Store.settings.set(bookmarks, forKey: key)
        hold(url)
        return true
    }
    static func restore(_ url: URL, refresh: Bool = true) -> URL {
        guard enabled else { return url }
        let path = url.standardizedFileURL.path
        if let held = held[path] { return held }
        guard let data = (Store.settings.dictionary(forKey: key) as? [String: Data])?[path] else { return url }
        var stale = false
        guard let resolved = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                relativeTo: nil, bookmarkDataIsStale: &stale) else { return url }
        hold(resolved)
        if stale && refresh { _ = remember(resolved) }
        return resolved
    }
    private static func hold(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard held[path] == nil, url.startAccessingSecurityScopedResource() else { return }
        held[path] = url
    }
}
