import AppKit
import Carbon
import WebKit

/// A dictation destination belongs to the field and document chosen before the
/// Nebula panel takes focus. Insertion fails if either has changed.
@MainActor
final class NebulaTarget {
    weak var browser: Browser?
    private weak var native: NSTextView?
    private weak var tab: Tab?
    private weak var web: WKWebView?
    private var frame: WKFrameInfo?
    private var original = ""
    private var selection = NSRange()
    private let token = UUID().uuidString

    static func capture(in browser: Browser) async -> NebulaTarget? {
        let target = NebulaTarget()
        target.browser = browser
        if let editor = browser.window?.firstResponder as? NSTextView {
            guard editor.isEditable, !IsSecureEventInputEnabled(), !(editor.delegate is NSSecureTextField),
                  editor.string.utf16.count < 1_000_000 else { return nil }
            target.native = editor
            target.original = editor.string
            target.selection = editor.selectedRange()
            return target
        }
        guard let tab = browser.active, tab.page == nil, let web = tab.built,
              ["http", "https", "file"].contains(tab.pageAddress?.scheme?.lowercased() ?? "") else { return nil }
        target.tab = tab
        target.web = web
        target.frame = tab.nebulaFrame
        let result = try? await web.callAsyncJavaScript(Self.captureScript, arguments: ["token": target.token],
                                                       in: target.frame, contentWorld: Web.world)
        return result as? Bool == true ? target : nil
    }

    func insert(_ text: String) async -> Bool {
        guard !text.isEmpty, text.count <= 16_000, let browser else { return false }
        if let native {
            guard native.window === browser.window, native.isEditable, !IsSecureEventInputEnabled(),
                  !(native.delegate is NSSecureTextField), native.string == original,
                  NSMaxRange(selection) <= native.string.utf16.count else { return false }
            native.window?.makeFirstResponder(native)
            native.insertText(text, replacementRange: selection)
            return true
        }
        guard let tab, browser.activeID == tab.id, let web, tab.built === web else { return false }
        let result = try? await web.callAsyncJavaScript(Self.insertScript,
            arguments: ["token": token, "text": text], in: frame, contentWorld: Web.world)
        return result as? Bool == true
    }

    func clear() {
        original = ""
        if let web {
            web.callAsyncJavaScript("if (globalThis.__moonNebula?.token === token) delete globalThis.__moonNebula;",
                                    arguments: ["token": token], in: frame, in: Web.world) { _ in }
        }
    }

    static let captureScript = """
    delete globalThis.__moonNebula;
    let el = document.activeElement;
    for (let depth = 0; depth < 12; depth++) {
      if (el?.shadowRoot?.activeElement) { el = el.shadowRoot.activeElement; continue; }
      if (el?.tagName === 'IFRAME') {
        try { el = el.contentDocument?.activeElement; continue; } catch (_) { return false; }
      }
      break;
    }
    if (!el || el.disabled || el.readOnly || el.type === 'password') return false;
    const field = el.tagName === 'TEXTAREA' ||
      (el.tagName === 'INPUT' && ['text','search','email','url','tel'].includes(el.type));
    if (!field && !el.isContentEditable) return false;
    if ((field ? el.value : el.textContent).length > 1000000) return false;
    const selection = el.ownerDocument.getSelection();
    globalThis.__moonNebula = {
      token, el, field, original: field ? el.value : el.textContent,
      start: field ? (el.selectionStart ?? el.value.length) : 0,
      end: field ? (el.selectionEnd ?? el.value.length) : 0,
      range: !field && selection?.rangeCount ? selection.getRangeAt(0).cloneRange() : null
    };
    return true;
    """

    static let insertScript = """
    const saved = globalThis.__moonNebula;
    if (!saved || saved.token !== token) return false;
    delete globalThis.__moonNebula;
    const el = saved.el;
    if (!el.isConnected || el.disabled || el.readOnly || el.type === 'password') return false;
    if ((saved.field ? el.value : el.textContent) !== saved.original) return false;
    const doc = el.ownerDocument, win = doc.defaultView;
    el.focus();
    if (saved.field) {
      const event = new win.InputEvent('beforeinput', {
        inputType: 'insertText', data: text, bubbles: true, cancelable: true, composed: true
      });
      if (!el.dispatchEvent(event)) return false;
      if (!el.isConnected || el.disabled || el.readOnly || el.type === 'password' || el.value !== saved.original) return false;
      const proto = el.tagName === 'TEXTAREA' ? win.HTMLTextAreaElement.prototype : win.HTMLInputElement.prototype;
      const value = saved.original.slice(0, saved.start) + text + saved.original.slice(saved.end);
      Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value);
      try { el.setSelectionRange(saved.start + text.length, saved.start + text.length); } catch (_) {}
      el.dispatchEvent(new win.InputEvent('input', {
        inputType: 'insertText', data: text, bubbles: true, composed: true
      }));
      return true;
    }
    if (!el.isContentEditable || !saved.range || !el.contains(saved.range.commonAncestorContainer)) return false;
    const selection = doc.getSelection();
    selection.removeAllRanges();
    selection.addRange(saved.range);
    return doc.execCommand('insertText', false, text);
    """
}
