import AppKit
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
    @MainActor static func confirmClosing(_ tab: Tab) -> Bool {
        guard !Store.testing, !tab.moonDirtyFrames.isEmpty || tab.moonDirtyOverflow else { return true }
        let alert = NSAlert()
        alert.messageText = "Close this tab?"
        alert.informativeText = "This page contains changes you may lose."
        alert.addButton(withTitle: "Keep Tab")
        alert.addButton(withTitle: "Close Tab")
        return alert.runModal() == .alertSecondButtonReturn
    }
}
