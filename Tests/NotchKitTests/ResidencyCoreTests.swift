//
//  ResidencyCoreTests.swift
//  NotchKit
//
//  Created by Kaan Firat.
//

import XCTest
@testable import NotchKit

/// Residents wired to each other in memory, with a clock moved by hand.
/// Each one's panel is played by the street: told to close, it closes.
private final class Street {
    typealias Effect = ResidencyCore.Effect

    var now: TimeInterval = 1000
    private var cores: [String: ResidencyCore] = [:]
    private var order: [String] = []
    private var queue: [ResidencyMessage] = []
    /// Crashed: hears nothing and says nothing more.
    private var dead: Set<String> = []
    /// What each resident was told to do, other than send.
    private(set) var told: [String: [Effect]] = [:]
    /// Every message sent, in order.
    private(set) var sent: [ResidencyMessage] = []

    /// A resident that registers now. `name` tells two copies with one id apart.
    @discardableResult
    func add(_ id: String, _ side: ResidentSide, name: String? = nil) -> String {
        let name = name ?? id
        cores[name] = ResidencyCore(id: id, side: side, since: now, token: "token-\(name)")
        order.append(name)
        act(name) { $0.start(now: now) }
        act(name) { $0.setVisible(true, now: now) }
        return name
    }

    /// Two residents, registered and past discovery.
    static func tunoAndPerch() -> Street {
        let street = Street()
        street.add("tuno", .leading)
        street.add("perch", .trailing)
        street.pass(0.2)
        return street
    }

    subscript(name: String) -> ResidencyCore { cores[name]! }

    func act(_ name: String, _ input: (inout ResidencyCore) -> [Effect]) {
        guard !dead.contains(name) else { return }
        handle(name, input(&cores[name]!))
    }

    /// Asks to open without delivering anything yet.
    @discardableResult
    func wantOpen(_ name: String, summoned: Bool) -> Bool {
        let (accepted, effects) = cores[name]!.wantOpen(summoned: summoned, now: now)
        handle(name, effects)
        return accepted
    }

    /// Asks to open and lets the residents talk it through.
    @discardableResult
    func open(_ name: String, summoned: Bool = false) -> Bool {
        let accepted = wantOpen(name, summoned: summoned)
        deliver()
        return accepted
    }

    func close(_ name: String) {
        act(name) { $0.closed(now: now) }
        deliver()
    }

    func crash(_ name: String) {
        dead.insert(name)
    }

    /// Delivers every message, and those sent in answer, to everyone:
    /// the sender too, as the real channel does.
    func deliver() {
        while !queue.isEmpty {
            let message = queue.removeFirst()
            for name in order where !dead.contains(name) {
                handle(name, cores[name]!.receive(message, now: now))
            }
        }
    }

    /// Lets time pass, ticking everyone every 50 ms.
    func pass(_ seconds: TimeInterval) {
        deliver()
        let end = now + seconds
        while now < end - 0.0001 {
            now += 0.05
            for name in order where !dead.contains(name) {
                handle(name, cores[name]!.tick(now: now))
            }
            deliver()
        }
    }

    func isOpen(_ name: String) -> Bool { cores[name]!.me.expanded }
    func opens(_ name: String) -> Int { told[name, default: []].filter { $0 == .open }.count }
    func closes(_ name: String) -> Int { told[name, default: []].filter { $0 == .close }.count }

    private func handle(_ name: String, _ effects: [Effect]) {
        for effect in effects {
            if case .send(let message) = effect {
                sent.append(message)
                queue.append(message)
                continue
            }
            told[name, default: []].append(effect)
            // The panel does as it's told, and reports back.
            if effect == .close { handle(name, cores[name]!.closed(now: now)) }
        }
    }
}

final class ResidencyCoreTests: XCTestCase {
    private typealias Arrangement = ResidencyCore.Arrangement

    // MARK: Alone

    func testANewcomerStaysOutOfSightWhileItListens() {
        let street = Street()
        street.add("perch", .trailing)
        XCTAssertEqual(street["perch"].arrangement, Arrangement(sides: .both, yielded: true))
        street.pass(0.2)
        XCTAssertEqual(street["perch"].arrangement, Arrangement(sides: .both, yielded: false))
    }

