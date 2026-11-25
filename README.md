# NotchKit

The plumbing for a macOS app that lives in the notch. NotchKit owns the window over the camera notch, the black shape that grows out of it, and the hover, click and swipe handling that opens and closes it. Your app supplies SwiftUI views for what goes inside.

It was pulled out of [tuno](https://github.com/kaanf/tuno), a now-playing app for the notch.

- A borderless panel above the menu bar, on every Space.
- Finds the notch from the screen's safe area, and follows it when displays change.
- A compact state with a wing each side of the notch, and an open state below it, with a spring between the two.
- Opens on hover, click or a two-finger swipe down. Closes when the pointer leaves or on a swipe up.
- An optional peek: a line under the closed notch for a few seconds.
- Optionally measures the free menu bar space on each side of the notch. When there's no room for the wings, they melt into a thin line under the notch.
- Global shortcuts through `GlobalHotKey`, with no Accessibility permission. Your app chooses the keys.
- Optionally steps aside while the display is in a full-screen Space.

macOS 14 or later, Swift 5.9 or later, no dependencies.

## Install

```swift
dependencies: [
    .package(url: "https://github.com/kaanf/notch-kit.git", branch: "main"),
]
```

## Use

```swift
import AppKit
import NotchKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notch: Notch?
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let notch = Notch {
            Image(systemName: "music.note").foregroundStyle(.white)
        } compactTrailing: {
            Text("3:07").font(.caption.monospacedDigit()).foregroundStyle(.white)
        } expanded: {
            Text("Hello from the notch")
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        notch.expandedContentSize = CGSize(width: 360, height: 120)
        notch.show()
        self.notch = notch

        // ⌥⌘P opens and closes it. Key code 35 is P; 0x0900 is cmdKey | optionKey.
        hotKey = GlobalHotKey { notch.toggleExpanded() }
        hotKey?.register(Shortcut(keyCode: 35, modifiers: 0x0900))
    }
}
```

Run the app as an accessory (`NSApp.setActivationPolicy(.accessory)` or `LSUIElement`) so it has no Dock icon.

## The pieces

`Notch` is the one place that decides what the notch shows and when it opens.

| | |
|---|---|
| `show()`, `hide()` | Put the notch on screen, closed, or take it off. |
| `toggleExpanded()` | Open it and hold it open, or close it. Meant for a shortcut. |
| `peek(for:)` | Show the `peek` view under the closed notch for some seconds. |
| `expandedContentSize` | The size of your open content. It sits below the notch's own height, and can change while open. |
| `showWings(for:)` | Bring the wings out for some seconds even when there's no room for them. |
| `clearance`, `onClearanceChange` | The free menu bar space left and right of the notch, reported separately. |
| `onExpand` | Called when the notch opens. |
| `onSwipe` | Called for a two-finger swipe left or right on the notch. |
| `isVisible`, `isExpanded` | What it's doing now. |

The initialiser takes six views: `compactLeading` and `compactTrailing` for the wings, `expanded` for the open state, and optionally `compactLine` (see below), `peek` and `menu` (the items of a right-click menu). They are created once, so drive them from an `ObservableObject` or `@Observable` model of your own.

`NotchConfiguration` sets the wing width, the peek height, `hidesInFullscreen` and `measuredSides`.

`GlobalHotKey` registers one system-wide `Shortcut`. `Shortcut(event:)` builds one from a key press, for a shortcut recorder, and `displayString` renders it the way menus do ("⌥⌘P").

## When the menu bar is full

Wings sit over the menu bar, so an app with many menus, or a row of status items, can end up underneath them. Set `measuredSides` and NotchKit measures the free space on those sides:

- **Leading**: from the end of the frontmost app's menus to the notch. This is read through Accessibility, so it needs that permission. NotchKit never asks for it; without it the side reads `nil` and counts as free.
- **Trailing**: from the notch to the first status item. This needs no permission, and can be measured on its own.

If a wing doesn't fit on either measured side, both wings go and the notch grows a small chin holding your `compactLine` view, a strip 3 points high, for a progress bar or the like. `showWings(for:)` brings the wings back for a moment, and a peek does the same for as long as it lasts.

Measuring happens when the frontmost app changes, and the answer is remembered per app. Opening and closing menus measures nothing.

**The probe.** macOS doesn't say where other apps' status items are. To find out, NotchKit adds an invisible status item of its own, named "NotchKit Clearance Probe", for about a quarter of a second per measurement: a new item lands at the left end of the row, and where it lands is the answer. A status item manager such as Ice or Bartender may list it briefly. If macOS can't place it, that side counts as full.

In a full-screen Space where the menu bar hides itself, the probe can't be placed, so the notch shows the line there.

## Screens without a notch

If a screen with a camera notch is attached, the notch goes there. Otherwise NotchKit draws a stand-in at the top centre of the main screen: 185 points wide, as tall as the menu bar. It behaves the same as the real one. When displays are plugged in or the lid closes, the notch moves to wherever these rules now put it.

## Full screen

By default the notch stays put in a full-screen Space. Set `hidesInFullscreen` to take it away there and bring it back afterwards.

There is no public API for "is this display full screen", so NotchKit looks for the backdrop window that macOS puts over the wallpaper in a full-screen Space. This needs no permission. It was checked on macOS 26; other versions may need adjusting.

## License

MIT. See [LICENSE](LICENSE).
