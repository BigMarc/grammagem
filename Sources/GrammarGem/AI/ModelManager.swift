import Foundation

/// Downloads the local LLM weights from Hugging Face on demand. This is a *real*
/// download (the model files are fetched to disk with progress) — one of the
/// only three network touchpoints in the product, and it never sends user text.
@MainActor
final class ModelManager: ObservableObject {
    enum State: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .notDownloaded
    @Published private(set) var statusText: String = ""
    @Published var selectedRepo: String = ModelManager.activeRepo() {
        didSet { UserDefaults.standard.set(selectedRepo, forKey: Self.selectedRepoKey) }
    }

    private var task: Task<Void, Never>?
    private var generation = 0

    init() {
        if isModelPresent(repo: selectedRepo) { state = .ready }
    }

    var modelsDirectory: URL { Self.modelsDirectory() }

    func modelDir(_ repo: String) -> URL { Self.modelDir(repo) }

    /// Considered present once the completion marker is written.
    func isModelPresent(repo: String) -> Bool { Self.isModelPresent(repo: repo) }

    // MARK: - Nonisolated path helpers
    //
    // The AI engine loads weights off the main actor, so the directory lookup must
    // be callable from any thread. These are pure FileManager/URL ops (no actor
    // state, no network) and back the @MainActor instance accessors above.

    nonisolated static func modelsDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("GrammarGem/Models", isDirectory: true)
    }

    nonisolated static func modelDir(_ repo: String) -> URL {
        modelsDirectory().appendingPathComponent(repo.replacingOccurrences(of: "/", with: "_"), isDirectory: true)
    }

    nonisolated static func isModelPresent(repo: String) -> Bool {
        FileManager.default.fileExists(atPath: modelDir(repo).appendingPathComponent(".complete").path)
    }

    /// The local model directory iff a *complete* model is on disk, else nil —
    /// fed to the AI engine as its network-free model source.
    nonisolated static func completedModelDirectory(repo: String) -> URL? {
        isModelPresent(repo: repo) ? modelDir(repo) : nil
    }

    /// UserDefaults key backing the user's chosen model repo.
    nonisolated static let selectedRepoKey = "GrammarGem.selectedModelRepo"

    /// The user's currently-selected repo, readable from ANY thread (it lives in
    /// UserDefaults, which is thread-safe). The AI engine's model-directory
    /// provider reads this so download, load, and `isReady` all agree on the SAME
    /// repo — including the paid large model, which the old hardcoded-default
    /// provider silently ignored. Falls back to the default repo when unset.
    nonisolated static func activeRepo() -> String {
        UserDefaults.standard.string(forKey: selectedRepoKey) ?? AppConfig.Model.defaultRepo
    }

    /// Safe URL construction for the two Hugging Face endpoints. A malformed
    /// repo/path yields nil → a thrown `ModelError`, never a force-unwrap crash.
    nonisolated static func fileURL(repo: String, path: String) -> URL? {
        var c = URLComponents(string: AppConfig.Model.huggingFaceBase)
        c?.path = "/\(repo)/resolve/main/\(path)"
        return c?.url
    }

    nonisolated static func treeURL(repo: String) -> URL? {
        var c = URLComponents(string: AppConfig.Model.huggingFaceBase)
        c?.path = "/api/models/\(repo)/tree/main"
        c?.queryItems = [URLQueryItem(name: "recursive", value: "1")]
        return c?.url
    }

    /// Kick off (or resume to) a real download. Safe to call from the UI.
    func startDownload(repo: String? = nil) {
        let target = repo ?? selectedRepo
        selectedRepo = target
        if isModelPresent(repo: target) { state = .ready; return }
        task?.cancel()
        generation += 1
        let gen = generation
        task = Task { await self.run(repo: target, generation: gen) }
    }

    func cancel() {
        task?.cancel()
        task = nil
        generation += 1 // invalidate any in-flight run's state writes
        statusText = ""
        state = isModelPresent(repo: selectedRepo) ? .ready : .notDownloaded
    }

    // MARK: - Download

    private func run(repo: String, generation gen: Int) async {
        if isModelPresent(repo: repo) { set(gen, .ready, ""); return }

        let dir = modelDir(repo)
        set(gen, .downloading(progress: 0), "Preparing…")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let files = try await fetchFileList(repo: repo)
            guard !files.isEmpty else { throw ModelError.empty }
            let total = max(files.reduce(Int64(0)) { $0 + $1.size }, 1)
            var done: Int64 = 0

            for file in files {
                try Task.checkCancellation()
                set(gen, .downloading(progress: min(1, Double(done) / Double(total))),
                    "Downloading \(file.path) (\(byteString(file.size)))…")
                guard let url = Self.fileURL(repo: repo, path: file.path) else {
                    throw ModelError.invalidURL(file.path)
                }
                let (tmp, response) = try await URLSession.shared.download(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    throw ModelError.http(http.statusCode, file.path)
                }
                let dest = dir.appendingPathComponent(file.path)
                try FileManager.default.createDirectory(
                    at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.moveItem(at: tmp, to: dest)

                // Reject a wrong/truncated body (e.g. an HTML interstitial served
                // with HTTP 200) by checking the on-disk size against the expected.
                if file.size > 0 {
                    let actual = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? nil
                    if let actual, actual != file.size {
                        throw ModelError.corrupt(file.path)
                    }
                }
                done += file.size
                set(gen, .downloading(progress: min(1, Double(done) / Double(total))), nil)
            }

            try Data().write(to: dir.appendingPathComponent(".complete"))
            set(gen, .ready, "")
            Log.ai.info("Model downloaded: \(repo, privacy: .public)")
        } catch is CancellationError {
            cleanupPartial(repo: repo)
            set(gen, isModelPresent(repo: repo) ? .ready : .notDownloaded, "")
        } catch let urlError as URLError where urlError.code == .cancelled {
            cleanupPartial(repo: repo)
            set(gen, isModelPresent(repo: repo) ? .ready : .notDownloaded, "")
        } catch {
            cleanupPartial(repo: repo)
            set(gen, .failed(error.localizedDescription), "")
            Log.ai.error("Model download failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Apply a state/status update only if this run hasn't been superseded.
    private func set(_ gen: Int, _ newState: State, _ status: String?) {
        guard gen == generation else { return }
        state = newState
        if let status { statusText = status }
    }

    /// Remove an incomplete model directory so partial files don't linger.
    private func cleanupPartial(repo: String) {
        guard !isModelPresent(repo: repo) else { return }
        try? FileManager.default.removeItem(at: modelDir(repo))
    }

    /// List the repo's files (+ sizes) from the Hugging Face tree API.
    private func fetchFileList(repo: String) async throws -> [(path: String, size: Int64)] {
        guard let url = Self.treeURL(repo: repo) else { throw ModelError.invalidURL("file list") }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ModelError.http(http.statusCode, "file list")
        }
        struct Entry: Decodable { let type: String; let path: String; let size: Int64? }
        let entries = try JSONDecoder().decode([Entry].self, from: data)
        return entries.filter { $0.type == "file" }.map { ($0.path, $0.size ?? 0) }
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    enum ModelError: LocalizedError {
        case empty
        case http(Int, String)
        case corrupt(String)
        case invalidURL(String)
        var errorDescription: String? {
            switch self {
            case .empty: return "No model files were found for this repository."
            case .http(let code, let what): return "Download failed (\(code)) while fetching \(what)."
            case .corrupt(let what): return "Downloaded file looked wrong (\(what)); please retry."
            case .invalidURL(let what): return "Couldn't build a valid download URL for \(what)."
            }
        }
    }
}
