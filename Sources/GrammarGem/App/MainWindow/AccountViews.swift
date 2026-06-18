import SwiftUI

// MARK: - General

struct GeneralView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var permissions: Permissions

    var body: some View {
        DetailScaffold(title: "General", subtitle: "Make GrammaGem feel like yours.") {
            Card {
                Toggle("Launch at login", isOn: $prefs.launchAtLogin)
                Divider()
                Toggle("Show live underlines as you type", isOn: $prefs.liveUnderlines)
                Divider()
                Toggle("Restore my clipboard after a fix", isOn: $prefs.restoreClipboard)
                Divider()
                Toggle("Play a sound on correction", isOn: $prefs.playSounds)
            }

            Card {
                Picker("Appearance", selection: $prefs.appearance) {
                    ForEach(Preferences.Appearance.allCases) { Text($0.label).tag($0) }
                }
                Picker("Menu bar", selection: $prefs.menuBarStyle) {
                    ForEach(Preferences.MenuBarStyle.allCases) { Text($0.label).tag($0) }
                }
            }

            Card {
                Text("Permissions").font(.headline)
                HStack {
                    Image(systemName: permissions.accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(permissions.accessibilityTrusted ? GG.emerald : .orange)
                    Text(permissions.accessibilityTrusted ? "Accessibility granted" : "Accessibility needed to fix text in apps")
                    Spacer()
                    if !permissions.accessibilityTrusted {
                        Button("Set up") { app.showOnboarding() }
                    }
                }
            }
        }
    }
}

// MARK: - License

struct LicenseView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var license: LicenseManager
    @State private var keyField = ""

    private let plans: [(String, Int, String)] = [
        ("Solo", 39, "1 Mac"),
        ("Personal", 59, "2 Macs"),
        ("Studio", 89, "4 Macs"),
        ("Startup License", 159, "10 Macs"),
    ]

    var body: some View {
        DetailScaffold(title: "License", subtitle: "One-time purchase. Lifetime updates.") {
            Card {
                HStack {
                    VStack(alignment: .leading) {
                        Text(license.tier.displayName).font(.title3.weight(.semibold))
                        Text(license.isLicensed ? "Lifetime license · active" : "Free plan")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: license.isLicensed ? "checkmark.seal.fill" : "gift")
                        .font(.title).foregroundStyle(license.isLicensed ? GG.emerald : GG.gold)
                }
            }

            if license.isLicensed {
                Card {
                    Text("Manage").font(.headline)
                    Button(role: .destructive) {
                        Task { await license.deactivateThisDevice() }
                    } label: { Text(license.isWorking ? "Working…" : "Deactivate this device") }
                        .disabled(license.isWorking)
                    Link("Open license portal", destination: AppConfig.modelPortalURL)
                }
            } else {
                Card {
                    Text("Activate a license").font(.headline)
                    HStack {
                        TextField("Paste your license key", text: $keyField).textFieldStyle(.roundedBorder)
                        Button(license.isWorking ? "…" : "Activate") {
                            Task { await license.activate(key: keyField) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(license.isWorking || keyField.isEmpty)
                    }
                }
                Card {
                    Text("Plans").font(.headline)
                    ForEach(plans, id: \.0) { name, price, devices in
                        HStack {
                            Text(name).fontWeight(name == "Personal" ? .semibold : .regular)
                            if name == "Personal" {
                                Text("Popular").font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(GG.gold.opacity(0.18), in: Capsule()).foregroundStyle(GG.gold)
                            }
                            Spacer()
                            Text(devices).font(.caption).foregroundStyle(.secondary)
                            Text("$\(price)").font(.body.weight(.semibold)).frame(width: 52, alignment: .trailing)
                        }
                        if name != plans.last?.0 { Divider() }
                    }
                    Link("Choose a plan", destination: AppConfig.websiteURL)
                        .buttonStyle(.borderedProminent)
                }
            }

            if let err = license.lastError {
                Label(err, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - About

struct AboutView: View {
    var body: some View {
        DetailScaffold(title: "About", subtitle: nil) {
            Card {
                HStack(spacing: 14) {
                    Image(systemName: "pencil.and.scribble")
                        .font(.system(size: 34)).foregroundStyle(GG.emerald)
                        .frame(width: 56, height: 56)
                        .background(GG.emerald.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GrammaGem").font(.title2.bold())
                        Text("Version \(AppConfig.appVersion)").foregroundStyle(.secondary)
                        Text("The private, on-device writing assistant for Mac.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            Card {
                Link(destination: AppConfig.websiteURL) { Label("Website", systemImage: "globe") }
                Divider()
                Link(destination: AppConfig.websiteURL.appendingPathComponent("docs")) { Label("Documentation", systemImage: "book") }
                Divider()
                Link(destination: URL(string: "mailto:\(AppConfig.supportEmail)")!) { Label("Contact support", systemImage: "envelope") }
            }

            Card {
                Text("Open source").font(.headline)
                Text("GrammaGem is open source under the MIT License — a privacy tool you can inspect.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(AppConfig.copyright).font(.caption).foregroundStyle(.secondary)
                Text(AppConfig.companyName + " · " + AppConfig.companyAddress)
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
