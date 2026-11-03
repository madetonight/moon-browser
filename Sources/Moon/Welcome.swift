import SwiftUI

/// A short, optional introduction. Browser discovery and protected imports
/// only happen after the person chooses them; browsing needs no setup grant.
struct WelcomePanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences

    @State private var page = 0
    @State private var forward = true
    @FocusState private var continuesFocused: Bool

    // Bringing things over. Nil until one is picked, which means the first:
    // finding them looks through each browser's folders, and as an initial
    // value that ran every time the panel was made, the first window's
    // included, for a page that isn't showing yet.
    @State private var source: ImportSource?
    @State private var wantsPasswords = false
    @State private var sources: [ImportSource] = []
    @State private var unreadable: [Chromium.Unavailable] = []
    @State private var discovered = false
    @State private var wantsHistory = true
    @State private var wantsBookmarks = true
    @State private var bringing = false
    @State private var brought: String?

    // The default browser.
    @State private var isDefault = Links.isDefault
    @State private var asked = false

    private var importsPasswords: Bool { (source ?? sources.first)?.importsPasswords ?? false }

    private let pages = 3

    var body: some View {
        ZStack {
            Palette.ground.ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Text("MOON")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(2)
                    Spacer()
                    Text("Step \(page + 1) of \(pages)")
                        .font(.system(size: 12))
                }
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: 520)

                ScrollView {
                    VStack(spacing: 28) {
                        switch page {
                        case 0: welcome; hold
                        case 1: bring
                        default: links
                        }
                    }
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .id(page)
                    .transition(.asymmetric(
                        insertion: .offset(x: forward ? 16 : -16).combined(with: .opacity),
                        removal: .offset(x: forward ? -16 : 16).combined(with: .opacity)
                    ))
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: 560)
                foot
            }
            .padding(32)
        }
        .animation(Motion.glide, value: page)
        .onAppear { continuesFocused = true }
        .onChange(of: page) { continuesFocused = true }
        .transition(.opacity)
    }

    // MARK: - the pages

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Plate(size: 76)
            Text("A little space.\nA wider web.")
                .font(.system(size: 36, weight: .medium, design: .rounded))
                .tracking(-1)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Welcome to Moon. Native to your Mac, with room for whatever comes next.")
                .font(.system(size: 14))
                .foregroundStyle(Palette.muted)
                .lineSpacing(3)
            VStack(alignment: .leading, spacing: 3) {
                Text("Built by heyjoseluna")
                Text("Inspired by Office Commun")
            }
            .font(.system(size: 11))
            .foregroundStyle(Palette.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bring: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("Make yourself at home.", "Bring your bookmarks and history along, or start fresh. You can import later in Settings.")

            if !discovered {
                Big("Choose a browser", filled: false) {
                    sources = ImportSource.installed()
                    unreadable = Chromium.unreadable()
                    discovered = true
                }
                Text("Moon only looks for other browser data when you ask. Passwords are optional and may require your approval in macOS.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else if sources.isEmpty {
                if unreadable.isEmpty {
                    Text("No other browser found on this Mac — nothing to bring.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    if sources.count > 1 {
                        Segmented(
                            options: sources.map { ($0, $0.name) },
                            selection: Binding(get: { source ?? sources[0] }, set: { source = $0 })
                        )
                    } else {
                        Text("From \(sources[0].name)")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.muted)
                    }
                    if importsPasswords {
                        Choice("Passwords", "macOS will ask once for that browser's keychain key", on: $wantsPasswords)
                    } else {
                        Text("Passwords from \((source ?? sources[0]).name) aren't supported yet.")
                            .font(.system(size: 13)).foregroundStyle(Palette.muted)
                    }
                    Choice("Bookmarks", "Folders and all, behind the bookmark button", on: $wantsBookmarks)
                    Choice("History", "The last few thousand places, for finishing addresses", on: $wantsHistory)
                }

                HStack(spacing: 12) {
                    Big(bringing ? "Bringing…" : "Bring them in", filled: true) { bringAll() }
                        .disabled(bringing || brought != nil || !((importsPasswords && wantsPasswords) || wantsHistory || wantsBookmarks))
                    if bringing { Ring(size: 10) }
                    if let brought {
                        Text(brought)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.muted)
                            .transition(.opacity)
                    }
                }
                .animation(Motion.settle, value: brought)
            }

            if !unreadable.isEmpty {
                Text(unreadable.map(\.message).joined(separator: "\n"))
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Safari, a browser on another Mac, one Moon can't read: what
            // it exported, bookmarks, passwords or Safari's own ZIP.
            Pill("From a file another browser exported…") { browser.importFile() }
        }
    }

    private var hold: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("Your view of the web.", "Keep tabs beside the page or across the top. Change it anytime in Settings.")
            HStack(spacing: 12) {
                Way(title: "Tab strip", sidebar: false, chosen: !prefs.sidebar) {
                    withAnimation(Motion.glide) { prefs.sidebar = false }
                }
                Way(title: "Sidebar", sidebar: true, chosen: prefs.sidebar) {
                    withAnimation(Motion.glide) { prefs.sidebar = true }
                }
            }
            HStack(spacing: 12) {
                Text("Tabs wear")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                Segmented(options: Glyph.allCases.map { ($0, $0.title) }, selection: $prefs.glyph)
            }
        }
    }

    private var links: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("Ready when you are.", "Browse right away. If you want links from Mail and other apps to open here, make Moon your default.")
            HStack(spacing: 12) {
                if isDefault {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .medium))
                        Text("Moon is the default browser")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink)
                } else {
                    Big("Make Moon the default", filled: true) {
                        asked = true
                        Links.becomeDefault { _ in isDefault = Links.isDefault }
                    }
                    if asked, !isDefault {
                        Text("macOS asks in its own dialog")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.faint)
                    }
                }
            }
            .animation(Motion.settle, value: isDefault)

            Divider().padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 14) {
                Key("⌘T", "Start a new tab.")
                Key("⌘L", "Go somewhere new.")
                Key("⌘,", "Make Moon yours in Settings.")
            }
            Text("Camera, microphone, location and notifications stay under your control. Moon asks when a website needs them, rather than during setup.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - the bottom edge

    private var foot: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(0..<pages, id: \.self) { i in
                    Circle()
                        .fill(i == page ? Palette.ink : Palette.faint.opacity(0.6))
                        .frame(width: 6, height: 6)
                }
            }
            Spacer()
            if page > 0 {
                Button("Back") { forward = false; page -= 1 }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
            }
            if page < pages - 1 {
                Button("Browse now") { finish() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
            }
            Big(page < pages - 1 ? "Continue" : "Start browsing", filled: true) {
                if page < pages - 1 { forward = true; page += 1 } else { finish() }
            }
            .keyboardShortcut(.defaultAction)
            .focused($continuesFocused)
        }
        .frame(maxWidth: 520)
        .disabled(bringing)
    }

    // MARK: - doing

    private func bringAll() {
        guard let source = source ?? sources.first else { return }
        // The profile used most recently, without asking: the sheet in
        // Settings › Passwords is where another is chosen.
        let profile = source.usual
        bringing = true
        var lines: [String] = []
        let group = DispatchGroup()
        if wantsPasswords && source.importsPasswords {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let outcome = Result { try source.read(profile: profile) }
                DispatchQueue.main.async {
                    switch outcome {
                    case .success(let found):
                        let kept = browser.keep(found)
                        ImportRecords.note(source.name, passwords: kept)
                        lines.append("\(kept) passwords" + (found.undecrypted > 0 ? " (\(found.undecrypted) couldn't be decrypted)" : ""))
                    case .failure(Chromium.Trouble.noPassphrase):
                        lines.append("passwords: macOS didn't hand over the key — allow it and try again")
                    case .failure(Mozilla.Trouble.primaryPassword):
                        lines.append("passwords: \(source.name) has a primary password — export them from it and bring in the CSV")
                    case .failure:
                        lines.append("passwords: nothing readable")
                    }
                    group.leave()
                }
            }
        }
        if wantsBookmarks {
            lines.append("\(browser.takeBookmarks(from: source, profile: profile).added) bookmarks")
        }
        if wantsHistory {
            group.enter()
            browser.takePlaces(from: source, profile: profile) { count in
                lines.append("\(count) places")
                group.leave()
            }
        }
        group.notify(queue: .main) {
            bringing = false
            brought = lines.joined(separator: " · ")
            browser.relist()
        }
    }

    private func finish() {
        guard !bringing else { return }
        prefs.welcomed = true
        withAnimation(Motion.settle) { browser.welcoming = false }
    }

    private func heading(_ title: String, _ line: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Palette.ink)
            Text(line)
                .font(.system(size: 14))
                .foregroundStyle(Palette.muted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - pieces

    /// Moon's installed app icon, matching the About page and the Dock.
    private struct Plate: View {
        let size: CGFloat
        var body: some View {
            MoonBrandIcon()
                .frame(width: size, height: size)
        }
    }

    private struct Big: View {
        let title: String
        var filled = false
        let act: () -> Void
        @State private var hovering = false

        init(_ title: String, filled: Bool = false, act: @escaping () -> Void) {
            self.title = title
            self.filled = filled
            self.act = act
        }

        var body: some View {
            Button(action: act) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(filled ? Palette.ground : Palette.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(filled ? Palette.ink : (hovering ? Palette.hover : Palette.wash), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
    }

    private struct Choice: View {
        let title: String
        let detail: String
        @Binding var on: Bool

        init(_ title: String, _ detail: String, on: Binding<Bool>) {
            self.title = title
            self.detail = detail
            _on = on
        }

        var body: some View {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13.5)).foregroundStyle(Palette.ink)
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(Palette.faint)
                }
                Spacer()
                Switch(on: $on)
            }
        }
    }

    /// One of the two ways, as a small drawing of the window.
    private struct Way: View {
        let title: String
        let sidebar: Bool
        let chosen: Bool
        let pick: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: pick) {
                VStack(alignment: .leading, spacing: 10) {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.ground)
                        if sidebar {
                            HStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in Circle().fill(Palette.faint).frame(width: 5, height: 5) } }
                                        .padding(.bottom, 4)
                                    ForEach(0..<4, id: \.self) { i in
                                        RoundedRectangle(cornerRadius: 3).fill(i == 0 ? Palette.wash : Palette.hover).frame(height: 8)
                                    }
                                }
                                .padding(8)
                                .frame(width: 62)
                                Rectangle().fill(Palette.hairline).frame(width: 1)
                                Spacer()
                            }
                        } else {
                            HStack(spacing: 3) {
                                HStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in Circle().fill(Palette.faint).frame(width: 5, height: 5) } }
                                    .padding(.trailing, 6)
                                ForEach(0..<4, id: \.self) { i in
                                    RoundedRectangle(cornerRadius: 3).fill(i == 0 ? Palette.wash : Palette.hover).frame(width: 30, height: 8)
                                }
                            }
                            .padding(8)
                        }
                    }
                    .frame(height: 110)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
                    Text(title)
                        .font(.system(size: 13, weight: chosen ? .medium : .regular))
                        .foregroundStyle(chosen ? Palette.ink : Palette.muted)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(chosen ? Palette.wash : (hovering ? Palette.hover : .clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(chosen ? Palette.ink.opacity(0.35) : Palette.hairline, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
            .animation(Motion.settle, value: chosen)
        }
    }

    private struct Key: View {
        let keys: String
        let what: String
        init(_ keys: String, _ what: String) { self.keys = keys; self.what = what }
        var body: some View {
            HStack(spacing: 10) {
                Text(keys)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Palette.wash, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .frame(minWidth: 44)
                Text(what).font(.system(size: 13)).foregroundStyle(Palette.muted)
            }
        }
    }
}
