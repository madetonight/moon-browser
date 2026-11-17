import SwiftUI

// Spaces, paged through: in the column, two fingers sideways go from one to
// the next, the rows following them, as in Arc; in the bar across the top,
// the same up and down, the row of tabs following them — or a mouse wheel's
// notch, one space at a time, or the mouse's back and forward buttons with
// the pointer over the tabs. Past the last space a new one is made in
// place. The space's icon turns over as it goes (see SpaceDot).

/// The swipe between spaces. It reads the trackpad's own scroll events
/// before anything else sees them, and takes only a gesture that starts over
/// the tabs and sets off clearly along the spaces' axis — sideways in the
/// column, up or down in the bar; everything else (scrolling the tabs, a
/// long row of them sideways) goes on as it would have.
@MainActor
final class SpaceSwipe {
    static let shared = SpaceSwipe()

    private weak var browser: Browser?
    private var monitor: Any?
    private var buttons: Any?
    private enum Axis { case undecided, across, along }
    private var axis = Axis.undecided
    private var tracking = false
    /// The glide after a swipe that was taken, which is taken too.
    private var gliding = false
    private var gathered = CGSize.zero
    /// When the wheel last turned over the bar, whether a space came of it
    /// or not. A spin of the wheel is a run of notches close together, and
    /// it brings one space: the next waits for the wheel to have rested.
    private var notched = Date.distantPast
    /// Until when a new gesture is let go by: the hand that just brought a
    /// space is often still moving, and its next stroke would take one more.
    private var resting = Date.distantPast
    /// A gesture let go by while resting, kept whole, glide included.
    private var ignoring = false

    /// How long after a space comes before another can.
    static let rest: TimeInterval = 0.4

    /// How far the fingers have to go for the next space to come: 50
    /// points in the column; in a bar only 52 tall, most of its height, so
    /// that scrolling the page with the pointer a little high doesn't.
    static func enough(for browser: Browser) -> CGFloat {
        browser.prefs.sidebar ? 50 : Metrics.strip * 0.6
    }

