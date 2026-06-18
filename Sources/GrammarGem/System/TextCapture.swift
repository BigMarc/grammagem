import Foundation
import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Reads the user's selected text from the frontmost app and writes a corrected
/// value back — the mechanism that makes GrammaGem work *everywhere*.
///
/// Two paths, mirroring the spec (§4):
///  1. **Accessibility API** (preferred): read/write `kAXSelectedTextAttribute`
///     on the focused element. Works in most native + many Electron apps.
///  2. **Clipboard fallback** (universal): synthesize ⌘C, read the pasteboard,
///     write the result back, synthesize ⌘V, then restore the prior clipboard.
final class TextCapture {
    enum Method { case accessibility, clipboard }

    struct Capture {
        let text: String
        let method: Method
        /// Held so the AX path can set the new value on the same element.
        let focusedElement: AXUIElement?
    }

    enum CaptureError: LocalizedError {
        case noSelection
        case notPermitted
        var errorDescription: String? {
            switch self {
            case .noSelection: return "Select some text first, then press the hotkey."
            case .notPermitted: return "GrammaGem needs Accessibility permission to read and replace text."
            }
        }
    }

    private let pasteboard = NSPasteboard.general

    /// When true (default), the clipboard-fallback path restores the user's
    /// previous clipboard after pasting the correction. Driven by Preferences.
    var restoreClipboard = true

    // MARK: - Capture

    /// Try AX first; on empty/unavailable, fall back to the clipboard path.
    func capture() throws -> Capture {
        if let ax = captureViaAccessibility() {
            return ax
        }
        if let clip = try captureViaClipboard() {
            return clip
        }
        throw CaptureError.noSelection
    }

    private func captureViaAccessibility() -> Capture? {
        guard AXIsProcessTrusted() else { return nil }
        guard let focused = AX.focusedElement() else { return nil }

        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused, kAXSelectedTextAttribute as CFString, &valueRef) == .success,
            let text = valueRef as? String, !text.isEmpty
        else { return nil }

        return Capture(text: text, method: .accessibility, focusedElement: focused)
    }

    private func captureViaClipboard() throws -> Capture? {
        guard AXIsProcessTrusted() else { throw CaptureError.notPermitted }
        let saved = pasteboard.string(forType: .string)
        let beforeChange = pasteboard.changeCount

        sendCommandKey(CGKeyCode(kVK_ANSI_C))
        // Give the frontmost app a moment to put the selection on the pasteboard.
        Thread.sleep(forTimeInterval: 0.12)

        guard pasteboard.changeCount != beforeChange,
              let copied = pasteboard.string(forType: .string), !copied.isEmpty
        else {
            // Restore and report nothing selected.
            if let saved { writeClipboard(saved) }
            return nil
        }

        // Stash the saved clipboard on the capture so replace() can restore it.
        savedClipboard = saved
        return Capture(text: copied, method: .clipboard, focusedElement: nil)
    }

    // MARK: - Focused field (whole-value read/write, for live monitoring + "fix all")

    /// The full text value of the focused element (not just the selection).
    func focusedFieldText() -> (text: String, element: AXUIElement)? {
        guard AXIsProcessTrusted() else { return nil }
        guard let focused = AX.focusedElement() else { return nil }

        // Only treat genuine editable text roles as fixable, so we don't report
        // "nothing selected" failures on sliders/steppers/custom controls.
        let role = AX.copyString(focused, kAXRoleAttribute)
        guard role == kAXTextFieldRole as String
            || role == kAXTextAreaRole as String
            || role == kAXComboBoxRole as String
        else { return nil }

        guard let text = AX.copyString(focused, kAXValueAttribute) else { return nil }
        return (text, focused)
    }

    /// Re-read an element's current value (used to avoid writing stale text).
    func currentValue(of element: AXUIElement) -> String? {
        AX.copyString(element, kAXValueAttribute)
    }

    @discardableResult
    func setFocusedField(_ text: String, element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef) == .success
    }

    // MARK: - Replace

    @discardableResult
    func replace(_ newText: String, capture: Capture) -> Bool {
        switch capture.method {
        case .accessibility:
            guard let element = capture.focusedElement else { return false }
            let status = AXUIElementSetAttributeValue(
                element, kAXSelectedTextAttribute as CFString, newText as CFTypeRef)
            return status == .success
        case .clipboard:
            writeClipboard(newText)
            sendCommandKey(CGKeyCode(kVK_ANSI_V))
            Thread.sleep(forTimeInterval: 0.10)
            // Restore the user's previous clipboard contents (if they want that).
            if restoreClipboard, let saved = savedClipboard {
                Thread.sleep(forTimeInterval: 0.05)
                writeClipboard(saved)
            }
            savedClipboard = nil
            return true
        }
    }

    // MARK: - Helpers

    private var savedClipboard: String?

    private func writeClipboard(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Synthesize a ⌘<key> keystroke via CGEvent (needs Accessibility / Input Monitoring).
    private func sendCommandKey(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
