//
//  NotchSurface.swift
//  NotchKit
//
//  Created by Kaan Firat.
//

import AppKit
import SwiftUI

/// The notch on one screen: its panel, and the hover, click and gesture
/// handling that opens and closes it. `Notch` decides which screen gets one.
@MainActor
final class NotchSurface {
    /// Called when the notch opens.
    var onExpand: (() -> Void)?
    var onSwipe: ((NotchSwipe) -> Void)?

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

    /// Opened from the keyboard: stays open until the pointer has been in
    /// and out, the shortcut is pressed again, or a click lands elsewhere.
    private var heldOpen = false {
        didSet { watchOutsideClicks(heldOpen) }
    }

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
    }

    var isShown: Bool { panel?.isVisible == true }
    var isExpanded: Bool { state.expanded }

    var expandedContentSize: CGSize {
        get { state.layout.expandedContentSize }
        set {
            guard state.layout.expandedContentSize != newValue else { return }
            state.layout.expandedContentSize = newValue
            if state.expanded { panel?.setFrame(currentFrame, display: true) }
        }
    }

    init(configuration: NotchConfiguration, content: NotchContent) {
        self.content = content
        state.layout.wingWidth = configuration.wingWidth
        state.layout.peekHeight = configuration.peekHeight
    }

    /// Shows the notch at `geometry`, closed if it wasn't showing.
    func show(at geometry: NotchGeometry) {
        let panel = self.panel ?? makePanel()
        if geometry != self.geometry {
            self.geometry = geometry
            state.layout.notch = geometry.rect.size
            if panel.isVisible { panel.setFrame(currentFrame, display: true) }
        }
        if !panel.isVisible {
            state.expanded = false
            state.compact.peeking = false
            state.compact.wingsForced = false
            panel.setFrame(currentFrame, display: true)
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        heldOpen = false
        cancelPending()
        peekEnd?.cancel()
        wingsEnd?.cancel()
        watchHover(false)
        state.expanded = false
        state.compact.peeking = false
        state.compact.wingsForced = false
        panel?.orderOut(nil)
    }

    /// Follows the notch to where the screens put it now.
    func move(to geometry: NotchGeometry) {
        self.geometry = geometry
        state.layout.notch = geometry.rect.size
        panel?.setFrame(currentFrame, display: true)
    }

    /// A new full-screen Space doesn't always pick the panel up.
    func bringForward() {
        guard isShown else { return }
        panel?.orderFrontRegardless()
    }

    /// Shows the peek content under the closed notch for `duration`.
    func peek(for duration: TimeInterval) {
        guard let panel, panel.isVisible, !state.expanded else { return }
        peekEnd?.cancel()
        if !state.compact.peeking {
            var next = state.compact
            next.peeking = true
            setCompact(next, animation: Timing.open)
        }
        let end = DispatchWorkItem { [weak self] in self?.endPeek() }
        peekEnd = end
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: end)
    }

    private func endPeek() {
        guard state.compact.peeking, !state.expanded else { return }
        var next = state.compact
        next.peeking = false
        setCompact(next, animation: Timing.close)
    }

    /// Brings the wings out for `duration` even without room for them.
    func showWings(for duration: TimeInterval) {
        guard let panel, panel.isVisible, !state.expanded else { return }
        wingsEnd?.cancel()
        if !state.compact.wingsForced {
            var next = state.compact
            next.wingsForced = true
            setCompact(next, animation: Timing.open)
        }
        let end = DispatchWorkItem { [weak self] in self?.endForcedWings() }
        wingsEnd = end
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: end)
    }

    private func endForcedWings() {
        guard state.compact.wingsForced else { return }
        let next = state.compact.afterForcedWings
        if next.peeking != state.compact.peeking { peekEnd?.cancel() }
        setCompact(next, animation: Timing.close)
    }

    /// Whether the menu bar has room for the wings right now.
    func setWingsFit(_ fit: Bool) {
        guard state.compact.wingsFit != fit else { return }
        var next = state.compact
        next.wingsFit = fit
        setCompact(next, animation: Timing.close)
    }

    /// Moves the closed notch to another state. As when opening: the window
    /// first grows to hold both shapes, then the change animates inside it,
    /// then the window is trimmed to the new shape.
    private func setCompact(_ next: CompactState, animation: Animation) {
        guard next != state.compact else { return }
        guard let panel, panel.isVisible, !state.expanded else {
            // Out of sight; it applies when the notch next closes or shows.
            state.compact = next
            return
        }
        let target = frame(expanded: false, compact: next)
        panel.setFrame(panel.frame.union(target), display: true)
        panel.contentView?.layoutSubtreeIfNeeded()
        // Wings coming or going is the slower, softer change.
        let animation = next.showsWings != state.compact.showsWings ? Timing.melt : animation
        DispatchQueue.main.async { [weak self] in
            withAnimation(Self.animation(animation)) { self?.state.compact = next }
        }
        shrinkWindowWhenSettled()
    }

    private static func animation(_ animation: Animation) -> Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : animation
    }

    /// From a global shortcut: open the notch, or close it if it's open.
    func toggleFromKeyboard() {
        guard isShown else { return NSSound.beep() }
        cancelPending()
        if state.expanded {
            heldOpen = false
            setExpanded(false)
        } else {
            heldOpen = true
            setExpanded(true)
        }
    }

    // MARK: - Opening and closing

    private func pointerEntered() {
        heldOpen = false
        cancelCollapse()
        guard !state.expanded else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.pointerInside else { return }
            self.setExpanded(true)
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
        if !state.expanded { setExpanded(true) }
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
        guard state.expanded, !heldOpen, pendingCollapse == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingCollapse = nil
            if !self.pointerInside { self.setExpanded(false) }
        }
        pendingCollapse = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.closeDelay, execute: work)
    }

    private func setExpanded(_ expanded: Bool) {
        guard let panel, state.expanded != expanded else { return }
        if expanded {
            peekEnd?.cancel()
            wingsEnd?.cancel()
            // Grow the window first and settle the layout at that size without
            // animation; otherwise the re-centring animates too and the shape
            // flies in from the old window's corner. Then open inside it.
            panel.setFrame(frame(expanded: true), display: true)
            panel.contentView?.layoutSubtreeIfNeeded()
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
        }
    }

    /// Shrinks the window once the shape has, so the transparent area around
    /// it never blocks clicks on the menu bar.
    private func shrinkWindowWhenSettled() {
        settleGeneration += 1
        let generation = settleGeneration
        let delay = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : Timing.closeSettle
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let panel = self.panel, generation == self.settleGeneration, !self.state.expanded else { return }
            panel.setFrame(self.currentFrame, display: true)
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

    /// While held open from the keyboard, a click anywhere else closes it,
    /// as a click outside a popover would.
    private func watchOutsideClicks(_ on: Bool) {
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
        frame(expanded: expanded, compact: state.compact)
    }

    private func frame(expanded: Bool, compact: CompactState) -> CGRect {
        guard let notch = geometry?.rect else { return .zero }
        return state.layout.windowFrame(notchRect: notch, expanded: expanded, peeking: compact.peeking, wings: compact.showsWings)
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
        self.panel = panel
        return panel
    }
}
