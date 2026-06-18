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
        AX.setMessagingTimeout(axApp, 0.3)
        guard let window = AX.copyElement(axApp, kAXFocusedWindowAttribute) else { return nil }
        if let urlString = AX.copyString(window, kAXDocumentAttribute),
           let host = URL(string: urlString)?.host {
            return host
        }
        return nil
    }

    /// Known web browsers, where a nil domain means "URL undeterminable" (so the
    /// page blocker should be conservative) rather than "not a web page".
    private static let browserBundleIDs: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "com.google.Chrome.canary",
        "company.thebrowser.Browser", "com.microsoft.edgemac", "com.brave.Browser",
        "org.mozilla.firefox", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
    ]

    func isBrowser(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return Self.browserBundleIDs.contains(bundleID)
    }
}
