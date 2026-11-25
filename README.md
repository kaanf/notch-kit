# NotchKit

The plumbing for a macOS app that lives in the notch. NotchKit owns the window over the camera notch, the black shape that grows out of it, and the hover, click and swipe handling that opens and closes it. Your app supplies SwiftUI views for what goes inside.

It was pulled out of [tuno](https://github.com/kaanf/tuno), a now-playing app for the notch.

- A borderless panel above the menu bar, on every Space.
- Finds the notch from the screen's safe area, and follows it when displays change.
- A compact state with a wing each side of the notch, and an open state below it, with a spring between the two.
- Opens on hover, click or a two-finger swipe down. Closes when the pointer leaves or on a swipe up.
- An optional peek: a line under the closed notch for a few seconds.
- An optional request pill: something the app wants answered, under the notch until the app takes it away.
- Optionally takes the keyboard when opened on purpose, and gives it back on closing.
- Optionally shares the notch with other NotchKit apps: a half each while closed, one panel open at a time.
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
| `expand(held:)`, `collapse()` | Open or close it from code. Held, the default, it stays open as after `toggleExpanded()`; otherwise it closes once the pointer is away. |
| `peek(for:)` | Show the `peek` view under the closed notch for some seconds. |
| `showRequest()`, `hideRequest()` | Show the `request` view until you take it away; see below. |
| `expandedContentSize` | The size of your open content. It sits below the notch's own height, and can change while open. |
| `showWings(for:)` | Bring the wings out for some seconds even when there's no room for them. |
| `clearance`, `onClearanceChange` | The free menu bar space left and right of the notch, reported separately. |
| `onExpand`, `onCollapse` | Called when the notch opens and when it closes. |
| `onKeyDown` | Called for a key press while the notch has the keyboard; return true if you used it. |
| `onSwipe` | Called for a two-finger swipe left or right on the notch. |
| `otherResidents`, `onResidentsChange` | The other apps in the notch, when it is shared; see below. |
| `handOver(to:)` | Close your panel and open another resident's. |
| `isVisible`, `isExpanded` | What it's doing now. |

The initialiser takes seven views: `compactLeading` and `compactTrailing` for the wings, `expanded` for the open state, and optionally `compactLine` (see below), `peek`, `request` and `menu` (the items of a right-click menu). They are created once, so drive them from an `ObservableObject` or `@Observable` model of your own.

`NotchConfiguration` sets the wing width, the peek height, the request pill's size, `keyboardFocus`, `residency`, `hidesInFullscreen` and `measuredSides`.

`GlobalHotKey` registers one system-wide `Shortcut`. `Shortcut(event:)` builds one from a key press, for a shortcut recorder, and `displayString` renders it the way menus do ("⌥⌘P").

## When the menu bar is full

Wings sit over the menu bar, so an app with many menus, or a row of status items, can end up underneath them. Set `measuredSides` and NotchKit measures the free space on those sides:

- **Leading**: from the end of the frontmost app's menus to the notch. This is read through Accessibility, so it needs that permission. NotchKit never asks for it; without it the side reads `nil` and counts as free.
- **Trailing**: from the notch to the first status item. This needs no permission, and can be measured on its own.

If a wing doesn't fit on either measured side, both wings go and the notch grows a small chin holding your `compactLine` view, a strip 3 points high, for a progress bar or the like. `showWings(for:)` brings the wings back for a moment, and a peek does the same for as long as it lasts.

Measuring happens when the frontmost app or Space changes and every five seconds while visible, so permission changes and changing menus or status items do not leave a stale result.

**The probe.** macOS doesn't say where other apps' status items are. To find out, NotchKit adds an invisible status item of its own, named "NotchKit Clearance Probe", for about a quarter of a second per measurement: a new item lands at the left end of the row, and where it lands is the answer. A status item manager such as Ice or Bartender may list it briefly. If macOS can't place it, that side counts as full.

In a full-screen Space where the menu bar hides itself, the probe can't be placed, so the notch shows the line there.

## Requests

A peek ends on its own; a request stays until the app withdraws it. After `showRequest()`:

- With room for the wings, NotchKit draws nothing. Show the request in one of your wings.
- Without room, a black pill of `requestSize` hangs under the notch, holding your `request` view. A click on it opens the notch.

The pill is away while the notch is open, during a peek and while `showWings(for:)` has the wings out, and comes back afterwards.

## The keyboard

By default the notch never takes the keyboard; only a click on a text field inside it does. Set `keyboardFocus` to `.whenOpenedDeliberately` and the notch takes it whenever it is opened on purpose: by a click, a swipe down, `toggleExpanded()` or `expand(held:)`. Opening on hover takes nothing, so brushing the notch doesn't cut off typing in another app.

While the notch has the keyboard it stays open with the pointer away. It closes on `collapse()`, the shortcut, a click elsewhere, or when another window takes the keyboard, and the keyboard then goes back to where it was. The app in front stays in front throughout.

`onKeyDown` sees each key press before the views in the notch do. Return true for the keys you use, and false for the rest so a text field still gets them:

```swift
notch.onKeyDown = { [weak notch] event in
    guard event.keyCode == 53 else { return false }   // esc
    notch?.collapse()
    return true
}
```

## Sharing the notch

Two NotchKit apps running at once each put a window over the same notch, and each takes the pointer for its own: hover one and both open. Give each app a residency and they work it out between them:

```swift
configuration.residency = NotchResidency(id: "tuno", side: .leading)
```

The `id` names the app among the residents; the `side` is the half it keeps while it has company. Without a residency nothing here applies, and the app behaves as if it were alone.

**Alone**, a resident has the whole notch, exactly as without a residency.

**With company**, the closed notch is split down the middle. Each app draws its own wing and the notch's half next to it, and the pointer on one half is nobody else's business. Without room for its wing, an app has its half of the line: `compactLine` gets half the width. Whether a wing fits is judged by the app's own side alone, so a crowded left doesn't cost the app on the right its wing. Open, a panel is as wide as ever.

**One panel is open at a time.** While another app's is open, yours is out of sight altogether, request pill included, and hover and click don't open it. A shortcut, `expand(held:)` or `toggleExpanded()` still does: the other panel closes first, then yours opens. The app the user called for wins. If two ask in the same instant, the one whose `id` comes first alphabetically opens and the other stays closed.

**Switching.** `otherResidents` lists the other apps whose notch is on screen, with `isExpanded` and `isRequesting`, and `onResidentsChange` says when the list changed. NotchKit draws no switch button; draw your own in the open panel and call `handOver(to:)`, which closes your panel and opens theirs:

```swift
// The notch's views are created once, so keep the list in your model.
notch.onResidentsChange = { [weak notch] in model.neighbours = notch?.otherResidents ?? [] }
model.onSwitch = { [weak notch] resident in notch?.handOver(to: resident) }

// In the expanded view:
ForEach(model.neighbours) { resident in
    Button(resident.id) { model.onSwitch(resident) }
        .opacity(resident.isRequesting ? 1 : 0.6)
}
```

A request never closes an open panel. If you call `showRequest()` while another app's panel is open, no pill shows; that app sees your `isRequesting` and can draw attention to its switch button. The pill comes up when the panel closes.

**How they find each other.** Residents talk over distributed notifications, which need no entitlement, app group or shared signing, so apps from different developers can share a notch. Each one announces its whole state when it changes and every 2 seconds; one that has been silent for 6 seconds is dropped, which is how a crashed app's half, or its hold on the open panel, comes back. An app that quits says so at once. After the Mac wakes, everyone starts from scratch.

A few things to know:

- A resident stays out of sight for its first 150 ms, while it hears who else is there. An app started while another's panel is open never flashes its wing.
- Two apps can't have the same side or the same `id`. The one that started second logs a warning and carries on without coordination.
- A hidden notch (`hide()`, or `hidesInFullscreen`) keeps its place among the residents but not its half: the other app has the whole notch until it's back.
- A peek is only as wide as the app's half while the notch is shared.
- If one app has its wing and the other its line, the chin under the notch is half as wide.
- Notifications are not a security boundary: any process in the session can claim to be a resident.

## Screens without a notch

If a screen with a camera notch is attached, the notch goes there. Otherwise NotchKit draws a stand-in at the top centre of the main screen: 185 points wide, as tall as the menu bar. It behaves the same as the real one. When displays are plugged in or the lid closes, the notch moves to wherever these rules now put it.

## Full screen

By default the notch stays put in a full-screen Space. Set `hidesInFullscreen` to take it away there and bring it back afterwards.

There is no public API for "is this display full screen", so NotchKit looks for the backdrop window that macOS puts over the wallpaper in a full-screen Space. This needs no permission. It was checked on macOS 26; other versions may need adjusting.

## License

MIT. See [LICENSE](LICENSE).
