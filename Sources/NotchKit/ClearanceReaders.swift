//
//  ClearanceReaders.swift
//  NotchKit
//
//  Created by Kaan Firat.
//

import AppKit
import ApplicationServices

/// Reads where an app's menu titles are, through Accessibility.
enum MenuBarReader {
    /// The frames of `pid`'s menu bar items in global coordinates, or nil
    /// without Accessibility permission or when the app doesn't answer.
    /// Blocks briefly; call it off the main thread.
    static func menuItemFrames(of pid: pid_t) -> [CGRect]? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        // A hung app mustn't hold the measurement up.
        AXUIElementSetMessagingTimeout(app, 0.5)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &bar) == .success,
              let bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
              let items = children as? [AXUIElement] else { return nil }
        return items.compactMap(frame(of:))
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size,
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }
}

/// Finds where the status items begin by adding one of its own.
///
/// macOS doesn't say where other apps' status items are without a
/// permission. But a new status item goes to the left end of the row, so
/// an invisible one, as wide as the space in question, shows whether that
/// much is free and exactly how much is. It exists for a fraction of a
/// second per measurement.
@MainActor
final class StatusItemProbe {
    /// What a status item manager (Ice, Bartender) will list it as.
    static let autosaveName = "NotchKit Clearance Probe"
    /// macOS adds this much to a status item's length for its window.
    private static let windowPadding: CGFloat = 16
    private static let pollInterval: TimeInterval = 0.05
    /// Placement normally settles within 150 ms.
    private static let maxPolls = 12
    /// Equal readings in a row that count as settled.
    private static let settledReadings = 3

    private var item: NSStatusItem?
    private var generation = 0

    /// Puts a probe `width` points wide in the menu bar and reports its
    /// frame and its screen's frame once it has settled, or nil if macOS
    /// hid it. A new call abandons one still in flight.
    func measure(width: CGFloat, completion: @escaping (_ probe: CGRect?, _ screen: CGRect?) -> Void) {
        remove()
        generation += 1
        // macOS would put it back where it last was; it must be leftmost.
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Preferred Position \(Self.autosaveName)")
        let item = NSStatusBar.system.statusItem(withLength: max(0, width - Self.windowPadding))
        item.autosaveName = Self.autosaveName
        item.button?.setAccessibilityLabel(Self.autosaveName)
        self.item = item
        poll(generation: generation, remaining: Self.maxPolls, last: nil, agreed: 0, completion: completion)
    }

    /// Reads the frame until several readings in a row agree: the item is
    /// first laid out off screen, then without its width, then moved.
    private func poll(generation: Int, remaining: Int, last: CGRect?, agreed: Int,
                      completion: @escaping (CGRect?, CGRect?) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pollInterval) { [weak self] in
            guard let self, generation == self.generation else { return }
            let window = self.item?.button?.window
            let screen = window?.screen
            let frame = screen != nil ? window?.frame : nil
            let agreed = frame != nil && frame == last ? agreed + 1 : 1
            if let frame, agreed >= Self.settledReadings {
                self.remove()
                completion(frame, screen?.frame)
            } else if remaining > 0 {
                self.poll(generation: generation, remaining: remaining - 1, last: frame, agreed: agreed, completion: completion)
            } else {
                self.remove()
                completion(nil, nil)
            }
        }
    }

    func cancel() {
        generation += 1
        remove()
    }

    private func remove() {
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }
}
