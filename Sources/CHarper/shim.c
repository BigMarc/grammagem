// CHarper is a header-only shim that exposes libharper_ffi's C ABI (declared in
// include/harper.h) to Swift as the `CHarper` module. The actual symbols are
// provided by libharper_ffi.a, linked via the GrammarGem target's linkerSettings.
// This translation unit exists only so SwiftPM treats CHarper as a C target.
