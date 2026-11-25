//
//  NotchLayoutTests.swift
//  NotchKit
//
//  Created by Kaan Firat.
//

import XCTest
@testable import NotchKit

final class NotchLayoutTests: XCTestCase {
    private var layout: NotchLayout {
        var layout = NotchLayout()
        layout.notch = CGSize(width: 185, height: 38)
        layout.wingWidth = 50
        layout.peekHeight = 22
        layout.expandedContentSize = CGSize(width: 360, height: 136)
        return layout
    }

    private let notchRect = CGRect(x: 663, y: 944, width: 185, height: 38)

    func testCompactAddsAWingEachSide() {
        XCTAssertEqual(layout.compactSize, CGSize(width: 285, height: 38))
    }

    func testPeekAddsItsHeightUnderTheCompactShape() {
        XCTAssertEqual(layout.peekSize, CGSize(width: 285, height: 60))
    }

    func testExpandedPutsTheContentBelowTheNotch() {
        XCTAssertEqual(layout.expandedSize, CGSize(width: 360, height: 174))
    }

    func testExpandedIsNeverNarrowerThanTheNotchPlusOverhang() {
        var layout = layout
        layout.notch.width = 300
        XCTAssertEqual(layout.expandedSize.width, 420)
    }

    func testExpandedWinsOverPeeking() {
        XCTAssertEqual(layout.bodySize(expanded: true, peeking: true), layout.expandedSize)
        XCTAssertEqual(layout.bodySize(expanded: false, peeking: true), layout.peekSize)
        XCTAssertEqual(layout.bodySize(expanded: false, peeking: false), layout.compactSize)
    }

    func testClosedWindowHugsTheShapeAndItsOutwardCorners() {
        let frame = layout.windowFrame(notchRect: notchRect, expanded: false, peeking: false)
        XCTAssertEqual(frame, CGRect(x: 755.5 - 148.5, y: 944, width: 297, height: 38))
    }

    func testPeekingWindowGrowsDownwardOnly() {
        let frame = layout.windowFrame(notchRect: notchRect, expanded: false, peeking: true)
        XCTAssertEqual(frame, CGRect(x: 607, y: 922, width: 297, height: 60))
    }

    // MARK: Half of a shared notch

    func testAHalfIsOneWingAndHalfTheNotch() {
        XCTAssertEqual(layout.bodySize(expanded: false, peeking: false, sides: .leading), CGSize(width: 142.5, height: 38))
        XCTAssertEqual(layout.bodySize(expanded: false, peeking: true, sides: .trailing), CGSize(width: 142.5, height: 60))
        XCTAssertEqual(layout.bodySize(expanded: false, peeking: false, wings: false, sides: .trailing), CGSize(width: 92.5, height: 43))
    }

    func testAHalfWindowStopsAtTheMiddleOfTheNotch() {
        let leading = layout.windowFrame(notchRect: notchRect, expanded: false, peeking: false, sides: .leading)
        let trailing = layout.windowFrame(notchRect: notchRect, expanded: false, peeking: false, sides: .trailing)
        XCTAssertEqual(leading, CGRect(x: 607, y: 944, width: 148.5, height: 38))
        XCTAssertEqual(trailing, CGRect(x: 755.5, y: 944, width: 148.5, height: 38))
        XCTAssertEqual(leading.maxX, notchRect.midX)
        // Side by side the two halves are the whole.
        XCTAssertEqual(leading.union(trailing), layout.windowFrame(notchRect: notchRect, expanded: false, peeking: false))
        XCTAssertFalse(leading.intersects(trailing))
    }

    func testAHalfLineWindowIsHalfTheNotchAndChin() {
        let leading = layout.windowFrame(notchRect: notchRect, expanded: false, peeking: false, wings: false, sides: .leading)
        let trailing = layout.windowFrame(notchRect: notchRect, expanded: false, peeking: false, wings: false, sides: .trailing)
        XCTAssertEqual(leading, CGRect(x: 663, y: 939, width: 92.5, height: 43))
        XCTAssertEqual(trailing, CGRect(x: 755.5, y: 939, width: 92.5, height: 43))
    }

    func testAHalfIsSquareWhereItMeetsTheOther() {
        XCTAssertEqual(NotchLayout.corners(expanded: false, sides: .leading),
                       NotchCorners(topLeading: 6, topTrailing: 0, bottomLeading: 14, bottomTrailing: 0))
        XCTAssertEqual(NotchLayout.corners(expanded: false, wings: false, sides: .trailing),
                       NotchCorners(topLeading: 0, topTrailing: 0, bottomLeading: 0, bottomTrailing: 14))
        XCTAssertEqual(NotchLayout.corners(expanded: false), NotchCorners(top: 6, bottom: 14))
    }

    func testAHalfHangsFromTheMiddleOfTheNotch() {
        XCTAssertEqual(layout.bodyOrigin(expanded: false, peeking: false), -142.5)
        XCTAssertEqual(layout.bodyOrigin(expanded: false, peeking: false, sides: .leading), -142.5)
        XCTAssertEqual(layout.bodyOrigin(expanded: false, peeking: false, sides: .trailing), 0)
        XCTAssertEqual(layout.bodyOrigin(expanded: true, peeking: false, sides: .trailing), -180)
    }

    func testAWholeNotchSitsInTheMiddleOfItsWindow() {
        let state = NotchState()
        state.layout = layout
        XCTAssertEqual(state.shapeOffset, 0)
        state.compact.wingsFit = false
        XCTAssertEqual(state.shapeOffset, 0)
        state.expanded = true
        XCTAssertEqual(state.shapeOffset, 0)
    }

    func testAHalfKeepsItsPlaceWhateverWindowIsAroundIt() {
        let state = NotchState()
        state.layout = layout
        state.compact.sides = .leading
        // In its own window the half fills it.
        let own = layout.windowFrame(notchRect: notchRect, expanded: false, peeking: false, sides: .leading)
        state.drift = notchRect.midX - own.midX
        XCTAssertEqual(state.shapeOffset, 0)
        // In the open window, centred on the notch, it stays left of the middle.
        state.drift = 0
        XCTAssertEqual(state.shapeOffset, own.midX - notchRect.midX)
        state.compact.sides = .trailing
        XCTAssertEqual(state.shapeOffset, notchRect.midX - own.midX)
        // Open, the shape is centred again.
        state.expanded = true
        XCTAssertEqual(state.shapeOffset, 0)
    }

    func testOpenTheNotchIsWholeWhoeverElseIsThere() {
        XCTAssertEqual(layout.windowFrame(notchRect: notchRect, expanded: true, peeking: false, sides: .leading),
                       layout.windowFrame(notchRect: notchRect, expanded: true, peeking: false))
        XCTAssertEqual(NotchLayout.corners(expanded: true, sides: .trailing), NotchCorners(top: 19, bottom: 24))
    }

    func testOpenWindowLeavesRoomForTheShadow() {
        let frame = layout.windowFrame(notchRect: notchRect, expanded: true, peeking: false)
        XCTAssertEqual(frame.size, CGSize(width: 360 + 38 + 48, height: 174 + 24))
        XCTAssertEqual(frame.midX, notchRect.midX)
        XCTAssertEqual(frame.maxY, notchRect.maxY)
    }
}
