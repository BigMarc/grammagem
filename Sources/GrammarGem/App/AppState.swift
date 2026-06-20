import Foundation
import AppKit
import SwiftUI
import Combine

/// Root application model. Owns the engines, managers, and the system-wide
/// coordinator, wires the global hotkeys, and presents the on-demand windows.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // Engines (Layer 1 + Layer 2)
    let grammar: GrammarEngine
    let ai: AIEngine

    // Managers
    let permissions: Permissions
    let model: ModelManager
    let license: LicenseManager
    let gate: FeatureGate
    let detector: AppDetector
    let hotkeys: HotkeyManager
    let dictionary: PersonalDictionary
    let preferences: Preferences
    let usage: UsageStats
    let customModes: CustomModesStore
    let snippets: SnippetStore
    let exclusions: Exclusions
    let liveMonitor: LiveMonitor
    let updater: UpdaterManager
    private let capture: TextCapture
    let coordinator: TextReplacementCoordinator
    /// Loopback bridge to the browser extension (opt-in; nil unless enabled).
    private var localServer: LocalEngineServer?

    // UI state
    @Published var lastStatus: String = "Ready"
    @Published var askText: String = ""
    @Published var appAwareEnabled: Bool = false
    @Published var isPaused: Bool = false

    private var onboardingWindow: NSWindow?
    private var askWindow: NSWindow?
    private var mainWindow: NSWindow?
    private var liveCheckWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let engine = SystemGrammarEngine()
        grammar = engine
        // The on-device LLM loads weights from ModelManager's local snapshot (if a
        // complete download is present) — never the network. Resolved lazily on use.
        // Reads the user's *selected* repo (default or paid large model) so the
        // model that gets loaded matches the one that gets downloaded.
        ai = AppState.makeAIEngine()
        permissions = Permissions()
        model = ModelManager()
        license = LicenseManager()
        gate = FeatureGate(license: license)
        detector = AppDetector()
        capture = TextCapture()
        hotkeys = HotkeyManager()
        dictionary = PersonalDictionary()
        preferences = Preferences()
        usage = UsageStats()
        customModes = CustomModesStore()
        snippets = SnippetStore()
        let excl = Exclusions()
        exclusions = excl
        liveMonitor = LiveMonitor(grammar: engine, detector: detector, exclusions: excl, capture: capture)
        updater = UpdaterManager()
        let dict = dictionary
        coordinator = TextReplacementCoordinator(
            capture: capture, grammar: engine, ai: ai, gate: gate, detector: detector,
            protectedTerms: { dict.entries })
    }

    // MARK: - Backend factory

    /// The single place the Layer-2 backend is chosen. Defaults to the MLX
    /// on-device engine (Apple Silicon); a user/CI override selects the
    /// cross-platform `OllamaEngine`. Adding a backend is a one-line branch here
    /// instead of edits scattered across construction sites. The MLX provider
    /// reads the user's *selected* repo so the loaded model matches the downloaded
    /// one (incl. the paid large model).
    static func makeAIEngine() -> AIEngine {
        let override = ProcessInfo.processInfo.environment["GRAMMARGEM_AI_BACKEND"]
            ?? UserDefaults.standard.string(forKey: "GrammarGem.aiBackend")
        if override == "ollama" {
            return OllamaEngine()
        }
        return MLXEngine(modelDirectoryProvider: {
            ModelManager.completedModelDirectory(repo: ModelManager.activeRepo())
        })
    }

    /// Called once at launch (from the AppDelegate).
    func start() {
        // Menu-bar app: no Dock icon (works even without LSUIElement in Info.plist).
        NSApp.setActivationPolicy(.accessory)

        hotkeys.onAction = { [weak self] action in
            Task { await self?.handle(action) }
        }
        reregisterHotkeys()

        // Live-apply preference changes.
        capture.restoreClipboard = preferences.restoreClipboard
        preferences.$restoreClipboard
            .sink { [weak self] value in self?.capture.restoreClipboard = value }
            .store(in: &cancellables)
        preferences.$fixHotkey.dropFirst()
            .sink { [weak self] _ in self?.reregisterHotkeys() }
            .store(in: &cancellables)
        preferences.$askHotkey.dropFirst()
            .sink { [weak self] _ in self?.reregisterHotkeys() }
            .store(in: &cancellables)

        // Always-on live monitoring (menu-bar resident), driven by the preference.
        liveMonitor.setEnabled(preferences.liveUnderlines)
        preferences.$liveUnderlines.dropFirst()
            .sink { [weak self] on in self?.liveMonitor.setEnabled(on) }
            .store(in: &cancellables)

        // Auto-install the on-device AI model in the background on first use, so
        // the AI features are ready without the user hunting for a button. The
        // download is resumable/cancelable from the AI Model screen. If a model is
        // already present, warm it up now so the first AI action is instant.
        if model.isModelPresent(repo: model.selectedRepo) {
            Task { [weak self] in await self?.ai.warmup() }
        } else {
            model.startDownload()
        }
        // Warm the model up as soon as a (first-run) download completes.
        model.$state.dropFirst()
            .sink { [weak self] state in
                if case .ready = state { Task { [weak self] in await self?.ai.warmup() } }
            }
            .store(in: &cancellables)

        permissions.refresh()
        appAwareEnabled = gate.appAwareEnabled
        syncIgnoreList()

        if !permissions.accessibilityTrusted {
            showOnboarding()
        }

        Task { await license.validateIfNeeded() }
        startLocalServerIfEnabled()
        Log.app.info("GrammarGem started. Licensed: \(self.license.isLicensed, privacy: .public)")
    }

    // MARK: - Browser-extension bridge (opt-in)

    /// Start the loopback engine server only when the user has opted in, so the app
    /// ships no listening socket by default. The server reuses the SAME engines,
    /// prompts, and entitlement gate as the menu-bar app.
    private func startLocalServerIfEnabled() {
        let enabled = ProcessInfo.processInfo.environment["GRAMMARGEM_LOCAL_SERVER"] == "1"
            || UserDefaults.standard.bool(forKey: AppConfig.LocalServer.enableKey)
        guard enabled, localServer == nil else { return }

        let server = LocalEngineServer(
            port: AppConfig.LocalServer.port,
            token: LocalEngineServer.loadOrCreateToken(),
            grammarHandler: { [weak self] text in
                await MainActor.run {
                    guard let self else { return (text, []) }
                    let corrected = self.grammar.correct(text)
                    let suggestions = self.grammar.check(text).map {
                        LocalEngineServer.WireSuggestion(
                            location: $0.location, length: $0.length,
                            original: $0.original, replacement: $0.replacement,
                            kind: $0.kind.rawValue, message: $0.message)
                    }
                    return (corrected, suggestions)
                }
            },
            aiHandler: { [weak self] (req: LocalEngineServer.AIRequest) async -> LocalEngineServer.AIOutcome in
                guard let self else { return .error("GrammarGem is shutting down.") }
                return await self.handleServerAI(req)
            },
            aiStreamHandler: { [weak self] (req, onChunk) -> LocalEngineServer.AIOutcome in
                guard let self else { return .error("GrammarGem is shutting down.") }
                return await self.handleServerAIStream(req, onChunk: onChunk)
            })
        server.start()
        localServer = server
    }

    /// Run an AI action requested by the extension — same gate + model as the app.
    private func handleServerAI(_ req: LocalEngineServer.AIRequest) async -> LocalEngineServer.AIOutcome {
        if case .denied(let reason) = gate.authorizeAI(req.action) { return .error(reason) }
        guard ai.isReady else { return .error(AIEngineError.modelNotReady.localizedDescription) }
        do {
            let out = try await ai.run(req.action, on: req.text, protectedTerms: dictionary.entries)
            gate.recordAIActionUsed()
            return .ok(out)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// Streaming variant for the extension: yields tokens as they generate.
    private func handleServerAIStream(_ req: LocalEngineServer.AIRequest,
                                      onChunk: @escaping (String) -> Void) async -> LocalEngineServer.AIOutcome {
        if case .denied(let reason) = gate.authorizeAI(req.action) { return .error(reason) }
        guard ai.isReady else { return .error(AIEngineError.modelNotReady.localizedDescription) }
        var accumulated = ""
        do {
            for try await chunk in ai.runStreaming(req.action, on: req.text, protectedTerms: dictionary.entries) {
                accumulated += chunk
                onChunk(chunk)
            }
            gate.recordAIActionUsed()
            return .ok(accumulated)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    // MARK: - Hotkey handling

    /// (Re)register the global hotkeys from the current preferences.
    func reregisterHotkeys() {
        hotkeys.unregisterAll()
        if !hotkeys.register(id: 1, keyCode: preferences.fixHotkey.keyCode,
                             modifiers: preferences.fixHotkey.carbonModifiers, action: .fix) {
            // The chosen combo was rejected (already claimed) — keep a working
            // shortcut by falling back to the default rather than leaving none.
            hotkeys.register(id: 1, keyCode: AppConfig.Hotkey.defaultKeyCode,
                             modifiers: AppConfig.Hotkey.defaultModifiers, action: .fix)
            lastStatus = "That Fix shortcut is already in use — kept the default (⌘;)."
        }
        if !hotkeys.register(id: 2, keyCode: preferences.askHotkey.keyCode,
                             modifiers: preferences.askHotkey.carbonModifiers, action: .ask) {
            hotkeys.register(id: 2, keyCode: AppConfig.Hotkey.askKeyCode,
                             modifiers: AppConfig.Hotkey.askModifiers, action: .ask)
            lastStatus = "That Ask shortcut is already in use — kept the default (⌘')."
        }
    }

    func handle(_ action: HotkeyManager.Action) async {
        switch action {
        case .fix:
            await runFix()
        case .ask:
            showAsk()
        }
    }

    func runFix() async {
        if let reason = blockReason() { lastStatus = reason; return }
        let outcome = await coordinator.handleFix()
        if case .replaced(let text) = outcome { usage.recordCorrection(words: wordCount(text)) }
        present(outcome)
    }

    /// Fix every issue in the focused field (the live monitor's "Fix all").
    func fixFocusedField() async {
        if let reason = blockReason() { lastStatus = reason; return }
        let outcome = await coordinator.handleFixFocusedField()
        if case .replaced(let text) = outcome { usage.recordCorrection(words: wordCount(text)) }
        present(outcome)
        liveMonitor.refreshSoon()
    }

    // MARK: - Live multi-field fixes (from the Live Check panel)

    func fixAllDetected() {
        if let reason = blockReason() { lastStatus = reason; return }
        let n = liveMonitor.fixAll()
        if n > 0 { usage.recordCorrection(words: n) }
        lastStatus = n > 0 ? "Fixed \(n) issue\(n == 1 ? "" : "s")" : "Nothing to fix"
    }

    func fixDetectedField(_ field: DetectedField) {
        if let reason = blockReason() { lastStatus = reason; return }
        let n = liveMonitor.fix(field)
        if n > 0 { usage.recordCorrection(words: n) }
    }

    func applySuggestion(_ suggestion: Suggestion, in field: DetectedField) {
        if let reason = blockReason() { lastStatus = reason; return }
        liveMonitor.apply(suggestion, in: field)
        usage.recordCorrection(words: 1)
    }

    /// Hide a single suggestion without changing the user's text.
    func dismissSuggestion(_ suggestion: Suggestion, in field: DetectedField) {
        liveMonitor.dismiss(suggestion, in: field)
    }

    /// Add a flagged word to the personal dictionary so it's never corrected
    /// again (gated by the free cap), then re-scan so it disappears now.
    @discardableResult
    func addWordToDictionary(_ word: String) -> FeatureGate.Decision {
        let decision = addDictionaryEntry(word)
        switch decision {
        case .allowed:
            lastStatus = "Added “\(word)” to your dictionary"
            liveMonitor.refreshSoon()
        case .denied(let reason):
            lastStatus = reason
        }
        return decision
    }

    /// Pause/resume all of GrammarGem (hotkeys + live monitoring).
    func togglePause() {
        isPaused.toggle()
        liveMonitor.setPaused(isPaused)
        lastStatus = isPaused ? "Paused" : "Ready"
    }

    /// A reason GrammarGem should stay out of the way right now, or nil.
    private func blockReason() -> String? {
        if isPaused { return "GrammarGem is paused." }
        let front = detector.frontmost()
        if exclusions.isBlocked(bundleID: front?.bundleID, domain: detector.frontmostDomain()) {
            return "GrammarGem is off for \(front?.name ?? "this app")."
        }
        return nil
    }

    func runAsk() async {
        let instruction = askText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }
        if let reason = blockReason() { lastStatus = reason; askWindow?.close(); return }
        let outcome = await coordinator.handleAsk(instruction)
        if case .replaced(let text) = outcome { usage.recordAIAction(words: wordCount(text)) }
        present(outcome)
        askWindow?.close()
    }

    private func wordCount(_ s: String) -> Int {
        s.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Apply the Mode suggested by the frontmost app (App-Aware, paid).
    func runAppAwareRewrite() async {
        if let reason = blockReason() { lastStatus = reason; return }
        guard gate.appAwareEnabled else {
            present(.blockedByEntitlement("App-aware switching is part of the lifetime upgrade."))
            return
        }
        guard let mode = detector.suggestedMode() else {
            lastStatus = "No mode mapped for the current app."
            return
        }
        let outcome = await coordinator.handleApplyMode(mode)
        if case .replaced(let text) = outcome { usage.recordAIAction(words: wordCount(text)) }
        present(outcome)
    }

    private func present(_ outcome: ProcessOutcome) {
        switch outcome {
        case .replaced:
            lastStatus = "Fixed ✓"
        case .noSelection:
            lastStatus = "Select some text first."
        case .blockedByEntitlement(let reason):
            lastStatus = reason
            notify(title: "Upgrade required", body: reason)
        case .failed(let message):
            lastStatus = message
        }
    }

    private func notify(title: String, body: String) {
        // Lightweight, content-free alert (no user text ever leaves the device).
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - On-demand windows (AppKit-hosted SwiftUI; reliable for menu-bar apps)

    func showOnboarding() {
        if onboardingWindow == nil {
            let host = NSHostingController(rootView: OnboardingView().environmentObject(self))
            let win = NSWindow(contentViewController: host)
            win.title = "Welcome to GrammarGem"
            win.styleMask = [.titled, .closable, .fullSizeContentView]
            win.setContentSize(NSSize(width: 560, height: 720))
            win.isReleasedWhenClosed = false
            win.center()
            onboardingWindow = win
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    /// The full management window (devices, modes, settings, insights).
    func showMainWindow(select section: MainSection? = nil) {
        if mainWindow == nil {
            let root = MainWindowView(initialSection: section ?? .dashboard)
                .environmentObject(self)
                .environmentObject(license)
                .environmentObject(gate)
                .environmentObject(model)
                .environmentObject(permissions)
                .environmentObject(dictionary)
                .environmentObject(preferences)
                .environmentObject(usage)
                .environmentObject(customModes)
                .environmentObject(snippets)
                .environmentObject(exclusions)
                .environmentObject(liveMonitor)
            let host = NSHostingController(rootView: root)
            let win = NSWindow(contentViewController: host)
            win.title = "GrammarGem"
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            win.setContentSize(NSSize(width: 940, height: 660))
            win.minSize = NSSize(width: 820, height: 560)
            win.isReleasedWhenClosed = false
            win.center()
            mainWindow = win
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    /// The Live Check panel: every on-screen text area with grammar issues.
    func showLiveCheck() {
        if liveCheckWindow == nil {
            let root = LiveCheckView()
                .environmentObject(self)
                .environmentObject(liveMonitor)
            let host = NSHostingController(rootView: root)
            let win = NSWindow(contentViewController: host)
            win.title = "Live Check"
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.setContentSize(NSSize(width: 560, height: 620))
            win.minSize = NSSize(width: 460, height: 420)
            win.isReleasedWhenClosed = false
            win.center()
            liveCheckWindow = win
        }
        liveMonitor.refreshSoon()
        NSApp.activate(ignoringOtherApps: true)
        liveCheckWindow?.makeKeyAndOrderFront(nil)
    }

    func showAsk() {
        askText = ""
        if askWindow == nil {
            let host = NSHostingController(rootView: AskView().environmentObject(self))
            let win = NSWindow(contentViewController: host)
            win.title = "Ask GrammarGem"
            win.styleMask = [.titled, .closable]
            win.setContentSize(NSSize(width: 460, height: 220))
            win.isReleasedWhenClosed = false
            win.center()
            win.level = .floating
            askWindow = win
        }
        NSApp.activate(ignoringOtherApps: true)
        askWindow?.makeKeyAndOrderFront(nil)
    }

    func showOnboardingDismiss() {
        onboardingWindow?.close()
    }

    func showAskDismiss() {
        askWindow?.close()
    }

    // MARK: - Personal dictionary (gated adds)

    @discardableResult
    func addDictionaryEntry(_ word: String) -> FeatureGate.Decision {
        let decision = gate.canAddDictionaryEntry(currentCount: dictionary.entries.count)
        if case .allowed = decision {
            dictionary.add(word)
            syncIgnoreList()
        }
        return decision
    }

    func removeDictionaryEntry(_ word: String) {
        dictionary.remove(word)
        syncIgnoreList()
    }

    private func syncIgnoreList() {
        grammar.ignoreList = Set(dictionary.entries.map { $0.lowercased() })
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
