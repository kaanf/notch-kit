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
    /// Whether the open notch takes keyboard input. Never by default.
    public var keyboardFocus: NotchKeyboardFocus = .never
    /// The size of the request pill under the notch; see `Notch.showRequest()`.
    public var requestSize = CGSize(width: 220, height: 32)
    /// The app's place in a notch it shares with other NotchKit apps. Nil
    /// by default: the app has the notch to itself and looks for nobody.
    /// See `Notch.otherResidents`.
    public var residency: NotchResidency?

    /// The defaults; change the properties you need.
    public init() {}
}

/// When the open notch takes keyboard input.
public enum NotchKeyboardFocus {
    /// Never on its own; only a click on a text field inside it gives it
    /// the keyboard.
    case never
    /// When it was opened on purpose: by a click, a swipe down,
    /// `toggleExpanded()` or `expand(held:)`. Opening on hover takes
    /// nothing, so brushing the notch doesn't cut off typing elsewhere.
    /// While it has the keyboard the notch stays open with the pointer away,
    /// and on closing the keyboard goes back to where it was.
    case whenOpenedDeliberately
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
/// Other NotchKit apps may live in the same notch. With a residency
/// (`NotchConfiguration.residency`) the apps share it: half each while
/// closed, and one open panel between them; see `otherResidents`.
///
/// Create and use it on the main thread, after the app has launched.
@MainActor
public final class Notch {
    /// Called when the notch opens, for the app to refresh what it shows.
    public var onExpand: (() -> Void)? {
        didSet { surface.onExpand = onExpand }
    }

    /// Called when the notch closes, however it came to: the pointer left,
    /// `collapse()`, a click elsewhere, or `hide()` while open.
    public var onCollapse: (() -> Void)? {
        didSet { surface.onCollapse = onCollapse }
    }

