import AppKit
import SwiftUI
import QuartzCore

/// Keep the live sidebar and its glass in one hosting surface. Core Animation
/// moves that surface; SwiftUI lays out its controls only when content changes,
/// rather than driving the slide through the entire browser view hierarchy.
struct SidebarSlide<Content: View>: NSViewRepresentable {
    var shown: Bool
    var width: CGFloat
    var onRight: Bool
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> SlidingSidebarView {
        SlidingSidebarView()
    }

    func updateNSView(_ view: SlidingSidebarView, context: Context) {
        view.update(content: AnyView(content().environment(\.self, context.environment)),
                    shown: shown, width: width, onRight: onRight,
                    reduced: context.environment.accessibilityReduceMotion)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SlidingSidebarView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? width, height: proposal.height ?? 0)
    }
}

@MainActor
final class SlidingSidebarView: NSView {
    let host = NSHostingView(rootView: AnyView(EmptyView()))
    private(set) var shown = false
    private var width: CGFloat = 0
    private var onRight = false
    private var initialized = false
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        host.sizingOptions = []
        host.wantsLayer = true
        addSubview(host)
    }
    required init?(coder: NSCoder) { nil }

    func update(content: AnyView, shown: Bool, width: CGFloat, onRight: Bool, reduced: Bool) {
        let changed = initialized && self.shown != shown
        let resized = self.width != width || self.onRight != onRight
        self.shown = shown
        self.width = width
        self.onRight = onRight
        host.rootView = content
        if reduced { host.layer?.removeAnimation(forKey: "sidebarSlide") }
        place(animated: changed && !resized && !reduced)
        initialized = true
    }

    override func layout() {
        super.layout()
        place(animated: false)
    }

    private func place(animated: Bool) {
        let visibleX = onRight ? bounds.width - width : 0
        let x = shown ? visibleX : (onRight ? bounds.width : -width)
        let target = NSRect(x: x, y: 0, width: width, height: bounds.height)
        guard target != host.frame else { return }
        let layer = host.layer
        let from = layer?.presentation()?.position ?? layer?.position
        layer?.removeAnimation(forKey: "sidebarSlide")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        host.frame = target
        host.layoutSubtreeIfNeeded()
        CATransaction.commit()
        guard animated, window != nil, let layer, let from else { return }
        let slide = CABasicAnimation(keyPath: "position")
        slide.fromValue = NSValue(point: from)
        slide.toValue = NSValue(point: layer.position)
        slide.duration = Motion.foldDuration(out: shown)
        let c = Motion.foldCurve
        slide.timingFunction = CAMediaTimingFunction(controlPoints: c.0, c.1, c.2, c.3)
        layer.add(slide, forKey: "sidebarSlide")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard shown, host.frame.contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }
}
