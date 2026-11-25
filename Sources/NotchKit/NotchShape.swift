//
//  NotchShape.swift
//  NotchKit
//
//  Created by Kaan Firat.
//

import SwiftUI

/// The notch outline: top corners that curve outward to meet the screen's
/// top edge, and rounded bottom corners. Both radii animate.
struct NotchShape: Shape {
    var top: CGFloat
    var bottom: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(top, bottom) }
        set { (top, bottom) = (newValue.first, newValue.second) }
    }

    /// The radii that fit `size`; a small shape can't take the full ones.
    static func fittedRadii(top: CGFloat, bottom: CGFloat, in size: CGSize) -> (top: CGFloat, bottom: CGFloat) {
        let t = min(top, size.width / 4)
        let b = min(bottom, size.height - t, (size.width - t * 2) / 2)
        return (t, b)
    }

    func path(in rect: CGRect) -> Path {
        let (t, b) = Self.fittedRadii(top: top, bottom: bottom, in: rect.size)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Outward top-left corner, then down the left side.
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t), control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY), control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b), control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
