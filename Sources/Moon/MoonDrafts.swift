import AppKit
import SwiftUI
import WebKit

/// Keep Moon's conservative draft protection alongside Search's form engine.
/// No field values cross this bridge, including for subframes or shadow roots.
final class MoonDraftRelay: NSObject, WKScriptMessageHandler {
    static let name = "moonDirty"
    weak var tab: Tab?
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let id = body["id"] as? String,
              UUID(uuidString: id) != nil, let dirty = body["dirty"] as? Bool else { return }
        MainActor.assumeIsolated {
            guard let tab else { return }
            if dirty {
                if tab.moonDirtyFrames.count >= 256 { tab.moonDirtyOverflow = true }
                else { tab.moonDirtyFrames.insert(id) }
            } else { tab.moonDirtyFrames.remove(id) }
        }
    }
    static let script = """
    (() => {
      const id = crypto.randomUUID(); let dirty = false;
      const publish = () => window.webkit.messageHandlers.moonDirty.postMessage({id, dirty});
      window.__moonMarkDirty = () => { dirty = true; publish(); };
      document.addEventListener('input', e => { if(e.isTrusted) window.__moonMarkDirty(); }, true);
      window.addEventListener('pageshow', publish);
    })();
    """
    @MainActor static func confirmClosing(_ tab: Tab, in window: NSWindow?) -> Bool {
        guard !Store.testing || Store.visibleMeasurement,
              !tab.moonDirtyFrames.isEmpty || tab.moonDirtyOverflow else { return true }
        return DraftClosePanel.confirm(over: window)
    }
}

/// The close operation waits for an answer, including when closing a batch of
/// tabs. Use a window for that modal behavior and Moon's own plate for its UI.
@MainActor
private final class DraftClosePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    static func confirm(over parent: NSWindow?) -> Bool {
        let panel = DraftClosePanel(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        panel.title = "Close this tab?"
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.appearance = parent?.effectiveAppearance
        panel.collectionBehavior = [.fullScreenAuxiliary]
        let host = NSHostingView(rootView: DraftCloseCard { close in
            NSApp.stopModal(withCode: close ? .OK : .cancel)
        }
        .padding(28))
        panel.contentView = host
        let size = host.fittingSize
        panel.setContentSize(size)
        if let parent {
            let visible = parent.frame.intersection(parent.screen?.visibleFrame ?? parent.frame)
            let anchor = visible.isEmpty ? parent.frame : visible
            panel.setFrameOrigin(NSPoint(x: anchor.midX - size.width / 2, y: anchor.midY - size.height / 2))
            parent.addChildWindow(panel, ordered: .above)
        } else {
            panel.center()
        }
        let answer = NSApp.runModal(for: panel)
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        return answer == .OK
    }
}

private struct DraftCloseCard: View {
    let answer: (Bool) -> Void

    var body: some View {
        Plate("Close this tab?", width: 350, close: { answer(false) }) {
            Text("You may lose unsaved changes on this page.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
        } foot: {
            HStack(spacing: 8) {
                choice("Close Tab", primary: true) { answer(true) }
                    .keyboardShortcut(.defaultAction)
                choice("Keep Tab", primary: false) { answer(false) }
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func choice(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(primary ? Palette.ground : Palette.ink)
                .padding(.horizontal, 16)
                .frame(height: 30)
                .background(primary ? Palette.ink : Palette.wash, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
