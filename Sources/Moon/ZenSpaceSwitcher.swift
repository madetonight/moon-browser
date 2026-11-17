/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * Native adaptation of Zen Browser's workspace strip metrics and cyclic
 * navigation, from zen-browser/desktop, src/zen/spaces/ZenSpaceManager.mjs
 * and zen-workspaces.css, revision 37513f03c5dcb0eb2520c839e3870b59cdc8aefe. The Firefox/XUL runtime is not embedded in Moon.
 */
import SwiftUI

/// Adapted from ZenSpaceManager.changeWorkspaceShortcut's wrap-around branch.
enum ZenSpaceNavigation {
    static func destination(from index: Int, offset: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((index + offset) % count + count) % count
    }
}

struct ZenSpaceHeader: View {
    @ObservedObject var browser: Browser
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: browser.space.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            Text(browser.space.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 0)
            Menu {
                ForEach(browser.spaces) { space in
                    Button { browser.switchSpace(to: space.id) } label: {
                        Label(space.name + (space.id == browser.spaceID ? " ✓" : ""), systemImage: space.symbol)
                    }
                }
                Divider()
                SpaceContextActions(browser: browser, space: browser.space)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium)).frame(width: 24, height: 26)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .opacity(hovering ? 1 : 0.35)
            .help("Manage workspace")
            .accessibilityLabel("Manage workspace")
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 9).fill(hovering ? Palette.hover : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.1), value: hovering)
        .contextMenu { SpaceContextActions(browser: browser, space: browser.space) }
        .background(SpaceDeleteKeyReader(browser: browser, hovered: hovering ? browser.spaceID : nil).frame(width: 1, height: 1).allowsHitTesting(false))
    }
}

struct ZenSpaceStrip: View {
    @ObservedObject var browser: Browser
    @State private var hovered: UUID?
    @State private var creating = false
    @State private var name = ""
    @State private var icon = "briefcase"
    @FocusState private var naming: Bool
    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(browser.spaces) { space in
                        Button { browser.switchSpace(to: space.id) } label: {
                            Image(systemName: space.symbol)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(space.id == browser.spaceID ? Color.accentColor : Palette.muted)
                                .frame(width: 30, height: 30)
                                .background(RoundedRectangle(cornerRadius: 8).fill(space.id == browser.spaceID ? Color.accentColor.opacity(0.15) : (hovered == space.id ? Palette.hover : .clear)))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(space.id)
                        .accessibilityLabel(space.name)
                        .accessibilityAddTraits(space.id == browser.spaceID ? .isSelected : [])
                        .onHover { inside in
                            if inside { hovered = space.id } else if hovered == space.id { hovered = nil }
                        }
                        .contextMenu { SpaceContextActions(browser: browser, space: space) }
                        .help(space.name)
                    }
                    Button { name = ""; creating = true } label: {
                        Image(systemName: "plus").font(.system(size: 12)).frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain).foregroundStyle(Palette.muted)
                    .help("New workspace").accessibilityLabel("New workspace")
                    .popover(isPresented: $creating, arrowEdge: .bottom) { creation }
                }
                .padding(.horizontal, 4)
            }
            .frame(width: min(CGFloat(browser.spaces.count + 1) * 34 + 4, max(40, browser.prefs.columnWidth - 40)), height: 38)
            .onChange(of: browser.spaceID) { _, id in reader.scrollTo(id, anchor: .center) }
        }
        .frame(maxWidth: .infinity)
        .background(SpaceDeleteKeyReader(browser: browser, hovered: hovered).frame(width: 1, height: 1).allowsHitTesting(false))
    }

    private var creation: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New workspace").font(.system(size: 15, weight: .semibold))
            TextField("Workspace name", text: $name)
                .textFieldStyle(.roundedBorder).focused($naming).onSubmit(create)
            HStack(spacing: 6) {
                ForEach(["house", "briefcase", "sparkles", "book", "leaf"], id: \.self) { symbol in
                    Button { icon = symbol } label: {
                        Image(systemName: symbol).frame(width: 30, height: 28)
                            .background(RoundedRectangle(cornerRadius: 7).fill(icon == symbol ? Color.accentColor.opacity(0.17) : .clear))
                    }.buttonStyle(.plain).accessibilityLabel(symbol)
                }
            }
            HStack {
                Button("Cancel") { creating = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create", action: create).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(18).frame(width: 250)
        .onAppear { naming = true }
    }

    private func create() {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        browser.addSpace(named: value.isEmpty ? "Space \(browser.spaces.count + 1)" : value, icon: icon)
        creating = false
    }
}
