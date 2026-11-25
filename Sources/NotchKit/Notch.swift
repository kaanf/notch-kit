//
//  Notch.swift
//  NotchKit
//
//  Created by Kaan Firat.
//

import AppKit
import SwiftUI

/// Fixed measurements of a notch, chosen by the app.
public struct NotchConfiguration {
    /// Black added beside the notch on each side when closed; the compact
    /// content on each side gets this width.
    public var wingWidth: CGFloat = 50
    /// Height added under the closed notch while peeking.
    public var peekHeight: CGFloat = 22
    /// Takes the notch off screen while its display shows a full-screen
    /// Space, and puts it back afterwards. Off by default: the notch stays.
    public var hidesInFullscreen = false
    /// The sides of the notch whose free menu bar space is measured, for
    /// `Notch.clearance`. None by default. The leading side needs
    /// Accessibility permission, which NotchKit never asks for itself; the
    /// trailing side needs none.
    public var measuredSides: NotchSides = []

    /// The defaults; change the properties you need.
    public init() {}
}

/// A horizontal two-finger swipe on the notch, in finger direction.
public enum NotchSwipe {
    /// The fingers moved left.
    case left
    /// The fingers moved right.
    case right
}

/// The app's presence in the notch, and the one place that decides what it
/// shows and when it opens.
///
/// Closed, it is a black extension of the camera notch with the app's
/// compact content in a wing on each side. If it measures the menu bar
/// (`NotchConfiguration.measuredSides`) and finds no room for the wings, it
/// shows the app's line in a small chin under the notch instead. On hover, click, a downward
/// swipe or `toggleExpanded()` it opens into the expanded content. On a
/// screen without a camera notch, a notch-sized stand-in at the top centre
/// of the main screen takes its place.
///
/// Create and use it on the main thread, after the app has launched.
@MainActor
public final class Notch {
    /// Called when the notch opens, for the app to refresh what it shows.
    public var onExpand: (() -> Void)? {
        didSet { surface.onExpand = onExpand }
    }

    /// Called for a horizontal two-finger swipe on the notch.
    public var onSwipe: ((NotchSwipe) -> Void)? {
        didSet { surface.onSwipe = onSwipe }
    }

    /// The size of the expanded content, which sits below the notch's own
    /// height. It may change while the notch is open.
    public var expandedContentSize: CGSize {
        get { surface.expandedContentSize }
        set { surface.expandedContentSize = newValue }
    }

    /// The free menu bar space beside the notch for the frontmost app, on
    /// the sides `NotchConfiguration.measuredSides` names. Measured while
    /// the notch is showing, when the frontmost app changes.
    public var clearance: NotchClearance { clearanceOverride ?? clearanceMonitor.clearance }

    /// Called when `clearance` changes.
    public var onClearanceChange: ((NotchClearance) -> Void)?

    /// Stands in for the measured clearance, to try the notch with and
    /// without room; nil goes back to measuring.
    @_spi(Testing) public var clearanceOverride: NotchClearance? {
        didSet { clearanceChanged() }
    }

    /// Whether the notch is on screen, open or closed.
    public var isVisible: Bool { surface.isShown }
    /// Whether the notch is open.
    public var isExpanded: Bool { surface.isExpanded }

    /// One surface, on the screen `NotchGeometry.current` picks. Surfaces
    /// are per screen, so showing on several is a matter of holding more.
    private let surface: NotchSurface
    private let configuration: NotchConfiguration
    private let clearanceMonitor: ClearanceMonitor
    /// What a wing takes beside the notch, outward corner included.
    private let wingFootprint: CGFloat
    /// The app asked for the notch, but a full-screen Space is keeping it away.
    private var hiddenForFullscreen = false
    private var screenObserver: Any?
    private var spaceObserver: Any?

