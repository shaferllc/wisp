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
spanning the union of every screen, with `window.sharingType = .none`. That one
property excludes the window from
every capture path on macOS — CGWindowList captures, ScreenCaptureKit, the
system screenshot UI, and screen sharing — so the ring exists only on your
physical display. Pointer tracking uses a global `NSEvent` mouse-move
monitor, which (unlike keyboard monitoring) requires no Accessibility
permission.

## Features

- Soft glowing marker that follows the pointer, across all displays and Spaces
  (including over full-screen apps), in four styles: ring, double ring, dot,
  crosshair
- Invisible to screenshots, recordings, and screen sharing (`sharingType = .none`)
- Click-through: the overlay never intercepts a mouse event
- **Highlight on click**: an expanding pulse flashes from the ring on mouse
  down (toggleable)
- **Spotlight**: dims the whole desktop except a soft-edged circle around the
  pointer — and, like the ring, only on your display. Radius, softness, and
  dimming are adjustable; **⌥⌘S** toggles it.
- **Cursor trail**: fading ghosts follow fast pointer movements, so the eye can
  catch up with a flick across the screen
- **Fade when idle**: the marker dims away after a quiet spell and returns the
  moment you move — the spotlight is deliberately left alone
- **Rebindable global hotkeys** for ring and spotlight (Carbon
  `RegisterEventHotKey` — tiny, no dependencies). The recorder rejects a
  shortcut that has no real modifier or that another app already owns.
- **Launch at login** via `SMAppService` — no helper bundle, no login-item plist
- **Keystroke display** (opt-in): shows the keys you press in a HUD. This one
  is for your *audience*, so it defaults to being visible in recordings — see
  [Permissions](#permissions).
- Menu bar app (no Dock icon): toggle ring, spotlight, click pulse, trail, and
  idle fade; Settings
- Settings in five panes — Ring, Motion, Spotlight, Keyboard, General — with
  five color presets plus a custom picker; changes apply live
- Settings persist as JSON in `~/Library/Application Support/Wisp/`, and a file
  written by an older Wisp still loads (missing keys fall back to defaults)

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

None, for everything above except one opt-in extra. Mouse-move monitoring does
not require Accessibility, the overlay draws in Wisp's own window, and the
hotkeys use the Carbon API — so out of the box Wisp never triggers a
permission prompt.

The sole exception is **keystroke display**. Reading keys pressed in *other*
apps needs a global keyboard monitor, and macOS gates those behind
Accessibility. It ships off; nothing is registered and no prompt appears until
you switch it on in Settings › Keyboard. Turn it back off and the monitor is
torn down.

Note the deliberate inversion there: the ring is for you, so it is hidden from
capture, but a keystroke HUD is for your audience, so by default it *is*
captured. A second switch flips it back to display-only.
