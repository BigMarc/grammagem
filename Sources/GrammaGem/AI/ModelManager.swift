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
    @Published var selectedRepo: String = AppConfig.Model.defaultRepo

    private var task: Task<Void, Never>?

    init() {
        if isModelPresent(repo: selectedRepo) { state = .ready }
    }

    var modelsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("GrammaGem/Models", isDirectory: true)
    }

    func modelDir(_ repo: String) -> URL {
        modelsDirectory.appendingPathComponent(repo.replacingOccurrences(of: "/", with: "_"), isDirectory: true)
    }

    /// Considered present once the completion marker is written.
    func isModelPresent(repo: String) -> Bool {
        FileManager.default.fileExists(atPath: modelDir(repo).appendingPathComponent(".complete").path)
    }

    /// Kick off (or resume to) a real download. Safe to call from the UI.
    func startDownload(repo: String? = nil) {
        let target = repo ?? selectedRepo
        selectedRepo = target
        task?.cancel()
        task = Task { await self.run(repo: target) }
    }

    func cancel() {
        task?.cancel()
        task = nil
        statusText = ""
        state = isModelPresent(repo: selectedRepo) ? .ready : .notDownloaded
    }

    // MARK: - Download

    private func run(repo: String) async {
        if isModelPresent(repo: repo) { state = .ready; return }

        let dir = modelDir(repo)
        state = .downloading(progress: 0)
        statusText = "Preparing…"
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let files = try await fetchFileList(repo: repo)
            guard !files.isEmpty else { throw ModelError.empty }
            let total = max(files.reduce(Int64(0)) { $0 + $1.size }, 1)
            var done: Int64 = 0

            for file in files {
                try Task.checkCancellation()
                statusText = "Downloading \(file.path) (\(byteString(file.size)))…"
                let url = URL(string: "\(AppConfig.Model.huggingFaceBase)/\(repo)/resolve/main/\(file.path)")!
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
                done += file.size
                state = .downloading(progress: min(1, Double(done) / Double(total)))
            }

            try Data().write(to: dir.appendingPathComponent(".complete"))
            statusText = ""
            state = .ready
            Log.ai.info("Model downloaded: \(repo, privacy: .public)")
        } catch is CancellationError {
            statusText = ""
            state = isModelPresent(repo: repo) ? .ready : .notDownloaded
        } catch {
            statusText = ""
            state = .failed(error.localizedDescription)
            Log.ai.error("Model download failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// List the repo's files (+ sizes) from the Hugging Face tree API.
    private func fetchFileList(repo: String) async throws -> [(path: String, size: Int64)] {
        let url = URL(string: "\(AppConfig.Model.huggingFaceBase)/api/models/\(repo)/tree/main?recursive=1")!
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
        var errorDescription: String? {
            switch self {
            case .empty: return "No model files were found for this repository."
            case .http(let code, let what): return "Download failed (\(code)) while fetching \(what)."
            }
        }
    }
}
