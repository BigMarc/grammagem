import SwiftUI

// MARK: - Shortcuts

struct ShortcutsView: View {
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        DetailScaffold(
            title: "Shortcuts",
            subtitle: "Global hotkeys that work in every app. Click a shortcut to change it."
        ) {
            Card {
                shortcutRow(
                    name: "Fix selection",
                    detail: "Grammar + clarity, in place",
                    combo: $prefs.fixHotkey)
                Divider()
                shortcutRow(
                    name: "Ask GrammarGem",
                    detail: "Rewrite with an instruction",
                    combo: $prefs.askHotkey)
            }
            Text("Tip: include at least one modifier (⌘, ⌥, ⌃, ⇧). Press Esc while recording to cancel.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func shortcutRow(name: String, detail: String, combo: Binding<HotkeyCombo>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            ShortcutRecorder(combo: combo)
        }
    }
}

/// A small click-to-record control that captures the next modifier+key combo.
struct ShortcutRecorder: View {
    @Binding var combo: HotkeyCombo
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Press keys…" : combo.display)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 76)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(recording ? GG.emerald.opacity(0.15) : Color(nsColor: .controlColor)))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(recording ? GG.emerald : Color.primary.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil } // Esc cancels
            if let captured = HotkeyCombo.from(event: event) {
                combo = captured
                stop()
                return nil
            }
            return event // ignore bare keys (no modifier)
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }
}

// MARK: - AI Model

struct ModelView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var gate: FeatureGate
    @EnvironmentObject private var model: ModelManager

    var body: some View {
        DetailScaffold(
            title: "AI Model",
            subtitle: "The local model that powers rewrites, tone, and Ask. Runs entirely on your Mac."
        ) {
            Card {
                Picker("Model", selection: $model.selectedRepo) {
                    Text("Qwen2.5-3B · balanced (default)").tag(AppConfig.Model.defaultRepo)
                    Text("Qwen2.5-7B · higher quality").tag(AppConfig.Model.largeRepo)
                }
                .disabled(!gate.entitlements.canUseLargeModel)

                if !gate.entitlements.canUseLargeModel {
                    HStack { Image(systemName: "lock.fill").foregroundStyle(GG.gold); Text("The larger model is available on the lifetime license.").font(.caption).foregroundStyle(.secondary) }
                }
                Divider()
                ModelDownloadControls()
            }

            Card {
                Label("Private by default", systemImage: "lock.shield")
                    .font(.headline)
                Text("The model is downloaded once from Hugging Face and then runs offline. It is never bundled in the app, and it never sends your text anywhere.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Privacy

struct PrivacyView: View {
    @EnvironmentObject private var usage: UsageStats
    @State private var confirmReset = false

    var body: some View {
        DetailScaffold(
            title: "Privacy",
            subtitle: "What touches the network — and what never does."
        ) {
            Card {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.shield.fill").font(.title2).foregroundStyle(GG.emerald)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("0 bytes of your writing leave this Mac").font(.headline)
                        Text("Every correction and rewrite runs locally. No telemetry is collected.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }

            Card {
                Text("The only times GrammarGem uses the network").font(.headline)
                networkRow("One-time AI model download", "Hugging Face, on first run")
                Divider()
                networkRow("License activation & checks", "To enforce your device cap")
                Divider()
                networkRow("App updates", "Signed update checks")
                Text("None of these ever include the text you write.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Card {
                Text("Local data").font(.headline)
                Text("Your dictionary, snippets, modes, and usage counts live only on this Mac.")
                    .font(.callout).foregroundStyle(.secondary)
                Button(role: .destructive) { confirmReset = true } label: {
                    Label("Reset usage statistics", systemImage: "arrow.counterclockwise")
                }
                .confirmationDialog("Reset all local usage statistics?", isPresented: $confirmReset) {
                    Button("Reset", role: .destructive) { usage.reset() }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
    }

    private func networkRow(_ title: String, _ detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.forward.circle").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
