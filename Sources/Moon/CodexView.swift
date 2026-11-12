import SwiftUI

struct CodexDoor: View {
    @ObservedObject var browser: Browser
    var body: some View {
        Door(icon: "terminal", on: browser.active?.page?.kind == .codex, help: "Codex — Work with shared tabs") { browser.openCodex() }
            .accessibilityLabel("Open a new Codex tab").accessibilityIdentifier("codex.door")
    }
}

@MainActor
struct CodexWorkspace: View {
    @ObservedObject var browser: Browser
    @StateObject private var session: CodexSession
    @State private var sharing = false
    @State private var followsConversation = true
    init(browser: Browser, tab: Tab) {
        self.browser = browser
        let session = tab.codex ?? CodexSession(browser: browser, tab: tab.id)
        tab.codex = session
        _session = StateObject(wrappedValue: session)
    }
    private var sharedCount: Int { session.availableTabs.filter { session.isShared($0) }.count }
    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        if session.messages.isEmpty { introduction }
                        ForEach(session.messages) { message in
                            CodexMessageView(message: message, provider: session.provider.name,
                                             streaming: session.busy && message.id == session.messages.last?.id)
                                .equatable()
                        }
                        if let approval = session.approval { approvalCard(approval) }
                        Color.clear.frame(height: 1).id("conversation-end")
                    }
                    .padding(.horizontal, 24).padding(.vertical, 30)
                    .frame(maxWidth: 808).frame(maxWidth: .infinity)
                }
                .onScrollPhaseChange { _, phase in
                    if phase == .interacting { followsConversation = false }
                }
                .onChange(of: session.messages.count) { _, _ in
                    followsConversation = true
                    proxy.scrollTo("conversation-end", anchor: .bottom)
                }
                .task(id: session.busy) {
                    guard session.busy else { return }
                    // Follow streaming at a bounded rate; do not re-layout the
                    // entire transcript for every token or fight manual scrolling.
                    while !Task.isCancelled {
                        if followsConversation { proxy.scrollTo("conversation-end", anchor: .bottom) }
                        do { try await Task.sleep(for: .milliseconds(160)) } catch { return }
                    }
                }
            }
            composer
        }
        .background(Palette.ground)
        .environment(\.openURL, OpenURLAction { url in
            guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return .discarded }
            return .systemAction(url)
        })
        .task { if !Store.testing { session.connect() } }
        .accessibilityIdentifier("codex.workspace")
    }
    private var header: some View {
        HStack(spacing: 12) {
            Menu {
                Picker("Provider", selection: $session.provider) {
                    Text("Codex").tag(AIProvider.codex)
                    Text("Gemini").tag(AIProvider.gemini)
                }.disabled(session.busy || session.connecting)
                if session.connected { Button("Disconnect", action: session.close) }
                else { Button("Reconnect", action: session.connect).disabled(session.connecting) }
            } label: {
                Label(session.provider.name, systemImage: session.provider == .codex ? "terminal" : "sparkles")
                    .font(.system(size: 12, weight: .medium))
            }.menuStyle(.borderlessButton).fixedSize()
            Spacer(minLength: 12)
            Text(session.conversationTitle).font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 12)
            Button { browser.openCodex() } label: { Image(systemName: "square.and.pencil") }
                .buttonStyle(.plain).help("New assistant tab").accessibilityLabel("New assistant tab")
        }
        .padding(.horizontal, 24).padding(.vertical, 15)
        .overlay(alignment: .bottom) { Divider().opacity(0.35) }
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                if session.connecting { ProgressView().controlSize(.mini) }
                Text(session.status).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(2).textSelection(.enabled)
                Spacer(minLength: 0)
            }
            VStack(spacing: 10) {
                ZStack(alignment: .topLeading) {
                    if session.draft.isEmpty {
                        Text("Ask about your tabs, or give Moon a task…")
                            .foregroundStyle(.tertiary).padding(.horizontal, 5).padding(.top, 1).allowsHitTesting(false)
                    }
                    TextEditor(text: $session.draft).scrollContentBackground(.hidden)
                        .frame(height: 52).accessibilityLabel("Message your browser assistant")
                        .onChange(of: session.draft) { _, text in
                            if text.count > 16_000 { session.draft = String(text.prefix(16_000)) }
                        }
                }.font(.system(size: 14))
                HStack(spacing: 14) {
                    Button { sharing.toggle() } label: {
                        Label(sharedCount == 0 ? "Add tabs" : "Tabs · \(sharedCount)", systemImage: "plus")
                    }
                    .popover(isPresented: $sharing) { sharedTabs }
                    .help("Choose the tabs this conversation can access")
                    .accessibilityIdentifier("codex.share")
                    Label("Asks first", systemImage: "hand.raised")
                        .foregroundStyle(.secondary).help("Page-changing actions require your approval")
                    Spacer(minLength: 0)
                    if !session.models.isEmpty {
                        Picker("Model", selection: $session.model) {
                            ForEach(session.models) { Text($0.name).tag($0.id) }
                        }.labelsHidden().pickerStyle(.menu).frame(maxWidth: 175).disabled(session.busy)
                    }
                    Button(action: session.busy ? session.interrupt : session.send) {
                        Image(systemName: session.busy ? "stop.fill" : "arrow.up")
                            .font(.system(size: 13, weight: .semibold)).frame(width: 21, height: 23)
                    }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.circle)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(!session.busy && (!session.signedIn || session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    .accessibilityLabel(session.busy ? "Stop" : "Send")
                }.font(.system(size: 11)).buttonStyle(.plain)
            }
            .padding(14)
            .background(Palette.ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 19))
            .overlay { RoundedRectangle(cornerRadius: 19).strokeBorder(Palette.ink.opacity(0.09), lineWidth: 1) }
            Text("Only shared tabs go to \(session.provider == .codex ? "OpenAI" : "Google"). Password fields, cookies and private tabs stay excluded.")
                .font(.system(size: 10)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24).padding(.bottom, 18).padding(.top, 10)
        .frame(maxWidth: 808).frame(maxWidth: .infinity)
    }
    private var introduction: some View {
        VStack(alignment: .leading, spacing: 15) {
            Image(systemName: session.provider == .codex ? "terminal" : "sparkles")
                .font(.system(size: 26, weight: .light)).foregroundStyle(.secondary)
            Text("What are we working on?").font(.system(size: 23, weight: .semibold))
            Text("Compare pages, find the details, or work through a website together. You choose what to share and approve what changes.")
                .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !session.connected {
                Button(session.connecting ? "Connecting…" : "Connect \(session.provider.name)", action: session.connect).disabled(session.connecting)
                if session.provider == .codex {
                    Link("Install the official Codex CLI", destination: URL(string: "https://developers.openai.com/codex/cli/")!).font(.system(size: 11))
                } else { Button("Set up Gemini in Settings") { browser.settingsPage = .ai; browser.tuning = true } }
            } else if !session.signedIn && session.provider == .codex {
                Button("Sign in with ChatGPT", action: session.signIn).buttonStyle(.borderedProminent)
                if let code = session.loginCode { Text("Sign-in code: \(code)").textSelection(.enabled) }
                if let url = session.loginURL { Link("Continue sign-in", destination: url) }
            } else {
                Button("Choose tabs to share") { sharing = true }
            }
        }.padding(.vertical, 30).frame(maxWidth: 530, alignment: .leading)
    }
    private func approvalCard(_ approval: CodexSession.Approval) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(approval.title, systemImage: "hand.raised").font(.system(size: 13, weight: .semibold))
            Text(approval.detail).font(.system(size: 12)).textSelection(.enabled)
            HStack {
                Button("Decline") { session.resolveApproval(false) }
                Spacer()
                Button("Allow Once") { session.resolveApproval(true) }.buttonStyle(.borderedProminent)
            }
        }.padding(16).background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 15))
            .accessibilityIdentifier("codex.approval")
    }
    private var sharedTabs: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Share with \(session.provider.name)").font(.system(size: 14, weight: .semibold))
            Text("Only these tabs are available to this conversation. A tab that changes site needs to be shared again.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(session.availableTabs) { tab in
                        Toggle(isOn: Binding(get: { session.isShared(tab) }, set: { on in
                            session.shared.remove(tab.id)
                            if on, let address = tab.pageAddress { session.share(tab, origin: address) }
                        })) {
                            HStack(spacing: 8) {
                                if let icon = tab.icon { Image(nsImage: icon).resizable().scaledToFit().frame(width: 16, height: 16) }
                                else { Image(systemName: "globe").frame(width: 16) }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tab.label).lineLimit(1)
                                    Text(tab.pageAddress?.host() ?? "").font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                            }
                        }.toggleStyle(.checkbox)
                    }
                    if session.availableTabs.isEmpty { Text("Open a website in this space to share it.").foregroundStyle(.secondary) }
                }
            }.frame(maxHeight: 320)
        }
        .padding(16).frame(width: 320).popoverGround()
    }
}


