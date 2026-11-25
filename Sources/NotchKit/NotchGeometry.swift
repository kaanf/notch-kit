//
//  NotchGeometry.swift
//  NotchKit
//
//  Created by Kaan Firat.
//

import AppKit

/// The measurements of one screen that locate its notch, apart from
/// `NSScreen` so the arithmetic can be tested.
struct ScreenMetrics: Equatable {
    var displayID: CGDirectDisplayID
    /// In global screen coordinates (origin bottom left), as is everything here.
    var frame: CGRect
    var visibleFrame: CGRect
    /// Height of the camera housing; zero on a screen without one.
    var safeAreaTop: CGFloat
    /// The menu bar areas left and right of the camera housing.
    var auxiliaryTopLeft: CGRect?
    var auxiliaryTopRight: CGRect?
}

extension ScreenMetrics {
    init(_ screen: NSScreen) {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        self.init(displayID: number?.uint32Value ?? 0, frame: screen.frame, visibleFrame: screen.visibleFrame,
                  safeAreaTop: screen.safeAreaInsets.top, auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
                  auxiliaryTopRight: screen.auxiliaryTopRightArea)
    }
}

/// Where the notch sits: over the camera notch, or, on a screen without
/// one, a notch-sized space at the top centre of the main screen.
struct NotchGeometry: Equatable {
    /// In global screen coordinates (origin bottom left).
    let rect: CGRect
    /// False for the stand-in on a screen without a camera notch.
    let isHardware: Bool
    /// The display it is on.
    let displayID: CGDirectDisplayID

    /// Width of the stand-in: a MacBook notch's.
    static let standInWidth: CGFloat = 185
    /// The stand-in is as tall as the menu bar, but never shorter than this.
    static let minimumStandInHeight: CGFloat = 24

    init?(notchOf screen: ScreenMetrics) {
        let height = screen.safeAreaTop
        guard height > 0, let left = screen.auxiliaryTopLeft, let right = screen.auxiliaryTopRight else { return nil }
        rect = CGRect(x: left.maxX, y: screen.frame.maxY - height, width: right.minX - left.maxX, height: height)
        isHardware = true
        displayID = screen.displayID
    }

    /// A notch the width of a MacBook's, as tall as the menu bar.
    init(standInOn screen: ScreenMetrics) {
        let menuBar = max(Self.minimumStandInHeight, screen.frame.maxY - screen.visibleFrame.maxY)
        let width = Self.standInWidth
        rect = CGRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - menuBar, width: width, height: menuBar)
        isHardware = false
        displayID = screen.displayID
    }

    /// The screen choice: the first screen with a camera notch, else a
    /// stand-in on the main screen (the first screen if there is no main).
    static func resolve(screens: [ScreenMetrics], main: ScreenMetrics?) -> NotchGeometry? {
        if let real = screens.lazy.compactMap(NotchGeometry.init(notchOf:)).first { return real }
        return (main ?? screens.first).map(NotchGeometry.init(standInOn:))
    }

    /// `resolve` over the screens attached right now.
    static var current: NotchGeometry? {
        resolve(screens: NSScreen.screens.map(ScreenMetrics.init), main: NSScreen.main.map(ScreenMetrics.init))
    }
}