    func start(for browser: Browser) {
        self.browser = browser
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            MainActor.assumeIsolated { SpaceSwipe.shared.takes(event) } ? nil : event
        }
        buttons = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .swipe]) { event in
            MainActor.assumeIsolated { SpaceSwipe.shared.pressed(event) } ? nil : event
        }
    }

    /// The mouse's back and forward buttons over the tabs: the space before,
    /// or the one after. Over the page they stay the page's back and forward
    /// (PageView.otherMouseDown). Past the last space, as with the wheel,
    /// an empty new page.
    ///
    /// Most mice send them as buttons 3 and 4. A Logitech mouse set up with
    /// Logi Options+, Logitech's own driver, doesn't: it turns them into the
    /// swipe a trackpad sends for going back or forward a page — deltaX 1
    /// for back, -1 for forward, which is how Safari reads it. A swipe of
    /// that kind over the tabs is taken the same way, whoever sends it.
    private func pressed(_ event: NSEvent) -> Bool {
        let step: Int
        switch event.type {
        case .otherMouseDown where event.buttonNumber == 3: step = -1
        case .otherMouseDown where event.buttonNumber == 4: step = 1
        case .swipe where event.deltaX != 0: step = event.deltaX > 0 ? -1 : 1
        default: return false
        }
        guard let browser = Browsers.browser(for: event.window), !browser.isPopup, !browser.ghostWindow,
              !browser.folded || browser.peeking, overTabs(event, in: browser) else { return false }
        self.browser = browser
        guard browser.prefs.usesSpaces || (browser.prefs.sidebar && step > 0) else { return false }
        let here = browser.makingSpace ? browser.spaces.count : (browser.spaces.firstIndex { $0.id == browser.spaceID } ?? 0)
        let target = SpaceComparison.zen ? ZenSpaceNavigation.destination(from: here, offset: step, count: browser.spaces.count) : here + step
        if target >= 0, target <= browser.spaces.count { slide(browser, to: target, from: here) }
        return true
    }

    /// Where the tabs are: the column, or the bar across the top.
    private func overTabs(_ event: NSEvent, in browser: Browser) -> Bool {
        guard let window = event.window, window === browser.window else { return false }
        if browser.prefs.sidebar {
            return browser.prefs.sidePosition == .right
                ? event.locationInWindow.x >= window.frame.width - browser.prefs.columnWidth
                : event.locationInWindow.x < browser.prefs.columnWidth
        }
        return event.locationInWindow.y > window.frame.height - Metrics.strip
    }

    /// True for an event the swipe keeps for itself.
    private func takes(_ event: NSEvent) -> Bool {
        // The window the fingers are over, at the start of a gesture or a
        // turn of the wheel; the rest of a gesture stays with it.
        if event.phase == .began || !event.hasPreciseScrollingDeltas, let over = Browsers.browser(for: event.window) {
            browser = over
        }
        guard let browser, !browser.isPopup, !browser.ghostWindow, browser.prefs.usesSpaces || browser.prefs.sidebar,
              !browser.folded || browser.peeking else { return false }
        // A mouse wheel over the tabs: a notch along the spaces' axis — up or down
        // in the bar, sideways in the column — brings one space. In the column
        // only a notch more sideways than up or down: scrolling the tabs is
        // never taken for it.
        if !event.hasPreciseScrollingDeltas {
            guard browser.prefs.usesSpaces else { return false }
            let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
            let step = browser.prefs.sidebar ? (abs(dx) > abs(dy) ? dx : 0) : dy
            guard step != 0, overTabs(event, in: browser) else { return false }
            let now = Date()
            let rested = now.timeIntervalSince(notched) > 0.3 && now > resting
            notched = now
            guard rested else { return true }
            let here = browser.makingSpace ? browser.spaces.count : (browser.spaces.firstIndex { $0.id == browser.spaceID } ?? 0)
            let offset = step < 0 ? 1 : -1
            let target = SpaceComparison.zen ? ZenSpaceNavigation.destination(from: here, offset: offset, count: browser.spaces.count) : here + offset
            if target >= 0, target <= browser.spaces.count { slide(browser, to: target, from: here) }
            return true
        }
        if !event.momentumPhase.isEmpty { return gliding }
        switch event.phase {
        case .began:
            gliding = false
            ignoring = false
            // Only a gesture that starts over the tabs.
            guard overTabs(event, in: browser) else {
                tracking = false
                return false
            }
            began()
            if ignoring { return true }
            return moved(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
        case .changed:
            if ignoring { return true }
            guard tracking else { return false }
            return moved(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
        case .ended, .cancelled:
            if ignoring {
                ignoring = false
                gliding = true
                return true
            }
            guard tracking else { return false }
            let taken = axis == .across
            ended(cancelled: event.phase == .cancelled)
            gliding = taken
            return taken
        default:
            return false
        }
    }

    // MARK: - the gesture, apart from where its events come from (the bench drives these)

    func began() {
        browser?.newSpaceSwipe = false
        axis = .undecided
        gathered = .zero
        // Just after a space came: the same hand's next stroke is let go by.
        ignoring = Date() <= resting
        tracking = !ignoring
    }

    /// True while the gesture is this one's to take. The spaces lie
    /// sideways in the column and one above the other in the bar.
    @discardableResult
    func moved(dx: CGFloat, dy: CGFloat) -> Bool {
        guard tracking, let browser else { return false }
        let (step, aside) = browser.prefs.sidebar ? (dx, dy) : (dy, dx)
        gathered.width += step
        gathered.height += aside
        if axis == .undecided {
            guard abs(gathered.width) + abs(gathered.height) > 6 else { return false }
            axis = abs(gathered.width) > abs(gathered.height) * 1.5 ? .across : .along
        }
        guard axis == .across else { return false }
        guard browser.prefs.usesSpaces || (browser.prefs.sidebar && gathered.width < 0) else { return false }
        browser.newSpaceSwipe = !SpaceComparison.zen && browser.prefs.sidebar && gathered.width < 0 && !browser.makingSpace && browser.spaceID == browser.spaces.last?.id
        browser.spaceSwipe = resisted(gathered.width, in: browser)
        return true
    }

    /// Along the spaces' axis, whichever it is — for the bench.
    @discardableResult
    func moved(along travel: CGFloat) -> Bool {
        guard let browser else { return false }
        return browser.prefs.sidebar ? moved(dx: travel, dy: 0) : moved(dx: 0, dy: travel)
    }

    func ended(cancelled: Bool = false) {
        defer { tracking = false }
        guard let browser, axis == .across else { return }
        let travel = gathered.width
        let here = browser.makingSpace ? browser.spaces.count : (browser.spaces.firstIndex { $0.id == browser.spaceID } ?? 0)
        // Sidebar: left advances, right returns. The top strip uses vertical paging.
        let offset = travel < 0 ? 1 : -1
        let target = cancelled || abs(travel) < Self.enough(for: browser) ? here
            : SpaceComparison.zen ? ZenSpaceNavigation.destination(from: here, offset: offset, count: browser.spaces.count) : here + offset
        guard target != here, target >= 0, target <= browser.spaces.count else {
            withAnimation(Motion.settle) { browser.spaceSwipe = 0 } completion: {
                if browser.spaceSwipe == 0 { browser.newSpaceSwipe = false }
            }
            return
        }
        slide(browser, to: target, from: here, direction: offset)
    }

    /// Nothing that way: the rows give a little, and come back.
    private func resisted(_ travel: CGFloat, in browser: Browser) -> CGFloat {
        if browser.newSpaceSwipe || (SpaceComparison.zen && browser.spaces.count > 1) { return travel }
        let here = browser.makingSpace ? browser.spaces.count : (browser.spaces.firstIndex { $0.id == browser.spaceID } ?? 0)
        let blocked = browser.prefs.sidebar ? (travel > 0 && here == 0) : (travel > 0 && here == 0)
        return blocked ? travel / 4 : travel
    }

    /// The pages carry on the way the fingers went until the next one is
    /// where this one was; then it becomes the one on screen, in the same
    /// frame and without anything moving — it was already there. One past
    /// the last space is an empty new page.
    func slide(_ browser: Browser, to target: Int, from here: Int, direction: Int? = nil) {
        if browser.makingSpace, target != browser.spaces.count {
            browser.cancelSpaceCreation()
        }
        let turn = UUID()
        browser.spaceSlideToken = turn
        let creating = target == browser.spaces.count
        let destination = browser.spaces.indices.contains(target) ? browser.spaces[target].id : nil
        // A page is the column's width, or the bar's height.
        let width = browser.prefs.sidebar ? browser.prefs.columnWidth : Metrics.strip
        browser.newSpaceSwipe = !SpaceComparison.zen && browser.prefs.sidebar && creating
        let away: CGFloat = (direction ?? (target > here ? 1 : -1)) > 0 ? -1 : 1
        browser.spaceStep = target > here ? 1 : -1
        resting = Date().addingTimeInterval(SpaceSwipe.rest)
        withAnimation(.easeOut(duration: 0.22), completionCriteria: .removed) {
            browser.spaceSwipe = away * width
        } completion: {
            guard browser.spaceSlideToken == turn else { return }
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                if creating {
                    browser.addInstantSpace()
                } else if let destination, browser.spaces.contains(where: { $0.id == destination }) {
                    browser.makingSpace = false
                    browser.prefs.usesSpaces = true
                    browser.switchSpace(to: destination)
                }
                browser.spaceSwipe = 0
                browser.newSpaceSwipe = false
            }
        }
    }
}

/// An empty neighboring page during the swipe; creation never asks for setup.
struct NewSpaceCard: View {
    @ObservedObject var browser: Browser
    var inline = false
    var body: some View {
        Color.clear.frame(width: inline ? 180 : nil, height: inline ? Metrics.strip : nil)
    }
}