    func testAloneItHasTheWholeNotchAndOpensAtOnce() {
        let street = Street()
        street.add("perch", .trailing)
        street.pass(0.2)
        XCTAssertTrue(street["perch"].residents.isEmpty)
        XCTAssertTrue(street.wantOpen("perch", summoned: false))
        XCTAssertEqual(street.told["perch"], [.open])
    }

    func testAnOpeningAskedForWhileListeningWaitsForTheAnswer() {
        let street = Street()
        street.add("perch", .trailing)
        XCTAssertTrue(street.wantOpen("perch", summoned: true))
        XCTAssertEqual(street.opens("perch"), 0)
        street.pass(0.2)
        XCTAssertEqual(street.opens("perch"), 1)
    }

    func testItSaysItIsAliveEveryTwoSeconds() {
        let street = Street()
        street.add("perch", .trailing)
        street.pass(0.2)
        let before = street.sent.count
        street.pass(6)
        XCTAssertEqual(street.sent.count - before, 3)
        XCTAssertTrue(street.sent.suffix(3).allSatisfy { $0.kind == .state })
    }

    // MARK: Splitting the notch

    func testWithCompanyEachKeepsItsOwnHalf() {
        let street = Street.tunoAndPerch()
        XCTAssertEqual(street["tuno"].arrangement, Arrangement(sides: .leading, yielded: false))
        XCTAssertEqual(street["perch"].arrangement, Arrangement(sides: .trailing, yielded: false))
        XCTAssertEqual(street["tuno"].residents, [NotchResident(id: "perch", side: .trailing, isExpanded: false, isRequesting: false)])
    }

    func testAResidentThatLeavesGivesTheNotchBackAtOnce() {
        let street = Street.tunoAndPerch()
        street.act("perch") { $0.stop() }
        street.deliver()
        XCTAssertEqual(street["tuno"].arrangement, Arrangement())
        XCTAssertTrue(street["tuno"].residents.isEmpty)
    }

    func testALiveResidentIsKeptPastTheExpiry() {
        let street = Street.tunoAndPerch()
        street.pass(20)
        XCTAssertEqual(street["tuno"].residents.map(\.id), ["perch"])
    }

    // MARK: The lock

    func testOnePanelOpensAndTheOtherStepsAside() {
        let street = Street.tunoAndPerch()
        XCTAssertTrue(street.open("perch"))
        XCTAssertTrue(street.isOpen("perch"))
        XCTAssertTrue(street["tuno"].arrangement.yielded)
        XCTAssertEqual(street["tuno"].residents.first?.isExpanded, true)
        // Hover and click get nowhere while the other has the panel.
        XCTAssertFalse(street.open("tuno"))
        XCTAssertEqual(street.opens("tuno"), 0)
        XCTAssertTrue(street.isOpen("perch"))
    }

    func testClosingGivesTheOtherItsWingBack() {
        let street = Street.tunoAndPerch()
        street.open("perch")
        street.close("perch")
        XCTAssertFalse(street["tuno"].arrangement.yielded)
        XCTAssertTrue(street.open("tuno"))
        XCTAssertTrue(street.isOpen("tuno"))
    }

    func testAShortcutTakesThePanelOnceTheHolderHasClosed() {
        let street = Street.tunoAndPerch()
        street.open("perch")
        XCTAssertTrue(street.wantOpen("tuno", summoned: true))
        // Nothing opens over a panel that hasn't heard yet.
        XCTAssertEqual(street.opens("tuno"), 0)
        street.deliver()
        XCTAssertEqual(street.closes("perch"), 1)
        XCTAssertFalse(street.isOpen("perch"))
        XCTAssertTrue(street.isOpen("tuno"))
        XCTAssertTrue(street["perch"].arrangement.yielded)
    }

    func testOfTwoAskingAtOnceOnlyTheAlphabeticallyFirstOpens() {
        let street = Street.tunoAndPerch()
        XCTAssertTrue(street.wantOpen("tuno", summoned: false))
        XCTAssertTrue(street.wantOpen("perch", summoned: false))
        street.deliver()
        XCTAssertEqual(street.opens("perch"), 1)
        XCTAssertEqual(street.opens("tuno"), 0)
        XCTAssertEqual(street.closes("tuno"), 1)
        XCTAssertTrue(street["tuno"].arrangement.yielded)
    }

