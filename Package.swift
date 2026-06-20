// swift-tools-version:5.10
import PackageDescription
import Foundation

// GrammarGem — native macOS menu-bar writing assistant.
//
// Layer-1 grammar is the real **Harper** core (Apache-2.0), embedded as a Rust
// C-FFI static library (see `harper-ffi/`). Build the lib first with
// `harper-ffi/build.sh`; `scripts/build.sh` does this automatically.
//
// Layer-2 AI (rewrite / tone / Ask) is the real on-device LLM via MLX
// (mlx-swift-examples). MLX is **Apple-Silicon / Metal only**, so the app is
// arm64-only (matches the product spec: Apple Silicon, macOS 14+). The Harper
// static lib stays universal; the linker just uses its arm64 slice.

// Absolute path to the prebuilt Harper static lib, independent of build cwd.
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let harperLibDir = packageRoot + "/harper-ffi/lib"

let package = Package(
    name: "GrammarGem",
    platforms: [
        .macOS(.v14) // Apple Silicon, macOS 14+ (per the product spec)
    ],
    products: [
        .executable(name: "GrammarGem", targets: ["GrammarGem"])
    ],
    dependencies: [
        // On-device LLM runtime. Pinned to an exact tag (the LLM libraries still
        // ship from this repo at 2.25.9; the package name is "mlx-libraries").
        .package(url: "https://github.com/ml-explore/mlx-swift-examples.git", exact: "2.25.9"),
        // Secure auto-updates (EdDSA-signed appcast served from grammargem.com).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // C shim exposing libharper_ffi's C ABI (harper-ffi/include/harper.h) to Swift.
        .target(name: "CHarper", path: "Sources/CHarper"),
        .executableTarget(
            name: "GrammarGem",
            dependencies: [
                "CHarper",
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/GrammarGem",
            linkerSettings: [
                // Link the prebuilt Harper static library (arm64 slice).
                .unsafeFlags(["-L\(harperLibDir)", "-lharper_ffi"])
            ]
        ),
        .testTarget(
            name: "GrammarGemTests",
            dependencies: ["GrammarGem"],
            path: "Tests/GrammarGemTests"
        ),
    ]
)
