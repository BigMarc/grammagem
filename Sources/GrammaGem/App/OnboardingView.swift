import SwiftUI

/// First-run onboarding: explains why GrammaGem needs Accessibility, deep-links
/// to System Settings, and advances automatically the moment permission is
/// granted (even if granted directly in System Settings).
struct OnboardingView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var permissions: Permissions
    @ObservedObject private var model: ModelManager

    init() {
        _permissions = ObservedObject(wrappedValue: AppState.shared.permissions)
        _model = ObservedObject(wrappedValue: AppState.shared.model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to GrammaGem")
                    .font(.largeTitle.bold())
                Text("A private, on-device writing assistant that works in every app.")
                    .foregroundStyle(.secondary)
            }

            stepCard(
                number: 1,
                title: "Grant Accessibility access",
                body: "GrammaGem reads the text you select and writes the correction back. macOS requires Accessibility permission for this. Your text is processed on-device and never leaves your Mac.",
                granted: permissions.accessibilityTrusted
            ) {
                if permissions.accessibilityTrusted {
                    Label("Permission granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    HStack {
                        Button("Open System Settings") { permissions.openAccessibilitySettings() }
                        Button("Request permission") { permissions.requestAccessibility() }
                    }
                    Text("This updates automatically once you flip GrammaGem on in Accessibility.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            stepCard(
                number: 2,
                title: "Download the on-device model (optional)",
                body: "Grammar & spelling work instantly with no download. The AI rewrite/tone/Ask features use a small model downloaded once from Hugging Face — then everything runs offline.",
                granted: model.state == .ready
            ) {
                ModelDownloadControls()
            }

            Spacer()

            HStack {
                if permissions.accessibilityTrusted {
                    Label("You're all set", systemImage: "sparkles").foregroundStyle(.secondary)
                }
                Spacer()
                Button(permissions.accessibilityTrusted ? "Done" : "Continue without permission") {
                    app.showOnboardingDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            permissions.startPollingUntilGranted()
        }
        .onDisappear {
            permissions.stopPolling()
        }
    }

    private func stepCard<Controls: View>(
        number: Int, title: String, body: String, granted: Bool,
        @ViewBuilder controls: () -> Controls
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(granted ? Color.green : Color.accentColor.opacity(0.15))
                    .frame(width: 30, height: 30)
                if granted {
                    Image(systemName: "checkmark").foregroundStyle(.white).font(.caption.bold())
                } else {
                    Text("\(number)").font(.callout.bold()).foregroundStyle(.tint)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Text(body).font(.callout).foregroundStyle(.secondary)
                controls()
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Real model download progress + controls, shared by onboarding and settings.
struct ModelDownloadControls: View {
    @ObservedObject private var model: ModelManager

    init() {
        _model = ObservedObject(wrappedValue: AppState.shared.model)
    }

    var body: some View {
        switch model.state {
        case .notDownloaded:
            VStack(alignment: .leading, spacing: 4) {
                Button("Download model") { model.startDownload() }
                Text("Downloads the model files from Hugging Face (about 1–2 GB). One time, then offline.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress) {
                    Text("Downloading… \(Int(progress * 100))%")
                }
                .frame(maxWidth: 320)
                if !model.statusText.isEmpty {
                    Text(model.statusText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Button("Cancel") { model.cancel() }.controlSize(.small)
            }
        case .ready:
            Label("Model ready", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Label("Download failed", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Button("Retry") { model.startDownload() }
            }
        }
    }
}
