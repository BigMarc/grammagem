import Foundation
import Network

/// A minimal, loopback-only HTTP server that exposes GrammarGem's local engines
/// (Harper grammar + the on-device LLM) to a **browser extension** — the
/// highest-volume surface for a grammar tool — with NO cloud round-trip. Built on
/// Network.framework so it adds no third-party HTTP dependency, keeping the
/// privacy/trust surface minimal.
///
/// Security posture (deliberate):
///  - Binds to 127.0.0.1 only (never a routable interface), via `requiredLocalEndpoint`.
///  - Every engine endpoint requires a per-install bearer token (`X-GrammarGem-Token`);
///    a web page that doesn't know the token cannot drive the engines.
///  - OFF by default — only starts when the user opts in, so the app ships no
///    listening socket unless explicitly enabled.
///
/// It reuses the SAME engines as the menu-bar app via injected async handlers, so
/// there is one engine, one set of prompts (`AIPrompts`), and one entitlement gate
/// across the app, the extension, and (later) other backends.
final class LocalEngineServer {

    struct AIRequest { let action: AIAction; let text: String }

    struct WireSuggestion: Encodable {
        let location: Int
        let length: Int
        let original: String
        let replacement: String
        let kind: String
        let message: String
    }

    /// Grammar pass: corrected text + suggestion spans for the extension to underline.
    typealias GrammarHandler = (String) async -> (corrected: String, suggestions: [WireSuggestion])
    /// AI action outcome (a plain enum so a user-facing message needn't be an `Error`).
    enum AIOutcome { case ok(String); case error(String) }
    /// AI action: runs the gate + model, returns the result or a user-facing error.
    typealias AIHandler = (AIRequest) async -> AIOutcome
    /// Streaming AI action: runs the gate + model, invoking `onChunk` per token as it
    /// generates, then returns the final outcome (full text, or an error message).
    typealias AIStreamHandler = (AIRequest, @escaping (String) -> Void) async -> AIOutcome

    private let port: UInt16
    private let token: String
    private let grammarHandler: GrammarHandler
    private let aiHandler: AIHandler
    private let aiStreamHandler: AIStreamHandler

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.grammargem.localserver")

    init(port: UInt16, token: String,
         grammarHandler: @escaping GrammarHandler,
         aiHandler: @escaping AIHandler,
         aiStreamHandler: @escaping AIStreamHandler) {
        self.port = port
        self.token = token
        self.grammarHandler = grammarHandler
        self.aiHandler = aiHandler
        self.aiStreamHandler = aiStreamHandler
    }

