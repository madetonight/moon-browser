import SwiftUI
import Translation

extension Tab {
    /// Internal pages and extension pages never enter the website translator.
    var canTranslate: Bool {
        guard PageTranslator.available, built != nil, let url = pageAddress, page == nil else { return false }
        return ["http", "https", "file"].contains(url.scheme?.lowercased() ?? "")
    }
}

extension Browser {
    func openTranslation() {
        guard active?.canTranslate == true else { return }
        translationOpen = true
    }
}

/// A permanent, quiet entry point; its state follows the active page only.
struct TranslationDoor: View {
    @ObservedObject var browser: Browser

    var body: some View {
        if let tab = browser.active {
            Active(browser: browser, tab: tab)
        } else {
            Door(icon: "translate", help: "Translate Website") {}.disabled(true).opacity(0.3)
        }
    }

    private struct Active: View {
        @ObservedObject var browser: Browser
        @ObservedObject var tab: Tab

        var body: some View {
            Door(icon: "translate", on: browser.translationOpen || tab.translator != nil,
                 help: "Translate Website") {
                if browser.translationOpen { browser.translationOpen = false }
                else { browser.openTranslation() }
            }
            .disabled(!tab.canTranslate)
            .opacity(tab.canTranslate ? 1 : 0.3)
            .accessibilityLabel("Translate Website")
        }
    }
}

/// A window-local panel, also reachable when the sidebar is folded away.
struct WebsiteTranslationPanel: View {
    @ObservedObject var tab: Tab
    let close: () -> Void
    @State private var languages: [String] = []
    @State private var target = PageTranslator.code(PageTranslator.reader)

    private var working: Bool { tab.translation?.phase == .working }
    private var hasTranslation: Bool { tab.translator != nil }
    private var targetName: String { PageTranslator.name(target) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "translate").font(.system(size: 18, weight: .regular))
                Text("Translate Website").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.muted)
                    .frame(width: 24, height: 24)
                    .help("Close")
                    .accessibilityLabel("Close translator")
            }
            if let mark = tab.translation {
                HStack(alignment: .top, spacing: 8) {
                    if working { ProgressView().controlSize(.small) }
                    Text(TranslateMenu.heading(mark))
                        .font(.system(size: 12))
                        .foregroundStyle(mark.failed ? Palette.unsafe : Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("Translate this page into your preferred language.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            Picker("Translate to", selection: $target) {
                // Keep the current choice present while the system loads its list.
                ForEach(languages.isEmpty ? [target] : languages, id: \.self) { code in
                    Text(PageTranslator.name(code)).tag(code)
                }
            }
            .disabled(working || languages.isEmpty)
            .accessibilityLabel("Translation language")

            if let mark = tab.translation, !mark.failed, let source = mark.from,
               target == PageTranslator.code(PageTranslator.reader), source != target {
                Toggle(isOn: Binding(get: { tab.alwaysTranslates(source) },
                                     set: { tab.setAlwaysTranslates(source, $0) })) {
                    Text(tab.shy ? "Always translate \(PageTranslator.name(source)) in this private tab"
                         : "Always translate \(PageTranslator.name(source)) to \(targetName)")
                        .font(.system(size: 11.5))
                }
                .toggleStyle(.checkbox)
            }
            HStack {
                if hasTranslation {
                    Button(working ? "Cancel" : "Show Original") { tab.translator?.end(restore: true) }
                        .controlSize(.regular)
                }
                Spacer(minLength: 4)
                Button(tab.translation?.failed == true ? "Try Again" : "Translate") {
                    guard tab.canTranslate else { return }
                    PageTranslator.start(tab, to: Locale.Language(identifier: target))
                }
                .buttonStyle(.borderedProminent)
                .disabled(working || languages.isEmpty || !tab.canTranslate)
                .keyboardShortcut(.defaultAction)
            }
            Text("Translated on this Mac. Page text stays on your device. macOS may ask to download a language first.")
                .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Palette.ink)
        .padding(18)
        .frame(width: 340)
        .popoverGround(card: true)
        .shadow(color: .black.opacity(0.16), radius: 18, y: 6)
        .task {
            target = tab.translation?.to ?? PageTranslator.code(PageTranslator.reader)
            let supported = await LanguageAvailability().supportedLanguages
            guard !Task.isCancelled else { return }
            languages = Array(Set(supported.map(PageTranslator.code) + [target]))
                .sorted { PageTranslator.name($0).localizedCaseInsensitiveCompare(PageTranslator.name($1)) == .orderedAscending }
        }
    }
}
