//
//  NotchLayout.swift
//  NotchKit
//
//  Created by Kaan Firat.
//

import CoreGraphics

/// The sizes of the black shape and of its window in each state. Pure
/// arithmetic over the notch's size and what the app asked for.
struct NotchLayout: Equatable {
    /// The camera notch, or its stand-in.
    var notch = CGSize(width: 180, height: 32)
    /// Black added beside the notch on each side when closed.
    var wingWidth: CGFloat = 50
    /// Height added under the closed notch for a peek.
    var peekHeight: CGFloat = 22
    /// The app's open content, which sits below the notch's height.
    var expandedContentSize = CGSize(width: 360, height: 112)

    /// Corner radii. The top corners curve outward into the menu bar,
    /// so the shape grows out of the screen edge like the notch itself.
    static let closedRadii = (top: CGFloat(6), bottom: CGFloat(14))
    static let openRadii = (top: CGFloat(19), bottom: CGFloat(24))
    /// Room around the open shape for its shadow.
    static let shadowMargin: CGFloat = 24
    /// The open shape reaches at least this far past the notch on each side.
    static let minimumOverhang: CGFloat = 60

    static func radii(expanded: Bool) -> (top: CGFloat, bottom: CGFloat) {
        expanded ? openRadii : closedRadii
    }

    /// The black body, not counting the outward top corners.
    var compactSize: CGSize { CGSize(width: notch.width + wingWidth * 2, height: notch.height) }

    var peekSize: CGSize { CGSize(width: compactSize.width, height: notch.height + peekHeight) }

    var expandedSize: CGSize {
        CGSize(width: max(expandedContentSize.width, notch.width + Self.minimumOverhang * 2),
               height: notch.height + expandedContentSize.height)
    }

    /// The body's size in a state; open wins over peeking.
    func bodySize(expanded: Bool, peeking: Bool) -> CGSize {
        expanded ? expandedSize : peeking ? peekSize : compactSize
    }

    /// The window around the body: wide enough for the outward top corners
    /// and, open, with room for the shadow.
    func windowSize(expanded: Bool, peeking: Bool) -> CGSize {
        let body = bodySize(expanded: expanded, peeking: peeking)
        if expanded {
            return CGSize(width: body.width + Self.openRadii.top * 2 + Self.shadowMargin * 2,
                          height: body.height + Self.shadowMargin)
        }
        return CGSize(width: body.width + Self.closedRadii.top * 2, height: body.height)
    }

    /// The window's frame, top-centred on the notch. `notchRect` is in
    /// global screen coordinates (origin bottom left).
    func windowFrame(notchRect: CGRect, expanded: Bool, peeking: Bool) -> CGRect {
        let size = windowSize(expanded: expanded, peeking: peeking)
        return CGRect(x: notchRect.midX - size.width / 2, y: notchRect.maxY - size.height, width: size.width, height: size.height)
    }
}
