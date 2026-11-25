//
//  NotchSurface.swift
//  NotchKit
//
//  Created by Kaan Firat.
//

import AppKit
import Combine
import SwiftUI

/// The notch on one screen: its panel, and the hover, click and gesture
/// handling that opens and closes it. `Notch` decides which screen gets one.
@MainActor
final class NotchSurface {
    /// Called when the notch opens.
    var onExpand: (() -> Void)?
    /// Called when the notch closes.
    var onCollapse: (() -> Void)?
    /// Asked before the notch opens, when it shares the notch with other
    /// apps: `summoned` for a shortcut or `expand(held:)`, which may take
    /// the panel from another app. False keeps it closed; true is followed,
    /// now or shortly, by `openGranted()` or `openRevoked()`.
    var openGate: ((_ summoned: Bool) -> Bool)?
    /// Called when the notch closes or stops waiting to open, for the
    /// other apps to be told.
    var onRelease: (() -> Void)?
    var onSwipe: ((NotchSwipe) -> Void)?
    var onKeyDown: ((NSEvent) -> Bool)? {
        didSet { panel?.onKeyDown = onKeyDown }
    }

    private let content: NotchContent
    private let state = NotchState()
    private var peekEnd: DispatchWorkItem?
    private var wingsEnd: DispatchWorkItem?
    /// Counts closed-shape changes, so only the latest one trims the window.
    private var settleGeneration = 0
    /// Accumulated trackpad travel in the current two-finger gesture, in
    /// finger direction (down and right are positive).
    private var gestureTravel = CGPoint.zero
    private var gestureHandled = false
    private var panel: NotchPanel?
    private var geometry: NotchGeometry?
    private var hoverTimer: Timer?
    private var pendingExpand: DispatchWorkItem?
    private var pendingCollapse: DispatchWorkItem?
    private var outsideClickMonitor: Any?
    /// The pill under the notch, in a window of its own so the notch's
    /// window needn't grow over the menu bar to hold it.
    private var requestPanel: NotchPanel?
    private var requestSync: AnyCancellable?
    /// Opening on purpose takes the keyboard.
    private let takesKeyboardFocus: Bool
    private var keyObservers: [Any] = []
    /// The app's own window that had the keyboard before the notch took it.
    private weak var previousKeyWindow: NSWindow?
    /// Pointer-entered events before this are ignored; see `giveBackKeyboardFocus()`.
    private var hoverIgnoredUntil = Date.distantPast
    /// An opening waiting on the other apps in the notch, and whether it
    /// was deliberate.
    private var pendingOpen: Bool?
    /// Where the closed notch is heading. The view's copy follows, a moment
    /// later when the change animates; changes build on this one, so two
    /// made in the same moment both count.
    private var compact = CompactState()

    /// Opened from the keyboard: stays open until the pointer has been in
    /// and out, the shortcut is pressed again, or a click lands elsewhere.
    private var heldOpen = false {
        didSet { syncOutsideClickWatch() }
    }

    /// The notch has the keyboard, and stays open for as long as it does.
    private var hasKeyboardFocus: Bool { takesKeyboardFocus && panel?.isKeyWindow == true }

    enum Timing {
        /// Hover this long before opening, so sweeping the pointer across
        /// the top of the screen doesn't pop the notch open.
        static let openDelay: TimeInterval = 0.3
        static let closeDelay: TimeInterval = 0.1
        /// Opening overshoots a little; closing settles without a bounce.
        static let open = Animation.spring(response: 0.42, dampingFraction: 0.8)
        static let close = Animation.spring(response: 0.45, dampingFraction: 1.0)
        /// How long `close` takes to come to rest, before the window shrinks.
        static let closeSettle: TimeInterval = 0.5
        /// Wings melting into the line and growing back out of it.
        static let melt = Animation.spring(response: 0.5, dampingFraction: 0.86)
        static let requestFade: TimeInterval = 0.2
    }

    var isShown: Bool { panel?.isVisible == true }
    var isExpanded: Bool { state.expanded }

