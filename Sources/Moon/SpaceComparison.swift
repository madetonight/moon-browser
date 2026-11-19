import AppKit
import SwiftUI

/// Explicitly labelled, separately sandboxed comparison apps; never the release app.
enum SpaceComparison {
    enum Style: String { case minimal, zen }
    static let style: Style? = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "MoonSpacesPreview") as? String,
              let style = Style(rawValue: value),
              Bundle.main.bundleIdentifier == "org.moonbrowser.Moon.preview.spaces.\(value)" else { return nil }
        return style
    }()
    static var zen: Bool { style == .zen }

    @MainActor static func prepare() {
        guard style != nil else { return }
        let prefs = Shared.prefs
        prefs.welcomed = true
        prefs.sidebar = true
        prefs.sideHides = false
        prefs.sideIcons = false
        prefs.sideWidth = 230
        prefs.usesSpaces = true
        prefs.confirmsQuit = false
    }

    @MainActor static func seed(_ browser: Browser) {
        guard let style, !Store.settings.bool(forKey: "spaces.comparison.seeded") else { return }
        let home = browser.homeSpaceID
        browser.renameSpace(home, to: style == .zen ? "Personal" : "Space 1")
        for text in ["https://www.apple.com", "https://en.wikipedia.org/wiki/Moon", "https://github.com/zen-browser/desktop"] {
            if let url = URL(string: text) { _ = browser.open(url, foreground: true) }
        }
        browser.addSpace(named: style == .zen ? "Work" : "Space 2", icon: "briefcase")
        if let url = URL(string: "https://developer.apple.com") { _ = browser.open(url, foreground: true) }
        let comparisonSpace = browser.spaceID
        browser.addSpace(named: style == .zen ? "Explore" : "Space 3", icon: "sparkles")
        if let url = URL(string: "https://en.wikipedia.org/wiki/Space_exploration") { _ = browser.open(url, foreground: true) }
        browser.switchSpace(to: comparisonSpace)
        Store.settings.set(true, forKey: "spaces.comparison.seeded")
    }

    @MainActor static func arrange() {
        guard let style else { return }
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.contentView != nil && !($0 is NSPanel) }),
                  let screen = window.screen ?? NSScreen.main else { return }
            let available = screen.visibleFrame
            let width = max(640, (available.width - 28) / 2)
            let height = min(800, available.height - 20)
            let left = available.minX + (style == .minimal ? 8 : available.width - width - 8)
            window.setFrame(NSRect(x: left, y: available.maxY - height - 8, width: width, height: height), display: true)
        }
    }

}

/// Listen only over a space control in this window, without taking page shortcuts.
struct SpaceDeleteKeyReader: NSViewRepresentable {
    var browser: Browser
    var hovered: UUID?
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.start()
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.browser = browser
        context.coordinator.hovered = hovered
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.stop() }

    @MainActor final class Coordinator {
        weak var view: NSView?
        weak var browser: Browser?
        var hovered: UUID?
        private var monitor: Any?
        func start() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, let browser = self.browser, let id = self.hovered,
                          let window = browser.window, (event.window ?? NSApp.keyWindow) === window,
                          event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function]) == [.command, .option],
                          [51, 117].contains(Int(event.keyCode)), browser.canDeleteSpace(id) else { return event }
                    if !event.isARepeat { browser.deleteSpace(id) }
                    return nil
                }
            }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

struct SpaceContextActions: View {
    @ObservedObject var browser: Browser
    let space: Space
    var body: some View {
        Button("Rename Space…") {
            Ask.name("Rename Space", placeholder: browser.spaceLabel(space), initial: browser.spaceLabel(space), confirm: "Rename") {
                browser.renameSpace(space.id, to: $0)
            }
        }
        if browser.canDeleteSpace(space.id) {
            Divider()
            Button("Delete Space", role: .destructive) { browser.deleteSpace(space.id) }
        }
    }
}
