import AppKit
import SwiftUI

enum GhostPrivacy {
    static var hideLocation: Bool {
        get { Store.settings.object(forKey: "ghost.hideLocation") as? Bool ?? true }
        set { Store.settings.set(newValue, forKey: "ghost.hideLocation") }
    }
}

extension Browsers {
    static func newGhostWindow() {
        let browser = Browser(record: WindowRecord(), ghostWindow: true)
        open(browser, frame: nil)
    }

    /// Discard only private browsing. Ordinary windows, saved sessions and
    /// credentials remain intact. Private stores die with their owning tabs.
    static func ghostPanic() {
        for browser in Array(all) {
            Nebula.shared.suspend(in: browser)
            if browser.ghostWindow { discard(browser); continue }
            browser.linkInsight = nil
            if browser.peekTab?.shy == true { browser.closePeek() }
            for (id, var row) in browser.parked {
                let privateTabs = row.tabs.filter(\.shy)
                for tab in privateTabs { tab.close() }
                row.tabs.removeAll { $0.shy }
                if !row.tabs.contains(where: { $0.id == row.active }) { row.active = row.tabs.first?.id }
                let ids = Set(row.tabs.map(\.id))
                row.splits.removeAll { !ids.contains($0.left) || !ids.contains($0.right) }
                browser.parked[id] = row
            }
            for tab in browser.tabs.filter(\.shy) { browser.close(tab) }
        }
    }
}

struct GhostHeading: View {
    @AppStorage("ghost.hideLocation", store: Store.settings) private var hideLocation = true
    var body: some View {
        Menu {
            Toggle("Hide precise location", isOn: $hideLocation)
            Text("Temporary cookies and logins. No saved history or session.")
            Text("Your IP address remains visible to websites.")
            Divider()
            Button("Close All Ghost Browsing") { Browsers.ghostPanic() }
        } label: {
            Label("Ghost", systemImage: "theatermasks")
                .font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading)
        }.menuStyle(.borderlessButton).padding(.horizontal, 10).frame(height: 28)

    }
}


struct GhostLocationSwitch: View {
    @AppStorage("ghost.hideLocation", store: Store.settings) private var hideLocation = true
    var body: some View { Switch(on: $hideLocation) }
}
