//
//  NotchTests.swift
//  NotchKit
//
//  Created by Kaan Firat.
//

import SwiftUI
import XCTest
@testable import NotchKit

@MainActor
final class NotchTests: XCTestCase {
    /// The README's minimum: three views, everything else defaulted.
    func testANotchStartsHiddenAndClosed() {
        let notch = Notch {
            Image(systemName: "music.note")
        } compactTrailing: {
            Text("3:07")
        } expanded: {
            Text("Hello from the notch")
        }
        notch.expandedContentSize = CGSize(width: 360, height: 120)
        XCTAssertFalse(notch.isVisible)
        XCTAssertFalse(notch.isExpanded)
        XCTAssertEqual(notch.expandedContentSize, CGSize(width: 360, height: 120))
    }

    func testWithoutAResidencyThereAreNoResidents() {
        let notch = Notch {
            EmptyView()
        } compactTrailing: {
            EmptyView()
        } expanded: {
            EmptyView()
        }
        XCTAssertTrue(notch.otherResidents.isEmpty)
        notch.handOver(to: NotchResident(id: "perch", side: .trailing, isExpanded: false, isRequesting: false))
        XCTAssertFalse(notch.isExpanded)
    }

    func testAHiddenNotchIgnoresOpeningAndRequests() {
        var configuration = NotchConfiguration()
        configuration.keyboardFocus = .whenOpenedDeliberately
        configuration.requestSize = CGSize(width: 200, height: 28)
        let notch = Notch(configuration: configuration) {
            EmptyView()
        } compactTrailing: {
            EmptyView()
        } expanded: {
            EmptyView()
        } request: {
            Text("Keyboard wanted")
        }
        var collapses = 0
        notch.onCollapse = { collapses += 1 }
        notch.onKeyDown = { _ in true }
        notch.expand()
        notch.showRequest()
        notch.collapse()
        notch.hideRequest()
        XCTAssertFalse(notch.isExpanded)
        XCTAssertEqual(collapses, 0)
    }
}
