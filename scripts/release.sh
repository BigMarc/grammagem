#!/usr/bin/env bash
# Cut a GrammarGem release and publish the Sparkle appcast (hosted on grammargem.com).
#
#   ./scripts/release.sh <version>      e.g.  ./scripts/release.sh 0.2.0
#
# Steps: stamp version -> build -> sign inside-out (incl. Sparkle) -> notarize +
# staple -> zip -> generate the EdDSA-signed appcast.xml. Then upload the .zip and
# appcast.xml to grammargem.com so every installed app shows "Update available".
#
# Notarization needs ONE of:
#   NOTARY_PROFILE                              (xcrun notarytool store-credentials)
#   APPLE_ID + TEAM_ID + NOTARY_PASSWORD        (Apple ID + app-specific password)
# Set SKIP_NOTARIZE=1 for a dry run (un-notarized build; do not ship).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:?usage: release.sh <version>   e.g. release.sh 0.2.0}"
APP="dist/GrammarGem.app"
RELDIR="dist/releases"
ZIP="${RELDIR}/GrammarGem-${VERSION}.zip"
DL_PREFIX="${DL_PREFIX:-https://www.grammargem.com/releases/}"
PB=/usr/libexec/PlistBuddy

# 1. Stamp the marketing version + bump the monotonic build number.
CUR_BUILD="$($PB -c 'Print :CFBundleVersion' AppSupport/Info.plist)"
NEW_BUILD=$((CUR_BUILD + 1))
$PB -c "Set :CFBundleShortVersionString ${VERSION}" AppSupport/Info.plist
$PB -c "Set :CFBundleVersion ${NEW_BUILD}" AppSupport/Info.plist
echo "==> Releasing ${VERSION} (build ${NEW_BUILD})"

# 2. Build + sign (inside-out so the embedded Sparkle.framework is valid).
./scripts/build.sh
./scripts/sign-app.sh "$APP"

# 3. Zip.
mkdir -p "$RELDIR"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# 4. Notarize + staple (the ticket lets Sparkle install it without Gatekeeper prompts).
if [ "${SKIP_NOTARIZE:-0}" != "1" ]; then
  echo "==> Notarizing"
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  elif [ -n "${APPLE_ID:-}" ] && [ -n "${TEAM_ID:-}" ] && [ -n "${NOTARY_PASSWORD:-}" ]; then
    xcrun notarytool submit "$ZIP" \
      --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$NOTARY_PASSWORD" --wait
  else
    echo "ERROR: set NOTARY_PROFILE or APPLE_ID+TEAM_ID+NOTARY_PASSWORD (or SKIP_NOTARIZE=1)." >&2
    exit 1
  fi
  xcrun stapler staple "$APP"
  rm -f "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"  # re-zip the stapled app
fi

# 5. Generate the EdDSA-signed appcast (keeps every zip in RELDIR in its history).
GA="$(find .build/artifacts -name generate_appcast -type f | head -1)"
[ -n "$GA" ] || { echo "ERROR: generate_appcast not found (run 'swift package resolve')." >&2; exit 1; }
"$GA" --download-url-prefix "$DL_PREFIX" "$RELDIR"

echo
echo "✓ Release ${VERSION} built. Upload these to grammargem.com:"
echo "    ${ZIP}"
echo "        ->  ${DL_PREFIX}GrammarGem-${VERSION}.zip"
echo "    ${RELDIR}/appcast.xml"
echo "        ->  https://www.grammargem.com/appcast.xml   (matches Info.plist SUFeedURL)"
echo
echo "  Once uploaded, installed apps show an 'Update available' button within a day"
echo "  (or immediately via menu bar -> Check for Updates...)."
