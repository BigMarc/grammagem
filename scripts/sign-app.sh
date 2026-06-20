#!/usr/bin/env bash
# Code-sign GrammarGem.app with Developer ID + Hardened Runtime, signing the
# embedded Sparkle.framework's nested helpers INSIDE-OUT first (required for a
# valid, notarizable signature).
#
# Usage: ./scripts/sign-app.sh [path/to/GrammarGem.app]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEV_ID="${DEV_ID:-Developer ID Application: Marc Schultheiss (D5KT5B9Z9M)}"
ENTITLEMENTS="AppSupport/GrammarGem.entitlements"
APP="${1:-dist/GrammarGem.app}"

sign() { codesign --force --timestamp --options runtime --sign "$DEV_ID" "$@"; }

FW="${APP}/Contents/Frameworks/Sparkle.framework"
if [ -d "$FW" ]; then
  echo "==> Signing Sparkle.framework (inside-out)"
  V="${FW}/Versions/B"
  for xpc in "$V"/XPCServices/*.xpc; do [ -e "$xpc" ] && sign "$xpc"; done
  [ -e "$V/Updater.app/Contents/MacOS/Autoupdate" ] && sign "$V/Updater.app/Contents/MacOS/Autoupdate" || true
  [ -e "$V/Updater.app" ] && sign "$V/Updater.app"
  [ -e "$V/Autoupdate" ] && sign "$V/Autoupdate"
  sign "$FW"
fi

echo "==> Signing ${APP}"
codesign --force --timestamp --options runtime \
  --entitlements "$ENTITLEMENTS" --sign "$DEV_ID" "$APP"

echo "==> Verifying"
codesign --verify --strict --verbose=2 "$APP"
echo "✓ signed: $APP"
