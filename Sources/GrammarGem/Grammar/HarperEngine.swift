import Foundation
import CHarper

/// Layer 1 — the real **Harper** grammar core (Apache-2.0), embedded via a Rust
/// C-FFI static lib (`harper-ffi/`, harper-core 2.5.0). Fully offline,
/// deterministic, and fast — real subject-verb agreement, verb forms,
/// punctuation, repetition, capitalization and spelling, not just a spell check.
///
/// `harper_check` returns a JSON array of spans with **char (Unicode scalar)**
/// offsets; we map those onto UTF-16 `NSRange` offsets so they compose with the
/// rest of the app (AX ranges, `NSMutableString`).
final class HarperEngine: GrammarEngine {
    var ignoreList: Set<String> = []

    func check(_ text: String) -> [Suggestion] {
        guard !text.isEmpty else { return [] }

        // Call into Rust. The returned C string is heap-allocated by Harper and
        // must be freed with harper_free (it outlives the withCString buffer).
        guard let raw = text.withCString({ harper_check($0) }) else { return [] }
        defer { harper_free(raw) }

        let json = String(cString: raw)
        guard let data = json.data(using: .utf8),
              let lints = try? JSONDecoder().decode([HarperLint].self, from: data)
        else { return [] }

        // Harper can emit several lints over the SAME span (e.g. two phrasings of
        // "checkin" -> "check in"). Keep the first (highest-priority) per span so
        // the right-to-left bulk apply in `correct()` never double-writes a range.
        var kept: [Suggestion] = []
        for lint in lints {
            guard lint.len > 0 || !lint.replacement.isEmpty else { continue }
            guard let range = Self.utf16Range(scalarStart: lint.start, scalarLen: lint.len, in: text)
            else { continue }
            let original = (text as NSString).substring(with: range)
            if !original.isEmpty, ignoreList.contains(original.lowercased()) { continue }
            if kept.contains(where: { NSIntersectionRange($0.range, range).length > 0 }) { continue }
            kept.append(Suggestion(
                location: range.location, length: range.length,
                original: original, replacement: lint.replacement,
                kind: GrammarKind(harperKind: lint.kind), message: lint.message))
        }
        return kept.sorted { $0.location < $1.location }
    }

    // MARK: - FFI decoding

    private struct HarperLint: Decodable {
        let start: Int
        let len: Int
        let replacement: String
        let message: String
        let kind: String
    }

    /// Map a Harper char-span (Unicode scalar offsets, end-exclusive) onto a
    /// UTF-16 `NSRange`. Scalar boundaries are always UTF-16 boundaries, so the
    /// conversion is exact.
    static func utf16Range(scalarStart: Int, scalarLen: Int, in text: String) -> NSRange? {
        let scalars = text.unicodeScalars
        guard let s = scalars.index(scalars.startIndex, offsetBy: scalarStart, limitedBy: scalars.endIndex),
              let e = scalars.index(s, offsetBy: scalarLen, limitedBy: scalars.endIndex)
        else { return nil }
        let location = text.utf16.distance(from: text.utf16.startIndex, to: s)
        let length = text.utf16.distance(from: s, to: e)
        return NSRange(location: location, length: length)
    }
}

extension GrammarKind {
    /// Map Harper's `kind` string (see harper.h) onto our category enum.
    init(harperKind kind: String) {
        switch kind {
        case "spelling": self = .spelling
        case "punctuation": self = .punctuation
        case "repetition": self = .repetition
        case "capitalization": self = .capitalization
        case "phrasing": self = .phrasing
        default: self = .grammar
        }
    }
}
