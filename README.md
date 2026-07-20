# Wisp

*Wisp (n.): a will-o'-the-wisp — a ghostly marsh light only you can follow.*

A cursor highlight ring for presenting, screen sharing, and pointing at
things — in the spirit of GhostCursor, but **free**. The ring glows around
your pointer on every display, yet it never shows up in screenshots, screen
recordings, or the screen you share on a call. Your audience sees a clean
screen; you see exactly where your cursor is. Built the house way: SwiftUI +
AppKit, SwiftPM, `make-app.sh`, no Xcode project, no external dependencies,
**no special permissions**.

## The trick

The ring lives in a borderless, transparent, click-through overlay window
with `window.sharingType = .none`. That one property excludes the window from
every capture path on macOS — CGWindowList captures, ScreenCaptureKit, the
system screenshot UI, and screen sharing — so the ring exists only on your
physical display. Pointer tracking uses a global `NSEvent` mouse-move
monitor, which (unlike keyboard monitoring) requires no Accessibility
permission.

## Features

- Soft glowing ring that follows the pointer, across all displays and Spaces
  (including over full-screen apps)
- Invisible to screenshots, recordings, and screen sharing (`sharingType = .none`)
- Click-through: the ring never intercepts a mouse event
- **Highlight on click**: an expanding pulse flashes from the ring on mouse
  down (toggleable)
- Global hotkey **⌥⌘W** to show/hide the ring from anywhere (Carbon
  `RegisterEventHotKey` — tiny, no dependencies)
- Menu bar app (no Dock icon): toggle ring, toggle click pulse, Settings
- Settings: five color presets + custom color picker, size / thickness /
  opacity sliders — changes apply live
- Settings persist as JSON in `~/Library/Application Support/Wisp/`

## Install

Download `Wisp-<version>.zip` from the
[latest release](https://github.com/shaferllc/wisp/releases/latest), unzip,
and drag `Wisp.app` to `/Applications`. The app is ad-hoc signed (not
notarized), so on first launch right-click → Open, or clear quarantine:

```
xattr -d com.apple.quarantine /Applications/Wisp.app
```

## Build

```
./make-app.sh
```

Builds a release binary, generates the icon, assembles `Wisp.app`, installs
to `/Applications`, and launches it. `./make-app.sh --dist` instead packages
`dist/Wisp-<version>.zip` (used by CI).

## Tests & releases

`swift test` runs the settings/persistence test suite; CI runs it on every
push and pull request. Pushing a tag like `v0.2` builds the app, packages
the zip, and publishes a GitHub release automatically.

## License

MIT — see [LICENSE](LICENSE).

## Permissions

None. Mouse-move monitoring does not require Accessibility, the overlay
draws in Wisp's own window, and the hotkey uses the Carbon API — so Wisp
never triggers a permission prompt.