    func testTwoShortcutsAtOnceAlsoOpenOnlyOne() {
        let street = Street.tunoAndPerch()
        street.wantOpen("tuno", summoned: true)
        street.wantOpen("perch", summoned: true)
        street.deliver()
        street.pass(1)
        XCTAssertEqual(street.opens("perch"), 1)
        XCTAssertEqual(street.opens("tuno"), 0)
    }

    func testALaterShortcutBeatsAnEarlierOne() {
        let street = Street.tunoAndPerch()
        street.open("perch", summoned: true)
        street.open("tuno", summoned: true)
        XCTAssertTrue(street.isOpen("tuno"))
        XCTAssertFalse(street.isOpen("perch"))
    }

    // MARK: Things going wrong

    func testAHolderThatCrashesFreesTheLockWithinTheExpiry() {
        let street = Street.tunoAndPerch()
        street.open("perch")
        street.crash("perch")
        street.pass(5.5)
        XCTAssertTrue(street["tuno"].arrangement.yielded)
        street.pass(0.6)
        XCTAssertEqual(street["tuno"].arrangement, Arrangement())
        XCTAssertTrue(street.open("tuno"))
        XCTAssertTrue(street.isOpen("tuno"))
    }

    func testAShortcutDoesNotWaitLongForAHolderThatCrashed() {
        let street = Street.tunoAndPerch()
        street.open("perch")
        street.crash("perch")
        street.open("tuno", summoned: true)
        XCTAssertEqual(street.opens("tuno"), 0)
        street.pass(0.4)
        XCTAssertEqual(street.opens("tuno"), 1)
    }

    func testStartingWhileAnotherIsOpenNeverShowsAWing() {
        let street = Street()
        street.add("perch", .trailing)
        street.pass(0.2)
        street.open("perch")
        street.add("tuno", .leading)
        XCTAssertTrue(street["tuno"].arrangement.yielded)
        street.deliver()
        XCTAssertTrue(street["tuno"].arrangement.yielded)
        street.pass(1)
        XCTAssertEqual(street["tuno"].arrangement, Arrangement(sides: .leading, yielded: true))
        XCTAssertTrue(street.isOpen("perch"))
        street.close("perch")
        XCTAssertEqual(street["tuno"].arrangement, Arrangement(sides: .leading, yielded: false))
    }

    func testAHoverAskedForWhileListeningIsDroppedIfAnotherIsOpen() {
        let street = Street()
        street.add("perch", .trailing)
        street.pass(0.2)
        street.open("perch")
        street.add("tuno", .leading)
        XCTAssertTrue(street.wantOpen("tuno", summoned: false))
        street.pass(0.2)
        XCTAssertEqual(street.opens("tuno"), 0)
        XCTAssertEqual(street.closes("tuno"), 1)
        XCTAssertTrue(street.isOpen("perch"))
    }

    func testTheSecondToAskForASideWarnsAndCarriesOnAlone() {
        let street = Street()
        street.add("tuno", .leading)
        street.pass(1)
        street.add("other", .leading)
        street.pass(1)
        XCTAssertTrue(street.told["other"]?.contains { if case .warn = $0 { return true } else { return false } } ?? false)
        XCTAssertEqual(street["other"].arrangement, Arrangement())
        XCTAssertNil(street["other"].nextDeadline)
        // The first never counted it, and neither holds the other back.
        XCTAssertEqual(street["tuno"].arrangement, Arrangement())
        XCTAssertTrue(street["tuno"].residents.isEmpty)
        street.open("tuno")
        XCTAssertTrue(street.wantOpen("other", summoned: false))
        XCTAssertEqual(street.opens("other"), 1)
        XCTAssertTrue(street.isOpen("tuno"))
    }

    func testASecondCopyOfAnAppStandsDownToo() {
        let street = Street()
        street.add("tuno", .leading)
        street.pass(1)
        street.add("tuno", .trailing, name: "copy")
        street.pass(1)
        XCTAssertNil(street["copy"].nextDeadline)
        XCTAssertNotNil(street["tuno"].nextDeadline)
        XCTAssertNil(street.told["tuno"])
    }

