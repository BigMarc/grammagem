#!/usr/bin/env bash
# Build a runnable GrammarGem.app bundle (arm64 / Apple Silicon — the MLX
# on-device LLM runtime is Metal-only, so Intel is not supported).
# Usage: ./scripts/build.sh   (run from the mac/ directory)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="release"
APP="GrammarGem.app"
DIST="dist"

echo "==> Building Harper static lib (universal)"
chmod +x harper-ffi/build.sh
./harper-ffi/build.sh

echo "==> Compiling (arm64 / Apple Silicon, ${CONFIG})"
# arm64-only: the MLX on-device LLM runtime is Apple-Silicon / Metal only.
swift build -c "${CONFIG}" --arch arm64
BIN="$(swift build -c "${CONFIG}" --arch arm64 --show-bin-path)"

echo "==> Assembling ${APP}"
rm -rf "${DIST}/${APP}"
mkdir -p "${DIST}/${APP}/Contents/MacOS" "${DIST}/${APP}/Contents/Resources"

cp "${BIN}/GrammarGem" "${DIST}/${APP}/Contents/MacOS/GrammarGem"
cp "AppSupport/Info.plist" "${DIST}/${APP}/Contents/Info.plist"
cp "AppSupport/AppIcon.icns" "${DIST}/${APP}/Contents/Resources/AppIcon.icns"

# SwiftPM resource bundles (tokenizer data, etc.) go in Contents/Resources so
# Bundle.module resolves via the main bundle and the signature stays valid.
shopt -s nullglob
for b in "${BIN}"/*.bundle; do
  cp -R "$b" "${DIST}/${APP}/Contents/Resources/"
done
shopt -u nullglob

# MLX Metal kernels: `swift build` (CLI) does NOT compile mlx-swift's .metal
# sources, so we ship a prebuilt metallib in the exact bundle mlx looks for —
# Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib —
# which mlx finds via the main bundle's resources and which codesigns cleanly.
# Regenerate AppSupport/mlx.metallib with: ./scripts/build-metallib.sh
MLX_RES="${DIST}/${APP}/Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources"
mkdir -p "${MLX_RES}"
cp "AppSupport/mlx.metallib" "${MLX_RES}/default.metallib"

# Embed Sparkle.framework (auto-update) and add an rpath so the executable can
# resolve it at @executable_path/../Frameworks. (Signed inside-out by sign-app.sh.)
echo "==> Embedding Sparkle.framework"
SPARKLE_FW="$(find .build -path '*Sparkle.xcframework/macos-arm64*/Sparkle.framework' -type d | head -1)"
mkdir -p "${DIST}/${APP}/Contents/Frameworks"
cp -R "${SPARKLE_FW}" "${DIST}/${APP}/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" \
  "${DIST}/${APP}/Contents/MacOS/GrammarGem" 2>/dev/null || true

echo "==> Built ${DIST}/${APP}"
lipo -info "${DIST}/${APP}/Contents/MacOS/GrammarGem"
echo "    Run with: open \"${DIST}/${APP}\"   (grant Accessibility on first launch)"
