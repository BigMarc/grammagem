#!/usr/bin/env bash
# Build (universal), codesign (Hardened Runtime + Developer ID), notarize, and
# staple GrammarGem.app. Requires the Apple Developer Program ($99/yr) — a FIXED
# cost, not per-user.
#
# Credentials are read from the environment or a stored keychain profile — never
# hard-coded here. Provide ONE of:
#   • NOTARY_PROFILE   (a profile saved via: xcrun notarytool store-credentials)
#   • APPLE_ID + TEAM_ID + NOTARY_PASSWORD   (Apple ID + Team ID + app-specific pw)
#
# DEV_ID defaults to this project's identity; override if signing as someone else.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEV_ID="${DEV_ID:-Developer ID Application: Marc Schultheiss (D5KT5B9Z9M)}"
APP="dist/GrammarGem.app"
ZIP="dist/GrammarGem.zip"
ENTITLEMENTS="AppSupport/GrammarGem.entitlements"

echo "==> Building universal bundle"
./scripts/build.sh >/dev/null

echo "==> Codesigning (Hardened Runtime, inside-out incl. Sparkle)"
DEV_ID="$DEV_ID" ./scripts/sign-app.sh "$APP"

echo "==> Zipping"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Notarizing"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
elif [[ -n "${APPLE_ID:-}" && -n "${TEAM_ID:-}" && -n "${NOTARY_PASSWORD:-}" ]]; then
  xcrun notarytool submit "$ZIP" \
    --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$NOTARY_PASSWORD" --wait
else
  echo "ERROR: set NOTARY_PROFILE, or APPLE_ID + TEAM_ID + NOTARY_PASSWORD." >&2
  exit 1
fi

echo "==> Stapling + verifying"
xcrun stapler staple "$APP"
spctl -a -vvv -t install "$APP"

echo "✓ Signed, notarized, stapled (universal): $APP"
