//
//  ShortcutTests.swift
//  NotchKit
//
//  Created by Kaan Firat.
//

import Carbon.HIToolbox
import XCTest
@testable import NotchKit

final class ShortcutTests: XCTestCase {
    func testDisplayStringOrdersModifiersAsMenusDo() {
        let all = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        XCTAssertEqual(Shortcut(keyCode: UInt32(kVK_F5), modifiers: all).displayString, "⌃⌥⇧⌘F5")
    }

    func testDisplayStringNamesSpecialKeys() {
        XCTAssertEqual(Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey)).displayString, "⌘Space")
        XCTAssertEqual(Shortcut(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(optionKey)).displayString, "⌥←")
    }
}