    var expandedContentSize: CGSize {
        get { state.layout.expandedContentSize }
        set {
            guard state.layout.expandedContentSize != newValue else { return }
            state.layout.expandedContentSize = newValue
            if state.expanded { place(currentFrame) }
        }
    }

    init(configuration: NotchConfiguration, content: NotchContent) {
        self.content = content
        state.layout.wingWidth = configuration.wingWidth
        state.layout.peekHeight = configuration.peekHeight
        state.layout.requestSize = configuration.requestSize
        takesKeyboardFocus = configuration.keyboardFocus == .whenOpenedDeliberately
        requestSync = state.$expanded.combineLatest(state.$compact).sink { [weak self] expanded, compact in
            self?.syncRequestPill(expanded: expanded, compact: compact)
        }
    }

    deinit {
        keyObservers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Shows the notch at `geometry`, closed if it wasn't showing.
    func show(at geometry: NotchGeometry) {
        let panel = self.panel ?? makePanel()
        if geometry != self.geometry {
            self.geometry = geometry
            state.layout.notch = geometry.rect.size
            if panel.isVisible { place(currentFrame) }
        }
        if !panel.isVisible {
            state.expanded = false
            compact.peeking = false
            compact.wingsForced = false
            state.compact = compact
            place(currentFrame)
            panel.orderFrontRegardless()
        }
        syncRequestPill()
    }

    func hide() {
        let wasExpanded = state.expanded
        heldOpen = false
        pendingOpen = nil
        cancelPending()
        peekEnd?.cancel()
        wingsEnd?.cancel()
        watchHover(false)
        state.expanded = false
        compact.peeking = false
        compact.wingsForced = false
        state.compact = compact
        panel?.orderOut(nil)
        previousKeyWindow = nil
        syncRequestPill()
        onRelease?()
        if wasExpanded { onCollapse?() }
    }

    /// Follows the notch to where the screens put it now.
    func move(to geometry: NotchGeometry) {
        self.geometry = geometry
        state.layout.notch = geometry.rect.size
        place(currentFrame)
        syncRequestPill()
    }

    /// A new full-screen Space doesn't always pick the panel up.
    func bringForward() {
        guard isShown else { return }
        panel?.orderFrontRegardless()
        syncRequestPill()
    }

    /// Shows the peek content under the closed notch for `duration`.
    func peek(for duration: TimeInterval) {
        guard let panel, panel.isVisible, !state.expanded else { return }
        peekEnd?.cancel()
        if !compact.peeking {
            var next = compact
            next.peeking = true
            setCompact(next, animation: Timing.open)
        }
        let end = DispatchWorkItem { [weak self] in self?.endPeek() }
        peekEnd = end
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: end)
    }

    private func endPeek() {
        guard compact.peeking, !state.expanded else { return }
        var next = compact
        next.peeking = false
        setCompact(next, animation: Timing.close)
    }

