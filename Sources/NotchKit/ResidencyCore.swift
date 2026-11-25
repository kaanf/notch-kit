//
//  ResidencyCore.swift
//  NotchKit
//
//  Created by Kaan Firat.
//

import Foundation

/// The half of the notch a resident lives in.
enum ResidentSide: String, Codable, Equatable {
    case leading
    case trailing

    /// Nil unless `sides` is exactly one side.
    init?(_ sides: NotchSides) {
        switch sides {
        case .leading: self = .leading
        case .trailing: self = .trailing
        default: return nil
        }
    }

    var sides: NotchSides { self == .leading ? .leading : .trailing }
}

/// What a resident tells the others about itself. It is always the whole
/// state, never a change, so a lost message is put right by the next one.
struct ResidentRecord: Codable, Equatable {
    var id: String
    var side: ResidentSide
    /// When it registered, in seconds since 1970; the later of two that
    /// can't share stands down.
    var since: TimeInterval
    /// The highest claim it has seen, its own included. A claimant opens
    /// once the others' clocks have caught up with its claim.
    var clock = 0
    /// Its notch is on screen.
    var visible = false
    var expanded = false
    var requesting = false
    /// Its claim on the one open panel, nil when it wants none.
    var claim: Int?
}

/// One message between residents.
struct ResidencyMessage: Codable, Equatable {
    enum Kind: String, Codable {
        /// The sender's record.
        case state
        /// A newcomer, or one just awake, asking everyone for their state.
        case hello
        /// The sender is leaving.
        case gone
        /// The sender hands the open panel to `to`.
        case summon
    }

    static let version = 1

    var v = ResidencyMessage.version
    var kind: Kind
    /// The sending process, to tell its messages from its own echo and
    /// from another copy of the same app.
    var sender: String
    var record: ResidentRecord?
    var to: String?
}

/// Who may open, who steps aside and who is still there: every decision of
/// sharing the notch, with no clock, process or window of its own. Each
/// input returns what to do about it.
///
/// The lock is not held anywhere. Each resident publishes its claim, and
/// the highest claim wins, the alphabetically first id between equals.
/// Hover and click claim only while nobody else does; a shortcut or
/// `expand()` always claims, one higher than any seen, and so takes over.
struct ResidencyCore {
    struct Timing: Equatable {
        /// A resident says it is alive this often.
        var heartbeat: TimeInterval = 2
        /// And is dropped after this long without a word.
        var expiry: TimeInterval = 6
        /// A newcomer stays out of sight this long, to hear who is there.
        var discovery: TimeInterval = 0.15
        /// A claimant waits this long for the others to step aside, then
        /// opens anyway: whoever hasn't answered isn't going to.
        var grantTimeout: TimeInterval = 0.3
    }

    enum Effect: Equatable {
        case send(ResidencyMessage)
        /// Open the panel that asked to open.
        case open
        /// Close the panel, or forget that it asked to open.
        case close
        /// Another resident handed over; open as for a shortcut.
        case summoned
        case warn(String)
    }

    /// What the closed notch should look like for the neighbours it has.
    struct Arrangement: Equatable {
        /// The halves of the notch this resident draws and answers in.
        var sides: NotchSides = .both
        /// Another resident has the panel, or might: stay out of sight.
        var yielded = false
    }

    let token: String
    let timing: Timing
    private(set) var me: ResidentRecord

    private struct Heard {
        var record: ResidentRecord
        var token: String
        var at: TimeInterval
    }

    private enum Phase: Equatable {
        case idle
        case discovering(until: TimeInterval)
        case active
        /// Another resident has this side; carrying on as if alone.
        case standalone
    }

    /// The other residents, by id.
    private var others: [String: Heard] = [:]
    private var phase = Phase.idle
    /// When the claim that is still waiting to open was made.
    private var claimedAt: TimeInterval?
    /// An opening asked for during discovery, and whether it was a summons.
    private var wanted: Bool?
    private var lastSent: TimeInterval = 0

    init(id: String, side: ResidentSide, since: TimeInterval, token: String, timing: Timing = Timing()) {
        self.token = token
        self.timing = timing
        me = ResidentRecord(id: id, side: side, since: since)
    }

    // MARK: - Reading

