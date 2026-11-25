//
//  ResidencyCoordinatorTests.swift
//  NotchKit
//
//  Created by Kaan Firat.
//

import XCTest
@testable import NotchKit

/// A channel, a clock and timers that live in the test: what one seat
/// sends reaches every seat, and time moves only when told to.
@MainActor
private final class Town {
    final class Line: ResidencyChannel {
        var onReceive: ((ResidencyMessage) -> Void)?
        var cut = false
        let post: (ResidencyMessage) -> Void

        init(post: @escaping (ResidencyMessage) -> Void) {
            self.post = post
        }

        func send(_ message: ResidencyMessage) {
            if !cut { post(message) }
        }
    }

    /// A seat and the panel it would drive.
    final class Seat {
        var coordinator: ResidencyCoordinator?
        let line: Line
        var isOpen = false
        var opens = 0
        var summons = 0

        init(line: Line) {
            self.line = line
        }
    }

    private(set) var now: TimeInterval = 500
    private var lines: [Line] = []
    private var queue: [ResidencyMessage] = []
    private var delivering = false
    private var timers: [(id: Int, at: TimeInterval, work: () -> Void)] = []
    private var nextTimer = 0

    func seat(_ id: String, _ side: ResidentSide) -> Seat {
        let line = Line { [weak self] message in self?.post(message) }
        lines.append(line)
        let seat = Seat(line: line)
        let coordinator = ResidencyCoordinator(
            id: id, side: side, channel: line,
            clock: { [unowned self] in self.now },
            schedule: { [unowned self] delay, work in self.schedule(delay, work) },
            since: now, token: "token-\(id)-\(lines.count)"
        )
        coordinator.onOpen = { [unowned seat] in
            seat.isOpen = true
            seat.opens += 1
        }
        coordinator.onClose = { [unowned seat] in
            seat.isOpen = false
            seat.coordinator?.released()
        }
        coordinator.onSummoned = { [unowned seat] in seat.summons += 1 }
        seat.coordinator = coordinator
        coordinator.start()
        coordinator.setVisible(true)
        return seat
    }

    /// The app dies without a word: nothing more goes out or comes in.
    func crash(_ seat: Seat) {
        seat.line.cut = true
        seat.line.onReceive = nil
    }

    func pass(_ seconds: TimeInterval) {
        let end = now + seconds
        while let next = timers.filter({ $0.at <= end }).min(by: { $0.at < $1.at }) {
            timers.removeAll { $0.id == next.id }
            now = max(now, next.at)
            next.work()
        }
        now = end
    }

    private func schedule(_ delay: TimeInterval, _ work: @escaping () -> Void) -> () -> Void {
        nextTimer += 1
        let id = nextTimer
        timers.append((id, now + delay, work))
        return { [weak self] in self?.timers.removeAll { $0.id == id } }
    }

    private func post(_ message: ResidencyMessage) {
        queue.append(message)
        guard !delivering else { return }
        delivering = true
        while !queue.isEmpty {
            let message = queue.removeFirst()
            for line in lines where !line.cut { line.onReceive?(message) }
        }
        delivering = false
    }
}

@MainActor
final class ResidencyCoordinatorTests: XCTestCase {
    func testTwoSeatsSplitTheNotchAndOpenOneAtATime() {
        let town = Town()
        let tuno = town.seat("tuno", .leading)
        let perch = town.seat("perch", .trailing)
        XCTAssertTrue(perch.coordinator!.arrangement.yielded)
        town.pass(0.2)
        XCTAssertEqual(tuno.coordinator!.arrangement, .init(sides: .leading, yielded: false))
        XCTAssertEqual(perch.coordinator!.arrangement, .init(sides: .trailing, yielded: false))

        XCTAssertTrue(perch.coordinator!.wantOpen(summoned: false))
        XCTAssertTrue(perch.isOpen)
        XCTAssertTrue(tuno.coordinator!.arrangement.yielded)
        XCTAssertFalse(tuno.coordinator!.wantOpen(summoned: false))

        // The shortcut closes the other panel and then opens this one.
        XCTAssertTrue(tuno.coordinator!.wantOpen(summoned: true))
        XCTAssertFalse(perch.isOpen)
        XCTAssertTrue(tuno.isOpen)
        XCTAssertEqual(tuno.opens, 1)
    }

    func testChangesAreAnnouncedOnce() {
        let town = Town()
        let tuno = town.seat("tuno", .leading)
        var arrangements: [ResidencyCore.Arrangement] = []
        var residentChanges = 0
        tuno.coordinator!.onArrangementChange = { arrangements.append($0) }
        tuno.coordinator!.onResidentsChange = { residentChanges += 1 }
        town.pass(0.2)
        XCTAssertEqual(arrangements, [.init()])

        let perch = town.seat("perch", .trailing)
        town.pass(0.2)
        XCTAssertEqual(arrangements, [.init(), .init(sides: .leading, yielded: false)])
        XCTAssertEqual(residentChanges, 1)

        perch.coordinator!.setRequesting(true)
        XCTAssertEqual(residentChanges, 2)
        XCTAssertEqual(tuno.coordinator!.residents.first?.isRequesting, true)
        town.pass(30)
        XCTAssertEqual(residentChanges, 2)
        XCTAssertEqual(arrangements.count, 2)
    }

    func testTheTimerDropsACrashedHolder() {
        let town = Town()
        let tuno = town.seat("tuno", .leading)
        let perch = town.seat("perch", .trailing)
        town.pass(0.2)
        _ = perch.coordinator!.wantOpen(summoned: false)
        town.crash(perch)
        town.pass(5)
        XCTAssertTrue(tuno.coordinator!.arrangement.yielded)
        town.pass(1.5)
        XCTAssertEqual(tuno.coordinator!.arrangement, .init())
    }

    func testASeatThatIsLetGoSaysSo() {
        let town = Town()
        let tuno = town.seat("tuno", .leading)
        let perch = town.seat("perch", .trailing)
        town.pass(0.2)
        perch.coordinator = nil
        XCTAssertEqual(tuno.coordinator!.arrangement, .init())
        XCTAssertTrue(tuno.coordinator!.residents.isEmpty)
    }

    func testHandingOverSummonsTheOther() {
        let town = Town()
        let tuno = town.seat("tuno", .leading)
        let perch = town.seat("perch", .trailing)
        town.pass(0.2)
        _ = tuno.coordinator!.wantOpen(summoned: false)
        tuno.coordinator!.released()
        tuno.coordinator!.handOver(to: "perch")
        XCTAssertEqual(perch.summons, 1)
        XCTAssertEqual(tuno.summons, 0)
    }

    func testWakingAsksEveryoneAgain() {
        let town = Town()
        let tuno = town.seat("tuno", .leading)
        let perch = town.seat("perch", .trailing)
        town.pass(0.2)
        town.crash(perch)
        tuno.coordinator!.wake()
        XCTAssertEqual(tuno.coordinator!.arrangement, .init())
    }

    func testAMessageGoesOverTheWireAsText() throws {
        let message = ResidencyMessage(kind: .summon, sender: "abc", to: "perch")
        let text = try XCTUnwrap(DistributedResidencyChannel.encode(message))
        XCTAssertEqual(DistributedResidencyChannel.decode(text), message)
        XCTAssertNil(DistributedResidencyChannel.decode("not a message"))
        XCTAssertNil(DistributedResidencyChannel.decode(#"{"v":1,"kind":"later","sender":"x"}"#))
    }
}
