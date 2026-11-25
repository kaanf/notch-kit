//
//  NotchPanel.swift
//  NotchKit
//
//  Created by Kaan Firat.
//

import AppKit
import SwiftUI

/// Borderless and non-activating, above the menu bar on every Space.
final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
    }

    /// It sits over the menu bar on purpose; don't push it below.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { true }
}

/// Reports the pointer entering and leaving the whole panel.
final class NotchContainerView: NSView {
    var onPointerEntered: (() -> Void)?
    var onPointerExited: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onPointerEntered?() }
    override func mouseExited(with event: NSEvent) { onPointerExited?() }
}

/// Buttons respond to the first click even though the app isn't active;
/// trackpad scrolls are handed on as gestures.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    var onScroll: ((NSEvent) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func scrollWheel(with event: NSEvent) { onScroll?(event) }
}
