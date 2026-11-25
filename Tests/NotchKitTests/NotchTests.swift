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
}
