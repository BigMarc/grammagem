import Foundation
import AppKit
import ApplicationServices

/// Reports the frontmost application so App-Aware mode switching can pick the
/// right Writing Mode. Pure local introspection — no network, no logging of content.
@MainActor
final class AppDetector {
    struct FrontApp: Equatable {
        let bundleID: String
        let name: String
    }

    /// The app currently in the foreground (the one the hotkey will act on).
    func frontmost() -> FrontApp? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return FrontApp(
            bundleID: app.bundleIdentifier ?? "unknown",
            name: app.localizedName ?? "App")
    }

    /// The Writing Mode App-Aware would auto-apply for the current frontmost app.
    func suggestedMode() -> WritingMode? {
        guard let front = frontmost() else { return nil }
        return ModeRegistry.mode(forBundleID: front.bundleID)
    }

    /// Best-effort hostname of the frontmost browser tab (used by the page blocker).
    /// Reads the window's AX document URL — works in Safari and some others with no
    /// extra permission beyond Accessibility. Returns nil when it can't tell.
    func frontmostDomain() -> String? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
            let winRef
        else { return nil }
        let window = winRef as! AXUIElement

        var docRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            window, kAXDocumentAttribute as CFString, &docRef) == .success,
            let urlString = docRef as? String,
            let host = URL(string: urlString)?.host {
            return host
        }
        return nil
    }
}
