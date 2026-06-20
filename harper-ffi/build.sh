#!/usr/bin/env bash
# Build the UNIVERSAL (Apple Silicon + Intel) Harper static library that the
# Swift app links against:  harper-ffi/lib/libharper_ffi.a
#
# Requires the Rust toolchain (rustup) with both macOS targets:
#   rustup target add aarch64-apple-darwin x86_64-apple-darwin
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# Make cargo available even in non-login shells.
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

echo "==> cargo build --release (aarch64 + x86_64)"
cargo build --release --target aarch64-apple-darwin
cargo build --release --target x86_64-apple-darwin

echo "==> lipo -> lib/libharper_ffi.a (universal)"
mkdir -p lib
lipo -create -output lib/libharper_ffi.a \
  target/aarch64-apple-darwin/release/libharper_ffi.a \
  target/x86_64-apple-darwin/release/libharper_ffi.a

lipo -info lib/libharper_ffi.a
echo "==> done"
