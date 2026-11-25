//
//  NotchView.swift
//  NotchKit
//
//  Created by Kaan Firat.
//

import SwiftUI

/// Size and state shared between a surface and its SwiftUI view.
final class NotchState: ObservableObject {
    @Published var expanded = false
    /// Wings, line or peek while closed.
    @Published var compact = CompactState()
    @Published var layout = NotchLayout()

    /// How far the middle of the notch is right of the middle of the
    /// window. Zero for an app with the notch to itself, whose windows are
    /// all centred on it; a half's aren't, so the surface sets this with
    /// every window frame and the shape keeps its place on screen.
    @Published var drift: CGFloat = 0

    var bodySize: CGSize {
        layout.bodySize(expanded: expanded, peeking: compact.peeking, wings: compact.showsWings, sides: compact.sides)
    }

    var corners: NotchCorners {
        NotchLayout.corners(expanded: expanded, wings: compact.showsWings, sides: compact.sides)
    }

    /// How far the shape's middle is right of the window's. Zero for a
    /// whole notch: centred, as the layout puts it anyway.
    var shapeOffset: CGFloat {
        let origin = layout.bodyOrigin(expanded: expanded, peeking: compact.peeking, wings: compact.showsWings, sides: compact.sides)
        return drift + origin + bodySize.width / 2 + (corners.topTrailing - corners.topLeading) / 2
    }

    /// Closed and stepping aside for another app's open panel.
    var hidden: Bool { !expanded && compact.yielded }
}

/// The views the app supplied, type-erased so `Notch` needn't be generic.
struct NotchContent {
    var compactLeading: AnyView
    var compactTrailing: AnyView
    var compactLine: AnyView
    var expanded: AnyView
    var peek: AnyView
    var request: AnyView
    var menu: AnyView
}

/// The black shape and the app's content inside it.
struct NotchView: View {
    @ObservedObject var state: NotchState
    let content: NotchContent
    /// A click on the closed notch, with the half it landed in.
    let onTap: (NotchSides) -> Void

    var body: some View {
        let size = state.bodySize
        let corners = state.corners
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if state.expanded {
                    expanded.transition(.scale(scale: 0.85, anchor: .top).combined(with: .opacity))
                } else {
                    VStack(alignment: chinAlignment, spacing: 0) {
                        compact
                        if state.compact.peeking {
                            content.peek
                                .frame(height: state.layout.peekHeight, alignment: .top)
                                .transition(.opacity)
                        } else if state.compact.showsLine {
                            chin.transition(.opacity)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .padding(.leading, corners.topLeading)
            .padding(.trailing, corners.topTrailing)
            .background(Color.black)
            .clipShape(NotchShape(corners: corners))
            // A black hairline over the top edge hides any seam with the
            // screen edge or the camera notch while the shape morphs.
            .overlay(alignment: .top) {
                Rectangle().fill(Color.black).frame(height: 1)
                    .padding(.leading, corners.topLeading)
                    .padding(.trailing, corners.topTrailing)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(state.expanded ? 0.6 : 0), radius: 8, y: 4)
            .opacity(state.hidden ? 0 : 1)
            .offset(x: state.shapeOffset)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .contextMenu { content.menu }
    }

    /// A wing each side of the notch; a click anywhere on the row opens.
    /// Without room the wings melt down and inward, toward the line. An
    /// app that shares the notch has only the wing on its own side.
    private var compact: some View {
        let wings = state.compact.showsWings
        let sides = state.compact.sides
        return HStack(spacing: 0) {
            wing(content.compactLeading, shown: sides.contains(.leading))
                .scaleEffect(wings ? 1 : 0.3, anchor: .bottomTrailing)
            Spacer(minLength: state.layout.notchShare(sides))
            wing(content.compactTrailing, shown: sides.contains(.trailing))
                .scaleEffect(wings ? 1 : 0.3, anchor: .bottomLeading)
        }
        .opacity(wings ? 1 : 0)
        .frame(height: state.layout.notch.height)
        .contentShape(Rectangle())
        .onTapGesture { onTap(.both) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func wing(_ content: AnyView, shown: Bool) -> some View {
        content.frame(width: shown ? state.layout.wingWidth : 0)
            .opacity(shown ? 1 : 0)
            .accessibilityHidden(!shown)
    }

    /// A half's chin hangs from the notch, not from the middle of its body.
    private var chinAlignment: HorizontalAlignment {
        switch state.compact.sides {
        case .leading: return .trailing
        case .trailing: return .leading
        default: return .center
        }
    }

    /// The line under the notch. It and its click area are two halves side
    /// by side: one app's view spans both, and two apps take one each,
    /// with a gap where they meet.
    private var chin: some View {
        let halves = state.layout.lineHalves
        let sides = state.compact.sides
        let whole = sides == .both
        return HStack(spacing: 0) {
            Color.clear.contentShape(Rectangle()).onTapGesture { onTap(.leading) }
            Color.clear.contentShape(Rectangle()).onTapGesture { onTap(.trailing) }
        }
        .frame(width: state.layout.notchShare(sides), height: NotchLayout.chinHeight)
        .overlay(alignment: whole ? .center : sides == .leading ? .trailing : .leading) {
            content.compactLine
                .frame(width: whole ? halves.leading.width + halves.trailing.width : halves.leading.width - NotchLayout.lineGap / 2,
                       height: halves.leading.height)
                .padding(.horizontal, whole ? 0 : NotchLayout.lineGap / 2)
                .allowsHitTesting(false)
        }
    }

    /// The app's open content, below the notch's own height.
    private var expanded: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: state.layout.notch.height)
            content.expanded
        }
    }
}

/// The request pill: the app's content on a black capsule of its own.
struct RequestPillView: View {
    let content: AnyView
    let onTap: () -> Void

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .onTapGesture(perform: onTap)
            .environment(\.colorScheme, .dark)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
    }
}
