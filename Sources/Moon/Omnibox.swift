import SwiftUI
import AppKit

/// One field, in the middle, and the few places it thinks you mean. It takes
/// addresses and only addresses: type something that isn't a place and it
/// shivers and says so, rather than quietly handing your keystrokes to a
/// search engine.
struct Omnibox: View {
    @ObservedObject var browser: Browser
    /// Raised over a page by ⌘L, rather than standing on an empty tab.
    let over: Bool

    /// The field's own height — the 22 of text and 14 of air above and below it
    /// that `field` lays out — so the list can sit below it without being
    /// stacked with it.
    private static let fieldHeight: CGFloat = 22 + 14 * 2

    @State private var shake: CGFloat = 0
    @State private var refused = false
    @Environment(\.moonWindowGlass) private var windowGlass

    /// Sized to a pane of a split rather than to the window.
    var fitted = false
    var paired = false

    var body: some View {
        GeometryReader { geometry in
            content(width: min(Metrics.fieldWidth, max(0, geometry.size.width - 28)), height: geometry.size.height)
        }
        .animation(Motion.quick, value: browser.assisting?.id)
        .allowsHitTesting(browser.fieldShowing)
    }

    private var homeAssistant: Assistant? {
        guard !over, let assistant = browser.assisting, assistant.general, assistant.tab == browser.activeID else { return nil }
        return assistant
    }

    private var offersHomeAI: Bool {
        AI.shipped && browser.active?.shy == false && !browser.ghostWindow
    }

    private var showHomeLinks: Bool {
        !browser.summoning && browser.typed.isEmpty && browser.offers.isEmpty && browser.siteOffer == nil
    }

