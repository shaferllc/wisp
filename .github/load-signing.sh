#!/bin/bash
# Loads the Developer ID certificate and the App Store Connect notary key from
# the environment into a throwaway keychain, and stores a notarytool profile
# named "wisp" for make-app.sh. Used by release.yml, and by ci.yml's signing
# job to prove the secrets work before a release depends on them.
#
# A missing secret fails here rather than letting a release quietly fall back
# to an ad-hoc build.
set -euo pipefail

for v in CERT_P12 CERT_PASSWORD NOTARY_KEY NOTARY_KEY_ID NOTARY_ISSUER; do
  [ -n "${!v:-}" ] || { echo "::error::Secret for $v is not set"; exit 1; }
done

KC="$RUNNER_TEMP/signing.keychain-db"
KC_PASS="$(uuidgen)"
security create-keychain -p "$KC_PASS" "$KC"
security set-keychain-settings -lut 21600 "$KC"
security unlock-keychain -p "$KC_PASS" "$KC"

echo "$CERT_P12" | base64 --decode > "$RUNNER_TEMP/cert.p12"
security import "$RUNNER_TEMP/cert.p12" -k "$KC" -P "$CERT_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$KC_PASS" "$KC" >/dev/null
security list-keychains -d user -s "$KC" $(security list-keychains -d user | tr -d '"')

printf '%s' "$NOTARY_KEY" > "$RUNNER_TEMP/notary.p8"
xcrun notarytool store-credentials wisp --keychain "$KC" \
  --key "$RUNNER_TEMP/notary.p8" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER"
rm "$RUNNER_TEMP/cert.p12" "$RUNNER_TEMP/notary.p8"

security find-identity -v -p codesigning "$KC" | grep -q '"Developer ID Application: ' \
  || { echo "::error::DEVELOPER_ID_P12 has no Developer ID Application identity"; exit 1; }
# make-app.sh looks the profile up without --keychain; prove that resolves and
# that Apple accepts the key before any build time is spent.
xcrun notarytool history --keychain-profile wisp >/dev/null
echo "Signing keychain ready; notary profile 'wisp' verified with Apple."
