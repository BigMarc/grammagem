import Foundation
import AppKit
import ApplicationServices

/// Safe Accessibility helpers shared across the System layer.
///
/// `AXUIElementCopyAttributeValue` returning `.success` only guarantees a
/// non-null `CFTypeRef` — NOT that it is an `AXUIElement`. A misbehaving AX
/// server (Electron/Java/custom) can return a different CF type, and a forced
/// `as!` cast then traps and crashes the whole app. These helpers cast safely.
enum AX {
    /// Safely bridge a CFTypeRef to AXUIElement, returning nil on type mismatch.
    static func element(_ ref: CFTypeRef?) -> AXUIElement? {
        guard let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement) // safe: type id verified above
    }

    /// Copy an attribute as an `AXUIElement` (nil on failure/type mismatch).
    static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else {
            return nil
        }
        return AX.element(ref)
    }

    /// Copy an attribute as a `String` (nil on failure/wrong type).
    static func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else {
            return nil
        }
        return ref as? String
    }

    /// Bound each cross-process AX message so a wedged target app can't hang us.
    static func setMessagingTimeout(_ element: AXUIElement, _ seconds: Float) {
        AXUIElementSetMessagingTimeout(element, seconds)
    }

    /// The currently-focused UI element across the system — robust to the
    /// system-wide element failing.
    ///
    /// On recent macOS, `AXUIElementCreateSystemWide()` returns
    /// `kAXErrorCannotComplete` (-25204) for *every* query made by a background /
    /// accessory process (which is exactly what a menu-bar app like GrammaGem is).
    /// When that happens the system-wide focused-element read yields nil and the
    /// app "sees" no text or text fields at all. Resolving the focused element
    /// through the **frontmost application's** own AX element works reliably in
    /// that context, so we prefer the system-wide read (one IPC hop, correct on
    /// OSes where it works) and transparently fall back to the per-app read.
    static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        setMessagingTimeout(systemWide, 0.5)
        if let element = copyElement(systemWide, kAXFocusedUIElementAttribute as String) {
            return element
        }
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }
        let axApp = AXUIElementCreateApplication(pid)
        setMessagingTimeout(axApp, 0.5)
        return copyElement(axApp, kAXFocusedUIElementAttribute as String)
    }
}
