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

/// The always-on, menu-bar–resident monitor. While enabled, it periodically
/// scans **every** text area in the frontmost window (Accessibility API), runs
/// the offline grammar engine on each, and publishes the ones with issues — so
/// GrammaGem reflects problems across the whole screen, not just the focused
/// field. It stays out of excluded apps/domains and never sends text anywhere.
@MainActor
final class LiveMonitor: ObservableObject {
    @Published private(set) var fields: [DetectedField] = []
    @Published private(set) var scannedCount = 0
    @Published private(set) var activeAppName = ""
    @Published private(set) var running = false

    /// Total number of issues across all detected text areas.
    var issueCount: Int { fields.reduce(0) { $0 + $1.suggestions.count } }

    private let grammar: GrammarEngine
    private let detector: AppDetector
    private let exclusions: Exclusions
    private let capture: TextCapture

    private var timer: Timer?
    private var enabled = false
    private var paused = false
    private var lastHash = 0
    private let interval: TimeInterval = 1.4

    init(grammar: GrammarEngine, detector: AppDetector, exclusions: Exclusions, capture: TextCapture) {
        self.grammar = grammar
        self.detector = detector
        self.exclusions = exclusions
        self.capture = capture
    }

    func setEnabled(_ on: Bool) { enabled = on; reconcile() }
    func setPaused(_ p: Bool) { paused = p; reconcile() }

    /// Re-scan now (e.g. after applying a fix).
    func refreshSoon() { lastHash = 0; tick() }

    // MARK: - Applying fixes

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
        let ns = NSMutableString(string: field.text)
        guard suggestion.location + suggestion.length <= ns.length else { return }
        ns.replaceCharacters(in: suggestion.range, with: suggestion.replacement)
        setValue(ns as String, on: field.element)
        refreshSoon()
    }

    private func applyCorrection(to field: DetectedField) -> Int {
        let corrected = grammar.correct(field.text)
        guard corrected != field.text else { return 0 }
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

    private func tick() {
        guard enabled, !paused, AXIsProcessTrusted() else { clear(); return }
        guard let app = NSWorkspace.shared.frontmostApplication else { clear(); return }
        activeAppName = app.localizedName ?? ""

        if exclusions.isBlocked(bundleID: app.bundleIdentifier, domain: detector.frontmostDomain()) {
            clear()
            return
        }

        let focused = systemFocusedElement()
        let scanned = TextFieldScanner.scan(pid: app.processIdentifier, focused: focused)
        guard !scanned.isEmpty else { clear(); return }

        // Skip re-checking if nothing on screen changed.
        var hasher = Hasher()
        hasher.combine(app.bundleIdentifier ?? "")
        for f in scanned { hasher.combine(f.text) }
        let h = hasher.finalize()
        if h == lastHash { return }
        lastHash = h

        scannedCount = scanned.count
        var detected: [DetectedField] = []
        for (i, f) in scanned.enumerated() {
            let suggestions = grammar.check(f.text)
            guard !suggestions.isEmpty else { continue }
            detected.append(DetectedField(
                id: "\(f.roleName)#\(i)", label: f.label, roleName: f.roleName,
                text: f.text, suggestions: suggestions, element: f.element, isFocused: f.isFocused))
        }
        // Focused field first.
        detected.sort { ($0.isFocused ? 0 : 1) < ($1.isFocused ? 0 : 1) }
        fields = detected
    }

    private func systemFocusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system, kAXFocusedUIElementAttribute as CFString, &ref) == .success, let ref
        else { return nil }
        return (ref as! AXUIElement)
    }

    private func clear() {
        if !fields.isEmpty { fields = [] }
        scannedCount = 0
        lastHash = 0
    }
}
