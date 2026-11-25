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

    public init() {}
}

/// A horizontal two-finger swipe on the notch, in finger direction.
public enum NotchSwipe {
    case left, right
}

/// The app's presence in the notch, and the one place that decides what it
/// shows and when it opens.
///
/// Closed, it is a black extension of the camera notch with the app's
/// compact content in a wing on each side. On hover, click, a downward
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

    /// Whether the notch is on screen, open or closed.
    public var isVisible: Bool { surface.isShown }
    /// Whether the notch is open.
    public var isExpanded: Bool { surface.isExpanded }

    /// One surface, on the screen `NotchGeometry.current` picks. Surfaces
    /// are per screen, so showing on several is a matter of holding more.
    private let surface: NotchSurface
    private var screenObserver: Any?
    private var spaceObserver: Any?

    /// - Parameters:
    ///   - compactLeading: Shown in the wing left of the closed notch.
    ///   - compactTrailing: Shown in the wing right of the closed notch.
    ///   - expanded: Shown when the notch is open, sized by `expandedContentSize`.
    ///   - peek: Shown under the closed notch during `peek(for:)`.
    ///   - menu: The items of the notch's right-click menu.
    public init<Leading: View, Trailing: View, Expanded: View, Peek: View, Menu: View>(
        configuration: NotchConfiguration = NotchConfiguration(),
        @ViewBuilder compactLeading: () -> Leading,
        @ViewBuilder compactTrailing: () -> Trailing,
        @ViewBuilder expanded: () -> Expanded,
        @ViewBuilder peek: () -> Peek = { EmptyView() },
        @ViewBuilder menu: () -> Menu = { EmptyView() }
    ) {
        let content = NotchContent(compactLeading: AnyView(compactLeading()), compactTrailing: AnyView(compactTrailing()),
                                   expanded: AnyView(expanded()), peek: AnyView(peek()), menu: AnyView(menu()))
        surface = NotchSurface(configuration: configuration, content: content)
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
            MainActor.assumeIsolated { self?.surface.bringForward() }
        }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
    }

    /// Puts the notch on screen, closed. Does nothing if it's already there.
    public func show() {
        guard let geometry = NotchGeometry.current else { return hide() }
        surface.show(at: geometry)
    }

    /// Takes the notch off screen.
    public func hide() {
        surface.hide()
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

    private func screensChanged() {
        guard surface.isShown else { return }
        guard let geometry = NotchGeometry.current else { return hide() }
        surface.move(to: geometry)
    }
}
