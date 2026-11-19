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
            let width = min(360, max(0, geometry.size.width - 24))
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
    @Environment(\.moonWindowGlass) private var windowGlass
    private var listening: Bool { nebula.phase == .listening }

    var body: some View {
        strip.background(Palette.ground, in: Capsule())
            .overlay {
                if !windowGlass { Capsule().strokeBorder(Palette.hairline, lineWidth: 1) }
            }
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: nebula.phase)
        .task { await nebula.loadLanguages() }
        .accessibilityIdentifier("nebula.panel")
    }

    private var strip: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(listening ? Color.accentColor : .secondary)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: listening && !reduceMotion)
                .frame(width: 23, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.system(size: 12, weight: .medium))
                    .lineLimit(2).accessibilityIdentifier("nebula.status")
                if listening && !nebula.transcript.isEmpty {
                    Text(nebula.transcript).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if nebula.phase == .confirming {
                Button("Close \(nebula.pendingTabs.count)", role: .destructive, action: nebula.confirmClose)
                    .controlSize(.small)
            }
            Button(action: nebula.dismiss) { Image(systemName: "xmark").font(.system(size: 10, weight: .medium)) }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .frame(width: 22, height: 26).accessibilityLabel("Cancel Nebula")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(minHeight: 46)
    }
    private var headline: String {
        switch nebula.phase {
        case .listening: "Listening…"
        case .finishing, .working: "Working…"
        case .ready: "Hold \(nebula.shortcut) to speak"
        default: nebula.status
        }
    }
}
