import AppKit
import QuartzCore
import SwiftUI

/// Re-enable motion only for visual properties. The row still changes its
/// hover state and close-button hit target immediately, without animating layout.
struct TabHoverFade: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let hovering: Bool

    func body(content: Content) -> some View {
        content
            .animation(reduceMotion ? nil : .easeInOut(duration: hovering ? 0.160 : 0.140), value: hovering)
            .transaction {
                $0.disablesAnimations = false
                $0.animation = nil
            }
    }
}

/// Isolate decorative motion from the row's immediate selection/close state.
/// Core Animation keeps rapid reversals continuous without per-frame SwiftUI work.
struct TabHoverHighlight: View {
    let hovering: Bool
    let colour: Color
    var radius: CGFloat = 9

    var body: some View {
        NativeTabHoverHighlight(hovering: hovering, colour: colour, radius: radius)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct NativeTabHoverHighlight: NSViewRepresentable {
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
        effectiveAppearance.performAsCurrentDrawingAppearance { highlight.backgroundColor = colour.cgColor }
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
        // A gentler arrival and departure; reversals still start at visible opacity.
        fade.duration = over ? 0.160 : 0.140
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        highlight.add(fade, forKey: Self.animationKey)
    }
}
