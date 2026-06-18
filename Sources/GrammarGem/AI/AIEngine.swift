import Foundation

/// Layer 2 — local-LLM-powered rewriting / tone / "Ask" / translate.
///
/// Backed in production by **MLX** (mlx-swift) running a small instruct model
/// downloaded once from Hugging Face. The protocol isolates the rest of the app
/// from the runtime so the UI, gating, and tests don't depend on MLX being present.
protocol AIEngine: AnyObject {
    /// Whether a model is loaded and ready to run locally.
    var isReady: Bool { get }

    /// Run an action against `text` and return the rewritten result.
    /// Throws on model-not-ready or generation failure. Never performs network I/O.
    func run(_ action: AIAction, on text: String) async throws -> String

    /// Best-effort local tone classification (used by tone-detection UI).
    func detectTone(_ text: String) async -> Tone
}

enum AIEngineError: LocalizedError {
    case modelNotReady
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotReady:
            return "The on-device model isn't ready yet. Finish the first-run download in Settings."
        case .generationFailed(let why):
            return "On-device rewrite failed: \(why)"
        }
    }
}