    private func content(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // Search #718: keep the stage mounted. The full-page cover fades;
            // only the field and its attached content take the small zoom.
            if browser.fieldShowing {
                if !over, homeAssistant == nil {
                    MoonWelcomeShortcuts()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 24)
                        .transition(.opacity)
                }
                if over {
                    Rectangle()
                        .fill(Palette.ground.opacity(0.74))
                        .ignoresSafeArea(.all, edges: fitted ? [] : .all)
                        .onTapGesture { browser.dismiss() }
                        .transition(.opacity)
                }
                VStack(alignment: .leading, spacing: 14) {
                    field
                        .frame(width: width)
                        .overlay(alignment: .top) {
                            if !browser.offers.isEmpty || browser.siteOffer != nil {
                                list.frame(width: width).offset(y: Self.fieldHeight + 8)
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            if !over {
                                MoonWelcomeHeading(privateMode: browser.active?.shy == true)
                                    .offset(y: -52)
                            }
                        }
                        .zIndex(1)

                    if let assistant = homeAssistant {
                        AssistantPanel(browser: browser, assistant: assistant, width: width,
                                       responseHeight: min(260, max(44, height - 245)))
                            .transition(.opacity)
                            .onDisappear {
                                if browser.assisting?.id == assistant.id { browser.closeAssistant() }
                            }
                    } else if !over, offersHomeAI || !paired {
                        homeLinks
                            .frame(width: width, alignment: .leading)
                            .opacity(showHomeLinks ? 1 : 0)
                            .allowsHitTesting(showHomeLinks)
                            .accessibilityHidden(!showHomeLinks)
                    }
                }
                    .padding(.top, over ? 0 : 54)
                    .padding(.bottom, homeAssistant == nil ? (over ? 60 : 42) : 18)
                    .transition(.scale(scale: 0.97).combined(with: .opacity))
                    .animation(Motion.quick, value: browser.offers.isEmpty && browser.siteOffer == nil)
                    .animation(Motion.settle, value: refused)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var homeLinks: some View {
        VStack(alignment: .leading, spacing: 16) {
            if offersHomeAI {
                Button { browser.askAnything() } label: {
                    Label("Ask anything…", systemImage: "sparkles")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 13)
                        .frame(height: 32)
                        .background(Palette.wash, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            if !paired { MoonWelcomeBookmarks(browser: browser) }
        }
    }

    private var field: some View {
        HStack(spacing: 8) {
            if let site = browser.siteChip {
                SiteChip(site: site)
                    .transition(.scale(scale: 0.9, anchor: .leading).combined(with: .opacity))
            }
            AddressField(browser: browser)
        }
            .animation(Motion.quick, value: browser.siteChip)
            .frame(height: 22)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background {
                if windowGlass {
                    if over {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Palette.ground.opacity(0.96))
                    }
                } else {
                    ZStack {
                        // A quiet glow beneath the solid address field.
                        Breath()

                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Palette.ground)
                    }
                }
            }
            .overlay {
                if refused || !windowGlass {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(refused ? Color.red.opacity(0.35) : Palette.hairline, lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .shadow(color: .black.opacity(0.06), radius: 24, y: 8)
            .modifier(Shake(travel: shake))
            .onAppear { shake = 0; refused = false }
            .onChange(of: browser.refusals) { _, _ in
                shake = 0
                refused = true
                withAnimation(.easeOut(duration: 0.5)) { shake = 1 }
            }
            .onChange(of: browser.typed) { _, _ in
                withAnimation(Motion.quick) { refused = false }
            }
    }

    /// What it thinks you mean. Places you have been come with their titles;
    /// the handful of well-known addresses it starts life knowing come without
    /// the weight of one.
    ///
    /// It lives below the field, in an overlay, so arriving or leaving never
    /// moves the field — and the transition that carried it in and out before
    /// is kept, only anchored to its own top edge.
    private var list: some View {
        VStack(spacing: 0) {
            if let site = browser.siteOffer {
                SiteOfferRow(site: site)
                    .contentShape(Rectangle())
                    .onTapGesture { _ = browser.lockSiteOffer() }
            }
            ForEach(Array(browser.offers.enumerated()), id: \.element.id) { index, offer in
                Row(offer: offer, picked: browser.picked == index)
                    .contentShape(Rectangle())
                    .onTapGesture { browser.take(offer) }
            }
        }
        .padding(6)
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.07), radius: 20, y: 6)
        .transition(.scale(scale: 0.98, anchor: .top).combined(with: .opacity))
    }

    /// One row of a list of places, here and under the field in the tab.
    struct Row: View {
        let offer: Suggestion
        /// Where the arrow keys have walked to. The pointer gets its own,
        /// quieter mark, and changes nothing but the look of the row.
        let picked: Bool

        @State private var hovering = false

        var body: some View {
            HStack(spacing: 10) {
                switch offer.kind {
                case .search:
                    // The engine's own icon when this Mac already has it: a
                    // search sent to a site you have been to says so with the
                    // site rather than a magnifying glass. Nothing is fetched
                    // for one that isn't known; the glass is what the row
                    // wears until then.
                    if let icon = Favicons.shared.cached(for: offer.url) {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 14, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    } else {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Palette.muted)
                    }
                case .suggested:
                    // The engine's own words: always the glass, so they read
                    // as searches rather than places.
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.muted)
                case .open:
                    // Already open: naming it takes you back to it rather than
                    // opening a second copy.
                    Circle()
                        .fill(Palette.ink.opacity(0.55))
                        .frame(width: 5, height: 5)
                        .padding(.horizontal, 2)
                case .command:
                    Image(systemName: "command")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.muted)
                default:
                    EmptyView()
                }
                // The row reads as 1.0.4's did, without the www; the key
                // itself keeps it, for completing and going there.
                Text(offer.kind == .suggested ? offer.key : Address.withoutWWW(offer.key))
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)

                if !offer.title.isEmpty {
                    Text(offer.title)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                if picked {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Palette.wash)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Palette.hover)
                }
            }
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
        }
    }
}

/// A site's icon when this Mac has it, or a glass.
private struct SiteIcon: View {
    let site: SearchSite
    var body: some View {
        let host = site.host.split(separator: "/").first.map(String.init) ?? site.host
        if let icon = Favicons.shared.cached(host) ?? Favicons.shared.cached("www." + host) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 14, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        } else {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.muted)
                .frame(width: 14, height: 14)
        }
    }
}

/// The site Tab put in the field: its icon and name, in the field's grey,
/// before what is typed.
private struct SiteChip: View {
    let site: SearchSite
    var body: some View {
        HStack(spacing: 6) {
            SiteIcon(site: site)
            Text(site.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Searching \(site.name)")
    }
}

/// "Search Reddit", first in the list, with the key that takes it.
private struct SiteOfferRow: View {
    let site: SearchSite
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 10) {
            SiteIcon(site: site)
            Text("Search \(site.name)")
                .font(.system(size: 13))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("Tab")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            if hovering { RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.hover) }
        }
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Search \(site.name), press Tab")
    }
}

