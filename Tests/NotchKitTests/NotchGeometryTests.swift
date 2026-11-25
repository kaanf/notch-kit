//
//  NotchGeometryTests.swift
//  NotchKit
//
//  Created by Kaan Firat.
//

import XCTest
@testable import NotchKit

final class NotchGeometryTests: XCTestCase {
    /// A 14" MacBook Pro at its default scaling.
    private let macBook = ScreenMetrics(
        displayID: 1,
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
        safeAreaTop: 38,
        auxiliaryTopLeft: CGRect(x: 0, y: 944, width: 663, height: 38),
        auxiliaryTopRight: CGRect(x: 848, y: 944, width: 664, height: 38)
    )

    /// An external 1440p display to the right of the MacBook.
    private let external = ScreenMetrics(
        displayID: 2,
        frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1415),
        safeAreaTop: 0,
        auxiliaryTopLeft: nil,
        auxiliaryTopRight: nil
    )

    func testHardwareNotchSitsBetweenTheAuxiliaryAreas() throws {
        let notch = try XCTUnwrap(NotchGeometry(notchOf: macBook))
        XCTAssertEqual(notch.rect, CGRect(x: 663, y: 944, width: 185, height: 38))
        XCTAssertTrue(notch.isHardware)
        XCTAssertEqual(notch.displayID, 1)
    }

    func testScreenWithoutSafeAreaHasNoHardwareNotch() {
        XCTAssertNil(NotchGeometry(notchOf: external))
    }

    func testSafeAreaWithoutAuxiliaryAreasIsNotANotch() {
        var screen = macBook
        screen.auxiliaryTopRight = nil
        XCTAssertNil(NotchGeometry(notchOf: screen))
    }

    func testStandInIsCentredAndAsTallAsTheMenuBar() {
        let notch = NotchGeometry(standInOn: external)
        XCTAssertEqual(notch.rect, CGRect(x: 1512 + 1280 - 92.5, y: 1415, width: 185, height: 25))
        XCTAssertFalse(notch.isHardware)
        XCTAssertEqual(notch.displayID, 2)
    }

    func testStandInKeepsAMinimumHeightWhenTheMenuBarIsHidden() {
        var screen = external
        screen.visibleFrame = screen.frame
        let notch = NotchGeometry(standInOn: screen)
        XCTAssertEqual(notch.rect.height, 24)
        XCTAssertEqual(notch.rect.maxY, screen.frame.maxY)
    }

    func testResolvePrefersTheHardwareNotchOverTheMainScreen() {
        let notch = NotchGeometry.resolve(screens: [external, macBook], main: external)
        XCTAssertEqual(notch?.displayID, 1)
        XCTAssertEqual(notch?.isHardware, true)
    }

    func testResolveFallsBackToAStandInOnTheMainScreen() {
        var second = external
        second.displayID = 3
        second.frame.origin.x += 2560
        second.visibleFrame.origin.x += 2560
        let notch = NotchGeometry.resolve(screens: [external, second], main: second)
        XCTAssertEqual(notch?.displayID, 3)
        XCTAssertEqual(notch?.isHardware, false)
    }

    func testResolveUsesTheFirstScreenWithoutAMainScreen() {
        XCTAssertEqual(NotchGeometry.resolve(screens: [external], main: nil)?.displayID, 2)
    }

    func testResolveWithoutScreensIsNil() {
        XCTAssertNil(NotchGeometry.resolve(screens: [], main: nil))
    }
}

final class NotchShapeTests: XCTestCase {
    func testRadiiThatFitAreKept() {
        let radii = NotchShape.fittedRadii(top: 6, bottom: 14, in: CGSize(width: 297, height: 38))
        XCTAssertEqual(radii.top, 6)
        XCTAssertEqual(radii.bottom, 14)
    }

    func testRadiiShrinkToFitASmallShape() {
        let radii = NotchShape.fittedRadii(top: 19, bottom: 24, in: CGSize(width: 40, height: 20))
        XCTAssertEqual(radii.top, 10)
        XCTAssertEqual(radii.bottom, 10)
    }
}