    func testAResidentThatRestartsReplacesItsOldRecord() {
        let street = Street.tunoAndPerch()
        street.open("perch")
        street.crash("perch")
        street.pass(1)
        street.add("perch", .trailing, name: "perch again")
        street.pass(0.2)
        XCTAssertEqual(street["tuno"].arrangement, Arrangement(sides: .leading, yielded: false))
        XCTAssertEqual(street["tuno"].residents.map(\.isExpanded), [false])
    }

    // MARK: Hiding and waking

    func testAHiddenResidentKeepsItsPlaceButNotItsHalf() {
        let street = Street.tunoAndPerch()
        street.open("perch")
        // hide() closes the panel first.
        street.close("perch")
        street.act("perch") { $0.setVisible(false, now: street.now) }
        street.deliver()
        XCTAssertEqual(street["tuno"].arrangement, Arrangement())
        XCTAssertTrue(street["tuno"].residents.isEmpty)
        street.pass(10)
        XCTAssertEqual(street["tuno"].arrangement, Arrangement())

        street.act("perch") { $0.setVisible(true, now: street.now) }
        street.deliver()
        XCTAssertEqual(street["tuno"].arrangement, Arrangement(sides: .leading, yielded: false))
        XCTAssertEqual(street["perch"].arrangement, Arrangement(sides: .trailing, yielded: false))
    }

    func testWakingForgetsTheDeadAndFindsTheLivingAgain() {
        let street = Street()
        street.add("tuno", .leading)
        street.add("perch", .trailing)
        street.pass(0.2)
        street.open("perch")
        street.crash("perch")
        street.act("tuno") { $0.wake(now: street.now) }
        XCTAssertEqual(street["tuno"].arrangement, Arrangement())

        let both = Street.tunoAndPerch()
        both.open("perch")
        both.act("tuno") { $0.wake(now: both.now) }
        both.deliver()
        XCTAssertEqual(both["tuno"].arrangement, Arrangement(sides: .leading, yielded: true))
    }

    // MARK: Requests and handing over

    func testARequestBehindAnOpenPanelOnlyShowsToItsNeighbour() {
        let street = Street.tunoAndPerch()
        street.open("tuno")
        street.act("perch") { $0.setRequesting(true, now: street.now) }
        street.deliver()
        XCTAssertEqual(street["tuno"].residents.first?.isRequesting, true)
        // The open panel is left alone, and the pill stays away with the wing.
        XCTAssertTrue(street.isOpen("tuno"))
        XCTAssertEqual(street.closes("tuno"), 0)
        XCTAssertTrue(street["perch"].arrangement.yielded)
        XCTAssertFalse(CompactState(wingsFit: false, requested: true, yielded: true).showsRequestPill)
    }

    func testHandingOverOpensTheOther() {
        let street = Street.tunoAndPerch()
        street.open("tuno")
        street.close("tuno")
        street.act("tuno") { $0.handOver(to: "perch") }
        street.deliver()
        XCTAssertEqual(street.told["perch"], [.summoned])
        // Its panel then asks to open as for a shortcut.
        street.open("perch", summoned: true)
        XCTAssertTrue(street.isOpen("perch"))
        XCTAssertTrue(street["tuno"].arrangement.yielded)
    }

    func testHandingOverToNobodyDoesNothing() {
        let street = Street.tunoAndPerch()
        XCTAssertTrue(street["tuno"].handOver(to: "ghost").isEmpty)
    }

    // MARK: Messages

    func testAMessageSurvivesTheWire() throws {
        var record = ResidentRecord(id: "perch", side: .trailing, since: 12.5)
        record.claim = 4
        record.clock = 4
        let message = ResidencyMessage(kind: .state, sender: "abc", record: record)
        let data = try JSONEncoder().encode(message)
        XCTAssertEqual(try JSONDecoder().decode(ResidencyMessage.self, from: data), message)
    }

    func testAMessageFromAnotherVersionIsIgnored() {
        let street = Street()
        street.add("tuno", .leading)
        street.pass(0.2)
        var message = ResidencyMessage(kind: .state, sender: "new", record: ResidentRecord(id: "perch", side: .trailing, since: 0, visible: true))
        message.v = 2
        street.act("tuno") { $0.receive(message, now: street.now) }
        XCTAssertEqual(street["tuno"].arrangement, Arrangement())
    }
}
