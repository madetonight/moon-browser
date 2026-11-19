import AppKit
import SwiftUI

/// Shared contour for the sidebar, its content inset and its shadow.
enum SidebarSurface {
    static let radius: CGFloat = 18
    static func insets(onRight: Bool) -> EdgeInsets {
        EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
    }
}

extension EnvironmentValues {
    @Entry var moonWindowGlass = false
}

/// Glass is an explicit local option.
struct MoonWindowGround: View {
    let glass: Bool
    let fullscreen: Bool
    let cards: Bool
    var body: some View {
        if fullscreen { Color.black }
        else if glass { MoonGlassSurface() }
        else { cards ? Palette.frame : Palette.ground }
    }
}

/// A single glass plane over the desktop's blurred colors, with an
/// appearance-aware tint to keep browser controls readable.
private struct MoonGlassSurface: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let reflectedLight = Color(red: 0.53, green: 0.64, blue: 0.81)

        Color.clear
            .glassEffect(.clear, in: Rectangle())
            .background {
                ZStack {
                    MoonDesktopBackdrop()
                    Palette.frame.opacity(dark ? 0.51 : 0.47)
                    RadialGradient(colors: [reflectedLight.opacity(dark ? 0.17 : 0.15), .clear],
                                   center: .topLeading, startRadius: 16, endRadius: 610)
                }
            }
            .overlay(dark ? Color.black.opacity(0.33) : Color.white.opacity(0.14))
            // Overscan the material so its refracting edge is outside the
            // window. The window's own contour is the only perimeter.
            .padding(-32)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct MoonDesktopBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
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

