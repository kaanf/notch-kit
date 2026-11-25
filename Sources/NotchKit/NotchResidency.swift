//
//  NotchResidency.swift
//  NotchKit
//
//  Created by Kaan Firat.
//

import Foundation

/// An app's place in a notch it shares with other NotchKit apps; see
/// `NotchConfiguration.residency`.
public struct NotchResidency: Equatable, Sendable {
    /// The app's name among the residents, such as "tuno". No two running
    /// apps may use the same one.
    public var id: String
    /// The half of the notch the app keeps while it has company: exactly
    /// `.leading` or `.trailing`. No two running apps may take the same one.
    public var side: NotchSides

    public init(id: String, side: NotchSides) {
        self.id = id
        self.side = side
    }
}

/// Another app in the notch, as it last described itself.
public struct NotchResident: Identifiable, Equatable, Sendable {
    public let id: String
    public let side: NotchSides
    /// Its panel is open.
    public let isExpanded: Bool
    /// It has a request up; see `Notch.showRequest()`.
    public let isRequesting: Bool
}