    /// A stable per-install token, persisted so the extension can be paired once.
    static func loadOrCreateToken() -> String {
        let d = UserDefaults.standard
        if let existing = d.string(forKey: AppConfig.LocalServer.tokenKey), !existing.isEmpty {
            return existing
        }
        let token = UUID().uuidString + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        d.set(token, forKey: AppConfig.LocalServer.tokenKey)
        return token
    }

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
            // Loopback-only: refuse to bind to any routable interface.
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: nwPort)
            let listener = try NWListener(using: params)
            listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            listener.start(queue: queue)
            self.listener = listener
            Log.app.info("Local engine server on 127.0.0.1:\(self.port, privacy: .public) (extension bridge)")
        } catch {
            Log.app.error("Local engine server failed to start: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection lifecycle

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self else { conn.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = HTTPRequest(buffer), request.isComplete {
                Task { await self.route(request, on: conn) }
                return
            }
            if isComplete || error != nil { conn.cancel(); return }
            self.receive(conn, buffer: buffer) // headers/body not fully arrived yet
        }
    }

    // MARK: - Routing

    private func route(_ request: HTTPRequest, on conn: NWConnection) async {
        // CORS preflight — extensions issue this before a cross-origin POST.
        if request.method == "OPTIONS" {
            send(conn, status: 204, body: Data())
            return
        }

        if request.path == "/health" || request.path == "/v1/health" {
            sendJSON(conn, status: 200, HealthResponse(ok: true, app: AppConfig.appName, version: AppConfig.appVersion))
            return
        }

        // Token gate for every engine endpoint.
        guard request.headers["x-grammargem-token"] == token else {
            sendJSON(conn, status: 401, ErrorResponse(error: "unauthorized"))
            return
        }

        switch (request.method, request.path) {
        case ("POST", "/v1/grammar"):
            guard let text = decodeText(request.body) else {
                sendJSON(conn, status: 400, ErrorResponse(error: "missing 'text'")); return
            }
            let result = await grammarHandler(text)
            sendJSON(conn, status: 200, GrammarResponse(corrected: result.corrected, suggestions: result.suggestions))

        case ("POST", "/v1/ai"):
            guard let req = decodeAI(request.body) else {
                sendJSON(conn, status: 400, ErrorResponse(error: "bad request")); return
            }
            switch await aiHandler(req) {
            case .ok(let out): sendJSON(conn, status: 200, AIResponse(result: out))
            case .error(let msg): sendJSON(conn, status: 422, ErrorResponse(error: msg))
            }

        case ("POST", "/v1/ai/stream"):
            guard let req = decodeAI(request.body) else {
                sendJSON(conn, status: 400, ErrorResponse(error: "bad request")); return
            }
            // Newline-delimited JSON frames: {"chunk":"…"} per token, then a final
            // {"done":true} or {"error":"…"}. The 200 header goes out before tokens,
            // so an entitlement/readiness failure surfaces as a closing error frame.
            beginStream(conn)
            let outcome = await aiStreamHandler(req) { [weak self] chunk in
                self?.streamFrame(conn, ["chunk": chunk])
            }
            switch outcome {
            case .ok: streamFrame(conn, ["done": true])
            case .error(let msg): streamFrame(conn, ["error": msg])
            }
            endStream(conn)

        default:
            sendJSON(conn, status: 404, ErrorResponse(error: "not found"))
        }
    }

    // MARK: - Body decoding

    private func decodeText(_ body: Data) -> String? {
        struct P: Decodable { let text: String }
        guard let p = try? JSONDecoder().decode(P.self, from: body), !p.text.isEmpty else { return nil }
        return p.text
    }

    private func decodeAI(_ body: Data) -> AIRequest? {
        struct P: Decodable {
            let action: String
            let text: String
            let instruction: String?
            let language: String?
            let mode: String?
            let tone: String?
        }
        guard let p = try? JSONDecoder().decode(P.self, from: body), !p.text.isEmpty else { return nil }
        let action: AIAction
        switch p.action {
        case "rewriteClarity": action = .rewriteClarity
        case "rewrite":        action = .rewrite
        case "ask":
            guard let i = p.instruction, !i.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            action = .ask(i)
        case "translate":
            guard let l = p.language, !l.isEmpty else { return nil }
            action = .translate(language: l)
        case "tone":
            action = .adjustTone(Tone(rawValue: p.tone ?? "") ?? .professional)
        case "mode":
            guard let id = p.mode, let m = ModeRegistry.mode(id: id) else { return nil }
            action = .applyMode(m)
        default:
            return nil
        }
        return AIRequest(action: action, text: p.text)
    }

    // MARK: - Responses

    private struct HealthResponse: Encodable { let ok: Bool; let app: String; let version: String }
    private struct GrammarResponse: Encodable { let corrected: String; let suggestions: [WireSuggestion] }
    private struct AIResponse: Encodable { let result: String }
    private struct ErrorResponse: Encodable { let error: String }

    private func sendJSON<T: Encodable>(_ conn: NWConnection, status: Int, _ value: T) {
        let body = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
        send(conn, status: status, body: body)
    }

    // MARK: - Streaming responses (newline-delimited JSON, no Content-Length)

    private func beginStream(_ conn: NWConnection) {
        var head = "HTTP/1.1 200 OK\r\n"
        head += "Content-Type: application/x-ndjson\r\n"
        head += "Cache-Control: no-cache\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Access-Control-Allow-Headers: Content-Type, X-GrammarGem-Token\r\n"
        head += "Connection: close\r\n\r\n"
        conn.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
    }

    private func streamFrame(_ conn: NWConnection, _ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A) // newline delimiter
        conn.send(content: data, completion: .contentProcessed { _ in })
    }

    private func endStream(_ conn: NWConnection) {
        conn.send(content: nil, completion: .contentProcessed { _ in conn.cancel() })
    }

    private func send(_ conn: NWConnection, status: Int, body: Data) {
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(body.count)\r\n"
        // The extension calls cross-origin; a secret token (not the origin) is the gate.
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Access-Control-Allow-Headers: Content-Type, X-GrammarGem-Token\r\n"
        head += "Access-Control-Allow-Methods: POST, GET, OPTIONS\r\n"
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 422: return "Unprocessable Entity"
        default:  return "Error"
        }
    }
}

/// A just-enough HTTP/1.1 request parser for small JSON POSTs. Returns nil until
/// the headers terminator (`\r\n\r\n`) has arrived; `isComplete` is false until the
/// full `Content-Length` body is buffered, so the receive loop knows to read more.
private struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
    let isComplete: Bool

    init?(_ raw: Data) {
        guard let headerEnd = raw.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let headerString = String(data: raw[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        var lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        method = String(parts[0])
        path = String(parts[1])
        lines.removeFirst()

        var hdrs: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            hdrs[key] = value
        }
        headers = hdrs

        let contentLength = Int(hdrs["content-length"] ?? "0") ?? 0
        let available = raw[headerEnd.upperBound...]
        body = Data(available.prefix(contentLength))
        isComplete = body.count >= contentLength
    }
}
