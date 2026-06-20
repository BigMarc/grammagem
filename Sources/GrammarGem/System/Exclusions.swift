import Foundation
import AppKit

/// The "page blocker": apps and domains where GrammarGem should stay completely
/// out of the way — password managers, banking sites, anything sensitive.
/// When the frontmost context is excluded, live monitoring and the hotkeys are
/// suppressed.
@MainActor
final class Exclusions: ObservableObject {
    @Published private(set) var blockedApps: [String]      // bundle identifiers
    @Published private(set) var blockedDomains: [String]   // hostnames, e.g. "chase.com"

    private let appsKey = "GrammarGem.blockedApps"
    private let domainsKey = "GrammarGem.blockedDomains"
    private let d = UserDefaults.standard

    /// Common sensitive apps offered as one-tap suggestions in the UI.
    static let suggestedApps: [(name: String, bundleID: String)] = [
        ("1Password", "com.1password.1password"),
        ("Bitwarden", "com.bitwarden.desktop"),
        ("Keychain Access", "com.apple.keychainaccess"),
        ("Terminal", "com.apple.Terminal"),
    ]

    init() {
        blockedApps = d.stringArray(forKey: appsKey) ?? []
        blockedDomains = d.stringArray(forKey: domainsKey) ?? []
    }

    /// True if the user has any domain rules (so we should be conservative when
    /// a browser's URL can't be read).
    var hasDomainRules: Bool { !blockedDomains.isEmpty }

    /// Whether GrammarGem should be suppressed for this frontmost context.
    func isBlocked(bundleID: String?, domain: String?) -> Bool {
        if let bundleID, blockedApps.contains(bundleID) { return true }
        if let host = domain?.lowercased(), !host.isEmpty {
            return blockedDomains.contains { dom in
                let d = dom.lowercased()
                return host == d || host.hasSuffix("." + d)
            }
        }
        return false
    }

    func addApp(_ bundleID: String) {
        let b = bundleID.trimmingCharacters(in: .whitespaces)
        guard !b.isEmpty, !blockedApps.contains(b) else { return }
        blockedApps.append(b)
        d.set(blockedApps, forKey: appsKey)
    }

    func removeApp(_ bundleID: String) {
        blockedApps.removeAll { $0 == bundleID }
        d.set(blockedApps, forKey: appsKey)
    }

    func addDomain(_ domain: String) {
        let host = normalizedDomain(domain)
        guard !host.isEmpty, !blockedDomains.contains(host) else { return }
        blockedDomains.append(host)
        d.set(blockedDomains, forKey: domainsKey)
    }

    func removeDomain(_ domain: String) {
        blockedDomains.removeAll { $0 == domain }
        d.set(blockedDomains, forKey: domainsKey)
    }

    /// Friendly app name for a bundle id, if installed.
    func appName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url),
           let name = (bundle.infoDictionary?["CFBundleName"] as? String) {
            return name
        }
        return bundleID
    }

    private func normalizedDomain(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if let url = URL(string: s), let host = url.host { return host }
        s = s.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        return s
    }
}
