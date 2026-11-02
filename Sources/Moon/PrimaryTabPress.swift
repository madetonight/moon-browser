import AppKit
import SwiftUI

/// Native primary-button observation, integrated through macOS 26 SwiftUI.
struct PrimaryTabPress: NSGestureRecognizerRepresentable {
    let enabled: Bool
    let changed: (Bool) -> Void
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }
    func makeNSGestureRecognizer(context: Context) -> Recognizer {
        let recognizer = Recognizer(target: nil, action: nil)
        recognizer.delaysPrimaryMouseButtonEvents = false
        recognizer.delegate = context.coordinator
        recognizer.isEnabled = enabled
        return recognizer
    }
    func updateNSGestureRecognizer(_ recognizer: Recognizer, context: Context) {
        if recognizer.isEnabled != enabled { recognizer.isEnabled = enabled }
    }
    func handleNSGestureRecognizerAction(_ recognizer: Recognizer, context: Context) {
        changed(recognizer.state == .began || recognizer.state == .changed)
    }
    final class Coordinator: NSObject, NSGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer) -> Bool { true }
    }
    final class Recognizer: NSGestureRecognizer {
        private var origin = NSPoint.zero
        override func mouseDown(with event: NSEvent) {
            guard event.buttonNumber == 0 else { state = .failed; return }
            origin = event.locationInWindow
            state = .began
        }
        override func mouseDragged(with event: NSEvent) {
            let point = event.locationInWindow
            if hypot(point.x - origin.x, point.y - origin.y) > TabPress.travel { state = .cancelled }
            else { state = .changed }
        }
        override func mouseUp(with event: NSEvent) { state = .ended }
        override func rightMouseDown(with event: NSEvent) { state = .failed }
        override func otherMouseDown(with event: NSEvent) { state = .failed }
    }
}
