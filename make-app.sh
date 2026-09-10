#!/bin/bash
# Usage:
#   ./make-app.sh          build for this Mac, install to /Applications, launch
#   ./make-app.sh --dist   build a universal dist/Wisp.app plus a .zip and .dmg
#
# The version comes from the VERSION file; VERSION=x.y.z in the environment
# overrides it, which is how the release workflow stamps a build.
#
# Signing: a Developer ID from the keychain when there is one, else ad-hoc.
# SIGN_IDENTITY names one explicitly; an empty SIGN_IDENTITY= forces ad-hoc,
# which is what CI's plain build job gets. NOTARY_PROFILE names a
# `notarytool store-credentials` keychain profile; unset skips notarization.
set -euo pipefail
cd "$(dirname "$0")"

DIST=0
[ "${1:-}" = "--dist" ] && DIST=1
SHORT_VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION 2>/dev/null || echo 0.1.0)}"
# CFBundleVersion must increase between builds; CI's run number does, locally 1 is fine.
WISP_BUILD="${WISP_BUILD:-${GITHUB_RUN_NUMBER:-1}}"

if [ "$DIST" = "1" ]; then
  # Anything people download has to run on both architectures — an arm64-only
  # binary is a broken download for every Intel Mac. The local install path
  # stays single-arch because it only ever has to run on this machine.
  echo "› Building universal release binary…"
  swift build -c release --arch arm64 --arch x86_64
  BINARY=".build/apple/Products/Release/Wisp"
else
  echo "› Building release binary…"
  swift build -c release
  BINARY=".build/release/Wisp"
fi

if [ ! -f AppIcon.icns ] || [ make-icon.swift -nt AppIcon.icns ]; then
  echo "› Generating AppIcon.icns…"
  swift make-icon.swift
fi

STAGE="$(mktemp -d)"
APP="$STAGE/Wisp.app"
echo "› Assembling in staging: $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY"     "$APP/Contents/MacOS/Wisp"
cp AppIcon.icns  "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                 <string>Wisp</string>
    <key>CFBundleDisplayName</key>          <string>Wisp</string>
    <key>CFBundleIdentifier</key>           <string>com.tomshafer.wisp</string>
    <key>CFBundleVersion</key>              <string>${WISP_BUILD}</string>
    <key>CFBundleShortVersionString</key>   <string>${SHORT_VERSION}</string>
    <key>CFBundleExecutable</key>           <string>Wisp</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>CFBundleSupportedPlatforms</key>   <array><string>MacOSX</string></array>
    <key>CFBundleIconFile</key>             <string>AppIcon</string>
    <key>CFBundleIconName</key>             <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>       <string>14.0</string>
    <key>LSUIElement</key>                  <true/>
    <key>NSHighResolutionCapable</key>      <true/>
    <!-- shafer.llc hands a registration key back via wisp://activate?key=…&state=… -->
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>      <string>com.tomshafer.wisp</string>
            <key>CFBundleURLSchemes</key>   <array><string>wisp</string></array>
        </dict>
    </array>
    <key>NSHumanReadableCopyright</key>     <string>© 2026 Tom Shafer</string>
</dict>
</plist>
PLIST

SIGN_IDENTITY="${SIGN_IDENTITY-$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)}"
xattr -cr "$APP" 2>/dev/null || true
if [ -n "$SIGN_IDENTITY" ]; then
  echo "› Signing with $SIGN_IDENTITY"
  # Hardened runtime + a secure timestamp are what notarization requires. Wisp
  # uses nothing the runtime gates behind an entitlement — Accessibility, for
  # keystroke display, is TCC-only — so there's no entitlements file.
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
  echo "› No Developer ID certificate — ad-hoc signing"
  codesign --force --sign - "$APP"
fi

NOTARY_PROFILE="${NOTARY_PROFILE:-}"
if [ -n "$NOTARY_PROFILE" ] && [ -z "$SIGN_IDENTITY" ]; then
  echo "NOTARY_PROFILE is set but there's no Developer ID identity to sign with" >&2
  exit 1
fi
# stapler fails if Apple rejected the submission, so a bad build stops here;
# `xcrun notarytool log <id> --keychain-profile …` says why.
notarize() {
  echo "› Notarizing $(basename "$1") (takes a few minutes)…"
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}

if [ "$DIST" = "1" ]; then
  rm -rf dist
  mkdir -p dist
  /bin/mv "$APP" dist/Wisp.app
  rm -rf "$STAGE"

  # Notarize and staple the app itself first, so the .zip and the copy inside
  # the .dmg both carry the ticket and open offline.
  if [ -n "$NOTARY_PROFILE" ]; then
    /usr/bin/ditto -c -k --keepParent dist/Wisp.app dist/notarize.zip
    notarize dist/notarize.zip
    rm dist/notarize.zip
    xcrun stapler staple dist/Wisp.app
  fi

  echo "› Packaging dist/Wisp-${SHORT_VERSION}.zip"
  /usr/bin/ditto -c -k --keepParent dist/Wisp.app "dist/Wisp-${SHORT_VERSION}.zip"

  # A DMG alongside the zip: it opens to a window holding Wisp.app next to an
  # /Applications alias, so installing is one drag rather than "unzip, then
  # find where it went". UDZO is compressed and read-only.
  echo "› Packaging dist/Wisp-${SHORT_VERSION}.dmg"
  DMG_ROOT="$(mktemp -d)"
  /bin/cp -R dist/Wisp.app "$DMG_ROOT/Wisp.app"
  /bin/ln -s /Applications "$DMG_ROOT/Applications"
  /usr/bin/hdiutil create \
    -volname "Wisp ${SHORT_VERSION}" \
    -srcfolder "$DMG_ROOT" \
    -fs HFS+ -format UDZO -ov -quiet \
    "dist/Wisp-${SHORT_VERSION}.dmg"
  rm -rf "$DMG_ROOT"
  if [ -n "$SIGN_IDENTITY" ]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "dist/Wisp-${SHORT_VERSION}.dmg"
  fi
  if [ -n "$NOTARY_PROFILE" ]; then
    notarize "dist/Wisp-${SHORT_VERSION}.dmg"
    xcrun stapler staple "dist/Wisp-${SHORT_VERSION}.dmg"
  fi
  echo "› Packaged: dist/Wisp-${SHORT_VERSION}.dmg"
else
  DEST="/Applications/Wisp.app"
  echo "› Installing to $DEST"
  /usr/bin/pkill -x Wisp 2>/dev/null || true
  /bin/sleep 0.3
  rm -rf "$DEST"
  /bin/mv "$APP" "$DEST"
  rm -rf "$STAGE"
  open "$DEST"
  echo "› Installed and launched: $DEST"
fi
