//
//  NotchClearance.swift
//  NotchKit
//
//  Created by Kaan Firat.
//

import CoreGraphics

/// The free menu bar space on each side of the notch, in points: from the
/// end of the frontmost app's menus to the notch, and from the notch to the
/// first status item. A side is nil when it wasn't measured or can't be.
public struct NotchClearance: Equatable, Sendable {
    /// Left of the notch. Needs Accessibility permission; nil without it.
    public var leading: CGFloat?
    /// Right of the notch. Exact when the wings fit there, zero when they
    /// don't; needs no permission.
    public var trailing: CGFloat?

    public init(leading: CGFloat? = nil, trailing: CGFloat? = nil) {
        self.leading = leading
        self.trailing = trailing
    }
}

/// The sides of the notch.
public struct NotchSides: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Left of the notch, where the frontmost app's menus are.
    public static let leading = NotchSides(rawValue: 1 << 0)
    /// Right of the notch, where the status items are.
    public static let trailing = NotchSides(rawValue: 1 << 1)
    public static let both: NotchSides = [.leading, .trailing]
}

/// The arithmetic of clearance, apart from how the frames are read. Only
/// horizontal positions matter, and those are the same in AppKit's and
/// Core Graphics' global coordinates.
enum ClearanceMath {
    /// Free space left of the notch, given the frontmost app's menu titles.
    /// Zero when the menus reach or pass the notch.
    static func leading(menuItems: [CGRect], notch: CGRect, screen: CGRect) -> CGFloat {
        let onScreen = menuItems.filter { $0.width > 0 && $0.midX >= screen.minX && $0.midX <= screen.maxX }
        guard let end = onScreen.map(\.maxX).max() else { return notch.minX - screen.minX }
        return max(0, notch.minX - end)
    }

    /// Whether the menus spill past the notch, which macOS does when they
    /// don't fit on its left. Then there's no room on the right either.
    static func menusPassNotch(menuItems: [CGRect], notch: CGRect, screen: CGRect) -> Bool {
        menuItems.contains { $0.width > 0 && $0.midX >= screen.minX && $0.midX <= screen.maxX && $0.maxX > notch.maxX }
    }

    /// Free space right of the notch, from where a probe status item landed.
    ///
    /// A new status item goes to the left end of the others, so its right
    /// edge is where they begin. When the bar has no room for it, macOS
    /// hides it or pushes it under the notch; either way the answer is zero.
    /// - Parameters:
    ///   - probe: The probe's frame, nil if it never appeared.
    ///   - probeScreen: The screen whose menu bar the probe is in.
    static func trailing(probe: CGRect?, probeScreen: CGRect, notch: CGRect, notchScreen: CGRect) -> CGFloat {
        guard let probe else { return 0 }
        if probeScreen == notchScreen {
            return probe.minX >= notch.maxX ? probe.maxX - notch.maxX : 0
        }
        // Another display's menu bar: status items take the same width
        // from the right edge of every screen.
        guard probe.minX >= probeScreen.minX else { return 0 }
        let edge = notchScreen.maxX - (probeScreen.maxX - probe.maxX)
        let gap = edge - notch.maxX
        return gap >= probe.width ? gap : 0
    }
}

/// Measured clearance per app, since menus differ from app to app.
struct ClearanceCache {
    private var entries: [String: NotchClearance] = [:]

    subscript(bundleIdentifier: String) -> NotchClearance? {
        get { entries[bundleIdentifier] }
        set { entries[bundleIdentifier] = newValue }
    }

    mutating func removeAll() {
        entries.removeAll()
    }
}
