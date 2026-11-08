import SwiftUI

extension Browser {
    func openNebula() { Nebula.shared.open(in: self) }
}

struct NebulaDoor: View {
    @ObservedObject var browser: Browser
    var body: some View {
        Door(icon: "waveform", on: browser.nebulaOpen, help: "Nebula — Talk to Moon") {
            if browser.nebulaOpen { Nebula.shared.dismiss() }
            else { browser.openNebula() }
        }
        .accessibilityLabel("Nebula — Talk to Moon")
        .accessibilityIdentifier("nebula.door")
    }
}

/// An in-window HUD, constrained by this window rather than the screen.
struct NebulaOverlay: View {
    @ObservedObject var browser: Browser
    var body: some View {
        GeometryReader { geometry in
            let width = min(460, max(0, geometry.size.width - 32))
            NebulaPanel(nebula: .shared)
                .frame(width: width)
                .frame(maxHeight: max(0, geometry.size.height - 32), alignment: .bottom)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 16)
        }
        .clipped()
    }
}

struct NebulaPanel: View {
    @ObservedObject var nebula: Nebula
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var listening: Bool { nebula.phase == .listening }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(listening ? Color.accentColor : .secondary)
                        .symbolEffect(.variableColor.iterative, options: .repeating,
                                      isActive: listening && !reduceMotion)
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(listening ? "Listening…" : "Nebula")
                            .font(.system(size: 14, weight: .semibold))
                        Text(nebula.busy ? nebula.status : "Just say it.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Menu {
                        Picker("Use your voice to", selection: $nebula.mode) {
                            Text("Control Moon").tag(Nebula.Mode.control)
                            Text("Dictate into a field").tag(Nebula.Mode.dictate)
                        }
                        Picker("Speech language", selection: $nebula.language) {
                            if !nebula.languages.contains(nebula.language) {
                                Text(languageName(nebula.language)).tag(nebula.language)
                            }
                            ForEach(nebula.languages, id: \.self) { Text(languageName($0)).tag($0) }
                        }
                    } label: { Image(systemName: "slider.horizontal.3") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .disabled(nebula.busy)
                    .help("Nebula mode and speech language")
                    Button(action: nebula.dismiss) { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .accessibilityLabel("Close Nebula")
                }

                if !nebula.transcript.isEmpty {
                    Text(nebula.transcript)
                        .font(.system(size: 16, weight: .medium))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("You said: \(nebula.transcript)")
                }
                if !nebula.busy {
                    Text(nebula.status)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("nebula.status")
                }
                if nebula.phase == .ready && nebula.mode == .control {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        example("Summarize this page", "text.alignleft")
                        example("Tidy my tabs", "square.stack.3d.up")
                    }
                    Text("Try “close all my YouTube tabs” or “switch to Work”.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if nebula.phase == .confirming {
                    HStack {
                        Button("Cancel", action: nebula.dismiss)
                        Spacer()
                        Button("Close \(nebula.pendingTabs.count) \(nebula.pendingTabs.count == 1 ? "Tab" : "Tabs")", role: .destructive,
                               action: nebula.confirmClose)
                            .buttonStyle(.borderedProminent).tint(.red)
                    }
                } else {
                    HStack(spacing: 8) {
                        Text(nebula.shortcut)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                        Text(nebula.mode == .control ? "Hold, talk, release." : "Hold to dictate into your field.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        if !nebula.transcript.isEmpty && !nebula.busy {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(nebula.transcript, forType: .string)
                            } label: { Image(systemName: "doc.on.doc") }
                            .help("Copy your words").buttonStyle(.plain)
                        }
                        Button {
                            if listening { nebula.stop() } else { nebula.start() }
                        } label: {
                            Image(systemName: listening ? "stop.fill" : "mic.fill")
                                .frame(width: 30, height: 30)
                                .background(Color.accentColor.opacity(0.13), in: Circle())
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(nebula.busy && !listening)
                        .accessibilityLabel(listening ? "Stop and act" : "Start speaking")
                        .accessibilityIdentifier("nebula.record")
                    }
                }
                if nebula.phase == .ready {
                    Text("Speech stays on this Mac. Apple may download a speech model on first use. Browser commands are spoken in English.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .fixedSize(horizontal: false, vertical: true)
        .popoverGround(card: true)
        .shadow(color: .black.opacity(0.12), radius: 20, y: 6)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: nebula.phase)
        .task { await nebula.loadLanguages() }
        .accessibilityIdentifier("nebula.panel")
    }

    private func example(_ title: String, _ icon: String) -> some View {
        Button { nebula.runExample(title) } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func languageName(_ identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }
}
