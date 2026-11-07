import SwiftUI

extension Browser {
    func openNebula() { Nebula.shared.open(in: self) }
}

struct NebulaDoor: View {
    @ObservedObject var browser: Browser
    var body: some View {
        Door(icon: "mic", on: browser.nebulaOpen, help: "Nebula — Dictation & Voice Control") {
            if browser.nebulaOpen { Nebula.shared.dismiss() }
            else { browser.openNebula() }
        }
        .accessibilityLabel("Nebula Dictation and Voice Control")
        .accessibilityIdentifier("nebula.door")
    }
}

struct NebulaOverlay: View {
    @ObservedObject var browser: Browser
    var body: some View {
        GeometryReader { geometry in
            let area = OrbitSummaryLayout.available(in: geometry.size,
                sidebarWidth: browser.prefs.sidebar ? browser.prefs.columnWidth : 0,
                onRight: browser.prefs.sidePosition == .right)
            NebulaPanel(nebula: .shared)
                .frame(width: area.width)
                .frame(height: min(440, area.height))
                .frame(height: area.height, alignment: .bottom)
                .offset(x: area.minX, y: area.minY)
        }
        .clipped()
    }
}

struct NebulaPanel: View {
    @ObservedObject var nebula: Nebula
    @State private var confirmingClose = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 9) {
                    Image(systemName: nebula.phase == .listening ? "waveform" : "mic")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(nebula.phase == .listening ? Color.accentColor : Palette.ink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nebula").font(.system(size: 17, weight: .semibold))
                        Text("Your voice, in Moon").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: nebula.dismiss) {
                        Label("Close Nebula", systemImage: "xmark").labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                }
                Picker("Mode", selection: $nebula.mode) {
                    ForEach(Nebula.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(nebula.busy)

                Picker("Language", selection: $nebula.language) {
                    if !nebula.languages.contains(nebula.language) {
                        Text(name(nebula.language)).tag(nebula.language)
                    }
                    ForEach(nebula.languages, id: \.self) { Text(name($0)).tag($0) }
                }
                .disabled(nebula.busy)
                .controlSize(.small)

                Text(nebula.status)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("nebula.status")
                if nebula.busy { ProgressView().controlSize(.small) }

                TextEditor(text: $nebula.transcript)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(7)
                    .frame(height: 100)
                    .background(Palette.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(alignment: .topLeading) {
                        if nebula.transcript.isEmpty {
                            Text("Your words appear here")
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                                .padding(12)
                                .allowsHitTesting(false)
                        }
                    }
                    .disabled(nebula.busy)
                    .accessibilityLabel("Nebula transcript")
                    .onChange(of: nebula.transcript) { _, words in
                        if words.count > 16_000 { nebula.transcript = String(words.prefix(16_000)) }
                    }

                HStack(spacing: 8) {
                    Button(nebula.phase == .listening ? "Stop" : "Start") {
                        if nebula.phase == .listening { nebula.stop() } else { nebula.start() }
                    }
                    .disabled(nebula.phase == .preparing || nebula.phase == .finishing)
                    .accessibilityIdentifier("nebula.record")
                    if !nebula.transcript.isEmpty {
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(nebula.transcript, forType: .string)
                        }
                        .disabled(nebula.busy)
                    }
                    Spacer(minLength: 0)
                    Button(nebula.mode == .dictate ? "Insert Text" : "Run Command") {
                        if nebula.mode == .control, nebula.command == .closeTab { confirmingClose = true }
                        else { Task { await nebula.apply() } }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(nebula.busy || nebula.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              (nebula.mode == .control && nebula.command == nil))
                    .accessibilityIdentifier("nebula.apply")
                }
                .controlSize(.small)
                .confirmationDialog("Close the current tab?", isPresented: $confirmingClose) {
                    Button("Close Tab", role: .destructive) { Task { await nebula.apply() } }
                }

                Divider()
                Text("Hold \(nebula.shortcut) to speak. Release to review. Change the shortcut in Settings → Shortcuts.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if nebula.mode == .control {
                    Text("Try “new tab”, “search for…”, “switch to…”, “go back”, “scroll down” or “show downloads”. Commands are spoken in English.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Speech is processed on this Mac. Apple may download a language model on first use. Audio and transcripts stay out of browsing history.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .popoverGround(card: true)
        .task { await nebula.loadLanguages() }
        .accessibilityIdentifier("nebula.panel")
    }

    private func name(_ identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }
}
