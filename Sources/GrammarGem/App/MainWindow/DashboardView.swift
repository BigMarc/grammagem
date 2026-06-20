import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var license: LicenseManager
    @EnvironmentObject private var gate: FeatureGate
    @EnvironmentObject private var usage: UsageStats
    @EnvironmentObject private var model: ModelManager
    @EnvironmentObject private var permissions: Permissions

    var body: some View {
        DetailScaffold(
            title: "Welcome back",
            subtitle: "Your private writing assistant, at a glance."
        ) {
            // Key metrics
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 158), spacing: 14)], spacing: 14) {
                StatTile(
                    value: license.tier.displayName,
                    label: license.isLicensed ? "Lifetime plan" : "Free plan",
                    systemImage: "key.fill", tint: license.isLicensed ? GG.emerald : .secondary)

                if gate.entitlements.unlimitedAIActions {
                    StatTile(value: "∞", label: "AI actions today", systemImage: "infinity", tint: GG.emerald)
                } else {
                    StatTile(
                        value: "\(gate.remainingAIActionsToday)/\(gate.entitlements.dailyAIActionCap)",
                        label: "AI actions left today", systemImage: "bolt.fill", tint: GG.gold)
                }

                StatTile(value: "\(usage.data.totalCorrections)", label: "Corrections made", systemImage: "checkmark.seal.fill", tint: GG.emerald)
                StatTile(value: timeSaved, label: "Time saved (est.)", systemImage: "clock.fill", tint: .primary)

                StatTile(
                    value: usage.currentStreak > 0 ? "\(usage.currentStreak)d" : "—",
                    label: "Day streak", systemImage: "flame.fill",
                    tint: usage.currentStreak > 0 ? .orange : .secondary)
                StatTile(
                    value: "$\(usage.subscriptionAvoidedUSD)",
                    label: "Subscription not paid", systemImage: "dollarsign.circle.fill",
                    tint: GG.emerald)
            }

            // Setup health
            Card {
                Text("Setup").font(.headline)
                healthRow(
                    ok: permissions.accessibilityTrusted,
                    okText: "Accessibility granted",
                    badText: "Accessibility needed to fix text in apps",
                    action: permissions.accessibilityTrusted ? nil : ("Fix", { app.showOnboarding() }))
                Divider()
                healthRow(
                    ok: model.state == .ready,
                    okText: "On-device AI model ready",
                    badText: "AI model not downloaded (grammar still works)",
                    action: model.state == .ready ? nil : ("Set up", { app.showMainWindow(select: .model) }))
            }

            // Activity
            Card {
                HStack {
                    Text("Activity").font(.headline)
                    Spacer()
                    Text("Last 7 days").font(.caption).foregroundStyle(.secondary)
                }
                WeeklyBars(points: usage.last7Days())
                    .frame(height: 110)
                Text("\(usage.data.totalWords) words polished overall — all on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            // Next milestone
            Card {
                let milestone = usage.nextMilestone
                HStack {
                    Text("Next milestone").font(.headline)
                    Spacer()
                    Text(milestone.label).font(.caption).foregroundStyle(.secondary)
                }
                ProgressView(value: milestone.progress).tint(GG.emerald)
                Text("\(usage.data.totalCorrections) corrections so far — keep the streak alive.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            // Quick actions
            Card {
                Text("Quick actions").font(.headline)
                HStack {
                    Button { Task { await app.runFix() } } label: {
                        Label("Fix selection", systemImage: "checkmark.circle")
                    }
                    Button { app.showAsk() } label: {
                        Label("Ask GrammarGem", systemImage: "sparkles")
                    }
                    if !license.isLicensed {
                        Spacer()
                        Button { app.showMainWindow(select: .license) } label: {
                            Label("Upgrade", systemImage: "arrow.up.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private var timeSaved: String {
        let m = usage.estimatedMinutesSaved
        if m >= 60 { return "\(m / 60)h \(m % 60)m" }
        return "\(m)m"
    }

    @ViewBuilder
    private func healthRow(ok: Bool, okText: String, badText: String, action: (String, () -> Void)?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? GG.emerald : .orange)
            Text(ok ? okText : badText)
            Spacer()
            if let action {
                Button(action.0, action: action.1)
            }
        }
    }
}

/// A tiny dependency-free weekly bar chart.
struct WeeklyBars: View {
    let points: [(label: String, count: Int)]

    var body: some View {
        let maxCount = max(points.map(\.count).max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                VStack(spacing: 6) {
                    Spacer(minLength: 0)
                    Text(point.count > 0 ? "\(point.count)" : "")
                        .font(.caption2).foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(point.count > 0 ? GG.emerald : Color.secondary.opacity(0.18))
                        .frame(height: barHeight(point.count, maxCount: maxCount))
                    Text(point.label).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func barHeight(_ count: Int, maxCount: Int) -> CGFloat {
        let ratio = CGFloat(count) / CGFloat(maxCount)
        return max(4, ratio * 78)
    }
}
