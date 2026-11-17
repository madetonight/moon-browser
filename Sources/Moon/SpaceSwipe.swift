import SwiftUI

// The sidebar pages sideways, and the top bar pages vertically. Trackpad
// motion follows the fingers; the wheel and mouse buttons take one step.

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
    private var claimed = false
    /// The glide after a swipe that was taken, which is taken too.
    private var gliding = false
    private var gathered = CGSize.zero
    /// When the wheel last turned over the bar, whether a space came of it
    /// or not. A spin of the wheel is a run of notches close together, and
    /// it brings one space: the next waits for the wheel to have rested.
    private var notched = Date.distantPast

    /// How far the fingers have to go for the next space to come: 50
    /// points in the column; in a bar only 52 tall, most of its height, so
    /// that scrolling the page with the pointer a little high doesn't.
    static func enough(for browser: Browser) -> CGFloat {
        browser.prefs.sidebar ? 50 : Metrics.strip * 0.6
    }

    func start(for browser: Browser) {
        if !tracking { self.browser = browser }
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
        let here = index(in: browser)
        let target = destination(in: browser, from: here, offset: step)
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
            let rested = now.timeIntervalSince(notched) > 0.3
            notched = now
            guard rested else { return true }
            let here = index(in: browser)
            let offset = step < 0 ? 1 : -1
            let target = destination(in: browser, from: here, offset: offset)
            if target >= 0, target <= browser.spaces.count { slide(browser, to: target, from: here) }
            return true
        }
        if !event.momentumPhase.isEmpty { return gliding }
        switch event.phase {
        case .began:
            gliding = false
            // Only a gesture that starts over the tabs.
            guard overTabs(event, in: browser) else {
                tracking = false
                return false
            }
            began()
            return moved(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
        case .changed:
            guard tracking else { return false }
            return moved(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
        case .ended, .cancelled:
            guard tracking else { return false }
            let taken = claimed
            ended(cancelled: event.phase == .cancelled)
            gliding = taken
            return taken
        default:
            return false
        }
    }

    // MARK: - the gesture, apart from where its events come from (the bench drives these)

    func began() {
        axis = .undecided
        gathered = .zero
        claimed = false
        tracking = true
    }

    /// Capture sideways paging without intercepting vertical tab scrolling.
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
        guard claimed || browser.prefs.usesSpaces || (browser.prefs.sidebar && gathered.width < 0) else { return false }
        claimed = true
        guard browser.spacePaging.settlement == nil else { return true }
        let offset = gathered.width < 0 ? 1 : -1
        let here = index(in: browser)
        let next = destination(in: browser, from: here, offset: offset)
        let page = gathered.width == 0 ? browser.spacePaging.neighbor : neighbor(in: browser, target: next, direction: offset)
        let travel = gathered.width / extent(in: browser)
        // Limit the drag to one pane and give the leading edge resistance.
        let progress = page == nil ? travel * 0.24 : travel
        if browser.spacePaging.neighbor != page { prepare(page, in: browser) }
        browser.spacePaging.progress = Motion.reduced ? 0 : min(max(progress, -1), 1)
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
        guard let browser, claimed, browser.spacePaging.settlement == nil else { return }
        let travel = gathered.width
        let here = index(in: browser)
        let offset = travel < 0 ? 1 : -1
        let target = destination(in: browser, from: here, offset: offset)
        if cancelled || abs(travel) < Self.enough(for: browser) || target == here {
            settle(browser, toward: nil)
        } else {
            slide(browser, to: target, from: here, direction: offset)
        }
    }

    private func index(in browser: Browser) -> Int {
        browser.spaces.firstIndex { $0.id == browser.spaceID } ?? 0
    }

    private func destination(in browser: Browser, from here: Int, offset: Int) -> Int {
        SpaceComparison.zen ? ZenSpaceNavigation.destination(from: here, offset: offset, count: browser.spaces.count) : here + offset
    }

    private func extent(in browser: Browser) -> CGFloat {
        browser.prefs.sidebar ? max(1, browser.prefs.columnWidth) : Metrics.strip
    }

    private func neighbor(in browser: Browser, target: Int, direction: Int) -> SpacePaging.Neighbor? {
        if target == browser.spaces.count { return .init(destination: .new, direction: direction) }
        guard browser.spaces.indices.contains(target), browser.spaces[target].id != browser.spaceID else { return nil }
        return .init(destination: .existing(browser.spaces[target].id), direction: direction)
    }

    private func prepare(_ page: SpacePaging.Neighbor?, in browser: Browser) {
        if case .existing(let id)? = page?.destination, browser.parked[id] == nil {
            browser.parked[id] = browser.loadRow(id)
        }
        browser.spacePaging.neighbor = page
    }

    func select(_ id: UUID, in browser: Browser) {
        guard !browser.ghostWindow, browser.prefs.usesSpaces,
              let target = browser.spaces.firstIndex(where: { $0.id == id }) else { return }
        if browser.spacePaging.settlement != nil {
            browser.spacePaging.queued = id
            return
        }
        if browser.folded && !browser.peeking {
            browser.switchSpace(to: id)
        } else if id != browser.spaceID {
            slide(browser, to: target, from: index(in: browser))
        }
    }

    func slide(_ browser: Browser, to target: Int, from here: Int, direction: Int? = nil) {
        guard browser.spacePaging.settlement == nil else { return }
        if browser.makingSpace { browser.cancelSpaceCreation() }
        let direction = direction ?? (target > here ? 1 : -1)
        settle(browser, toward: neighbor(in: browser, target: target, direction: direction))
    }

    private func settle(_ browser: Browser, toward page: SpacePaging.Neighbor?) {
        let paging = browser.spacePaging
        guard page != nil || paging.progress != 0 || paging.neighbor != nil else { return }
        if let page, paging.neighbor != page {
            // An indicator can select a space several positions away.
            // Bring that pane in from offscreen instead of an adjacent space.
            paging.progress = 0
            prepare(page, in: browser)
        }
        let ticket = UUID()
        paging.settlement = ticket
        let end = page.map { -CGFloat($0.direction) } ?? 0
        let complete = { [weak self, weak browser] in
            guard let self, let browser, paging.settlement == ticket else { return }
            let queued = paging.queued
            var still = Transaction(animation: nil)
            still.disablesAnimations = true
            withTransaction(still) {
                if let page {
                    switch page.destination {
                    case .new: browser.addInstantSpace()
                    case .existing(let id): browser.switchSpace(to: id)
                    }
                }
                paging.reset()
            }
            if let queued { self.select(queued, in: browser) }
        }
        guard let animation = Motion.spacePaging(remaining: abs(end - paging.progress)), end != paging.progress else {
            complete()
            return
        }
        let animate = {
            guard paging.settlement == ticket else { return }
            withAnimation(animation, completionCriteria: .removed) {
                paging.progress = end
            } completion: {
                complete()
            }
        }
        // A clicked indicator inserts an incoming pane. Give that pane an
        // offscreen starting position before sending the animated endpoint.
        if let pane = paging.neighbor, paging.mounted != pane, browser.window?.isVisible == true {
            paging.afterMount = animate
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak paging] in
                guard let paging, paging.settlement == ticket else { return }
                paging.startWhenReady()
            }
        } else {
            animate()
        }
    }
}

