import Foundation

/// A deterministic, on-device "cleanliness" score (0–100) for a chunk of text.
///
/// Honest by construction: it's defined relative to *this* text — weighted issues
/// per 100 words — never a hidden cloud cohort, and grammar/spelling are always
/// fully resolvable, so a clean document genuinely reaches 100. (Contrast with
/// Grammarly's percentile-vs-other-users score, which needs telemetry + an
/// account; see docs/grammarly-value-plan.md §5.)
enum WritingScore {
    /// - Parameters:
    ///   - weightedIssues: sum of `GrammarKind.severity` across outstanding issues.
    ///   - words: total words in the scanned text.
    static func score(weightedIssues: Int, words: Int) -> Int {
        guard words > 0 else { return 100 }
        let perHundredWords = Double(weightedIssues) / Double(words) * 100.0
        // Each weighted issue per 100 words costs ~4 points; clamp to 0…100.
        return max(0, min(100, Int((100.0 - perHundredWords * 4.0).rounded())))
    }
}
