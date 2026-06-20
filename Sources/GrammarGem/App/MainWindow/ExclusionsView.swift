import SwiftUI
import AppKit

struct ExclusionsView: View {
    @EnvironmentObject private var exclusions: Exclusions
    @State private var newDomain = ""

    var body: some View {
        DetailScaffold(
            title: "Page Blocker",
            subtitle: "Keep GrammarGem out of the way in sensitive apps and sites."
        ) {
            Card {
                Label("How it works", systemImage: "hand.raised")
                    .font(.headline)
                Text("When the frontmost app or website is on these lists, GrammarGem stops monitoring and the hotkeys do nothing — useful for password managers, banking, and private work.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            // Blocked apps
            Card {
                HStack {
                    Text("Blocked apps").font(.headline)
                    Spacer()
                    addAppMenu
                }
                if exclusions.blockedApps.isEmpty {
                    Text("No apps blocked.").font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(exclusions.blockedApps, id: \.self) { bundle in
                        HStack {
                            Image(systemName: "app.dashed").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(exclusions.appName(for: bundle))
                                Text(bundle).font(.caption2.monospaced()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) { exclusions.removeApp(bundle) } label: {
                                Image(systemName: "trash")
                            }.buttonStyle(.borderless)
                        }
                        if bundle != exclusions.blockedApps.last { Divider() }
                    }
                }
                Divider()
                HStack(spacing: 8) {
                    Text("Suggestions:").font(.caption).foregroundStyle(.secondary)
                    ForEach(Exclusions.suggestedApps, id: \.bundleID) { item in
                        if !exclusions.blockedApps.contains(item.bundleID) {
                            Button(item.name) { exclusions.addApp(item.bundleID) }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
            }

            // Blocked domains
            Card {
                Text("Blocked websites").font(.headline)
                if exclusions.blockedDomains.isEmpty {
                    Text("No websites blocked.").font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(exclusions.blockedDomains, id: \.self) { domain in
                        HStack {
                            Image(systemName: "globe").foregroundStyle(.secondary)
                            Text(domain)
                            Spacer()
                            Button(role: .destructive) { exclusions.removeDomain(domain) } label: {
                                Image(systemName: "trash")
                            }.buttonStyle(.borderless)
                        }
                        if domain != exclusions.blockedDomains.last { Divider() }
                    }
                }
                HStack {
                    TextField("Add a domain (e.g. mybank.com)", text: $newDomain)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addDomain)
                    Button("Block", action: addDomain)
                        .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Website blocking works best in Safari; other browsers are matched when possible.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var addAppMenu: some View {
        Menu {
            ForEach(runningApps(), id: \.bundleID) { item in
                Button(item.name) { exclusions.addApp(item.bundleID) }
            }
        } label: {
            Label("Add app", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func addDomain() {
        exclusions.addDomain(newDomain)
        newDomain = ""
    }

    private func runningApps() -> [(name: String, bundleID: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .compactMap { app -> (String, String)? in
                guard let id = app.bundleIdentifier else { return nil }
                return (app.localizedName ?? id, id)
            }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
            .map { (name: $0.0, bundleID: $0.1) }
    }
}
