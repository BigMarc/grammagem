#!/usr/bin/env bash
# Regenerate AppSupport/mlx.metallib — the MLX on-device LLM's compiled Metal
# kernels.
#
# `swift build` (SwiftPM CLI) does NOT compile mlx-swift's .metal sources into a
# metallib, but Xcode's build system does. So we build the package once via
# xcodebuild, then vendor the resulting metallib (shipped colocated with the app
# executable; see scripts/build.sh). Run this when bumping the mlx-swift version.
#
# Requires the Metal Toolchain:  xcodebuild -downloadComponent MetalToolchain
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DD=".xcode-build"

echo "==> xcodebuild (compiles mlx-swift metal kernels — a few minutes)"
xcodebuild build -scheme GrammarGem -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DD" -skipMacroValidation >/dev/null

SRC="$DD/Build/Products/Release/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
[ -f "$SRC" ] || { echo "ERROR: metallib not produced at $SRC" >&2; exit 1; }
cp "$SRC" AppSupport/mlx.metallib
echo "==> vendored AppSupport/mlx.metallib ($(du -h AppSupport/mlx.metallib | cut -f1))"
