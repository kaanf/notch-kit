//
//  FullscreenDetectorTests.swift
//  NotchKit
//
//  Created by Kaan Firat.
//

import XCTest
@testable import NotchKit

final class FullscreenDetectorTests: XCTestCase {
    private let display = CGRect(x: 0, y: 0, width: 1470, height: 956)
    private let wallpaperLayer = Int(Int32.min) + 24
    private let backdropLayer = Int(Int32.min) + 26

    private func window(_ owner: String, _ name: String?, _ layer: Int, _ bounds: CGRect) -> WindowSnapshot {
        WindowSnapshot(ownerName: owner, name: name, layer: layer, bounds: bounds)
    }

    /// What a desktop Space lists: menu bar, an app window, wallpaper, backstop.
    private var desktop: [WindowSnapshot] {
        [
            window("Window Server", nil, 24, CGRect(x: 0, y: 0, width: 1470, height: 33)),
            window("Terminal", nil, 0, CGRect(x: 0, y: 33, width: 1470, height: 923)),
            window("WindowManager", nil, wallpaperLayer, display),
            window("Window Server", nil, Int(Int32.min) + 22, display),
        ]
    }

    func testDesktopSpaceIsNotFullscreen() {
        XCTAssertFalse(FullscreenDetector.isFullscreen(displayBounds: display, windows: desktop))
    }

    func testBackdropOverTheWallpaperMeansFullscreen() {
        let windows = desktop + [window("WindowManager", nil, backdropLayer, display)]
        XCTAssertTrue(FullscreenDetector.isFullscreen(displayBounds: display, windows: windows))
    }

    func testNamedBackdropIsEnoughOnItsOwn() {
        let windows = [window("Dock", "Fullscreen Backdrop", backdropLayer, display)]
        XCTAssertTrue(FullscreenDetector.isFullscreen(displayBounds: display, windows: windows))
    }

    func testBackdropOnAnotherDisplayDoesNotCount() {
        let other = CGRect(x: 1470, y: 0, width: 2560, height: 1440)
        let windows = desktop + [window("WindowManager", nil, wallpaperLayer, other), window("WindowManager", nil, backdropLayer, other)]
        XCTAssertFalse(FullscreenDetector.isFullscreen(displayBounds: display, windows: windows))
        XCTAssertTrue(FullscreenDetector.isFullscreen(displayBounds: other, windows: windows))
    }

    func testAppWindowsCoveringTheDisplayDoNotCount() {
        let windows = desktop + [window("Keynote", nil, 0, display), window("WindowManager", nil, 0, display)]
        XCTAssertFalse(FullscreenDetector.isFullscreen(displayBounds: display, windows: windows))
    }
}
