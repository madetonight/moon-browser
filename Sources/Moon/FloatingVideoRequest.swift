import Foundation

/// One app-wide floating window, and one request allowed to take ownership.
/// WebKit snapshots and script replies can finish after a newer tab was chosen.
@MainActor
enum FloatingVideoRequest {
    struct Ticket: Equatable {
        let id = UUID()
        let owner: ObjectIdentifier
        let tab: Tab.ID
    }
    private(set) static var pending: Ticket?

    static func begin(in browser: Browser, tab: Tab.ID) -> Ticket {
        let ticket = Ticket(owner: ObjectIdentifier(browser), tab: tab)
        pending = ticket
        return ticket
    }
    static func owns(_ ticket: Ticket) -> Bool { pending == ticket }
    static func contains(_ browser: Browser, tab: Tab.ID) -> Bool {
        pending?.owner == ObjectIdentifier(browser) && pending?.tab == tab
    }
    static func finish(_ ticket: Ticket) { if owns(ticket) { pending = nil } }
    static func cancel(in browser: Browser, tab: Tab.ID? = nil) {
        guard pending?.owner == ObjectIdentifier(browser), tab == nil || pending?.tab == tab else { return }
        pending = nil
    }
    static func cancelAll() { pending = nil }
}

/// Ignore hidden ad/preload players when a page contains several videos.
enum PlayingVideo {
    static func script(allowPaused: Bool) -> String {
        """
        (function () {
          var all = document.querySelectorAll('video'), best = null, area = 0;
          for (var pass = 0; pass < \(allowPaused ? 2 : 1); pass++) {
            for (var i = 0; i < all.length; i++) {
              var v = all[i], box = v.getBoundingClientRect(), style = getComputedStyle(v);
              if (v.ended || v.readyState < 2 || (pass === 0 && v.paused)) continue;
              if (box.width < 2 || box.height < 2 || style.display === 'none' || (style.visibility === 'hidden' && !document.documentElement.classList.contains('office-floating'))) continue;
              var size = box.width * box.height;
              if (size > area) { area = size; best = v; }
            }
            if (best) break;
          }
          return best;
        })()
        """
    }
}