/// The breath under the field: a soft shape of ink, blurred, moved by Core
/// Animation. Animated by SwiftUI, it was drawn again on the main thread
/// every frame for as long as an empty tab was showing — 18% of a core with
/// the window doing nothing (24 Sep 2026). As a layer's shadow, breathed by
/// Core Animation, it is played in the render server and costs the app
/// nothing; and it is a layer, not a second SwiftUI view to build before
/// the first frame.
private struct Breath: NSViewRepresentable {
    /// As dark as the shape it replaces, 5% ink blurred by 26: a shadow of
    /// the same radius comes out at 0.7 of the darkness at equal strength,
    /// measured on pictures of both (24 Sep 2026), so 7%.
    static let strength: Swift.Float = 0.07

    func makeNSView(context: Context) -> NSView { Lung() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Lung: NSView {
        private let glow = CALayer()
        private var breathed: CGSize = .zero

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            glow.shadowOpacity = Breath.strength
            glow.shadowOffset = .zero
            glow.shadowRadius = 26
            layer?.addSublayer(glow)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        /// The ink is the look's: light on a dark window, dark on a light one.
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            effectiveAppearance.performAsCurrentDrawingAppearance { glow.shadowColor = Palette.NS.ink.cgColor }
        }

        override func layout() {
            super.layout()
            guard bounds.size != breathed, bounds.width > 0 else { return }
            breathed = bounds.size
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            glow.bounds = bounds
            glow.position = CGPoint(x: bounds.midX, y: bounds.midY)
            glow.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 26, cornerHeight: 26, transform: nil)
            effectiveAppearance.performAsCurrentDrawingAppearance { glow.shadowColor = Palette.NS.ink.cgColor }
            CATransaction.commit()
            // From 0.97 to 1.03, from 0.65 to full, 2.6 s each way, for as
            // long as the field is there.
            let size = CABasicAnimation(keyPath: "transform.scale")
            size.fromValue = 0.97
            size.toValue = 1.03
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.65
            fade.toValue = 1.0
            let both = CAAnimationGroup()
            both.animations = [size, fade]
            both.duration = 2.6
            both.autoreverses = true
            both.repeatCount = .infinity
            both.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            glow.add(both, forKey: "breath")
        }
    }
}

/// The field itself, in AppKit.
///
/// SwiftUI's TextField can hold a string and nothing else, and the whole point
/// here is the part you didn't type: the rest of the address, already there and
/// selected, so carrying on typing replaces it and Return accepts it. That
/// needs a real text field and its delegate.
struct AddressField: NSViewRepresentable {
    @ObservedObject var browser: Browser

