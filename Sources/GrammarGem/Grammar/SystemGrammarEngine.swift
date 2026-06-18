import Foundation
import AppKit

/// Layer 1 orchestrator. The real **Harper** core is the primary engine
/// (grammar, punctuation, repetition, capitalization, spelling); macOS's
/// `NSSpellChecker` is layered on top purely for *extra spelling coverage* from
/// its large system dictionary.
///
/// Two correctness rules make the combination trustworthy:
///  1. **Harper wins on overlap** — a system spelling guess is dropped if Harper
///     already flagged the same span (Harper's fixes carry correct casing + a
///     real explanation).
///  2. **Case-preserving** — a system spelling replacement is matched to the
///     original token's casing, so a mid-sentence word is never spuriously
///     capitalized (the historical `problemm` -> `Problem` bug). Genuine
///     sentence-start capitalization is surfaced separately by Harper.
final class SystemGrammarEngine: GrammarEngine {
    var ignoreList: Set<String> = [] {
        didSet { harper.ignoreList = ignoreList }
    }

    private let checker = NSSpellChecker.shared
    private let tag = NSSpellChecker.uniqueSpellDocumentTag()
    private let harper = HarperEngine()

    func check(_ text: String) -> [Suggestion] {
        guard text.count >= 2 else { return [] }
        var out = harper.check(text)

        // Supplement with NSSpellChecker spelling only (Harper owns grammar),
        // de-duped against Harper spans and case-matched to the original token.
        let spelling = onMain { self.spellingSupplement(text) }
        for s in spelling where !out.contains(where: { overlaps($0.range, s.range) }) {
            out.append(s)
        }
        return out.sorted { $0.location < $1.location }
    }

    private func spellingSupplement(_ text: String) -> [Suggestion] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        let language = checker.language()
        let results = checker.check(
            text, range: full, types: NSTextCheckingResult.CheckingType.spelling.rawValue,
            options: nil, inSpellDocumentWithTag: tag, orthography: nil, wordCount: nil)

        var out: [Suggestion] = []
        for r in results where r.resultType == .spelling {
            let word = ns.substring(with: r.range)
            if ignoreList.contains(word.lowercased()) { continue }
            guard let raw = checker.correction(
                forWordRange: r.range, in: text, language: language, inSpellDocumentWithTag: tag)
                ?? checker.guesses(
                    forWordRange: r.range, in: text, language: language,
                    inSpellDocumentWithTag: tag)?.first
            else { continue }
            let fix = Self.matchingCase(of: word, in: raw)
            guard fix != word else { continue } // never emit a no-op
            out.append(Suggestion(
                location: r.range.location, length: r.range.length,
                original: word, replacement: fix,
                kind: .spelling, message: "Possible spelling mistake"))
        }
        return out
    }

    /// Re-case `replacement` to follow `original`'s casing.
    static func matchingCase(of original: String, in replacement: String) -> String {
        guard let o = original.first, let r = replacement.first else { return replacement }
        // ALL-CAPS original (with at least one cased letter) -> upper the whole thing.
        if original.count > 1, original == original.uppercased(), original != original.lowercased() {
            return replacement.uppercased()
        }
        if o.isLowercase, r.isUppercase {
            return r.lowercased() + replacement.dropFirst()
        }
        if o.isUppercase, r.isLowercase {
            return r.uppercased() + replacement.dropFirst()
        }
        return replacement
    }

    private func overlaps(_ a: NSRange, _ b: NSRange) -> Bool {
        NSIntersectionRange(a, b).length > 0
    }

    private func onMain<T>(_ work: @escaping () -> T) -> T {
        Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work)
    }
}
