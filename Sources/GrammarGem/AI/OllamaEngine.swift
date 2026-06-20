import Foundation

/// A cross-platform Layer-2 backend that talks to a locally-running **Ollama**
/// server over HTTP. Conforms to the same `AIEngine` seam as `MLXEngine`, reuses
/// the backend-neutral `AIPrompts` (so prompts/output are identical across
/// runtimes), and depends only on `URLSession` — no MLX, no Metal — so it compiles
/// and runs anywhere, including Windows/Linux. This is what converts the AIEngine
/// abstraction from nominal to real and opens the non-Apple-Silicon market.
///
/// Privacy is preserved: Ollama runs the model on the user's own machine on
/// loopback (127.0.0.1); no text leaves the device.
final class OllamaEngine: AIEngine {
    private let base: URL
    private let model: String
    private let session: URLSession

    /// `isReady` is read synchronously by the coordinator but readiness for an HTTP
    /// backend is an async probe, so we cache the last-known result behind a lock.
    private let lock = NSLock()
    private var cachedReady = false

    init(base: URL = AppConfig.Ollama.baseURL,
         model: String = AppConfig.Ollama.defaultModel,
         session: URLSession = .shared) {
        self.base = base
        self.model = model
        self.session = session
    }

    var isReady: Bool {
        lock.lock(); defer { lock.unlock() }
        return cachedReady
    }

    private func setReady(_ value: Bool) {
        lock.lock(); cachedReady = value; lock.unlock()
    }

    // MARK: - AIEngine

    /// Probe the server and confirm the configured model is pulled. Readiness for
    /// Ollama means "server up + model present" (vs. MLX's "weights on disk").
    func warmup() async {
        setReady(await probeModelPresent())
    }

    func run(_ action: AIAction, on text: String, protectedTerms: [String]) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        let raw = try await chat(
            system: AIPrompts.systemPrompt(for: action, protectedTerms: protectedTerms),
            user: trimmed,
            temperature: AIPrompts.temperature(for: action),
            maxTokens: AIPrompts.maxTokens(for: action))
        setReady(true)
        return AIPrompts.clean(raw)
    }

    func detectTone(_ text: String) async -> Tone {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .professional }
        do {
            let raw = try await chat(
                system: AIPrompts.toneClassifierPrompt(), user: trimmed,
                temperature: 0.0, maxTokens: 8)
            return AIPrompts.parseTone(raw)
        } catch {
            return .professional
        }
    }

    func runStreaming(_ action: AIAction, on text: String, protectedTerms: [String])
        -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continuation.yield(text); continuation.finish(); return }
                do {
                    try await streamChat(
                        system: AIPrompts.systemPrompt(for: action, protectedTerms: protectedTerms),
                        user: trimmed,
                        temperature: AIPrompts.temperature(for: action),
                        maxTokens: AIPrompts.maxTokens(for: action),
                        onChunk: { continuation.yield($0) })
                    setReady(true)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - HTTP

    private func probeModelPresent() async -> Bool {
        do {
            let (data, response) = try await session.data(from: base.appendingPathComponent("api/tags"))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            let names = (try JSONDecoder().decode(TagsResponse.self, from: data)).models.map(\.name)
            // Match exact or family (e.g. configured "qwen2.5:3b" vs a pulled "qwen2.5:3b-instruct").
            return names.contains(model)
                || names.contains { $0.hasPrefix(model) || model.hasPrefix($0) }
        } catch {
            return false
        }
    }

    private func chat(system: String, user: String,
                      temperature: Float, maxTokens: Int) async throws -> String {
        let request = try makeRequest(path: "api/chat", body: ChatRequest(
            model: model,
            messages: [.init(role: "system", content: system), .init(role: "user", content: user)],
            stream: false,
            options: .init(temperature: temperature, num_predict: maxTokens)))
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIEngineError.generationFailed("No HTTP response from Ollama at \(base.absoluteString)")
        }
        guard http.statusCode == 200 else {
            throw AIEngineError.generationFailed("Ollama returned HTTP \(http.statusCode)")
        }
        return (try JSONDecoder().decode(ChatResponse.self, from: data)).message?.content ?? ""
    }

    private func streamChat(system: String, user: String,
                            temperature: Float, maxTokens: Int,
                            onChunk: (String) -> Void) async throws {
        let request = try makeRequest(path: "api/chat", body: ChatRequest(
            model: model,
            messages: [.init(role: "system", content: system), .init(role: "user", content: user)],
            stream: true,
            options: .init(temperature: temperature, num_predict: maxTokens)))
        let (bytes, response) = try await session.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AIEngineError.generationFailed("Ollama streaming request failed")
        }
        // Ollama streams newline-delimited JSON frames, one per token-ish chunk.
        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8),
                  let frame = try? JSONDecoder().decode(ChatResponse.self, from: data),
                  let chunk = frame.message?.content, !chunk.isEmpty
            else { continue }
            onChunk(chunk)
        }
    }

    private func makeRequest<T: Encodable>(path: String, body: T) throws -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    // MARK: - Wire types

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool
        let options: Options
        struct Message: Encodable { let role: String; let content: String }
        struct Options: Encodable { let temperature: Float; let num_predict: Int }
    }

    private struct ChatResponse: Decodable {
        let message: Message?
        struct Message: Decodable { let content: String }
    }

    private struct TagsResponse: Decodable {
        let models: [Model]
        struct Model: Decodable { let name: String }
    }
}