private struct CodexMessageView: View, Equatable {
    let message: CodexSession.Message
    let provider: String
    let streaming: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.user { Spacer(minLength: 54) }
            VStack(alignment: .leading, spacing: 12) {
                if !message.user {
                    Label(provider, systemImage: provider == "Codex" ? "terminal" : "sparkles")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    if !message.steps.isEmpty {
                        DisclosureGroup("\(message.steps.count) browser \(message.steps.count == 1 ? "action" : "actions")") {
                            VStack(alignment: .leading, spacing: 9) {
                                ForEach(message.steps) { step in
                                    HStack(spacing: 8) {
                                        Image(systemName: step.state == "Done" ? "checkmark.circle" : step.state == "Working" ? "circle.dotted" : "minus.circle")
                                        Text(step.title)
                                        Spacer()
                                        Text(step.state).foregroundStyle(.tertiary)
                                    }
                                }
                            }.padding(.top, 8)
                        }.font(.system(size: 11)).foregroundStyle(.secondary)
                            .padding(12).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                if message.text.isEmpty && streaming { ProgressView().controlSize(.small) }
                else if message.user || streaming { Text(message.text).textSelection(.enabled) }
                else { CodexMarkdownView(text: message.text) }
            }
            .font(.system(size: 14)).lineSpacing(4)
            .padding(message.user ? 14 : 0)
            .foregroundStyle(message.user ? Color.white : Palette.ink)
            .background(message.user ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 17))
            .frame(maxWidth: message.user ? 600 : .infinity, alignment: .leading)
            if !message.user { Spacer(minLength: 0) }
        }
    }
}

/// Parse completed responses only; streaming text stays cheap and readable.
private struct CodexMarkdownView: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(text.components(separatedBy: "```").enumerated()), id: \.offset) { index, block in
                if index.isMultiple(of: 2) {
                    Text((try? AttributedString(markdown: block, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(block))
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                } else {
                    let lines = block.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                    let code = lines.count > 1 ? String(lines[1]) : block
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(lines.count > 1 ? String(lines[0]) : "Code").foregroundStyle(.secondary)
                            Spacer()
                            Button("Copy", systemImage: "document.on.document") {
                                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string)
                            }.buttonStyle(.plain)
                        }.font(.system(size: 10))
                        ScrollView(.horizontal) { Text(code).font(.system(size: 12, design: .monospaced)).textSelection(.enabled) }
                    }.padding(12).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 11))
                }
            }
        }
    }
}
