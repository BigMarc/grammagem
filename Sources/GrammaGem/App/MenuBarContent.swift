import SwiftUI

/// The menu-bar icon label — reflects live status (issue count / paused).
struct MenuBarLabel: View {
    @ObservedObject private var app: AppState
    @ObservedObject private var monitor: LiveMonitor

    init() {
        _app = ObservedObject(wrappedValue: AppState.shared)
        _monitor = ObservedObject(wrappedValue: AppState.shared.liveMonitor)
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: app.isPaused ? "pause.circle" : "pencil.and.scribble")
            if !app.isPaused, monitor.issueCount > 0 {
                Text("\(monitor.issueCount)")
            }
        }
    }
}

/// The dropdown shown from the menu-bar icon.
struct MenuBarContent: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var monitor: LiveMonitor
    @Environment(\.openSettings) private var openSettings

    init() {
        _monitor = ObservedObject(wrappedValue: AppState.shared.liveMonitor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Divider()

            liveStatus

            Divider()

            actionRow(title: "Fix selection", shortcut: app.preferences.fixHotkey.display) {
                Task { await app.runFix() }
            }
            actionRow(title: "Ask GrammaGem…", shortcut: app.preferences.askHotkey.display) {
                app.showAsk()
            }
            if app.gate.appAwareEnabled {
                actionRow(title: "Apply app-aware mode", shortcut: nil) {
                    Task { await app.runAppAwareRewrite() }
                }
            }
            actionRow(title: app.isPaused ? "Resume GrammaGem" : "Pause GrammaGem", shortcut: nil) {
                app.togglePause()
            }

            Divider()

            actionRow(title: "Open GrammaGem…", shortcut: nil) { app.showMainWindow() }
            actionRow(title: "Manage devices…", shortcut: nil) { app.showMainWindow(select: .devices) }
            actionRow(title: "Page blocker…", shortcut: nil) { app.showMainWindow(select: .exclusions) }

            Divider()

            usageRow

            Divider()

            HStack {
                Button("Settings…") { openSettings() }
                Spacer()
                Button("Quit") { app.quit() }
            }
            .buttonStyle(.borderless)

            Text(app.lastStatus)
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(14)
        .frame(width: 290)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil.and.scribble").foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("GrammaGem").font(.headline)
                Text(app.license.tier.displayName + (app.license.isLicensed ? " · licensed" : " · free"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !app.permissions.accessibilityTrusted {
                Button { app.showOnboarding() } label: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .buttonStyle(.borderless)
                .help("Accessibility permission needed")
            }
        }
    }

    @ViewBuilder
    private var liveStatus: some View {
        if app.isPaused {
            Label("Paused — not monitoring", systemImage: "pause.circle")
                .font(.callout).foregroundStyle(.secondary)
        } else if monitor.issueCount > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Label("\(monitor.issueCount) suggestion\(monitor.issueCount == 1 ? "" : "s")"
                      + (monitor.activeAppName.isEmpty ? "" : " in \(monitor.activeAppName)"),
                      systemImage: "text.badge.checkmark")
                    .font(.callout).foregroundStyle(.primary)
                ForEach(monitor.suggestions.prefix(3)) { s in
                    Text("• \(s.message): “\(s.original)” → “\(s.replacement)”")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Button { Task { await app.fixFocusedField() } } label: {
                    Label("Fix all", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
            }
        } else if monitor.running {
            Label(monitor.activeAppName.isEmpty ? "Monitoring — looks clean"
                  : "Watching \(monitor.activeAppName) — looks clean",
                  systemImage: "checkmark.circle")
                .font(.callout).foregroundStyle(.secondary)
        } else {
            Label("Live monitoring is off", systemImage: "eye.slash")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var usageRow: some View {
        if app.gate.entitlements.unlimitedAIActions {
            Label("Unlimited AI actions", systemImage: "infinity")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            let used = app.gate.aiActionsUsedToday
            let cap = app.gate.entitlements.dailyAIActionCap
            Label("\(max(0, cap - used)) of \(cap) free AI actions left today", systemImage: "bolt")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func actionRow(title: String, shortcut: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut).foregroundStyle(.secondary).font(.callout.monospaced())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
