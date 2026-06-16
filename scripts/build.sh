#!/usr/bin/env bash
# Build a runnable, UNIVERSAL (Apple Silicon + Intel) GrammaGem.app bundle.
# Usage: ./scripts/build.sh   (run from the mac/ directory)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="release"
APP="GrammaGem.app"
DIST="dist"

echo "==> Compiling universal (arm64 + x86_64, ${CONFIG})"
swift build -c "${CONFIG}" --arch arm64 --arch x86_64
BIN="$(swift build -c "${CONFIG}" --arch arm64 --arch x86_64 --show-bin-path)"

echo "==> Assembling ${APP}"
rm -rf "${DIST}/${APP}"
mkdir -p "${DIST}/${APP}/Contents/MacOS" "${DIST}/${APP}/Contents/Resources"

cp "${BIN}/GrammaGem" "${DIST}/${APP}/Contents/MacOS/GrammaGem"
cp "AppSupport/Info.plist" "${DIST}/${APP}/Contents/Info.plist"
cp "AppSupport/AppIcon.icns" "${DIST}/${APP}/Contents/Resources/AppIcon.icns"

echo "==> Built ${DIST}/${APP}"
lipo -info "${DIST}/${APP}/Contents/MacOS/GrammaGem"
echo "    Run with: open \"${DIST}/${APP}\"   (grant Accessibility on first launch)"
