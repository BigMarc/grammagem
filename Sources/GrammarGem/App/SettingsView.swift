import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            LicenseSettings()
                .tabItem { Label("License", systemImage: "key") }
            ModelSettings()
                .tabItem { Label("Model", systemImage: "cpu") }
            DictionarySettings()
                .tabItem { Label("Dictionary", systemImage: "character.book.closed") }
        }
        .padding(20)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        Form {
            Section("Shortcuts") {
                LabeledContent("Fix selection", value: "⌘;")
                LabeledContent("Ask GrammaGem", value: "⌘'")
                Text("Custom shortcuts coming via the KeyboardShortcuts recorder (see README).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("App-aware switching") {
                if app.gate.appAwareEnabled {
                    Toggle("Auto-apply a Writing Mode based on the active app", isOn: $app.appAwareEnabled)
                } else {
                    Label("App-aware switching is part of the lifetime upgrade.", systemImage: "lock")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Permissions") {
                LabeledContent("Accessibility",
                               value: app.permissions.accessibilityTrusted ? "Granted" : "Needed")
                if !app.permissions.accessibilityTrusted {
                    Button("Open onboarding") { app.showOnboarding() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - License

private struct LicenseSettings: View {
    @EnvironmentObject private var app: AppState
    @State private var keyField = ""

    var body: some View {
        Form {
            Section("Plan") {
                LabeledContent("Current tier", value: app.license.tier.displayName)
                LabeledContent("Device cap", value: "\(app.license.tier.deviceCap) Mac\(app.license.tier.deviceCap == 1 ? "" : "s")")
            }

            if app.license.isLicensed {
                Section("This device") {
                    Button(app.license.isWorking ? "Working…" : "Deactivate this device") {
                        Task { await app.license.deactivateThisDevice() }
                    }
                    .disabled(app.license.isWorking)
                    Text("Frees a slot so you can move the license to another Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section("Activate") {
                    TextField("Paste your license key", text: $keyField)
                        .textFieldStyle(.roundedBorder)
                    Button(app.license.isWorking ? "Activating…" : "Activate") {
                        Task { await app.license.activate(key: keyField) }
                    }
                    .disabled(app.license.isWorking || keyField.isEmpty)
                }
            }

            if let error = app.license.lastError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Link("Manage your license", destination: AppConfig.modelPortalURL)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Model

private struct ModelSettings: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var model: ModelManager

    init() {
        _model = ObservedObject(wrappedValue: AppState.shared.model)
    }

    var body: some View {
        Form {
            Section("On-device model") {
                Picker("Model", selection: $model.selectedRepo) {
                    Text("Qwen2.5-3B (default)").tag(AppConfig.Model.defaultRepo)
                    Text("Qwen2.5-7B (more RAM)")
                        .tag(AppConfig.Model.largeRepo)
                }
                .disabled(!app.gate.entitlements.canUseLargeModel)
                if !app.gate.entitlements.canUseLargeModel {
                    Label("The larger 7B model is available on paid plans.", systemImage: "lock")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ModelDownloadControls().environmentObject(app)
            }
            Section {
                Text("Downloaded once from Hugging Face, then everything runs offline. The model is never bundled in the app binary.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Dictionary

private struct DictionarySettings: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var dict: PersonalDictionary
    @State private var newWord = ""
    @State private var capMessage: String?

    init() {
        // Bound at render via environment; we re-observe the shared instance.
        _dict = ObservedObject(wrappedValue: AppState.shared.dictionary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Add a word GrammaGem should never correct", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add).disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let capMessage {
                Label(capMessage, systemImage: "lock").font(.caption).foregroundStyle(.orange)
            }

            let cap = app.gate.entitlements.dictionaryCap
            Text(cap == Int.max
                 ? "\(dict.entries.count) entries · unlimited"
                 : "\(dict.entries.count) / \(cap) entries")
                .font(.caption).foregroundStyle(.secondary)

            List {
                ForEach(dict.entries, id: \.self) { word in
                    HStack {
                        Text(word)
                        Spacer()
                        Button {
                            app.removeDictionaryEntry(word)
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }
            .frame(minHeight: 220)
        }
    }

    private func add() {
        let decision = app.addDictionaryEntry(newWord)
        switch decision {
        case .allowed:
            newWord = ""
            capMessage = nil
        case .denied(let message):
            capMessage = message
        }
    }
}
