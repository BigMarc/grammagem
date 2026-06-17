import Foundation
import AppKit

/// Real, on-device grammar + spelling using macOS's built-in `NSSpellChecker`
/// (the same engine TextEdit/Mail use). No network, no model — fully local,
/// matching the privacy promise. Augmented with a few deterministic Harper-style
/// rules (repeated words, lowercase "i", common expansions) the system checker
/// doesn't surface.
final class SystemGrammarEngine: GrammarEngine {
    var ignoreList: Set<String> = []

    private let checker = NSSpellChecker.shared
    private let tag = NSSpellChecker.uniqueSpellDocumentTag()
    private let extras = HarperEngine()

    func check(_ text: String) -> [Suggestion] {
        guard text.count >= 2 else { return [] }
        return onMain { self.checkOnMain(text) }
    }

    private func checkOnMain(_ text: String) -> [Suggestion] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        let language = checker.language()
        var out: [Suggestion] = []

        let types = NSTextCheckingResult.CheckingType([.spelling, .grammar]).rawValue
        let results = checker.check(
            text, range: full, types: types, options: nil,
            inSpellDocumentWithTag: tag, orthography: nil, wordCount: nil)

        for r in results {
            switch r.resultType {
            case .spelling:
                let word = ns.substring(with: r.range)
                if ignoreList.contains(word.lowercased()) { continue }
                let fix = checker.correction(
                    forWordRange: r.range, in: text, language: language, inSpellDocumentWithTag: tag)
                    ?? checker.guesses(
                        forWordRange: r.range, in: text, language: language,
                        inSpellDocumentWithTag: tag)?.first
                out.append(Suggestion(
                    location: r.range.location, length: r.range.length,
                    original: word, replacement: fix ?? word,
                    kind: .spelling, message: "Possible spelling mistake"))

            case .grammar:
                let details = r.grammarDetails ?? []
                if details.isEmpty {
                    let phrase = ns.substring(with: r.range)
                    out.append(Suggestion(
                        location: r.range.location, length: r.range.length,
                        original: phrase, replacement: phrase,
                        kind: .grammar, message: "Grammar issue"))
                } else {
                    for d in details {
                        var loc = r.range.location, len = r.range.length
                        if let rv = d[NSGrammarRange] as? NSValue {
                            let sub = rv.rangeValue
                            loc = r.range.location + sub.location
                            len = sub.length
                        }
                        guard len > 0, loc + len <= ns.length else { continue }
                        let phrase = ns.substring(with: NSRange(location: loc, length: len))
                        let message = (d[NSGrammarUserDescription] as? String) ?? "Grammar issue"
                        let corrections = (d[NSGrammarCorrections] as? [String]) ?? []
                        out.append(Suggestion(
                            location: loc, length: len,
                            original: phrase, replacement: corrections.first ?? phrase,
                            kind: .grammar, message: message))
                    }
                }
            default:
                break
            }
        }

        // Deterministic extras, skipping anything overlapping a system result.
        extras.ignoreList = ignoreList
        for h in extras.check(text) where !out.contains(where: { overlaps($0.range, h.range) }) {
            out.append(h)
        }
        return out.sorted { $0.location < $1.location }
    }

    private func overlaps(_ a: NSRange, _ b: NSRange) -> Bool {
        NSIntersectionRange(a, b).length > 0
    }

    private func onMain<T>(_ work: @escaping () -> T) -> T {
        Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work)
    }
}
