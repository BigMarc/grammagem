import Foundation
import AppKit
import ApplicationServices

/// A text area discovered on screen that has at least one grammar/spelling issue.
struct DetectedField: Identifiable {
    let id: String
    let label: String
    let roleName: String
    let text: String
    let suggestions: [Suggestion]
    let element: AXUIElement
    let isFocused: Bool
}

/// The always-on, menu-bar–resident monitor. While enabled it periodically scans
/// **every** text area in the frontmost window and publishes the ones with issues.
///
/// Performance & safety: the Accessibility-tree traversal (the part that can hang
/// on a busy/wedged app) runs OFF the main thread with a per-message timeout; only
/// the bounded spell/grammar pass and publish happen on the main actor. It never
/// scans GrammarGem itself, respects the page blocker, and applies fixes against the
/// element's *live* value so it can't overwrite text typed since the last scan.
@MainActor
final class LiveMonitor: ObservableObject {
    @Published private(set) var fields: [DetectedField] = []
    @Published private(set) var scannedCount = 0
    @Published private(set) var scannedWordCount = 0
    @Published private(set) var activeAppName = ""
    @Published private(set) var running = false

    /// Total number of issues across all detected text areas.
    var issueCount: Int { fields.reduce(0) { $0 + $1.suggestions.count } }

    /// Outstanding issues grouped into the user-facing buckets (for filter chips).
    var bucketCounts: [IssueBucket: Int] {
        var counts: [IssueBucket: Int] = [:]
        for field in fields {
            for s in field.suggestions { counts[s.kind.bucket, default: 0] += 1 }
        }
        return counts
    }

    /// 0–100 on-device cleanliness score for the text currently on screen.
    var writingScore: Int {
        let weighted = fields.reduce(0) { acc, f in
            acc + f.suggestions.reduce(0) { $0 + $1.kind.severity }
        }
        return WritingScore.score(weightedIssues: weighted, words: scannedWordCount)
    }

    /// Content keys of suggestions the user has dismissed; survives re-scans so a
    /// dismissed issue doesn't reappear on the next poll.
    private var dismissedKeys: Set<String> = []

    private let grammar: GrammarEngine
    private let detector: AppDetector
    private let exclusions: Exclusions
    private let capture: TextCapture

    private var timer: Timer?
    private var enabled = false
    private var paused = false
    private var scanning = false
    private var lastHash = 0
    private var scanGeneration = 0
    private let interval: TimeInterval = 1.6
    private let maxCheckChars = 4000
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    init(grammar: GrammarEngine, detector: AppDetector, exclusions: Exclusions, capture: TextCapture) {
        self.grammar = grammar
        self.detector = detector
        self.exclusions = exclusions
        self.capture = capture
    }

    func setEnabled(_ on: Bool) { enabled = on; reconcile() }
    func setPaused(_ p: Bool) { paused = p; reconcile() }

    /// Re-scan now (e.g. after applying a fix), superseding any in-flight scan.
    func refreshSoon() { lastHash = 0; tick(force: true) }

    // MARK: - Applying fixes (always against the element's LIVE value)

    @discardableResult
    func fixAll() -> Int {
        let total = fields.reduce(0) { $0 + applyCorrection(to: $1) }
        refreshSoon()
        return total
    }

    @discardableResult
    func fix(_ field: DetectedField) -> Int {
        let n = applyCorrection(to: field)
        refreshSoon()
        return n
    }

    func apply(_ suggestion: Suggestion, in field: DetectedField) {
        // Only apply a span edit if the field still matches the snapshot the
        // suggestion offsets were computed against; otherwise re-scan instead of
        // corrupting text the user has since changed.
        guard let live = capture.currentValue(of: field.element) else { return }
        guard live == field.text else { refreshSoon(); return }
        let ns = NSMutableString(string: live)
        guard suggestion.location + suggestion.length <= ns.length else { return }
        ns.replaceCharacters(in: suggestion.range, with: suggestion.replacement)
        setValue(ns as String, on: field.element)
        refreshSoon()
    }

    // MARK: - Dismissing (hide a suggestion without applying it)

    /// Hide one suggestion. A cheap, always-available "no" is what makes saying
    /// "yes" (Apply) feel safe. The dismissal is keyed by content so it persists
    /// across re-scans of unchanged text.
    func dismiss(_ suggestion: Suggestion, in field: DetectedField) {
        dismissedKeys.insert(Self.dismissKey(fieldID: field.id, suggestion))
        fields = filterDismissed(fields)
    }

