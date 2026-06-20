import SwiftUI

struct WritingModesView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var gate: FeatureGate
    @EnvironmentObject private var customModes: CustomModesStore

    @State private var newName = ""
    @State private var newPrompt = ""
    @State private var newBundleID = ""
    @State private var newMappedMode = ModeRegistry.polish.id

    private var paid: Bool { gate.entitlements.allModes }

    var body: some View {
        DetailScaffold(
            title: "Writing Modes",
            subtitle: "Tune the tone for every context — or let GrammarGem pick it for you."
        ) {
            builtInCard
            customCard
            appAwareCard
        }
    }

    private var builtInCard: some View {
        Card {
            Text("Built-in modes").font(.headline)
            ForEach(ModeRegistry.all) { mode in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: mode.isPaid ? "lock.fill" : "checkmark.circle.fill")
                        .foregroundStyle(mode.isPaid && !paid ? Color.secondary : GG.emerald)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(mode.name).fontWeight(.medium)
                            if mode.isPaid && !paid { UpgradeBadge() }
                        }
                        Text(mode.autoFormat ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if mode.id != ModeRegistry.all.last?.id { Divider() }
            }
        }
    }

    private var customCard: some View {
        Card {
            HStack { Text("Custom modes").font(.headline); if !paid { UpgradeBadge() } }
            if customModes.customModes.isEmpty {
                Text("Create your own modes with your own instructions — one per context you write in.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(customModes.customModes) { mode in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(mode.name).fontWeight(.medium)
                            Text(mode.systemPrompt).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Button(role: .destructive) { customModes.removeCustom(id: mode.id) } label: {
                            Image(systemName: "trash")
                        }.buttonStyle(.borderless)
                    }
                    Divider()
                }
            }

            if paid {
                TextField("Mode name (e.g. “Newsletter”)", text: $newName).textFieldStyle(.roundedBorder)
                TextField("Instruction the model should follow…", text: $newPrompt, axis: .vertical)
                    .lineLimit(2...4).textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Add mode") {
                        customModes.addCustom(name: newName, prompt: newPrompt)
                        newName = ""; newPrompt = ""
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                Button("Unlock custom modes") { app.showMainWindow(select: .license) }
            }
        }
    }

    private var appAwareCard: some View {
        Card {
            HStack { Text("App-aware switching").font(.headline); if !paid { UpgradeBadge() } }
            Text("Map an app to a Mode and GrammarGem applies it automatically when that app is in front.")
                .font(.callout).foregroundStyle(.secondary)

            if !customModes.appOverrides.isEmpty {
                ForEach(customModes.appOverrides.sorted(by: { $0.key < $1.key }), id: \.key) { bundle, modeID in
                    HStack {
                        Text(bundle).font(.callout.monospaced())
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Text(modeName(modeID)).fontWeight(.medium)
                        Spacer()
                        Button(role: .destructive) { customModes.clearOverride(bundleID: bundle) } label: {
                            Image(systemName: "trash")
                        }.buttonStyle(.borderless)
                    }
                    Divider()
                }
            }

            if paid {
                HStack {
                    TextField("App bundle id (e.g. com.apple.mail)", text: $newBundleID)
                        .textFieldStyle(.roundedBorder)
                    Picker("", selection: $newMappedMode) {
                        ForEach(customModes.allModes()) { m in Text(m.name).tag(m.id) }
                    }.labelsHidden().frame(width: 160)
                    Button("Map") {
                        customModes.setOverride(bundleID: newBundleID, modeID: newMappedMode)
                        newBundleID = ""
                    }
                    .disabled(newBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                Button("Unlock app-aware switching") { app.showMainWindow(select: .license) }
            }
        }
    }

    private func modeName(_ id: String) -> String {
        customModes.allModes().first { $0.id == id }?.name ?? id
    }
}
