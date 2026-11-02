import AppKit
import SwiftUI

/// Moon keeps Search's geometry and motion; glass is an explicit local option.
struct MoonWindowGround: View {
    let glass: Bool
    let fullscreen: Bool
    let cards: Bool
    let sidebar: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        if fullscreen { Color.black }
        else if glass && !reduceTransparency {
            // The sidebar owns its material and rounded contour. A full-window
            // material here would fill its corners with a second, square frame.
            if sidebar { Color.clear }
            else { MoonVibrancy() }
        }
        else { cards ? Palette.frame : Palette.ground }
    }
}

private struct MoonVibrancy: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = MoonGlassView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// One continuous glass surface, flush with the window's bounds. Both the
/// backdrop and native glass share the same clip; no rectangular backing,
/// inset outline or second shadow sits outside its rounded corners.
struct MoonSidebarGlass: View {
    let enabled: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if enabled && !reduceTransparency {
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            MoonVibrancy()
                .clipShape(shape)
                .glassEffect(.regular.tint(Palette.frame.opacity(0.12)), in: shape)
                .clipShape(shape)
                .allowsHitTesting(false)
        }
    }
}

struct MoonWelcomeHeading: View {
    let privateMode: Bool
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: privateMode ? "hand.raised" : "moon.fill")
                .font(.system(size: 20, weight: .light))
            Text(privateMode ? "Private Browsing" : "Moon")
                .font(.system(size: 26, weight: .regular)).tracking(-0.7)
        }.foregroundStyle(Palette.ink)
    }
}

struct MoonWelcomeBookmarks: View {
    @ObservedObject var browser: Browser
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if browser.active?.shy == true {
                Text("This tab won’t appear in your history or saved session.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            } else {
                ForEach(Array(browser.bookmarks.roots.filter { !$0.isFolder }.prefix(4))) { bookmark in
                    if let url = bookmark.address {
                        Button { browser.visit(url) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "bookmark").font(.system(size: 12)).foregroundStyle(Palette.muted)
                                Text(bookmark.label).font(.system(size: 13)).lineLimit(1)
                                Spacer()
                                Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(Palette.muted)
                            }.frame(height: 24).contentShape(Rectangle())
                        }.buttonStyle(.plain).foregroundStyle(Palette.ink)
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MoonWelcomeShortcuts: View {
    var body: some View {
        HStack(spacing: 22) {
            Text("New tab  ⌘T")
            Text("Switch tabs  ⌃Tab")
            Text("Address  ⌘L")
        }.font(.system(size: 11)).foregroundStyle(Palette.muted).allowsHitTesting(false)
    }
}

private final class MoonGlassView: NSVisualEffectView {}

struct MoonFieldGlass: ViewModifier {
    let enabled: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if enabled && !reduceTransparency { content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous)) }
        else { content }
    }
}
