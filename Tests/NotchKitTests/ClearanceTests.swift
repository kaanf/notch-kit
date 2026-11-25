//
//  ClearanceTests.swift
//  NotchKit
//
//  Created by Kaan Firat.
//

import XCTest
@testable import NotchKit

final class ClearanceMathTests: XCTestCase {
    /// A 14" MacBook Pro: notch from 645.5 to 824.5.
    private let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
    private let notch = CGRect(x: 645.5, y: 924, width: 179, height: 32)
    private let external = CGRect(x: 1470, y: 0, width: 2560, height: 1440)

    private func menu(_ x: CGFloat, _ width: CGFloat) -> CGRect {
        CGRect(x: x, y: 0, width: width, height: 24)
    }

    private func probe(_ x: CGFloat, width: CGFloat = 56) -> CGRect {
        CGRect(x: x, y: 923, width: width, height: 33)
    }

    // MARK: Leading

    func testLeadingIsFromTheLastMenuToTheNotch() {
        let menus = [menu(10, 30), menu(40, 60), menu(450, 53)]
        XCTAssertEqual(ClearanceMath.leading(menuItems: menus, notch: notch, screen: screen), 142.5)
    }

    func testLeadingIsZeroWhenMenusReachTheNotch() {
        let menus = [menu(10, 30), menu(600, 60)]
        XCTAssertEqual(ClearanceMath.leading(menuItems: menus, notch: notch, screen: screen), 0)
    }

    func testLeadingWithNoMenusIsEverythingLeftOfTheNotch() {
        XCTAssertEqual(ClearanceMath.leading(menuItems: [], notch: notch, screen: screen), 645.5)
    }

    func testLeadingIgnoresMenusOnAnotherScreen() {
        let menus = [menu(10, 30), menu(1480, 400)]
        XCTAssertEqual(ClearanceMath.leading(menuItems: menus, notch: notch, screen: screen), 605.5)
    }

    func testMenusPastTheNotchAreNoticed() {
        XCTAssertFalse(ClearanceMath.menusPassNotch(menuItems: [menu(10, 30), menu(450, 53)], notch: notch, screen: screen))
        XCTAssertTrue(ClearanceMath.menusPassNotch(menuItems: [menu(10, 30), menu(840, 53)], notch: notch, screen: screen))
    }

    // MARK: Trailing

    func testTrailingIsFromTheNotchToTheProbesRightEdge() {
        let trailing = ClearanceMath.trailing(probe: probe(1146), probeScreen: screen, notch: notch, notchScreen: screen)
        XCTAssertEqual(trailing, 377.5)
    }

    func testProbePushedUnderTheNotchMeansNoRoom() {
        let trailing = ClearanceMath.trailing(probe: probe(818), probeScreen: screen, notch: notch, notchScreen: screen)
        XCTAssertEqual(trailing, 0)
    }

    func testHiddenProbeMeansNoRoom() {
        XCTAssertEqual(ClearanceMath.trailing(probe: nil, probeScreen: screen, notch: notch, notchScreen: screen), 0)
    }

    func testProbeThatJustFitsReportsItsOwnWidth() {
        let trailing = ClearanceMath.trailing(probe: probe(824.5), probeScreen: screen, notch: notch, notchScreen: screen)
        XCTAssertEqual(trailing, 56)
    }

    func testProbeOnAnotherScreenIsCarriedOverByItsDistanceFromTheRightEdge() {
        // Status items take 268 points on the external display, so they start at 1202 on the MacBook.
        let onExternal = probe(external.maxX - 268 - 56)
        let trailing = ClearanceMath.trailing(probe: onExternal, probeScreen: external, notch: notch, notchScreen: screen)
        XCTAssertEqual(trailing, 377.5)
    }

    func testProbeOnAnotherScreenWithTooLittleRoomHereMeansNoRoom() {
        // 620 points of status items leave 25.5 beside the notch.
        let onExternal = probe(external.maxX - 620 - 56)
        let trailing = ClearanceMath.trailing(probe: onExternal, probeScreen: external, notch: notch, notchScreen: screen)
        XCTAssertEqual(trailing, 0)
    }
}

final class ClearanceCacheTests: XCTestCase {
    func testRemembersPerApp() {
        var cache = ClearanceCache()
        cache["com.apple.Safari"] = NotchClearance(leading: 142.5, trailing: 377.5)
        cache["com.apple.Terminal"] = NotchClearance(leading: 20, trailing: 377.5)
        XCTAssertEqual(cache["com.apple.Safari"], NotchClearance(leading: 142.5, trailing: 377.5))
        XCTAssertEqual(cache["com.apple.Terminal"]?.leading, 20)
        XCTAssertNil(cache["com.apple.Music"])
    }

    func testRemoveAllForgetsEverything() {
        var cache = ClearanceCache()
        cache["com.apple.Safari"] = NotchClearance(leading: 1, trailing: 2)
        cache.removeAll()
        XCTAssertNil(cache["com.apple.Safari"])
    }
}
