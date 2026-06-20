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
    /// `protectedTerms` are vocabulary the model must reproduce verbatim (the
    /// personal dictionary / style-guide terms). Throws on model-not-ready or
    /// generation failure. Never performs network I/O on the on-device backend.
    func run(_ action: AIAction, on text: String, protectedTerms: [String]) async throws -> String

    /// Best-effort local tone classification (used by tone-detection UI).
    func detectTone(_ text: String) async -> Tone

    /// Optionally preload the model so the first real action is instant.
    func warmup() async

    /// Streaming variant: yields incremental output as it generates. The default
    /// implementation wraps `run` as a single chunk, so a backend that doesn't
    /// natively stream still conforms.
    func runStreaming(_ action: AIAction, on text: String, protectedTerms: [String])
        -> AsyncThrowingStream<String, Error>
}

extension AIEngine {
    /// Convenience: run with no protected terms.
    func run(_ action: AIAction, on text: String) async throws -> String {
        try await run(action, on: text, protectedTerms: [])
    }

    /// Default: no preload.
    func warmup() async {}

    /// Default streaming: produce the full result, then emit it as one chunk.
    func runStreaming(_ action: AIAction, on text: String, protectedTerms: [String])
        -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    continuation.yield(try await run(action, on: text, protectedTerms: protectedTerms))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Convenience streaming overload with no protected terms.
    func runStreaming(_ action: AIAction, on text: String) -> AsyncThrowingStream<String, Error> {
        runStreaming(action, on: text, protectedTerms: [])
    }
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
