//
//  ResidencyCoordinator.swift
//  NotchKit
//
//  Created by Kaan Firat.
//

import AppKit

/// One app's seat among the residents of a notch: feeds `ResidencyCore`
/// from the channel, the clock and the notch, and carries out what it
/// decides. The channel, the clock and the timer all come from outside.
@MainActor
final class ResidencyCoordinator {
    /// Runs `work` after `delay` seconds; the result cancels it.
    typealias Schedule = (_ delay: TimeInterval, _ work: @escaping () -> Void) -> () -> Void

    /// The halves of the notch to draw, or stepping aside, changed.
    var onArrangementChange: ((ResidencyCore.Arrangement) -> Void)?
    var onResidentsChange: (() -> Void)?
    /// The opening that was asked for may go ahead.
    var onOpen: (() -> Void)?
    /// Another app has the panel: close, or stop waiting to open.
    var onClose: (() -> Void)?
    /// Another app handed its panel over: open as for a shortcut.
    var onSummoned: (() -> Void)?

    var arrangement: ResidencyCore.Arrangement { core.arrangement }
    var residents: [NotchResident] { core.residents }

    private var core: ResidencyCore
    private let channel: ResidencyChannel
    private let clock: () -> TimeInterval
    private let schedule: Schedule
    private var cancelTimer: (() -> Void)?
    private var published: (arrangement: ResidencyCore.Arrangement, residents: [NotchResident])
    private var systemObservers: [(center: NotificationCenter, token: Any)] = []

    init(id: String, side: ResidentSide, channel: ResidencyChannel,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         schedule: @escaping Schedule = ResidencyCoordinator.timer,
         since: TimeInterval = Date().timeIntervalSince1970, token: String = UUID().uuidString,
         timing: ResidencyCore.Timing = ResidencyCore.Timing()) {
        core = ResidencyCore(id: id, side: side, since: since, token: token, timing: timing)
        self.channel = channel
        self.clock = clock
        self.schedule = schedule
        published = (core.arrangement, core.residents)
    }

    deinit {
        cancelTimer?()
        systemObservers.forEach { $0.center.removeObserver($0.token) }
        // Whoever is left shouldn't have to wait for the silence.
        channel.send(ResidencyMessage(kind: .gone, sender: core.token))
    }

    /// Joins the residents.
    func start() {
        channel.onReceive = { [weak self] message in
            MainActor.assumeIsolated { self?.receive(message) }
        }
        apply(core.start(now: clock()))
    }

    /// Leaves them.
    func stop() {
        apply(core.stop())
    }

    /// Leaves when the app quits, and starts afresh when the Mac wakes.
    func watchSystem() {
        let quit = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        let wake = workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.wake() }
        }
        systemObservers = [(NotificationCenter.default, quit), (workspace, wake)]
    }

    func receive(_ message: ResidencyMessage) {
        apply(core.receive(message, now: clock()))
    }

    func tick() {
        apply(core.tick(now: clock()))
    }

    func wake() {
        apply(core.wake(now: clock()))
    }

    /// The notch wants to open; false keeps it closed. See `ResidencyCore.wantOpen`.
    func wantOpen(summoned: Bool) -> Bool {
        let (accepted, effects) = core.wantOpen(summoned: summoned, now: clock())
        apply(effects)
        return accepted
    }

    /// The notch closed, or gave up waiting to open.
    func released() {
        apply(core.closed(now: clock()))
    }

    func setVisible(_ visible: Bool) {
        apply(core.setVisible(visible, now: clock()))
    }

    func setRequesting(_ requesting: Bool) {
        apply(core.setRequesting(requesting, now: clock()))
    }

    func handOver(to id: String) {
        apply(core.handOver(to: id))
    }

    /// Carries out what the core decided. A step may come back in here, by
    /// the notch closing or a message being answered; the core has finished
    /// its own change by then.
    private func apply(_ effects: [ResidencyCore.Effect]) {
        for effect in effects {
            switch effect {
            case .send(let message): channel.send(message)
            case .open: onOpen?()
            case .close: onClose?()
            case .summoned: onSummoned?()
            case .warn(let text): NSLog("NotchKit: %@", text)
            }
        }
        publish()
        reschedule()
    }

    private func publish() {
        let (arrangement, residents) = (core.arrangement, core.residents)
        let changed = (arrangement != published.arrangement, residents != published.residents)
        published = (arrangement, residents)
        if changed.0 { onArrangementChange?(arrangement) }
        if changed.1 { onResidentsChange?() }
    }

    private func reschedule() {
        cancelTimer?()
        cancelTimer = nil
        guard let deadline = core.nextDeadline else { return }
        cancelTimer = schedule(max(0, deadline - clock())) { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    /// A timer on the main run loop that keeps running while a menu is open.
    nonisolated static func timer(delay: TimeInterval, work: @escaping () -> Void) -> () -> Void {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in work() }
        RunLoop.main.add(timer, forMode: .common)
        return { timer.invalidate() }
    }
}
