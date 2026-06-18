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

    func run(_ action: AIAction, on text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        let container = try await container()
        let params = GenerateParameters(temperature: temperature(for: action))
        let raw = try await complete(
            system: systemPrompt(for: action), user: trimmed,
            maxTokens: 512, parameters: params, container: container)
        return clean(raw)
    }

    func detectTone(_ text: String) async -> Tone {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .professional }
        let options = Tone.allCases.map(\.rawValue).joined(separator: ", ")
        let system = """
        You are a tone classifier. Read the user's text and respond with exactly ONE \
        word — the single best-matching tone from this list: \(options). \
        Output only that word, lowercase, no punctuation or explanation.
        """
        do {
            let container = try await container()
            let raw = try await complete(
                system: system, user: trimmed, maxTokens: 8,
                parameters: GenerateParameters(temperature: 0.0), container: container)
            return parseTone(raw)
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

    // MARK: - Prompting

    private func systemPrompt(for action: AIAction) -> String {
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

    /// Low temperature for faithful rewrites; a touch higher for free paraphrase.
    private func temperature(for action: AIAction) -> Float {
        switch action {
        case .rewrite: return 0.5
        case .ask:     return 0.4
        default:       return 0.2
        }
    }

    // MARK: - Output cleanup

    private func clean(_ s: String) -> String {
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

    private func parseTone(_ raw: String) -> Tone {
        let token = raw.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if let exact = Tone(rawValue: token) { return exact }
        let lower = raw.lowercased()
        for tone in Tone.allCases where lower.contains(tone.rawValue) { return tone }
        return .professional
    }
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
