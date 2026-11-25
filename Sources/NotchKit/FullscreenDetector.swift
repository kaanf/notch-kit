//
//  FullscreenDetector.swift
//  NotchKit
//
//  Created by Kaan Firat.
//

import AppKit

/// What the window list says about one on-screen window.
struct WindowSnapshot: Equatable {
    var ownerName: String
    /// Only present with Screen Recording permission.
    var name: String?
    var layer: Int
    /// In Core Graphics coordinates (origin top left).
    var bounds: CGRect
}

/// Tells whether a display is showing a full-screen Space.
///
/// macOS puts a backdrop window over the wallpaper in a full-screen Space,
/// and only there. So a display is full screen when the window manager has
/// a second display-sized window down at the wallpaper's depth. Its name
/// would settle it, but names need Screen Recording permission.
enum FullscreenDetector {
    /// Processes that have owned the wallpaper and the backdrop.
    private static let owners: Set<String> = ["WindowManager", "Dock"]
    /// Wallpaper and backdrop sit just above the lowest window level,
    /// far below anything an app can put on screen.
    private static let deepestAppLayer = Int(Int32.min) + 1000

    static func isFullscreen(displayBounds: CGRect, windows: [WindowSnapshot]) -> Bool {
        let backdrops = windows.filter {
            owners.contains($0.ownerName) && $0.layer < deepestAppLayer && $0.bounds == displayBounds
        }
        if backdrops.contains(where: { $0.name == "Fullscreen Backdrop" }) { return true }
        return backdrops.count >= 2
    }

    /// `isFullscreen` over the windows on screen right now.
    static func isFullscreen(displayID: CGDirectDisplayID) -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let windows = list.compactMap { info -> WindowSnapshot? in
            guard let owner = info[kCGWindowOwnerName as String] as? String,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let dictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary) else { return nil }
            return WindowSnapshot(ownerName: owner, name: info[kCGWindowName as String] as? String, layer: layer, bounds: bounds)
        }
        return isFullscreen(displayBounds: CGDisplayBounds(displayID), windows: windows)
    }
}
