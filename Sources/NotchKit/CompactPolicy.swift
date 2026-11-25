//
//  CompactPolicy.swift
//  NotchKit
//
//  Created by Kaan Firat.
//

import CoreGraphics

/// Decides what the closed notch looks like: wings beside it when the menu
/// bar has room, otherwise only a line in a chin under it.
enum CompactPolicy {
    /// Whether a wing fits on each side. A side that wasn't measured counts
    /// as free, so an app that measures nothing always has its wings. The
    /// wings come and go together.
    static func wingsFit(clearance: NotchClearance, footprint: CGFloat) -> Bool {
        fits(clearance.leading, footprint) && fits(clearance.trailing, footprint)
    }

    private static func fits(_ side: CGFloat?, _ footprint: CGFloat) -> Bool {
        side.map { $0 >= footprint } ?? true
    }
}

/// The closed notch's state, and what follows from it.
struct CompactState: Equatable {
    /// The menu bar has room for the wings.
    var wingsFit = true
    /// The app asked for the wings for a moment, room or not.
    var wingsForced = false
    /// The peek content is showing under the notch.
    var peeking = false

    /// A peek is as wide as the wings, so it brings them along.
    var showsWings: Bool { wingsFit || wingsForced || peeking }
    /// The line shows only when nothing else is under or beside the notch.
    var showsLine: Bool { !showsWings }

    /// The state once forced wings run out: without room, a peek still up
    /// goes with them, so the chin comes straight back.
    var afterForcedWings: CompactState {
        var next = self
        next.wingsForced = false
        if !wingsFit { next.peeking = false }
        return next
    }
}
