import SwiftUI

/// First-run onboarding: explains why GrammarGem needs Accessibility, deep-links
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
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Welcome to GrammarGem")
                            .font(.largeTitle.bold())
                        Text("A private, on-device writing assistant that works in every app.")
                            .foregroundStyle(.secondary)
                    }

                    // The rigged win: prove the value in one click, before any ask.
                    VStack(alignment: .leading, spacing: 10) {
                        Label("See it work", systemImage: "wand.and.stars").font(.headline)
                        DemoStep()
                    }
                    .padding(16)
                    .background(GG.emerald.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(GG.emerald.opacity(0.25)))

                    stepCard(
                        number: 1,
                        title: "Turn it on everywhere",
                        body: "GrammarGem reads the text you select and writes the correction back. macOS requires Accessibility permission for this. Your text is processed on-device and never leaves your Mac.",
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
                            Text("This updates automatically once you flip GrammarGem on in Accessibility.")
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
                }
                .padding(28)
            }

            Divider()

            HStack {
                Label("Yours once. No subscription, nothing leaves your Mac.", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(permissions.accessibilityTrusted ? "Done" : "Continue without permission") {
                    app.showOnboardingDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 28).padding(.vertical, 14)
        }
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

/// A safe, on-rails first-run demo: a local sample with planted mistakes that
/// the REAL grammar engine fixes in one click. It operates on a plain string
/// (never a live Accessibility element), so it's completely risk-free — the
/// "guaranteed visible win" before GrammarGem asks for anything.
private struct DemoStep: View {
    @State private var text = "i has wrote alot of mistakes here, and it dont look profesional"
    @State private var issues: [Suggestion] = []
    @State private var cleaned = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(headline)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(cleaned ? GG.emerald : .primary)
            Text(highlighted)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .animation(.easeInOut(duration: 0.35), value: text)
            Button {
                let fixed = AppState.shared.grammar.correct(text)
                withAnimation(.easeOut(duration: 0.4)) {
                    text = fixed
                    issues = []
                    cleaned = true
                }
            } label: {
                Label(cleaned ? "All clean" : "Clean it up",
                      systemImage: cleaned ? "checkmark.circle.fill" : "wand.and.stars")
            }
            .buttonStyle(.borderedProminent)
            .disabled(cleaned || issues.isEmpty)
        }
        .onAppear {
            if issues.isEmpty && !cleaned { issues = AppState.shared.grammar.check(text) }
        }
    }

    private var headline: String {
        if cleaned { return "Clean ✨ — GrammarGem does this in every app you type." }
        if issues.isEmpty { return "Checking…" }
        return "We spotted \(issues.count) thing\(issues.count == 1 ? "" : "s") to tidy up — one click fixes them."
    }

    private var highlighted: AttributedString {
        let ns = text as NSString
        var result = AttributedString()
        var cursor = 0
        for s in issues.sorted(by: { $0.location < $1.location }) {
            guard s.location >= cursor, s.length > 0, s.location + s.length <= ns.length else { continue }
            if s.location > cursor {
                result += AttributedString(ns.substring(with: NSRange(location: cursor, length: s.location - cursor)))
            }
            var run = AttributedString(ns.substring(with: s.range))
            let tint: Color = s.kind == .spelling ? .red : .orange
            run.backgroundColor = tint.opacity(0.18)
            run.foregroundColor = tint
            run.underlineStyle = .single
            result += run
            cursor = s.location + s.length
        }
        if cursor < ns.length {
            result += AttributedString(ns.substring(with: NSRange(location: cursor, length: ns.length - cursor)))
        }
        return result
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
                Button("Download model now") { model.startDownload() }
                Text("Installs automatically in the background on first launch (about 1–2 GB from Hugging Face). One time, then fully offline.")
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
