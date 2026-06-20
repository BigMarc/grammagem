# harper-ffi

A thin Rust static library that exposes the **Harper** grammar core
(Apache-2.0) to Swift over a C-FFI. This directory is a placeholder for the real
integration (spec §1, §2, §8).

The Swift side talks to this through the `GrammarEngine` protocol; today
[`HarperEngine.swift`](../Sources/GrammarGem/Grammar/HarperEngine.swift) ships a
small pure-Swift rule stub so the system loop + tests run with zero native deps.

## Planned shape

```
harper-ffi/
├─ Cargo.toml          # crate-type = ["staticlib"]; depends on `harper-core`
├─ src/lib.rs          # #[no_mangle] extern "C" fns over harper-core
└─ include/harper.h    # C header consumed by Swift (module map / bridging)
```

Sketch of the FFI surface:

```rust
// src/lib.rs
#[no_mangle]
pub extern "C" fn harper_check(text: *const c_char,
                               out_json: *mut *mut c_char) -> usize { /* … */ }

#[no_mangle]
pub extern "C" fn harper_free(ptr: *mut c_char) { /* … */ }
```

## Wiring into SwiftPM

1. Build the static lib: `cargo build --release` → `libharper_ffi.a`.
2. Add a `systemLibrary`/binary target (or `linkerSettings`/`unsafeFlags`) in
   `Package.swift` pointing at the `.a` + the header's module map.
3. Replace the rule set in `HarperEngine.check(_:)` with calls to
   `harper_check`, decoding the returned span JSON into `[Suggestion]`.

> Alternative considered: bundle `harper-ls` and talk to it as a subprocess over
> LSP. The FFI route is leaner (no process, no JSON-RPC) and is preferred.

## Why Harper (not LanguageTool)

Harper is ~1/50th the memory of LanguageTool and needs no multi-GB n-gram data,
so it's the right *embeddable* core. LanguageTool stays an optional power-user
backend, never the default (spec §2).
