//
//  ResidencyChannel.swift
//  NotchKit
//
//  Created by Kaan Firat.
//

import Foundation

/// How the apps in a notch reach each other. Everything sent goes to every
/// resident, the sender included.
protocol ResidencyChannel: AnyObject {
    /// Called on the main thread for each message that arrives.
    var onReceive: ((ResidencyMessage) -> Void)? { get set }
    func send(_ message: ResidencyMessage)
}

/// Distributed notifications: they cross between apps of any developer
/// with no entitlement, group container or signing set-up. They keep no
/// state, which the residents make up for by always sending all of theirs.
///
/// The message travels as JSON in the notification's object rather than
/// its user info, which a sandboxed app isn't allowed to send.
final class DistributedResidencyChannel: NSObject, ResidencyChannel {
    static let name = Notification.Name("com.kaanfirat.NotchKit.residency")

    var onReceive: ((ResidencyMessage) -> Void)?

    override init() {
        super.init()
        // Immediately, or macOS holds the messages back while the app
        // isn't frontmost, which a notch app never is.
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(received(_:)), name: Self.name,
                                                            object: nil, suspensionBehavior: .deliverImmediately)
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func send(_ message: ResidencyMessage) {
        guard let text = Self.encode(message) else { return }
        DistributedNotificationCenter.default().postNotificationName(Self.name, object: text, userInfo: nil,
                                                                     deliverImmediately: true)
    }

    @objc private func received(_ notification: Notification) {
        guard let text = notification.object as? String, let message = Self.decode(text) else { return }
        if Thread.isMainThread {
            onReceive?(message)
        } else {
            DispatchQueue.main.async { [weak self] in self?.onReceive?(message) }
        }
    }

    static func encode(_ message: ResidencyMessage) -> String? {
        (try? JSONEncoder().encode(message)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Nil for anything that isn't a message this version understands.
    static func decode(_ text: String) -> ResidencyMessage? {
        try? JSONDecoder().decode(ResidencyMessage.self, from: Data(text.utf8))
    }
}
