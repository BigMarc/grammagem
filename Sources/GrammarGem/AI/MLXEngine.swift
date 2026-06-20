import Foundation
import MLXLMCommon
import MLXLLM

/// Layer 2 — the real on-device LLM (rewrite / tone / "Ask" / translate), backed
/// by **MLX** via mlx-swift-examples (verified against tag 2.25.9; SPM package
/// "mlx-libraries", products MLXLLM + MLXLMCommon).
///
/// Loads weights ONLY from a local on-disk snapshot (ModelManager's download
/// directory) — `ModelConfiguration(directory:)` never contacts the network, so
/// inference is fully on-device, honoring the privacy promise.
///
/// API surface used (all confirmed in the 2.25.9 source):
///   ModelConfiguration(directory:)                 MLXLMCommon/ModelConfiguration.swift
///   LLMModelFactory.shared.loadContainer(...)      MLXLLM/LLMModelFactory.swift
///   ModelContainer.perform { context in ... }      MLXLMCommon/ModelContainer.swift
///   context.processor.prepare(input: UserInput(chat:))   MLXLMCommon/UserInput.swift
///   MLXLMCommon.generate(...) -> AsyncStream<Generation>  MLXLMCommon/Evaluate.swift
final class MLXEngine: AIEngine {

    /// Returns the local model snapshot directory if a complete model is present,
    /// else nil. Owned by ModelManager; MLXEngine only loads + infers.
    private let modelDirectoryProvider: () -> URL?

    /// Serializes the (expensive) first load and caches the container.
    private let loader = ContainerLoader()

    init(modelDirectoryProvider: @escaping () -> URL?) {
        self.modelDirectoryProvider = modelDirectoryProvider
    }

    var isReady: Bool { modelDirectoryProvider() != nil }

    // MARK: - AIEngine

    func run(_ action: AIAction, on text: String, protectedTerms: [String]) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        let container = try await container()
        let params = GenerateParameters(temperature: AIPrompts.temperature(for: action))
        let raw = try await complete(
            system: AIPrompts.systemPrompt(for: action, protectedTerms: protectedTerms),
            user: trimmed,
            maxTokens: AIPrompts.maxTokens(for: action),
            parameters: params, container: container)
        return AIPrompts.clean(raw)
    }

    /// Preload the model container so the first real action doesn't pay the
    /// multi-second load. Safe to call repeatedly (the loader caches).
    func warmup() async {
        _ = try? await container()
    }

    func runStreaming(_ action: AIAction, on text: String, protectedTerms: [String])
        -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continuation.yield(text); continuation.finish(); return }
                do {
                    let container = try await container()
                    var params = GenerateParameters(temperature: AIPrompts.temperature(for: action))
                    params.maxTokens = AIPrompts.maxTokens(for: action)
                    let system = AIPrompts.systemPrompt(for: action, protectedTerms: protectedTerms)
                    try await container.perform { context in
                        let input = try await context.processor.prepare(
                            input: UserInput(chat: [.system(system), .user(trimmed)]))
                        let stream = try MLXLMCommon.generate(
                            input: input, parameters: params, context: context)
                        for await item in stream {
                            if let chunk = item.chunk { continuation.yield(chunk) }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func detectTone(_ text: String) async -> Tone {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .professional }
        do {
            let container = try await container()
            let raw = try await complete(
                system: AIPrompts.toneClassifierPrompt(), user: trimmed, maxTokens: 8,
                parameters: GenerateParameters(temperature: 0.0), container: container)
            return AIPrompts.parseTone(raw)
        } catch {
            return .professional
        }
    }

    // MARK: - Loading

    private func container() async throws -> ModelContainer {
        guard let dir = modelDirectoryProvider() else { throw AIEngineError.modelNotReady }
        return try await loader.container(at: dir)
    }

    // MARK: - Generation

    private func complete(system: String, user: String, maxTokens: Int,
                          parameters: GenerateParameters,
                          container: ModelContainer) async throws -> String {
        do {
            return try await container.perform { context in
                let input = try await context.processor.prepare(
                    input: UserInput(chat: [.system(system), .user(user)]))
                var params = parameters
                params.maxTokens = maxTokens
                var out = ""
                let stream = try MLXLMCommon.generate(
                    input: input, parameters: params, context: context)
                for await item in stream {
                    if let chunk = item.chunk { out += chunk }
                }
                return out
            }
        } catch let error as AIEngineError {
            throw error
        } catch {
            throw AIEngineError.generationFailed(error.localizedDescription)
        }
    }

    // Prompt construction, temperature, token budget, and output cleanup now live
    // in `AIPrompts` (backend-neutral; see AIPromptKit.swift) so every AIEngine
    // backend produces identical prompts and identical output trimming.
}

/// Caches one loaded `ModelContainer` (keyed by directory) and coalesces
/// concurrent first-loads. `ModelContainer` is itself an actor, so generation
/// calls through it are serialized safely.
private actor ContainerLoader {
    private var cached: (url: URL, container: ModelContainer)?

    func container(at directory: URL) async throws -> ModelContainer {
        if let cached, cached.url == directory { return cached.container }
        let configuration = ModelConfiguration(directory: directory)
        let container = try await LLMModelFactory.shared.loadContainer(configuration: configuration)
        cached = (directory, container)
        return container
    }
}