    /// - Parameters:
    ///   - compactLeading: Shown in the wing left of the closed notch.
    ///   - compactTrailing: Shown in the wing right of the closed notch.
    ///   - compactLine: Shown in place of the wings when the menu bar has
    ///     no room for them: a strip 3 points high under the notch.
    ///   - expanded: Shown when the notch is open, sized by `expandedContentSize`.
    ///   - peek: Shown under the closed notch during `peek(for:)`.
    ///   - menu: The items of the notch's right-click menu.
    public init<Leading: View, Trailing: View, Line: View, Expanded: View, Peek: View, Menu: View>(
        configuration: NotchConfiguration = NotchConfiguration(),
        @ViewBuilder compactLeading: () -> Leading,
        @ViewBuilder compactTrailing: () -> Trailing,
        @ViewBuilder compactLine: () -> Line = { EmptyView() },
        @ViewBuilder expanded: () -> Expanded,
        @ViewBuilder peek: () -> Peek = { EmptyView() },
        @ViewBuilder menu: () -> Menu = { EmptyView() }
    ) {
        let content = NotchContent(compactLeading: AnyView(compactLeading()), compactTrailing: AnyView(compactTrailing()),
                                   compactLine: AnyView(compactLine()),
                                   expanded: AnyView(expanded()), peek: AnyView(peek()), menu: AnyView(menu()))
        self.configuration = configuration
        surface = NotchSurface(configuration: configuration, content: content)
        wingFootprint = configuration.wingWidth + NotchLayout.closedRadii.top
        clearanceMonitor = ClearanceMonitor(sides: configuration.measuredSides, probeWidth: wingFootprint)
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
        // A new full-screen Space doesn't always pick the panel up, so
        // bring it forward again whenever the Space changes.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.spaceChanged() }
        }
        clearanceMonitor.onChange = { [weak self] _ in self?.clearanceChanged() }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
    }

    /// Puts the notch on screen, closed. Does nothing if it's already there.
    public func show() {
        guard let geometry = NotchGeometry.current else { return hide() }
        if configuration.hidesInFullscreen, FullscreenDetector.isFullscreen(displayID: geometry.displayID) {
            hiddenForFullscreen = true
            return surface.hide()
        }
        hiddenForFullscreen = false
        surface.show(at: geometry)
        clearanceMonitor.start()
    }

    /// Takes the notch off screen.
    public func hide() {
        hiddenForFullscreen = false
        surface.hide()
        clearanceMonitor.stop()
    }

    /// Opens the notch and holds it open, or closes it if it's open: the
    /// action for a global shortcut. Beeps when the notch isn't showing.
    public func toggleExpanded() {
        surface.toggleFromKeyboard()
    }

    /// Shows the peek content under the closed notch for `duration` seconds.
    /// Ignored while the notch is open or hidden.
    public func peek(for duration: TimeInterval) {
        surface.peek(for: duration)
    }

    /// Brings the wings out for `duration` seconds even when the menu bar
    /// has no room for them, for an event worth showing. A peek running at
    /// the same time ends with them. Ignored while the notch is open or
    /// hidden; with room the wings are there anyway.
    public func showWings(for duration: TimeInterval) {
        surface.showWings(for: duration)
    }

    private func clearanceChanged() {
        let clearance = clearance
        surface.setWingsFit(CompactPolicy.wingsFit(clearance: clearance, footprint: wingFootprint))
        onClearanceChange?(clearance)
    }

    private func spaceChanged() {
        if configuration.hidesInFullscreen {
            recheckFullscreen()
            // The backdrop that marks a full-screen Space can land a moment
            // after the Space change is announced.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.fullscreenRecheckDelay) { [weak self] in
                self?.recheckFullscreen()
            }
        }
        surface.bringForward()
    }

    private static let fullscreenRecheckDelay: TimeInterval = 0.5

    /// Hides or restores the notch for the Space now showing, if the app
    /// wants it on screen at all.
    private func recheckFullscreen() {
        guard surface.isShown || hiddenForFullscreen else { return }
        show()
    }

    private func screensChanged() {
        clearanceMonitor.invalidate()
        if hiddenForFullscreen { return recheckFullscreen() }
        guard surface.isShown else { return }
        guard let geometry = NotchGeometry.current else { return hide() }
        surface.move(to: geometry)
    }
}
