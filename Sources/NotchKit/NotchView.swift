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

    var bodySize: CGSize { layout.bodySize(expanded: expanded, peeking: compact.peeking, wings: compact.showsWings) }
    var radii: (top: CGFloat, bottom: CGFloat) { NotchLayout.radii(expanded: expanded, wings: compact.showsWings) }
}

/// The views the app supplied, type-erased so `Notch` needn't be generic.
struct NotchContent {
    var compactLeading: AnyView
    var compactTrailing: AnyView
    var compactLine: AnyView
    var expanded: AnyView
    var peek: AnyView
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
        let radii = state.radii
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if state.expanded {
                    expanded.transition(.scale(scale: 0.85, anchor: .top).combined(with: .opacity))
                } else {
                    VStack(spacing: 0) {
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
            .padding(.horizontal, radii.top)
            .background(Color.black)
            .clipShape(NotchShape(top: radii.top, bottom: radii.bottom))
            // A black hairline over the top edge hides any seam with the
            // screen edge or the camera notch while the shape morphs.
            .overlay(alignment: .top) {
                Rectangle().fill(Color.black).frame(height: 1).padding(.horizontal, radii.top)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(state.expanded ? 0.6 : 0), radius: 8, y: 4)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .contextMenu { content.menu }
    }

    /// A wing each side of the notch; a click anywhere on the row opens.
    /// Without room the wings melt down and inward, toward the line.
    private var compact: some View {
        let wings = state.compact.showsWings
        return HStack(spacing: 0) {
            content.compactLeading.frame(width: state.layout.wingWidth)
                .scaleEffect(wings ? 1 : 0.3, anchor: .bottomTrailing)
            Spacer(minLength: state.layout.notch.width)
            content.compactTrailing.frame(width: state.layout.wingWidth)
                .scaleEffect(wings ? 1 : 0.3, anchor: .bottomLeading)
        }
        .opacity(wings ? 1 : 0)
        .frame(height: state.layout.notch.height)
        .contentShape(Rectangle())
        .onTapGesture { onTap(.both) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// The line under the notch. It and its click area are two halves side
    /// by side, so two apps could take one each; today one view spans both.
    private var chin: some View {
        let halves = state.layout.lineHalves
        return HStack(spacing: 0) {
            Color.clear.contentShape(Rectangle()).onTapGesture { onTap(.leading) }
            Color.clear.contentShape(Rectangle()).onTapGesture { onTap(.trailing) }
        }
        .frame(width: state.layout.notch.width, height: NotchLayout.chinHeight)
        .overlay {
            content.compactLine
                .frame(width: halves.leading.width + halves.trailing.width, height: halves.leading.height)
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
