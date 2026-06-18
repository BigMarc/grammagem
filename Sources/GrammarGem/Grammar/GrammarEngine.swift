import Foundation

/// Layer 1 — deterministic, instant, offline grammar checking.
///
/// In production this is backed by **Harper** (Rust, Apache-2.0) via a C-FFI
/// static lib (see `harper-ffi/`) or a bundled `harper-ls` subprocess. The
/// protocol keeps the rest of the app independent of that integration.
protocol GrammarEngine: AnyObject {
    /// Return suggestions over `text` (non-destructive; UI draws underlines).
    func check(_ text: String) -> [Suggestion]

    /// Apply every suggestion to produce a corrected string (used by the
    /// "fix in place" hotkey path).
    func correct(_ text: String) -> String

    /// Words the engine should never flag (names, brand terms, jargon).
    var ignoreList: Set<String> { get set }
}

extension GrammarEngine {
    /// Default correction: apply suggestions right-to-left so offsets stay valid.
    ///
    /// No-op flags (where the replacement equals the original — e.g. a grammar
    /// issue Harper can describe but not auto-fix) are skipped, so "Fix all" /
    /// the in-place hotkey only ever apply real, text-changing corrections and
    /// never silently rewrite a span to itself.
    func correct(_ text: String) -> String {
        let ns = NSMutableString(string: text)
        for s in check(text).sorted(by: { $0.location > $1.location }) {
            guard s.replacement != s.original else { continue }
            guard s.location + s.length <= ns.length else { continue }
            ns.replaceCharacters(in: s.range, with: s.replacement)
        }
        return ns as String
    }
}
