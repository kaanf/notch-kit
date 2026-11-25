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
    /// Without wings the shape is the notch grown down by this much: a chin
    /// that holds the line.
    static let chinHeight: CGFloat = 5
    static let lineHeight: CGFloat = 3
    /// The line stops short of the chin's rounded corners.
    static let lineInset: CGFloat = 16

    /// Without wings the top corners have nothing to curve out from.
    static func radii(expanded: Bool, wings: Bool = true) -> (top: CGFloat, bottom: CGFloat) {
        expanded ? openRadii : wings ? closedRadii : (top: 0, bottom: closedRadii.bottom)
    }

    /// The black body, not counting the outward top corners.
    var compactSize: CGSize { CGSize(width: notch.width + wingWidth * 2, height: notch.height) }

    var peekSize: CGSize { CGSize(width: compactSize.width, height: notch.height + peekHeight) }

    /// The notch and its chin, when there's no room for wings.
    var lineSize: CGSize { CGSize(width: notch.width, height: notch.height + Self.chinHeight) }

    /// The line's two halves inside the chin, in the body's coordinates
    /// (origin top left). One app owns both today; the split is where two
    /// would meet.
    var lineHalves: (leading: CGRect, trailing: CGRect) {
        let width = max(0, notch.width - Self.lineInset * 2)
        let y = notch.height + (Self.chinHeight - Self.lineHeight) / 2
        let leading = CGRect(x: Self.lineInset, y: y, width: width / 2, height: Self.lineHeight)
        return (leading, leading.offsetBy(dx: width / 2, dy: 0))
    }

    /// Which half of the notch a point at `x` in the body belongs to.
    func side(atX x: CGFloat, bodyWidth: CGFloat) -> NotchSides {
        x < bodyWidth / 2 ? .leading : .trailing
    }

    var expandedSize: CGSize {
        CGSize(width: max(expandedContentSize.width, notch.width + Self.minimumOverhang * 2),
               height: notch.height + expandedContentSize.height)
    }

    /// The body's size in a state; open wins over peeking, and a peek
    /// always has its wings.
    func bodySize(expanded: Bool, peeking: Bool, wings: Bool = true) -> CGSize {
        expanded ? expandedSize : peeking ? peekSize : wings ? compactSize : lineSize
    }

    /// The window around the body: wide enough for the outward top corners
    /// and, open, with room for the shadow.
    func windowSize(expanded: Bool, peeking: Bool, wings: Bool = true) -> CGSize {
        let body = bodySize(expanded: expanded, peeking: peeking, wings: wings)
        if expanded {
            return CGSize(width: body.width + Self.openRadii.top * 2 + Self.shadowMargin * 2,
                          height: body.height + Self.shadowMargin)
        }
        let top = Self.radii(expanded: false, wings: wings || peeking).top
        return CGSize(width: body.width + top * 2, height: body.height)
    }

    /// The window's frame, top-centred on the notch. `notchRect` is in
    /// global screen coordinates (origin bottom left).
    func windowFrame(notchRect: CGRect, expanded: Bool, peeking: Bool, wings: Bool = true) -> CGRect {
        let size = windowSize(expanded: expanded, peeking: peeking, wings: wings)
        return CGRect(x: notchRect.midX - size.width / 2, y: notchRect.maxY - size.height, width: size.width, height: size.height)
    }
}
