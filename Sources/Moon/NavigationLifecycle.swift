import WebKit

/// WebKit can finish an older navigation after the next one has begun.
/// Keep callbacks from that older load from covering the current document.
@MainActor
final class NavigationLifecycle {
    private var current: WKNavigation?
    private var awaitingStart = false

    func invalidate() {
        current = nil
        awaitingStart = true
    }

    func started(_ navigation: WKNavigation) {
        current = navigation
        awaitingStart = false
    }

    func accepts(_ navigation: WKNavigation?) -> Bool {
        guard !awaitingStart else { return false }
        if let current { return current === navigation }
        return true
    }
}
