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

    func testOpenWindowLeavesRoomForTheShadow() {
        let frame = layout.windowFrame(notchRect: notchRect, expanded: true, peeking: false)
        XCTAssertEqual(frame.size, CGSize(width: 360 + 38 + 48, height: 174 + 24))
        XCTAssertEqual(frame.midX, notchRect.midX)
        XCTAssertEqual(frame.maxY, notchRect.maxY)
    }
}
