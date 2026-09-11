# Wisp

*Wisp (n.): a will-o'-the-wisp — a ghostly marsh light only you can follow.*

A cursor highlight ring for presenting, screen sharing, and pointing at
things — in the spirit of GhostCursor, but **free**. The ring glows around
your pointer on every display, yet it never shows up in screenshots, screen
recordings, or the screen you share on a call. Your audience sees a clean
screen; you see exactly where your cursor is. Built the house way: SwiftUI +
AppKit, SwiftPM, `make-app.sh`, no Xcode project, no third-party dependencies,
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
- Settings in six panes — Ring, Motion, Spotlight, Keyboard, General, Account —
  with five color presets plus a custom picker; changes apply live
- Settings persist as JSON in `~/Library/Application Support/Wisp/`, and a file
  written by an older Wisp still loads (missing keys fall back to defaults)

## Install

Download `Wisp.dmg` from the
[latest release](https://github.com/shaferllc/wisp/releases/latest), open it,
and drag `Wisp.app` onto the `Applications` folder beside it. A `.zip` of the
same app is attached to every release too, if you prefer it.

From 0.3.0 Wisp is signed with a Developer ID and notarized by Apple, so it
opens normally. (0.2.0 and earlier were ad-hoc signed and needed right-click →
Open the first time.)

## Registration

Optional and free — every feature works without it. **Settings › Account ›
Register…** opens shafer.llc; after you sign in, the site hands the key back to
Wisp through `wisp://activate`, Wisp checks it with
`shafer.llc/api/licenses/verify`, keeps it in the keychain, and shows the
Account window so you can see it took. There's also a field to paste a key. The
registration code is Shafer LLC's own
[ShaferAccount](https://github.com/shaferllc/swift-licensing), shared by its apps. The
key and a one-way hash of the Mac's hardware ID are all that's sent.

## Build

```
./make-app.sh
```

Builds a release binary, generates the icon, assembles `Wisp.app`, signs it
(with your Developer ID if one is in the keychain, else ad-hoc), installs to
`/Applications`, and launches it. `./make-app.sh --dist` instead packages
`dist/Wisp-<version>.dmg` and `dist/Wisp-<version>.zip` (used by CI).
`SIGN_IDENTITY=` forces ad-hoc; `NOTARY_PROFILE=<profile>` notarizes and
staples.

## Tests & releases

`swift test` runs the settings/persistence and registration suites. On every
push and pull request, CI runs them *and* assembles the real `.app` — bundle
layout, icon generation, the URL scheme, and signing are only exercised there,
so a packaging break can't hide behind a green `swift build`. The disk image is
mounted and checked too, and both artifacts are downloadable from the run.

Releases are driven by the `VERSION` file: bump it in a commit on `main` and
`release.yml` builds the universal app, signs it with the Developer ID,
notarizes and staples it, verifies the disk image, and publishes a GitHub
release (with a stable-named `Wisp.dmg` alongside the versioned one). It reads
the shaferllc org secrets `DEVELOPER_ID_P12`, `DEVELOPER_ID_P12_PASSWORD`,
`NOTARY_API_KEY`, `NOTARY_API_KEY_ID`, and `NOTARY_API_ISSUER`; CI's `signing`
job checks them on every push without building or publishing.

## License

MIT — see [LICENSE](LICENSE).

## Permissions

None, for everything above except one opt-in extra. Mouse-move monitoring does
not require Accessibility, the overlay draws in Wisp's own window, and the
hotkeys use the Carbon API — so out of the box Wisp never triggers a
permission prompt. (Registration talks to shafer.llc over the network, which
needs no permission either.)

The sole exception is **keystroke display**. Reading keys pressed in *other*
apps needs a global keyboard monitor, and macOS gates those behind
Accessibility. It ships off; nothing is registered and no prompt appears until
you switch it on in Settings › Keyboard. Turn it back off and the monitor is
torn down. If you used it before 0.3.0, macOS asks once more after upgrading —
the app is now signed by its developer, and the grant follows the signature.

Note the deliberate inversion there: the ring is for you, so it is hidden from
capture, but a keystroke HUD is for your audience, so by default it *is*
captured. A second switch flips it back to display-only.