    var arrangement: Arrangement {
        switch phase {
        case .idle, .standalone:
            return Arrangement()
        case .discovering:
            return Arrangement(sides: .both, yielded: true)
        case .active:
            let sharing = others.values.contains { $0.record.visible }
            return Arrangement(sides: sharing ? me.side.sides : .both, yielded: bestOtherClaim != nil && !winning)
        }
    }

    /// The other residents whose notch is on screen, by id.
    var residents: [NotchResident] {
        others.values.map(\.record).filter(\.visible).sorted { $0.id < $1.id }.map {
            NotchResident(id: $0.id, side: $0.side.sides, isExpanded: $0.expanded, isRequesting: $0.requesting)
        }
    }

    /// When `tick` next has something to do.
    var nextDeadline: TimeInterval? {
        guard coordinating else { return nil }
        var deadlines = [lastSent + timing.heartbeat]
        if case .discovering(let until) = phase { deadlines.append(until) }
        if let claimedAt { deadlines.append(claimedAt + timing.grantTimeout) }
        deadlines += others.values.map { $0.at + timing.expiry }
        return deadlines.min()
    }

    // MARK: - Inputs

    /// Registers: asks who is there and says who this is.
    mutating func start(now: TimeInterval) -> [Effect] {
        guard phase == .idle else { return [] }
        phase = .discovering(until: now + timing.discovery)
        lastSent = now
        return [.send(message(.hello)), .send(stateMessage)]
    }

    /// Leaves at once, rather than by falling silent.
    mutating func stop() -> [Effect] {
        guard coordinating else { return [] }
        phase = .idle
        others = [:]
        return [.send(message(.gone))]
    }

    mutating func receive(_ message: ResidencyMessage, now: TimeInterval) -> [Effect] {
        guard coordinating, message.v == ResidencyMessage.version, message.sender != token else { return [] }
        let before = me
        var effects: [Effect] = []
        switch message.kind {
        case .hello:
            lastSent = now
            effects.append(.send(stateMessage))
        case .gone:
            others = others.filter { $0.value.token != message.sender }
        case .summon:
            if message.to == me.id, me.visible { effects.append(.summoned) }
        case .state:
            guard let record = message.record else { return [] }
            if record.id == me.id || record.side == me.side {
                // Two can't have one side. The one that came second gives
                // way; the first never counts it as a neighbour.
                guard (me.since, token) > (record.since, message.sender) else { return [] }
                return standDown(to: record)
            }
            others[record.id] = Heard(record: record, token: message.sender, at: now)
            me.clock = max(me.clock, record.clock, record.claim ?? 0)
        }
        settle(now: now, before: before, effects: &effects)
        return effects
    }

    /// Time passing: drops the silent, ends discovery, stops waiting for an
    /// answer that isn't coming, and says this resident is still alive.
    mutating func tick(now: TimeInterval) -> [Effect] {
        guard coordinating else { return [] }
        let before = me
        var effects: [Effect] = []
        others = others.filter { now - $0.value.at < timing.expiry }
        settle(now: now, before: before, effects: &effects)
        if now - lastSent >= timing.heartbeat {
            lastSent = now
            effects.append(.send(stateMessage))
        }
        return effects
    }

    /// The Mac woke: what was heard before it slept says nothing about now.
    mutating func wake(now: TimeInterval) -> [Effect] {
        guard coordinating else { return [] }
        let before = me
        others = [:]
        lastSent = now
        var effects: [Effect] = [.send(message(.hello)), .send(stateMessage)]
        settle(now: now, before: before, effects: &effects)
        return effects
    }

    /// The panel wants to open; `summoned` for a shortcut or `expand()`,
    /// which take the panel from whoever has it. Not accepted means it
    /// stays closed; accepted, `.open` comes now or later, or `.close` if
    /// another resident wins after all.
    mutating func wantOpen(summoned: Bool, now: TimeInterval) -> (accepted: Bool, effects: [Effect]) {
        let before = me
        var effects: [Effect] = []
        endDiscovery(now: now, effects: &effects)
        switch phase {
        case .idle, .standalone:
            return (true, [.open])
        case .discovering:
            wanted = (wanted ?? false) || summoned
            return (true, effects)
        case .active:
            if me.claim == nil {
                if !summoned, bestOtherClaim != nil {
                    settle(now: now, before: before, effects: &effects)
                    return (false, effects)
                }
                claim(now: now)
            }
            settle(now: now, before: before, effects: &effects)
            return (true, effects)
        }
    }

