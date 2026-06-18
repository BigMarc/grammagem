import Foundation

/// Orchestrates the end-to-end system-wide loop:
/// capture selected text → gate by entitlement → run an engine → write it back.
///
/// `fix` uses Layer 1 (Harper grammar — free, unlimited, instant).
/// `ask` and Mode rewrites use Layer 2 (local LLM — gated + counted on free tier).
@MainActor
final class TextReplacementCoordinator {
    private let capture: TextCapture
    private let grammar: GrammarEngine
    private let ai: AIEngine
    private let gate: FeatureGate
    private let detector: AppDetector

    init(capture: TextCapture, grammar: GrammarEngine, ai: AIEngine,
         gate: FeatureGate, detector: AppDetector) {
        self.capture = capture
        self.grammar = grammar
        self.ai = ai
        self.gate = gate
        self.detector = detector
    }

    /// The "fix" hotkey — instant grammar correction (Layer 1, always free).
    func handleFix() async -> ProcessOutcome {
        let cap: TextCapture.Capture
        do {
            cap = try await captureOffMain()
        } catch TextCapture.CaptureError.noSelection {
            return .noSelection
        } catch {
            return .failed(error.localizedDescription)
        }

        let corrected = grammar.correct(cap.text)
        guard corrected != cap.text else { return .replaced(corrected) }

        let ok = await replaceOffMain(corrected, cap)
        return ok ? .replaced(corrected) : .failed("Couldn't write the correction back.")
    }

    /// The "Ask" hotkey/popover — a local-LLM instruction over the selection.
    func handleAsk(_ instruction: String) async -> ProcessOutcome {
        let action = AIAction.ask(instruction)
        if case .denied(let reason) = gate.authorizeAI(action) {
            return .blockedByEntitlement(reason)
        }
        guard ai.isReady else { return .failed(AIEngineError.modelNotReady.localizedDescription) }

        let cap: TextCapture.Capture
        do { cap = try await captureOffMain() } catch { return .failed(error.localizedDescription) }

        do {
            let result = try await ai.run(action, on: cap.text)
            gate.recordAIActionUsed()
            let ok = await replaceOffMain(result, cap)
            return ok ? .replaced(result) : .failed("Couldn't write the result back.")
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Apply a Writing Mode rewrite to the selection (paid; free tier only Polish).
    func handleApplyMode(_ mode: WritingMode) async -> ProcessOutcome {
        let action = AIAction.applyMode(mode)
        if case .denied(let reason) = gate.authorizeAI(action) {
            return .blockedByEntitlement(reason)
        }
        guard ai.isReady else { return .failed(AIEngineError.modelNotReady.localizedDescription) }

        let cap: TextCapture.Capture
        do { cap = try await captureOffMain() } catch { return .failed(error.localizedDescription) }

        do {
            let result = try await ai.run(action, on: cap.text)
            gate.recordAIActionUsed()
            let ok = await replaceOffMain(result, cap)
            return ok ? .replaced(result) : .failed("Couldn't write the result back.")
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Grammar-fix the entire focused text field (used by the live monitor's
    /// "Fix all" — Layer 1, always free, no selection required).
    func handleFixFocusedField() async -> ProcessOutcome {
        let field = await Task.detached(priority: .userInitiated) { [capture] in
            capture.focusedFieldText()
        }.value
        guard let field else { return .noSelection }

        let corrected = grammar.correct(field.text)
        guard corrected != field.text else { return .replaced(corrected) }

        let element = field.element
        let ok = await Task.detached(priority: .userInitiated) { [capture] in
            capture.setFocusedField(corrected, element: element)
        }.value
        return ok ? .replaced(corrected) : .failed("Couldn't update the text field.")
    }

    /// Milestone-1 proof: capture → UPPERCASE → replace, end-to-end, no engine.
    func handleDebugUppercase() async -> ProcessOutcome {
        let cap: TextCapture.Capture
        do { cap = try await captureOffMain() } catch { return .failed(error.localizedDescription) }
        let out = cap.text.uppercased()
        let ok = await replaceOffMain(out, cap)
        return ok ? .replaced(out) : .failed("Replace failed.")
    }

    // MARK: - Off-main wrappers (capture/replace block on synthetic keystrokes)

    private func captureOffMain() async throws -> TextCapture.Capture {
        let capture = self.capture
        return try await Task.detached(priority: .userInitiated) {
            try capture.capture()
        }.value
    }

    private func replaceOffMain(_ text: String, _ cap: TextCapture.Capture) async -> Bool {
        let capture = self.capture
        return await Task.detached(priority: .userInitiated) {
            capture.replace(text, capture: cap)
        }.value
    }
}
