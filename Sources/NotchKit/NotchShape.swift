//
//  NotchShape.swift
//  NotchKit
//
//  Created by Kaan Firat.
//

import SwiftUI

/// The shape's corner radii, a corner at a time. The top ones curve
/// outward; a half of a shared notch has them on its own side only.
struct NotchCorners: Equatable {
    var topLeading: CGFloat
    var topTrailing: CGFloat
    var bottomLeading: CGFloat
    var bottomTrailing: CGFloat

    init(topLeading: CGFloat, topTrailing: CGFloat, bottomLeading: CGFloat, bottomTrailing: CGFloat) {
        self.topLeading = topLeading
        self.topTrailing = topTrailing
        self.bottomLeading = bottomLeading
        self.bottomTrailing = bottomTrailing
    }

    /// The same on both sides.
    init(top: CGFloat, bottom: CGFloat) {
        self.init(topLeading: top, topTrailing: top, bottomLeading: bottom, bottomTrailing: bottom)
    }
}

/// The notch outline: top corners that curve outward to meet the screen's
/// top edge, and rounded bottom corners. All the radii animate.
struct NotchShape: Shape {
    var corners: NotchCorners

    init(corners: NotchCorners) {
        self.corners = corners
    }

    init(top: CGFloat, bottom: CGFloat) {
        corners = NotchCorners(top: top, bottom: bottom)
    }

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(AnimatablePair(corners.topLeading, corners.topTrailing),
                           AnimatablePair(corners.bottomLeading, corners.bottomTrailing))
        }
        set {
            corners = NotchCorners(topLeading: newValue.first.first, topTrailing: newValue.first.second,
                                   bottomLeading: newValue.second.first, bottomTrailing: newValue.second.second)
        }
    }

    /// The radii that fit `size`; a small shape can't take the full ones.
    static func fittedRadii(top: CGFloat, bottom: CGFloat, in size: CGSize) -> (top: CGFloat, bottom: CGFloat) {
        let fitted = fitted(NotchCorners(top: top, bottom: bottom), in: size)
        return (fitted.topLeading, fitted.bottomLeading)
    }

    static func fitted(_ corners: NotchCorners, in size: CGSize) -> NotchCorners {
        let tl = min(corners.topLeading, size.width / 4)
        let tr = min(corners.topTrailing, size.width / 4)
        let across = (size.width - tl - tr) / 2
        return NotchCorners(topLeading: tl, topTrailing: tr,
                            bottomLeading: min(corners.bottomLeading, size.height - tl, across),
                            bottomTrailing: min(corners.bottomTrailing, size.height - tr, across))
    }

    func path(in rect: CGRect) -> Path {
        let c = Self.fitted(corners, in: rect.size)
        let (left, right) = (rect.minX + c.topLeading, rect.maxX - c.topTrailing)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Outward top-left corner, then down the left side.
        p.addQuadCurve(to: CGPoint(x: left, y: rect.minY + c.topLeading), control: CGPoint(x: left, y: rect.minY))
        p.addLine(to: CGPoint(x: left, y: rect.maxY - c.bottomLeading))
        p.addQuadCurve(to: CGPoint(x: left + c.bottomLeading, y: rect.maxY), control: CGPoint(x: left, y: rect.maxY))
        p.addLine(to: CGPoint(x: right - c.bottomTrailing, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: right, y: rect.maxY - c.bottomTrailing), control: CGPoint(x: right, y: rect.maxY))
        p.addLine(to: CGPoint(x: right, y: rect.minY + c.topTrailing))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: right, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
