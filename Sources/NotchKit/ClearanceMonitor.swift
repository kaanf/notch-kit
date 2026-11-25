//
//  ClearanceMonitor.swift
//  NotchKit
//
//  Created by Kaan Firat.
//

import AppKit

/// Keeps the clearance for the frontmost app: measures when the frontmost
/// app changes and remembers the answer per app, so each app is measured
/// once. Menus opening and closing don't trigger anything.
@MainActor
final class ClearanceMonitor {
    /// Called on the main queue when the clearance changes.
    var onChange: ((NotchClearance) -> Void)?
    private(set) var clearance = NotchClearance() {
        didSet { if clearance != oldValue { onChange?(clearance) } }
    }

    private let sides: NotchSides
    /// The width the probe asks the menu bar for: what a wing takes.
    private let probeWidth: CGFloat
    private let probe = StatusItemProbe()
    private var cache = ClearanceCache()
    private var activationObserver: Any?
    private var generation = 0
    private var running = false

    /// A newly frontmost app's menus take a moment to replace the old ones.
    private static let settleDelay: TimeInterval = 0.35
    private static let readQueue = DispatchQueue(label: "NotchKit.clearance", qos: .userInitiated)

    init(sides: NotchSides, probeWidth: CGFloat) {
        self.sides = sides
        self.probeWidth = probeWidth
    }

    deinit {
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }

    /// Starts following the frontmost app. Does nothing with no sides to measure.
    func start() {
        guard !running, !sides.isEmpty else { return }
        running = true
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.frontmostChanged() }
        }
        frontmostChanged()
    }

    func stop() {
        guard running else { return }
        running = false
        generation += 1
        probe.cancel()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
    }

    /// The screens changed: every remembered measurement is off.
    func invalidate() {
        cache.removeAll()
        if running { frontmostChanged() }
    }

    private func frontmostChanged() {
        generation += 1
        probe.cancel()
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        if let id = app.bundleIdentifier, let known = cache[id] {
            clearance = known
            return
        }
        let generation = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
            guard let self, generation == self.generation else { return }
            self.measure(app, generation: generation)
        }
    }

    private func measure(_ app: NSRunningApplication, generation: Int) {
        guard let geometry = NotchGeometry.current,
              let screen = NSScreen.screens.first(where: { ScreenMetrics($0).displayID == geometry.displayID })?.frame else { return }
        let notch = geometry.rect
        let sides = sides
        let pid = app.processIdentifier
        // An app still launching hasn't built all its menus; measure, but
        // don't remember the answer.
        let cacheable = app.isFinishedLaunching

        Self.readQueue.async { [weak self] in
            let menus = sides.contains(.leading) ? MenuBarReader.menuItemFrames(of: pid) : nil
            DispatchQueue.main.async {
                guard let self, generation == self.generation else { return }
                var result = NotchClearance()
                result.leading = menus.map { ClearanceMath.leading(menuItems: $0, notch: notch, screen: screen) }
                let menusPass = menus.map { ClearanceMath.menusPassNotch(menuItems: $0, notch: notch, screen: screen) } ?? false
                guard sides.contains(.trailing) else { return self.finish(result, for: app, cacheable: cacheable) }
                self.probe.measure(width: self.probeWidth) { [weak self] frame, probeScreen in
                    guard let self, generation == self.generation else { return }
                    result.trailing = menusPass ? 0 : ClearanceMath.trailing(
                        probe: frame, probeScreen: probeScreen ?? screen, notch: notch, notchScreen: screen)
                    self.finish(result, for: app, cacheable: cacheable)
                }
            }
        }
    }

    private func finish(_ result: NotchClearance, for app: NSRunningApplication, cacheable: Bool) {
        if cacheable, let id = app.bundleIdentifier { cache[id] = result }
        clearance = result
    }
}