    /// The panel closed, or gave up asking to open.
    mutating func closed(now: TimeInterval) -> [Effect] {
        guard coordinating else { return [] }
        let before = me
        var effects: [Effect] = []
        wanted = nil
        release()
        settle(now: now, before: before, effects: &effects)
        return effects
    }

    mutating func setVisible(_ visible: Bool, now: TimeInterval) -> [Effect] {
        update(now: now) { $0.visible = visible }
    }

    mutating func setRequesting(_ requesting: Bool, now: TimeInterval) -> [Effect] {
        update(now: now) { $0.requesting = requesting }
    }

    /// Asks the resident `id` to open, as its own shortcut would. The panel
    /// here closes first, by `closed`.
    func handOver(to id: String) -> [Effect] {
        guard phase == .active, others[id] != nil else { return [] }
        var summon = message(.summon)
        summon.to = id
        return [.send(summon)]
    }

    // MARK: - Deciding

    private var coordinating: Bool { phase != .idle && phase != .standalone }

    /// The strongest claim among the others.
    private var bestOtherClaim: (claim: Int, id: String)? {
        others.values
            .compactMap { heard in heard.record.claim.map { (claim: $0, id: heard.record.id) } }
            .max { ($0.claim, $1.id) < ($1.claim, $0.id) }
    }

    /// This resident has a claim and no other beats it.
    private var winning: Bool {
        guard let mine = me.claim else { return false }
        guard let best = bestOtherClaim else { return true }
        return (mine, best.id) > (best.claim, me.id)
    }

    /// Every other resident has seen the claim and has nothing open, or
    /// has had long enough to.
    private func granted(now: TimeInterval) -> Bool {
        guard let mine = me.claim else { return false }
        if let claimedAt, now - claimedAt >= timing.grantTimeout { return true }
        return others.values.allSatisfy { $0.record.clock >= mine && !$0.record.expanded }
    }

    private mutating func claim(now: TimeInterval) {
        me.clock += 1
        me.claim = me.clock
        claimedAt = now
    }

    private mutating func release() {
        me.claim = nil
        me.expanded = false
        claimedAt = nil
    }

    private mutating func update(now: TimeInterval, _ change: (inout ResidentRecord) -> Void) -> [Effect] {
        guard coordinating else { return [] }
        let before = me
        var effects: [Effect] = []
        change(&me)
        settle(now: now, before: before, effects: &effects)
        return effects
    }

    private mutating func endDiscovery(now: TimeInterval, effects: inout [Effect]) {
        guard case .discovering(let until) = phase, now >= until else { return }
        phase = .active
        guard let summoned = wanted else { return }
        wanted = nil
        if summoned || bestOtherClaim == nil {
            claim(now: now)
        } else {
            effects.append(.close)
        }
    }

    /// Brings the claim in line with what is now known, and tells the
    /// others if anything about this resident changed.
    private mutating func settle(now: TimeInterval, before: ResidentRecord, effects: inout [Effect]) {
        endDiscovery(now: now, effects: &effects)
        if me.claim != nil, !winning {
            release()
            effects.append(.close)
        }
        if me.claim != nil, !me.expanded, granted(now: now) {
            me.expanded = true
            claimedAt = nil
            effects.append(.open)
        }
        if me != before {
            lastSent = now
            effects.append(.send(stateMessage))
        }
    }

    /// Gives the side up to the resident that had it first, and carries on
    /// as if alone.
    private mutating func standDown(to record: ResidentRecord) -> [Effect] {
        let waiting = wanted != nil || (me.claim != nil && !me.expanded)
        var effects: [Effect] = [
            .warn("\"\(me.id)\" can't share the notch with \"\(record.id)\", which already has that side or that id; carrying on without coordination"),
            .send(message(.gone)),
        ]
        phase = .standalone
        others = [:]
        wanted = nil
        release()
        if waiting { effects.append(.open) }
        return effects
    }

    private func message(_ kind: ResidencyMessage.Kind) -> ResidencyMessage {
        ResidencyMessage(kind: kind, sender: token)
    }

    private var stateMessage: ResidencyMessage {
        var state = message(.state)
        state.record = me
        return state
    }
}