    func makeCoordinator() -> Coordinator { Coordinator(browser: browser) }

    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 15.5)
        field.textColor = Palette.NS.ink
        field.lineBreakMode = .byClipping
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        // Scrolls with the caret, so a long address can be read and edited
        // all the way along rather than cut off at the field's edge.
        field.cell?.isScrollable = true
        // SwiftUI picks its own colour for a placeholder, and on a pale ground
        // that colour was near-white.
        field.placeholderAttributedString = NSAttributedString(
            string: "Enter a web address",
            attributes: [
                .font: NSFont.systemFont(ofSize: 15.5),
                .foregroundColor: NSColor(Palette.ink.opacity(0.3)),
            ]
        )
        return field
    }

    func updateNSView(_ field: Field, context: Context) {
        let coordinator = context.coordinator
        coordinator.browser = browser

        // Only when something other than typing changed it — ⌘L arriving with
        // an address, a walk through the list, a submit clearing it.
        //
        // Comparing against the field's own text instead would undo every
        // backspace: deleting leaves the field shorter than what the browser
        // still considers complete, and the next update would helpfully type
        // it back in. That is a field you cannot shorten, and it reads exactly
        // like one that has stopped responding.
        let want = browser.completed
        if want != coordinator.synced {
            coordinator.synced = want
            field.stringValue = want
            coordinator.select(from: browser.typed.count, in: field)
        }

        if coordinator.answered != browser.focusRequest {
            coordinator.answered = browser.focusRequest
            DispatchQueue.main.async { coordinator.focus(field) }
        }
    }

    /// The field, told when it lands in a window.
    ///
    /// SwiftUI makes the view and updates it before it is in one, and with
    /// Split View on it comes only once the stage has said where the page is,
    /// a turn of the run loop later. Asked for the keys before then, the
    /// field had no window to ask: the request went nowhere and nothing asked
    /// again, so ⌘T left a field with no caret and typing that went nowhere
    /// until it was clicked. Now the request waits for the window.
    final class Field: NSTextField {
        var arrived: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, let arrived else { return }
            self.arrived = nil
            arrived()
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var browser: Browser
        var answered = -1
        /// The last value pushed in from the browser side, so an update can
        /// tell a change worth applying from one it made itself.
        var synced = ""

        /// A backspace has to be allowed to actually take a letter off. Without
        /// this the field puts the same letter straight back as a completion
        /// and the address can never be shortened.
        private var deleting = false

        init(browser: Browser) {
            self.browser = browser
        }

        /// The keys to the field, now if it is in a window, or the moment it is.
        @MainActor func focus(_ field: Field) {
            guard let window = field.window else {
                field.arrived = { [weak self, weak field] in
                    DispatchQueue.main.async {
                        guard let self, let field, self.browser.fieldShowing else { return }
                        self.focus(field)
                    }
                }
                return
            }
            field.arrived = nil
            window.makeFirstResponder(field)
            guard let editor = field.currentEditor() as? NSTextView else { return }
            defer { browser.fieldFocused(in: window) }
            // The system paints selected text as a block of accent colour,
            // which over this pale field is the loudest thing in the
            // window. A tenth of the ink says "selected" quietly enough.
            editor.selectedTextAttributes = [
                .backgroundColor: NSColor(Palette.ink.opacity(0.12)),
                .foregroundColor: Palette.NS.ink,
            ]
            // A draft come back to its blank tab is carried on, not typed
            // over: the caret after it. An address ⌘L raises is selected whole.
            if browser.active?.isBlank == true, !browser.typed.isEmpty {
                select(from: browser.typed.count, in: field)
            } else {
                editor.selectAll(nil)
            }
        }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            let text = field.stringValue

            browser.typed = text
            guard !deleting, let ending = browser.ending else {
                if deleting { browser.stopCompleting() }
                deleting = false
                synced = browser.completed
                return
            }
            deleting = false

            field.stringValue = text + ending
            synced = field.stringValue
            select(from: text.count, in: field)
        }

        /// The part after the caret, shown as selected, so the next keystroke
        /// replaces it and Return takes it.
        func select(from start: Int, in field: NSTextField) {
            guard let editor = field.currentEditor() as? NSTextView else { return }
            editor.selectedTextAttributes = [
                .backgroundColor: NSColor(Palette.ink.opacity(0.12)),
                .foregroundColor: Palette.NS.ink,
            ]
            let length = field.stringValue.count
            guard start <= length else { return }
            editor.selectedRange = NSRange(location: start, length: length - start)
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy command: Selector
        ) -> Bool {
            switch command {
            case #selector(NSResponder.insertNewline(_:)):
                browser.submit()
                return true
            case #selector(NSResponder.moveDown(_:)):
                browser.walk(1)
                return true
            case #selector(NSResponder.moveUp(_:)):
                browser.walk(-1)
                return true
            case #selector(NSResponder.deleteWordBackward(_:)):
                // ⌥⌫ over an offered ending lets go of it and takes the last
                // word typed, as it does with no ending there. Left to the
                // text view it would only take the selected ending.
                deleting = true
                let selected = textView.selectedRange()
                guard browser.ending != nil, selected.length > 0,
                      NSMaxRange(selected) == (textView.string as NSString).length
                else { return false }
                textView.delete(nil)
                deleting = true
                textView.deleteWordBackward(nil)
                return true
            case #selector(NSResponder.deleteBackward(_:)) where textView.string.isEmpty && browser.siteChip != nil:
                // ⌫ on an empty field takes the site out of it.
                browser.siteChip = nil
                return true
            case #selector(NSResponder.deleteBackward(_:)),
                 #selector(NSResponder.deleteForward(_:)),
                 #selector(NSResponder.deleteWordForward(_:)):
                deleting = true
                return false
            default:
                return false
            }
        }
    }
}
