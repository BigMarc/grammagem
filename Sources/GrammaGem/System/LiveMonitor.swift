import Foundation
import AppKit
import ApplicationServices

/// The always-on, menu-bar–resident monitor. While enabled, it periodically
/// reads the focused text field (Accessibility API), runs the offline grammar
/// engine, and publishes live suggestions — so the menu bar reflects issues as
/// you type. It stays out of excluded apps/domains and never sends text anywhere.
@MainActor
final class LiveMonitor: ObservableObject {
    @Published private(set) var suggestions: [Suggestion] = []
    @Published private(set) var activeAppName: String = ""
    @Published private(set) var running = false

    var issueCount: Int { suggestions.count }

    private let grammar: GrammarEngine
    private let detector: AppDetector
    private let exclusions: Exclusions
    private let capture: TextCapture

    private var timer: Timer?
    private var enabled = false
    private var paused = false
    private var lastHash = 0
    private let interval: TimeInterval = 1.3

    init(grammar: GrammarEngine, detector: AppDetector, exclusions: Exclusions, capture: TextCapture) {
        self.grammar = grammar
        self.detector = detector
        self.exclusions = exclusions
        self.capture = capture
    }

    /// Turn live monitoring on/off (driven by the "live underlines" preference).
    func setEnabled(_ on: Bool) {
        enabled = on
        reconcile()
    }

    /// Global pause (also stops the hotkeys, handled in AppState).
    func setPaused(_ p: Bool) {
        paused = p
        reconcile()
    }

    /// Re-run immediately (e.g. after a "fix all").
    func refreshSoon() {
        lastHash = 0
        tick()
    }

    private func reconcile() {
        let shouldRun = enabled && !paused
        if shouldRun && timer == nil {
            running = true
            tick()
            let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            t.tolerance = 0.4
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

        let front = detector.frontmost()
        activeAppName = front?.name ?? ""

        // Respect the page blocker.
        if exclusions.isBlocked(bundleID: front?.bundleID, domain: detector.frontmostDomain()) {
            clear()
            return
        }

        guard let field = capture.focusedFieldText() else { clear(); return }
        let text = field.text
        guard text.count >= 3 else { clear(); return }

        let h = text.hashValue
        if h == lastHash { return } // unchanged since last check
        lastHash = h

        suggestions = grammar.check(text)
    }

    private func clear() {
        if !suggestions.isEmpty { suggestions = [] }
        lastHash = 0
    }
}
