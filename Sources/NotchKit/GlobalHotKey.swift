//
//  GlobalHotKey.swift
//  NotchKit
//
//  Created by Kaan Firat.
//

import AppKit
import Carbon.HIToolbox

/// One system-wide hotkey, registered through Carbon. Unlike a key event
/// monitor this needs no Accessibility permission and works whichever app
/// is frontmost. The app supplies the shortcut; an app may hold several.
public final class GlobalHotKey {
    private let action: () -> Void
    private let id: UInt32
    private var reference: EventHotKeyRef?
    /// The shortcut currently registered, nil when none is.
    public private(set) var registered: Shortcut?

    /// Carbon calls back through a C function, so live instances are kept
    /// here, by hotkey id, for it to find.
    private static var instances: [UInt32: Weak] = [:]
    private static var nextID: UInt32 = 1
    private static var handler: EventHandlerRef?
    private static let signature: OSType = 0x4E_54_43_48 // "NTCH"

    private struct Weak {
        weak var hotKey: GlobalHotKey?
    }

    /// `action` runs on the main queue each time the shortcut is pressed.
    public init(action: @escaping () -> Void) {
        self.action = action
        id = Self.nextID
        Self.nextID += 1
        Self.instances[id] = Weak(hotKey: self)
        Self.installHandler()
    }

    deinit {
        unregister()
        Self.instances[id] = nil
    }

    /// Registers `shortcut` in place of any previous one; nil just clears it.
    /// Returns false when macOS refuses, usually because another app owns
    /// the same combination.
    @discardableResult
    public func register(_ shortcut: Shortcut?) -> Bool {
        unregister()
        guard let shortcut else { return true }
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &reference)
        guard status == noErr else {
            reference = nil
            return false
        }
        registered = shortcut
        return true
    }

    /// Releases the shortcut, so its keys reach other apps again.
    public func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        registered = nil
    }

    /// One handler serves every instance; it stays installed for the life
    /// of the app.
    private static func installHandler() {
        guard handler == nil else { return }
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, hotKeyID.signature == GlobalHotKey.signature else { return OSStatus(eventNotHandledErr) }
            let id = hotKeyID.id
            DispatchQueue.main.async { GlobalHotKey.instances[id]?.hotKey?.action() }
            return noErr
        }, 1, &pressed, nil, &handler)
    }
}