    /// Brings the wings out for `duration` even without room for them.
    func showWings(for duration: TimeInterval) {
        guard let panel, panel.isVisible, !state.expanded else { return }
        wingsEnd?.cancel()
        if !compact.wingsForced {
            var next = compact
            next.wingsForced = true
            setCompact(next, animation: Timing.open)
        }
        let end = DispatchWorkItem { [weak self] in self?.endForcedWings() }
        wingsEnd = end
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: end)
    }

    private func endForcedWings() {
        guard compact.wingsForced else { return }
        let next = compact.afterForcedWings
        if next.peeking != compact.peeking { peekEnd?.cancel() }
        setCompact(next, animation: Timing.close)
    }

    /// Whether the menu bar has room for the wings right now.
    func setWingsFit(_ fit: Bool) {
        guard compact.wingsFit != fit else { return }
        var next = compact
        next.wingsFit = fit
        setCompact(next, animation: Timing.close)
    }

    /// Moves the closed notch to another state. As when opening: the window
    /// first grows to hold both shapes, then the change animates inside it,
    /// then the window is trimmed to the new shape.
    private func setCompact(_ next: CompactState, animation: Animation) {
        guard next != compact else { return }
        // Wings coming or going is the slower, softer change.
        let animation = next.showsWings != compact.showsWings ? Timing.melt : animation
        compact = next
        guard let panel, panel.isVisible, !state.expanded else {
            // Out of sight; it applies when the notch next closes or shows.
            state.compact = next
            return
        }
        let target = frame(expanded: false, compact: next)
        place(panel.frame.union(target))
        panel.contentView?.layoutSubtreeIfNeeded()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            withAnimation(Self.animation(animation)) { self.state.compact = self.compact }
        }
        shrinkWindowWhenSettled()
    }

    private static func animation(_ animation: Animation) -> Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : animation
    }

    /// From a global shortcut: open the notch, or close it if it's open.
    func toggleFromKeyboard() {
        guard isShown else { return NSSound.beep() }
        if state.expanded || pendingOpen != nil { collapse() } else { expand(held: true) }
    }

    /// Opens the notch on the app's say-so; if it's open already, only the
    /// hold and the keyboard change.
    func expand(held: Bool) {
        guard isShown else { return }
        cancelPending()
        heldOpen = held
        if state.expanded { takeKeyboardFocus() } else { requestOpen(deliberately: true, summoned: true) }
    }

    func collapse() {
        cancelPending()
        heldOpen = false
        abandonPendingOpen()
        setExpanded(false)
    }

    // MARK: - Sharing the notch

    /// The halves of the notch this app draws, and whether it steps aside
    /// altogether for another app's open panel.
    func setArrangement(sides: NotchSides, yielded: Bool) {
        var next = compact
        next.sides = sides
        next.yielded = yielded
        setCompact(next, animation: Timing.close)
    }

    /// Opens, once the other apps in the notch allow it.
    private func requestOpen(deliberately: Bool, summoned: Bool) {
        guard !state.expanded else { return }
        guard let openGate else { return setExpanded(true, deliberately: deliberately) }
        pendingOpen = deliberately
        if !openGate(summoned) { pendingOpen = nil }
    }

    /// The other apps have made way for the opening that was asked for.
    func openGranted() {
        guard let deliberately = pendingOpen else { return }
        pendingOpen = nil
        // A hover that has moved on while waiting no longer wants it.
        guard isShown, deliberately || pointerInside else {
            onRelease?()
            return
        }
        setExpanded(true, deliberately: deliberately)
    }

    /// Another app has the panel after all: close, or stop waiting to open.
    func openRevoked() {
        cancelPending()
        heldOpen = false
        abandonPendingOpen()
        setExpanded(false)
    }

    private func abandonPendingOpen() {
        guard pendingOpen != nil else { return }
        pendingOpen = nil
        onRelease?()
    }

    // MARK: - Request pill

    func setRequested(_ requested: Bool) {
        guard compact.requested != requested else { return }
        compact.requested = requested
        state.compact.requested = requested
    }

    private func syncRequestPill() {
        syncRequestPill(expanded: state.expanded, compact: state.compact)
    }

    /// Shows the pill when the closed notch calls for it, and hides it
    /// otherwise; and keeps the notch's own window out of the pointer's
    /// way while it has nothing to show.
    private func syncRequestPill(expanded: Bool, compact: CompactState) {
        // Stepping aside for another app's panel, this one mustn't take
        // the clicks meant for it.
        panel?.ignoresMouseEvents = !expanded && compact.yielded
        guard let panel, panel.isVisible else {
            requestPanel?.orderOut(nil)
            requestPanel?.alphaValue = 0
            return
        }
        guard !expanded, compact.showsRequestPill, let notch = geometry?.rect else {
            if let requestPanel { fade(requestPanel, to: 0) }
            return
        }
        let pill = requestPanel ?? makeRequestPanel()
        pill.setFrame(state.layout.requestFrame(notchRect: notch), display: true)
        // Under the notch's window, so the shape closing over it uncovers it.
        pill.order(.below, relativeTo: panel.windowNumber)
        fade(pill, to: 1)
    }

    private func fade(_ pill: NSPanel, to alpha: CGFloat) {
        guard pill.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : Timing.requestFade
            pill.animator().alphaValue = alpha
        } completionHandler: {
            MainActor.assumeIsolated {
                // Unless it was asked back in the meantime.
                if pill.alphaValue == 0 { pill.orderOut(nil) }
            }
        }
    }

    private func makeRequestPanel() -> NotchPanel {
        let pill = NotchPanel()
        pill.alphaValue = 0
        pill.contentView = FirstMouseHostingView(rootView: RequestPillView(content: content.request,
                                                                           onTap: { [weak self] in self?.clicked() }))
        requestPanel = pill
        return pill
    }

    // MARK: - Keyboard focus

    private func takeKeyboardFocus() {
        guard takesKeyboardFocus, let panel, !panel.isKeyWindow else { return }
        previousKeyWindow = NSApp.keyWindow
        panel.makeKey()
    }

    /// Hands the keyboard back to whoever had it before the notch.
    private func giveBackKeyboardFocus() {
        guard takesKeyboardFocus, let panel, panel.isKeyWindow else { return }
        if let previous = previousKeyWindow, previous.isVisible {
            previous.makeKey()
        } else {
            // Another app had the keyboard, and a panel that stays on screen
            // has no way to hand it back; leaving and returning does. If the
            // pointer is resting on the notch, coming back reports it as
            // newly entered, which mustn't open the notch again.
            hoverIgnoredUntil = Date().addingTimeInterval(Timing.closeSettle)
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
        previousKeyWindow = nil
    }

    /// Losing the keyboard to another window ends what it was holding open.
    private func keyStatusChanged() {
        guard takesKeyboardFocus else { return }
        syncOutsideClickWatch()
        guard let panel, !panel.isKeyWindow, state.expanded else { return }
        heldOpen = false
        if !pointerInside { setExpanded(false) }
    }

    // MARK: - Opening and closing

    private func pointerEntered() {
        heldOpen = false
        cancelCollapse()
        guard !state.expanded, Date() >= hoverIgnoredUntil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.pointerInside else { return }
            self.requestOpen(deliberately: false, summoned: false)
        }
        pendingExpand = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.openDelay, execute: work)
    }

    private func pointerExited() {
        pendingExpand?.cancel()
        scheduleCollapse()
    }

    private func clicked() {
        pendingExpand?.cancel()
        requestOpen(deliberately: true, summoned: false)
    }

    /// Two-finger swipes on the notch: down opens, up closes, left and
    /// right are the app's. One action per gesture; momentum is ignored.
    private func scrolled(_ event: NSEvent) {
        guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return }
        if event.phase == .began {
            gestureTravel = .zero
            gestureHandled = false
        }
        // In finger direction, whichever way scrolling is set to run.
        let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        gestureTravel.x += event.scrollingDeltaX * sign
        gestureTravel.y += event.scrollingDeltaY * sign
        defer {
            if event.phase == .ended || event.phase == .cancelled { gestureHandled = false }
        }
        guard !gestureHandled else { return }

        let (x, y) = (gestureTravel.x, gestureTravel.y)
        if abs(y) > abs(x), y > 30, !state.expanded {
            gestureHandled = true
            clicked()
        } else if abs(y) > abs(x), y < -30, state.expanded {
            gestureHandled = true
            heldOpen = false
            setExpanded(false)
        } else if abs(x) > 50, abs(x) > abs(y) * 1.5 {
            gestureHandled = true
            Self.haptic()
            onSwipe?(x < 0 ? .left : .right)
        }
    }

    private static func haptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    private func scheduleCollapse() {
        guard state.expanded, !heldOpen, !hasKeyboardFocus, pendingCollapse == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingCollapse = nil
            if !self.pointerInside { self.setExpanded(false) }
        }
        pendingCollapse = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.closeDelay, execute: work)
    }

    /// Opening deliberately, rather than on hover, may take the keyboard.
    private func setExpanded(_ expanded: Bool, deliberately: Bool = false) {
        guard let panel, state.expanded != expanded else { return }
        if expanded {
            peekEnd?.cancel()
            wingsEnd?.cancel()
            // Grow the window first and settle the layout at that size without
            // animation; otherwise the re-centring animates too and the shape
            // flies in from the old window's corner. Then open inside it.
            place(frame(expanded: true))
            panel.contentView?.layoutSubtreeIfNeeded()
            if deliberately { takeKeyboardFocus() }
            compact.peeking = false
            compact.wingsForced = false
            DispatchQueue.main.async { [weak self] in
                withAnimation(Self.animation(Timing.open)) {
                    self?.state.expanded = true
                    self?.state.compact.peeking = false
                    self?.state.compact.wingsForced = false
                }
            }
            Self.haptic()
            watchHover(true)
            onExpand?()
        } else {
            watchHover(false)
            withAnimation(Self.animation(Timing.close)) { state.expanded = false }
            shrinkWindowWhenSettled()
            giveBackKeyboardFocus()
            onRelease?()
            onCollapse?()
        }
    }

    /// Shrinks the window once the shape has, so the transparent area around
    /// it never blocks clicks on the menu bar.
    private func shrinkWindowWhenSettled() {
        settleGeneration += 1
        let generation = settleGeneration
        let delay = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : Timing.closeSettle
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, generation == self.settleGeneration, !self.state.expanded else { return }
            self.place(self.currentFrame)
        }
    }

    /// Collapses when the pointer has really left, in case an exit event was
    /// missed while the window resized under it.
    private func watchHover(_ on: Bool) {
        hoverTimer?.invalidate()
        hoverTimer = nil
        guard on else { return }
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.pointerInside else { return }
                self.scheduleCollapse()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    /// While held open, from the keyboard or by having it, a click anywhere
    /// else closes it, as a click outside a popover would.
    private func syncOutsideClickWatch() {
        let on = heldOpen || hasKeyboardFocus
        guard on != (outsideClickMonitor != nil) else { return }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        guard on else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.pointerInside else { return }
                self.heldOpen = false
                self.setExpanded(false)
            }
        }
    }

    private var pointerInside: Bool {
        guard let panel, panel.isVisible else { return false }
        return panel.frame.contains(NSEvent.mouseLocation)
    }

    private func cancelPending() {
        pendingExpand?.cancel()
        cancelCollapse()
    }

    /// Cancels a scheduled collapse and forgets it. A cancelled item left in
    /// `pendingCollapse` would block every later collapse from scheduling.
    private func cancelCollapse() {
        pendingCollapse?.cancel()
        pendingCollapse = nil
    }

    // MARK: - Window

    private var currentFrame: CGRect { frame(expanded: state.expanded) }

    private func frame(expanded: Bool) -> CGRect {
        frame(expanded: expanded, compact: compact)
    }

    private func frame(expanded: Bool, compact: CompactState) -> CGRect {
        guard let notch = geometry?.rect else { return .zero }
        return state.layout.windowFrame(notchRect: notch, expanded: expanded, peeking: compact.peeking,
                                        wings: compact.showsWings, sides: compact.sides)
    }

    /// Moves the window, telling the view where the notch now is inside it.
    private func place(_ frame: CGRect) {
        guard let panel, let notch = geometry?.rect else { return }
        let drift = notch.midX - frame.midX
        if state.drift != drift { state.drift = drift }
        panel.setFrame(frame, display: true)
    }

    private func makePanel() -> NotchPanel {
        let panel = NotchPanel()
        let container = NotchContainerView()
        container.onPointerEntered = { [weak self] in self?.pointerEntered() }
        container.onPointerExited = { [weak self] in self?.pointerExited() }
        let hosting = FirstMouseHostingView(rootView: NotchView(state: state, content: content, onTap: { [weak self] _ in self?.clicked() }))
        hosting.onScroll = { [weak self] event in self?.scrolled(event) }
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container
        hosting.frame = container.bounds
        panel.onKeyDown = onKeyDown
        keyObservers = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.keyStatusChanged() }
            }
        }
        self.panel = panel
        return panel
    }
}
