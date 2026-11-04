import AppKit
import SwiftUI

/// Shared contour for the sidebar, its content inset and its shadow.
enum SidebarSurface {
    static let radius: CGFloat = 18
    static func insets(onRight: Bool) -> EdgeInsets {
        EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
    }
}

/// Glass is an explicit local option.
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

/// One native, adaptive glass surface. An opaque vibrancy view underneath
/// would conceal the content being sampled and flatten its depth.
struct MoonSidebarGlass: ViewModifier {
    let enabled: Bool
    let insets: EdgeInsets
    let look: Look
    @Environment(\.colorScheme) private var inheritedScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if enabled && !reduceTransparency {
            // Keep labels and controls above the material. Applying glass to
            // the entire subtree also adapts their tint against page content,
            // making resting footer icons almost disappear over bright pages.
            content.background {
                Color.clear
                    .glassEffect(.regular.tint(Palette.frame.opacity(0.8)), in: SidebarContour(insets: insets))
                    .allowsHitTesting(false)
            }
                .environment(\.colorScheme, look == .dark ? .dark : look == .light ? .light : inheritedScheme)
        } else {
            content
        }
    }
}

private struct SidebarContour: Shape {
    let insets: EdgeInsets
    func path(in rect: CGRect) -> Path {
        let surface = CGRect(x: rect.minX + insets.leading, y: rect.minY + insets.top,
                             width: max(0, rect.width - insets.leading - insets.trailing),
                             height: max(0, rect.height - insets.top - insets.bottom))
        return RoundedRectangle(cornerRadius: SidebarSurface.radius, style: .continuous).path(in: surface)
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
