//
//  CompactTests.swift
//  NotchKit
//
//  Created by Kaan Firat.
//

import XCTest
@testable import NotchKit

final class CompactPolicyTests: XCTestCase {
    func testWingsFitWhenBothSidesHaveRoom() {
        XCTAssertTrue(CompactPolicy.wingsFit(clearance: NotchClearance(leading: 142.5, trailing: 377.5), footprint: 56))
        XCTAssertTrue(CompactPolicy.wingsFit(clearance: NotchClearance(leading: 56, trailing: 56), footprint: 56))
    }

    func testOneTightSideTakesBothWingsAway() {
        XCTAssertFalse(CompactPolicy.wingsFit(clearance: NotchClearance(leading: 20, trailing: 377.5), footprint: 56))
        XCTAssertFalse(CompactPolicy.wingsFit(clearance: NotchClearance(leading: 142.5, trailing: 0), footprint: 56))
    }

    func testAnUnmeasuredSideCountsAsFree() {
        XCTAssertTrue(CompactPolicy.wingsFit(clearance: NotchClearance(), footprint: 56))
        XCTAssertTrue(CompactPolicy.wingsFit(clearance: NotchClearance(leading: nil, trailing: 100), footprint: 56))
        XCTAssertFalse(CompactPolicy.wingsFit(clearance: NotchClearance(leading: nil, trailing: 0), footprint: 56))
    }
}

final class CompactStateTests: XCTestCase {
    func testWithRoomTheWingsShowAndTheLineDoesNot() {
        let state = CompactState()
        XCTAssertTrue(state.showsWings)
        XCTAssertFalse(state.showsLine)
    }

    func testWithoutRoomTheLineShows() {
        let state = CompactState(wingsFit: false)
        XCTAssertFalse(state.showsWings)
        XCTAssertTrue(state.showsLine)
    }

    func testForcedWingsReplaceTheLine() {
        let state = CompactState(wingsFit: false, wingsForced: true)
        XCTAssertTrue(state.showsWings)
        XCTAssertFalse(state.showsLine)
    }

    func testAPeekBringsTheWingsAndNeverSharesWithTheLine() {
        let state = CompactState(wingsFit: false, peeking: true)
        XCTAssertTrue(state.showsWings)
        XCTAssertFalse(state.showsLine)
    }

    func testWithoutRoomForcedWingsTakeThePeekWithThem() {
        let state = CompactState(wingsFit: false, wingsForced: true, peeking: true).afterForcedWings
        XCTAssertEqual(state, CompactState(wingsFit: false))
        XCTAssertTrue(state.showsLine)
    }

    func testWithRoomThePeekOutlivesForcedWings() {
        let state = CompactState(wingsFit: true, wingsForced: true, peeking: true).afterForcedWings
        XCTAssertEqual(state, CompactState(wingsFit: true, peeking: true))
    }
}

final class LineLayoutTests: XCTestCase {
    private var layout: NotchLayout {
        var layout = NotchLayout()
        layout.notch = CGSize(width: 179, height: 32)
        return layout
    }

    private let notchRect = CGRect(x: 645.5, y: 924, width: 179, height: 32)

    func testWithoutWingsTheBodyIsTheNotchPlusAChin() {
        XCTAssertEqual(layout.bodySize(expanded: false, peeking: false, wings: false), CGSize(width: 179, height: 37))
    }

    func testAPeekIsWingWideEvenWithoutRoom() {
        XCTAssertEqual(layout.bodySize(expanded: false, peeking: true, wings: false), layout.peekSize)
    }

    func testLineWindowIsExactlyTheNotchAndChin() {
        let frame = layout.windowFrame(notchRect: notchRect, expanded: false, peeking: false, wings: false)
        XCTAssertEqual(frame, CGRect(x: 645.5, y: 919, width: 179, height: 37))
    }

    func testWithoutWingsTheTopCornersAreSquare() {
        XCTAssertEqual(NotchLayout.radii(expanded: false, wings: false).top, 0)
        XCTAssertEqual(NotchLayout.radii(expanded: false, wings: true).top, 6)
        XCTAssertEqual(NotchLayout.radii(expanded: true, wings: false).top, 19)
    }

    func testLineHalvesMeetInTheMiddleInsideTheChin() {
        let halves = layout.lineHalves
        XCTAssertEqual(halves.leading, CGRect(x: 16, y: 33, width: 73.5, height: 3))
        XCTAssertEqual(halves.trailing, CGRect(x: 89.5, y: 33, width: 73.5, height: 3))
        XCTAssertEqual(halves.leading.maxX, 179 / 2)
    }

    func testAClickBelongsToTheHalfItLandsIn() {
        XCTAssertEqual(layout.side(atX: 10, bodyWidth: 179), .leading)
        XCTAssertEqual(layout.side(atX: 120, bodyWidth: 179), .trailing)
    }
}
