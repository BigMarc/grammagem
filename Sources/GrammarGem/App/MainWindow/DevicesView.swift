import SwiftUI

struct DevicesView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var license: LicenseManager

    var body: some View {
        DetailScaffold(
            title: "Devices",
            subtitle: "Manage the Macs your license is active on."
        ) {
            if let record = license.record {
                usageSummary(record)
                thisDevice(record)
                otherDevices(record)
            } else {
                Card {
                    Label("No active license on this Mac", systemImage: "key.slash")
                        .font(.headline)
                    Text("Activate a license to manage devices. The free plan runs on one Mac.")
                        .foregroundStyle(.secondary)
                    Button("Enter a license key") { app.showMainWindow(select: .license) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func usageSummary(_ r: LicenseRecord) -> some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text("\(max(r.activationUsage, 1)) of \(r.activationLimit)")
                    .font(.system(.title, design: .rounded).weight(.semibold))
                Text("devices in use").foregroundStyle(.secondary)
                Spacer()
                Text(license.tier.displayName).font(.subheadline).foregroundStyle(GG.emerald)
            }
            ProgressView(value: Double(max(r.activationUsage, 1)), total: Double(max(r.activationLimit, 1)))
                .tint(GG.emerald)
            Text("Your \(license.tier.displayName) plan covers up to \(r.activationLimit) Mac\(r.activationLimit == 1 ? "" : "s").")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func thisDevice(_ r: LicenseRecord) -> some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: "laptopcomputer")
                    .font(.title2).foregroundStyle(GG.emerald)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(r.deviceName).font(.headline)
                        Text("This Mac")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(GG.emerald.opacity(0.15), in: Capsule())
                            .foregroundStyle(GG.emerald)
                    }
                    Text("Activated \(r.activatedAt.formatted(date: .abbreviated, time: .omitted)) · validated \(r.lastValidated.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) {
                    Task { await app.license.deactivateThisDevice() }
                } label: {
                    if license.isWorking { ProgressView().controlSize(.small) }
                    else { Text("Deactivate") }
                }
                .disabled(license.isWorking)
            }
            if let err = license.lastError {
                Label(err, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func otherDevices(_ r: LicenseRecord) -> some View {
        Card {
            Text("Other devices").font(.headline)
            Text("Deactivating a Mac here frees a slot instantly. To rename or remove a Mac you no longer have access to, open the license portal.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Link("Open license portal", destination: AppConfig.modelPortalURL)
                Spacer()
                Text("Add a Mac: install GrammarGem there and paste the same key.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
