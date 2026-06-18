// swift-tools-version:5.10
import PackageDescription
import Foundation

// GrammaGem — native macOS menu-bar writing assistant.
//
// Layer-1 grammar is the real **Harper** core (Apache-2.0), embedded as a Rust
// C-FFI static library (see `harper-ffi/`). Build the lib first with
// `harper-ffi/build.sh` (universal arm64+x86_64 -> harper-ffi/lib/libharper_ffi.a);
// `scripts/build.sh` does this automatically. The remaining heavyweight pieces
// (MLX local LLM, Sparkle, KeyboardShortcuts) are still behind protocol seams.

// Absolute path to the prebuilt Harper static lib, independent of build cwd.
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let harperLibDir = packageRoot + "/harper-ffi/lib"

let package = Package(
    name: "GrammaGem",
    platforms: [
        .macOS(.v14) // Apple Silicon, macOS 14+ (per the product spec)
    ],
    products: [
        .executable(name: "GrammaGem", targets: ["GrammaGem"])
    ],
    targets: [
        // C shim exposing libharper_ffi's C ABI (harper-ffi/include/harper.h) to Swift.
        .target(name: "CHarper", path: "Sources/CHarper"),
        .executableTarget(
            name: "GrammaGem",
            dependencies: ["CHarper"],
            path: "Sources/GrammaGem",
            linkerSettings: [
                // Link the prebuilt universal Harper static library.
                .unsafeFlags(["-L\(harperLibDir)", "-lharper_ffi"])
            ]
        ),
        .testTarget(
            name: "GrammaGemTests",
            dependencies: ["GrammaGem"],
            path: "Tests/GrammaGemTests"
        ),
    ]
)
