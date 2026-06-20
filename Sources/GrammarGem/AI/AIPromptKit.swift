import Foundation

/// Backend-neutral prompt construction, generation parameters, and output
/// cleanup for Layer-2 actions. Extracted from `MLXEngine` so EVERY `AIEngine`
/// backend (MLX today, Ollama/llama.cpp next, the localhost extension server) is
/// guaranteed to produce identical prompts and identical output trimming — no
/// behavioral drift between runtimes — and so the personal dictionary / a future
/// style guide can inject protected vocabulary in exactly ONE place.
///
/// Everything here is a pure function of its inputs (no MLX, no I/O), which also
/// makes per-action behavior unit-testable without a model present.
enum AIPrompts {

    /// The system prompt for an action. `protectedTerms` (personal-dictionary
    /// entries + future style-guide vocabulary) are terms the model must never
    /// alter, so AI rewrites stop "correcting" brand names and jargon.
    static func systemPrompt(for action: AIAction, protectedTerms: [String] = []) -> String {
        base(for: action) + protectedTermsClause(protectedTerms)
    }

    private static func base(for action: AIAction) -> String {
        switch action {
        case .rewriteClarity:
            return "Rewrite the user's text to be clearer and more concise. Preserve the "
                + "original meaning and the author's voice. Output only the rewritten text."
        case .rewrite:
            return "Paraphrase the user's text. Keep the meaning but vary the wording and "
                + "structure. Output only the rewritten text."
        case .adjustTone(let tone):
            return "Rewrite the user's text in a \(tone.rawValue) tone. Preserve the meaning. "
                + "Output only the rewritten text."
        case .ask(let instruction):
            return "Apply this instruction to the user's text: \(instruction). "
                + "Output only the resulting text."
        case .translate(let language):
            return "Translate the user's text into \(language). Output only the translation."
        case .applyMode(let mode):
            return mode.systemPrompt
        }
    }

    /// Appended to every system prompt: terms the model must reproduce verbatim
    /// (brand names, jargon the user added to their personal dictionary). Capped
    /// so a large dictionary can't blow the context window.
    private static func protectedTermsClause(_ terms: [String]) -> String {
        let cleaned = terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "" }
        let list = cleaned.prefix(50).map { "\"\($0)\"" }.joined(separator: ", ")
        return " Never change, translate, or \"correct\" these exact terms — reproduce them "
            + "verbatim, including capitalization: \(list)."
    }

    /// Low temperature for faithful rewrites; a touch higher for free paraphrase.
    static func temperature(for action: AIAction) -> Float {
        switch action {
        case .rewrite: return 0.5
        case .ask:     return 0.4
        default:       return 0.2
        }
    }

    /// Generation token budget. Honors a Mode's `lengthCap` (in characters) for
    /// short-form modes (Post = 280, Team Chat = 60) so we don't spend the full
    /// 512-token default on a one-line message; falls back to the default otherwise.
    static func maxTokens(for action: AIAction) -> Int {
        let fallback = 512
        guard case .applyMode(let mode) = action, let cap = mode.lengthCap else { return fallback }
        // ~1 token per 3 characters of English, plus headroom; clamp to a floor.
        return min(fallback, max(64, cap / 3 + 48))
    }

    /// Strip a leading "Sure, here's …:" preamble and surrounding quotes that small
    /// instruct models sometimes add, so the result drops cleanly into the field.
    static func clean(_ s: String) -> String {
        var out = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = out.lowercased()
        for prefix in ["sure, here", "sure! here", "here is", "here's", "certainly"] {
            if lower.hasPrefix(prefix), let colon = out.firstIndex(of: ":") {
                let after = out[out.index(after: colon)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !after.isEmpty { out = after }
                break
            }
        }
        if out.count >= 2, out.first == "\"", out.last == "\"" {
            out = String(out.dropFirst().dropLast())
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The tone-classifier system prompt (kept here so any backend reuses it).
    static func toneClassifierPrompt() -> String {
        let options = Tone.allCases.map(\.rawValue).joined(separator: ", ")
        return """
        You are a tone classifier. Read the user's text and respond with exactly ONE \
        word — the single best-matching tone from this list: \(options). \
        Output only that word, lowercase, no punctuation or explanation.
        """
    }

    /// Parse the one-word tone classification output into a `Tone`.
    static func parseTone(_ raw: String) -> Tone {
        let token = raw.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if let exact = Tone(rawValue: token) { return exact }
        let lower = raw.lowercased()
        for tone in Tone.allCases where lower.contains(tone.rawValue) { return tone }
        return .professional
    }
}
