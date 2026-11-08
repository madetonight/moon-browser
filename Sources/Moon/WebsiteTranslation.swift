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
        Nebula.shared.suspend(in: self)
        guard active?.canTranslate == true else { return }
        // The View command uses the same icon anchor, even with tabs folded.
        // Reveal it without changing the user's sidebar/folding preference.
        if folded { peeking = true }
        translationOpen = true
    }
}

/// A permanent, quiet entry point; its state follows the active page only.
struct TranslationDoor: View {
    @ObservedObject var browser: Browser
    var arrowEdge: Edge = .trailing

    var body: some View {
        if let tab = browser.active {
            Active(browser: browser, tab: tab, arrowEdge: arrowEdge)
        } else {
            Door(icon: "translate", help: "Translate Website") {}.disabled(true).opacity(0.3)
        }
    }

    private struct Active: View {
        @ObservedObject var browser: Browser
        @ObservedObject var tab: Tab
        let arrowEdge: Edge

        var body: some View {
            Door(icon: "translate", on: browser.translationOpen || tab.translator != nil,
                 help: "Translate Website") {
                if browser.translationOpen { browser.translationOpen = false }
                else { browser.openTranslation() }
            }
            .disabled(!tab.canTranslate)
            .opacity(tab.canTranslate ? 1 : 0.3)
            .accessibilityLabel("Translate Website")
            .popover(isPresented: $browser.translationOpen, attachmentAnchor: .rect(.bounds), arrowEdge: arrowEdge) {
                WebsiteTranslationPanel(tab: tab) { browser.translationOpen = false }
                    .id(tab.id)
                    .onExitCommand { browser.translationOpen = false }
            }
        }
    }
}

/// A compact language menu attached to the translate button, never the page's
/// far corner. Choosing a language starts translation in a single action.
struct WebsiteTranslationPanel: View {
    @ObservedObject var tab: Tab
    @ObservedObject private var prefs = Shared.prefs
    let close: () -> Void
    @State private var languages: [String] = []

    private static let defaults: [(code: String, name: String)] = [
        ("en", "English"), ("fr", "French"), ("it", "Italian"),
        ("de", "German"), ("es", "Spanish"), ("zh-Hans", "Chinese"),
        ("ja", "Japanese"), ("ko", "Korean"), ("pt", "Portuguese")
    ]

    private var working: Bool { tab.translation?.phase == .working }
    private var hasTranslation: Bool { tab.translator != nil }
    private var additional: [String] {
        languages.filter { code in !Self.defaults.contains { $0.code == code } }
    }

    private func translate(to code: String) {
        guard tab.canTranslate, !working else { return }
        PageTranslator.start(tab, to: Locale.Language(identifier: code))
        close()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Translate to")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 5)
            if let mark = tab.translation {
                HStack(alignment: .top, spacing: 8) {
                    if working { ProgressView().controlSize(.small) }
                    Text(TranslateMenu.heading(mark))
                        .font(.system(size: 12))
                        .foregroundStyle(mark.failed ? Palette.unsafe : Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
            }
            VStack(spacing: 1) {
                ForEach(Self.defaults, id: \.code) { language in
                    LanguageRow(title: language.name,
                                selected: tab.translation?.to == language.code && tab.translation?.failed == false) {
                        translate(to: language.code)
                    }
                    .disabled(working || !tab.canTranslate)
                }
                if !additional.isEmpty {
                    Menu("More Languages…") {
                        ForEach(additional, id: \.self) { code in
                            Button(PageTranslator.name(code)) { translate(to: code) }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 9)
                    .frame(height: 27)
                    .disabled(working || !tab.canTranslate)
                }
            }
            .padding(5)
            if hasTranslation {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    LanguageRow(title: working ? "Cancel Translation" : "Show Original", symbol: "arrow.uturn.backward") {
                        tab.translator?.end(restore: true)
                        close()
                    }
                    if let mark = tab.translation, !mark.failed, let source = mark.from,
                       mark.to == PageTranslator.code(PageTranslator.reader), source != mark.to {
                        Toggle(isOn: Binding(get: { tab.alwaysTranslates(source) },
                                             set: { tab.setAlwaysTranslates(source, $0) })) {
                            Text(tab.shy ? "Always translate \(PageTranslator.name(source)) in this private tab"
                                 : "Always translate \(PageTranslator.name(source))")
                                .font(.system(size: 11.5))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .toggleStyle(.checkbox)
                        .padding(.horizontal, 9)
                        .padding(.bottom, 5)
                    }
                }
                .padding(5)
            }
            Divider()
            Text("On-device translation. macOS may download a language first.")
                .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
        }
        .foregroundStyle(Palette.ink)
        .frame(width: 240)
        .popoverGround()
        .task {
            let supported = await LanguageAvailability().supportedLanguages
            guard !Task.isCancelled else { return }
            languages = Array(Set(supported.map(PageTranslator.code)))
                .sorted { PageTranslator.name($0).localizedCaseInsensitiveCompare(PageTranslator.name($1)) == .orderedAscending }
        }
    }

    private struct LanguageRow: View {
        @Environment(\.greys) private var greys
        let title: String
        var selected = false
        var symbol: String? = nil
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 7) {
                    Text(title).font(.system(size: 12.5))
                    Spacer(minLength: 4)
                    Image(systemName: symbol ?? "checkmark")
                        .font(.system(size: 10, weight: .medium))
                        .opacity(selected || symbol != nil ? 1 : 0)
                }
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 9)
                .frame(height: 27)
                .background(hovering ? greys.hover : .clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityLabel(title)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}