    /// Called for a key press while the notch has keyboard focus, before
    /// anything in the notch sees it. Return true if the key was used;
    /// false passes it on, to a text field in the notch for one.
    public var onKeyDown: ((NSEvent) -> Bool)? {
        didSet { surface.onKeyDown = onKeyDown }
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

    /// The other apps in the notch whose notch is on screen, by id. Empty
    /// without `NotchConfiguration.residency`, and when there are none.
    ///
    /// With company, the closed notch is split down the middle: each app
    /// draws its own wing and its half of the line, and answers the pointer
    /// there only. One panel is open at a time. While another app's is,
    /// this one is out of sight, and hover and click don't open it; a
    /// shortcut or `expand(held:)` closes the other's panel and opens this.
    public var otherResidents: [NotchResident] { coordinator?.residents ?? [] }

    /// Called when `otherResidents` changes: an app came or went, opened or
    /// closed its panel, or put up or took down a request.
    public var onResidentsChange: (() -> Void)?

    /// Whether the notch is on screen, open or closed.
    public var isVisible: Bool { surface.isShown }
    /// Whether the notch is open.
    public var isExpanded: Bool { surface.isExpanded }

    /// One surface, on the screen `NotchGeometry.current` picks. Surfaces
    /// are per screen, so showing on several is a matter of holding more.
    private let surface: NotchSurface
    private let configuration: NotchConfiguration
    private let clearanceMonitor: ClearanceMonitor
    /// The app's seat among the apps that share the notch, if it took one.
    private let coordinator: ResidencyCoordinator?
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
    ///   - request: Shown in a pill under the notch after `showRequest()`,
    ///     sized by `NotchConfiguration.requestSize`.
    ///   - menu: The items of the notch's right-click menu.
    public init<Leading: View, Trailing: View, Line: View, Expanded: View, Peek: View, Request: View, Menu: View>(
        configuration: NotchConfiguration = NotchConfiguration(),
        @ViewBuilder compactLeading: () -> Leading,
        @ViewBuilder compactTrailing: () -> Trailing,
        @ViewBuilder compactLine: () -> Line = { EmptyView() },
        @ViewBuilder expanded: () -> Expanded,
        @ViewBuilder peek: () -> Peek = { EmptyView() },
        @ViewBuilder request: () -> Request = { EmptyView() },
        @ViewBuilder menu: () -> Menu = { EmptyView() }
    ) {
        let content = NotchContent(compactLeading: AnyView(compactLeading()), compactTrailing: AnyView(compactTrailing()),
                                   compactLine: AnyView(compactLine()),
                                   expanded: AnyView(expanded()), peek: AnyView(peek()), request: AnyView(request()),
                                   menu: AnyView(menu()))
        self.configuration = configuration
        surface = NotchSurface(configuration: configuration, content: content)
        wingFootprint = configuration.wingWidth + NotchLayout.closedRadii.top
        clearanceMonitor = ClearanceMonitor(sides: configuration.measuredSides, probeWidth: wingFootprint)
        coordinator = Self.coordinator(for: configuration.residency)
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
        if let coordinator { join(coordinator) }
    }

    private static func coordinator(for residency: NotchResidency?) -> ResidencyCoordinator? {
        guard let residency else { return nil }
        guard let side = ResidentSide(residency.side), !residency.id.isEmpty else {
            NSLog("NotchKit: a residency needs an id and exactly one side, .leading or .trailing; carrying on without coordination")
            return nil
        }
        return ResidencyCoordinator(id: residency.id, side: side, channel: DistributedResidencyChannel())
    }

    /// Lets the other apps in the notch decide, with this one, who opens
    /// and who draws where.
    private func join(_ coordinator: ResidencyCoordinator) {
        surface.openGate = { summoned in coordinator.wantOpen(summoned: summoned) }
        surface.onRelease = { coordinator.released() }
        coordinator.onOpen = { [weak surface] in surface?.openGranted() }
        coordinator.onClose = { [weak surface] in surface?.openRevoked() }
        coordinator.onSummoned = { [weak surface] in surface?.expand(held: true) }
        coordinator.onArrangementChange = { [weak self] _ in self?.arrangementChanged() }
        coordinator.onResidentsChange = { [weak self] in self?.onResidentsChange?() }
        coordinator.watchSystem()
        coordinator.start()
        arrangementChanged()
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
    }

    /// Puts the notch on screen, closed. Does nothing if it's already there.
    public func show() {
        defer { coordinator?.setVisible(surface.isShown) }
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
        defer { coordinator?.setVisible(surface.isShown) }
        hiddenForFullscreen = false
        surface.hide()
        clearanceMonitor.stop()
    }

    /// Opens the notch and holds it open, or closes it if it's open: the
    /// action for a global shortcut. Beeps when the notch isn't showing.
    public func toggleExpanded() {
        surface.toggleFromKeyboard()
    }

    /// Opens the notch. Held, it stays open until `collapse()`, the shortcut
    /// or a click elsewhere, as after `toggleExpanded()`; otherwise it
    /// closes once the pointer is away from it, as after a hover. Ignored
    /// while the notch is hidden.
    public func expand(held: Bool = true) {
        surface.expand(held: held)
    }

    /// Closes the notch if it's open.
    public func collapse() {
        surface.collapse()
    }

    /// Shows the request content until `hideRequest()`: something the app
    /// wants answered, with no time limit. With room for the wings NotchKit
    /// draws nothing, and the app shows the request in a wing itself;
    /// without room, a pill hangs under the notch. A click on the pill
    /// opens the notch, and the pill is away while the notch is open, this
    /// app's or another's; the other apps see `NotchResident.isRequesting`.
    public func showRequest() {
        surface.setRequested(true)
        coordinator?.setRequesting(true)
    }

    /// Takes the request content away.
    public func hideRequest() {
        surface.setRequested(false)
        coordinator?.setRequesting(false)
    }

    /// Closes this app's panel and opens `resident`'s, as that app's own
    /// shortcut would: the action for a switch button drawn from
    /// `otherResidents`.
    public func handOver(to resident: NotchResident) {
        surface.collapse()
        coordinator?.handOver(to: resident.id)
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
        refit()
        onClearanceChange?(clearance)
    }

    /// Sharing the notch, only this app's own side has to have room.
    private func refit() {
        let sides = coordinator?.arrangement.sides ?? .both
        surface.setWingsFit(CompactPolicy.wingsFit(clearance: clearance, footprint: wingFootprint, sides: sides))
    }

    private func arrangementChanged() {
        guard let arrangement = coordinator?.arrangement else { return }
        surface.setArrangement(sides: arrangement.sides, yielded: arrangement.yielded)
        refit()
    }

    private func spaceChanged() {
        clearanceMonitor.invalidate()
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