    private static func dismissKey(fieldID: String, _ s: Suggestion) -> String {
        "\(fieldID)|\(s.location)|\(s.length)|\(s.original)|\(s.replacement)"
    }

    private func filterDismissed(_ input: [DetectedField]) -> [DetectedField] {
        input.compactMap { f in
            let remaining = f.suggestions.filter {
                !dismissedKeys.contains(Self.dismissKey(fieldID: f.id, $0))
            }
            guard !remaining.isEmpty else { return nil }
            return DetectedField(id: f.id, label: f.label, roleName: f.roleName,
                                 text: f.text, suggestions: remaining,
                                 element: f.element, isFocused: f.isFocused)
        }
    }

    private static func wordCount(_ s: String) -> Int {
        s.split { $0.isWhitespace || $0.isNewline }.count
    }

    /// Correct the element's *current* value (never a stale snapshot), so any
    /// keystrokes entered since the scan are preserved.
    private func applyCorrection(to field: DetectedField) -> Int {
        guard let live = capture.currentValue(of: field.element) else { return 0 }
        let corrected = grammar.correct(live)
        guard corrected != live else { return 0 }
        setValue(corrected, on: field.element)
        return field.suggestions.count
    }

    private func setValue(_ text: String, on element: AXUIElement) {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
    }

    // MARK: - Scanning

    private func reconcile() {
        let shouldRun = enabled && !paused
        if shouldRun && timer == nil {
            running = true
            tick()
            let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            t.tolerance = 0.5
            timer = t
        } else if !shouldRun {
            running = false
            timer?.invalidate()
            timer = nil
            clear()
        }
    }

    private func tick(force: Bool = false) {
        guard enabled, !paused, AXIsProcessTrusted() else { clear(); return }
        if scanning && !force { return } // don't pile up scans
        guard let app = NSWorkspace.shared.frontmostApplication else { clear(); return }

        // Never scan GrammarGem's own windows.
        if app.processIdentifier == ownPID { clear(); return }
        activeAppName = app.localizedName ?? ""

        let bundleID = app.bundleIdentifier
        let domain = detector.frontmostDomain()
        if exclusions.isBlocked(bundleID: bundleID, domain: domain) { clear(); return }
        // Conservative: a blocked-domain user in a browser whose URL we can't read
        // should not be monitored rather than risk leaking a sensitive page.
        if domain == nil, detector.isBrowser(bundleID), exclusions.hasDomainRules { clear(); return }

        let pid = app.processIdentifier
        scanGeneration += 1
        let generation = scanGeneration
        scanning = true

        // Heavy AX traversal off the main thread.
        Task.detached(priority: .utility) {
            let focused = LiveMonitor.systemFocusedElement()
            let scanned = TextFieldScanner.scan(pid: pid, focused: focused)
            await MainActor.run { self.ingest(scanned, generation: generation) }
        }
    }

    private func ingest(_ scanned: [ScannedField], generation: Int) {
        scanning = false
        guard generation == scanGeneration else { return } // superseded by a newer scan
        guard !scanned.isEmpty else { clear(); return }

        // Total words across ALL scanned fields (clean ones included) so the
        // writing score is honest about the whole on-screen text, not just the
        // fields that happen to have issues.
        scannedWordCount = scanned.reduce(0) { $0 + Self.wordCount($1.text) }

        // Change detection includes focus + element identity so tabbing between
        // same-text fields still updates the focused indicator.
        var hasher = Hasher()
        for f in scanned {
            hasher.combine(f.text)
            hasher.combine(f.isFocused)
            hasher.combine(f.stableID)
        }
        let h = hasher.finalize()
        if h == lastHash { return }
        lastHash = h

        scannedCount = scanned.count
        var detected: [DetectedField] = []
        for f in scanned {
            let text = f.text.count > maxCheckChars ? String(f.text.prefix(maxCheckChars)) : f.text
            let suggestions = grammar.check(text)
            guard !suggestions.isEmpty else { continue }
            detected.append(DetectedField(
                id: f.stableID, label: f.label, roleName: f.roleName,
                text: f.text, suggestions: suggestions, element: f.element, isFocused: f.isFocused))
        }
        detected.sort { ($0.isFocused ? 0 : 1) < ($1.isFocused ? 0 : 1) }
        fields = filterDismissed(detected)
    }

    private nonisolated static func systemFocusedElement() -> AXUIElement? {
        AX.focusedElement()
    }

    private func clear() {
        if !fields.isEmpty { fields = [] }
        scannedCount = 0
        scannedWordCount = 0
        lastHash = 0
    }
}