/// Observe movement only where the two panes are placed. A trackpad event
/// does not invalidate Browser, its tab rows, or the WebKit stage.
@MainActor @Observable
final class SpacePaging {
    enum Destination: Hashable { case existing(UUID), new }
    struct Neighbor: Hashable {
        let destination: Destination
        let direction: Int
    }

    var progress: CGFloat = 0
    var neighbor: Neighbor?
    @ObservationIgnored var settlement: UUID?
    @ObservationIgnored var queued: UUID?
    @ObservationIgnored var mounted: Neighbor?
    @ObservationIgnored var afterMount: (() -> Void)?

    func startWhenReady() {
        let start = afterMount
        afterMount = nil
        start?()
    }

    func reset() {
        progress = 0
        neighbor = nil
        settlement = nil
        queued = nil
        mounted = nil
        afterMount = nil
    }
}

struct SpacePages<Current: View, Incoming: View>: View {
    let paging: SpacePaging
    let axis: Axis
    let extent: CGFloat
    @ViewBuilder let current: () -> Current
    @ViewBuilder let incoming: (SpacePaging.Destination) -> Incoming

    var body: some View {
        ZStack(alignment: .topLeading) {
            current()
                .modifier(SpacePageOffset(paging: paging, axis: axis, extent: extent, page: 0))
                .allowsHitTesting(paging.neighbor == nil)
            if let neighbor = paging.neighbor {
                incoming(neighbor.destination)
                    .modifier(SpacePageOffset(paging: paging, axis: axis, extent: extent, page: neighbor.direction))
                    .id(neighbor)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.identity)
                    .onAppear {
                        paging.mounted = neighbor
                        DispatchQueue.main.async {
                            if paging.neighbor == neighbor { paging.startWhenReady() }
                        }
                    }
                    .onDisappear {
                        if paging.mounted == neighbor { paging.mounted = nil }
                    }
            }
        }
    }
}

private struct SpacePageOffset: ViewModifier {
    let paging: SpacePaging
    let axis: Axis
    let extent: CGFloat
    let page: Int

    func body(content: Content) -> some View {
        let offset = (paging.progress + CGFloat(page)) * extent
        content.offset(x: axis == .horizontal ? offset : 0, y: axis == .vertical ? offset : 0)
    }
}

/// An empty neighboring page during the swipe; creation never asks for setup.
struct NewSpaceCard: View {
    var inline = false
    var body: some View {
        Color.clear.frame(width: inline ? 180 : nil, height: inline ? Metrics.strip : nil)
    }
}
