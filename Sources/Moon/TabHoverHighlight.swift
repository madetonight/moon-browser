import AppKit
import QuartzCore
import SwiftUI

/// Isolate decorative motion from the row's immediate selection/close state.
/// Core Animation keeps rapid reversals continuous without per-frame SwiftUI work.
struct TabHoverHighlight: NSViewRepresentable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let hovering: Bool
    let colour: Color
    var radius: CGFloat = 9

    func makeNSView(context: Context) -> TabHoverLayerView { TabHoverLayerView() }

    func updateNSView(_ view: TabHoverLayerView, context: Context) {
        view.update(hovering: hovering, colour: NSColor(colour), radius: radius,
                    reduceMotion: reduceMotion)
    }

    static func dismantleNSView(_ view: TabHoverLayerView, coordinator: ()) {
        view.highlight.removeAllAnimations()
    }
}

final class TabHoverLayerView: NSView {
    let highlight = CALayer()
    private var hovering: Bool?
    static let animationKey = "tabHoverOpacity"

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        highlight.opacity = 0
        highlight.cornerCurve = .continuous
        layer?.addSublayer(highlight)
        setAccessibilityElement(false)
    }

    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        highlight.frame = bounds
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { highlight.removeAllAnimations() }
    }

    func update(hovering over: Bool, colour: NSColor, radius: CGFloat, reduceMotion: Bool) {
        let changed = hovering != over
        let initial = hovering == nil
        let target: Swift.Float = over ? 1 : 0
        // Capture the visible value BEFORE replacing an interrupted animation.
        let visible = highlight.presentation()?.opacity ?? highlight.opacity
        hovering = over
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        highlight.backgroundColor = colour.cgColor
        highlight.cornerRadius = radius
        highlight.opacity = target
        CATransaction.commit()

        if reduceMotion || initial || window == nil {
            highlight.removeAnimation(forKey: Self.animationKey)
            return
        }
        // Title, theme or layout updates must not restart a fade already underway.
        guard changed else { return }
        highlight.removeAnimation(forKey: Self.animationKey)
        guard abs(visible - target) > 0.001 else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = visible
        fade.toValue = target
        // A responsive arrival and a shorter departure avoid dim trails across rows.
        fade.duration = over ? 0.085 : 0.065
        fade.timingFunction = over
            ? CAMediaTimingFunction(controlPoints: 0.16, 0.72, 0.28, 1)
            : CAMediaTimingFunction(controlPoints: 0.32, 0, 0.68, 1)
        highlight.add(fade, forKey: Self.animationKey)
    }
}
