import Foundation

/// Owns license state and maps it to an `Entitlements` value the rest of the app
/// gates on. Implements the two gaps Lemon Squeezy leaves to us (spec §6):
/// device fingerprinting (via `DeviceFingerprint`) and **offline grace**.
@MainActor
final class LicenseManager: ObservableObject {
    @Published private(set) var record: LicenseRecord?
    @Published private(set) var lastError: String?
    @Published private(set) var isWorking = false

    private let client: LemonSqueezyClient
    private let account = "license"

    init(client: LemonSqueezyClient = LemonSqueezyClient()) {
        self.client = client
        self.record = Keychain.getObject(LicenseRecord.self, account: account)
    }

    /// Effective tier *right now*, honoring the 30-day offline grace: if the
    /// device hasn't validated within the window, downgrade to Free rather than
    /// hard-lock (writing features never need the network anyway).
    var tier: Tier {
        guard let record else { return .free }
        let grace = TimeInterval(AppConfig.Limits.offlineGraceDays * 86_400)
        if Date().timeIntervalSince(record.lastValidated) > grace {
            return .free
        }
        return record.tier
    }

    var isLicensed: Bool { tier.isPaid }

    var entitlements: Entitlements { Entitlements(tier: tier) }

    // MARK: - Flows

    /// Activate a pasted key against this device.
    func activate(key: String) async {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { lastError = "Enter a license key."; return }
        isWorking = true; lastError = nil
        defer { isWorking = false }

        do {
            let instanceName = DeviceFingerprint.stableID()
            let result = try await client.activate(key: key, instanceName: instanceName)
            let rec = LicenseRecord(
                key: key, instanceID: result.instanceID, tier: result.tier,
                lastValidated: Date(), activatedAt: Date(),
                deviceName: DeviceFingerprint.deviceName(),
                activationUsage: result.usage, activationLimit: result.limit)
            Keychain.setObject(rec, account: account)
            record = rec
            Log.licensing.info("Activated tier \(result.tier.rawValue, privacy: .public)")
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// On launch + every ~7 days. Network failures are non-fatal (offline grace).
    func validateIfNeeded(force: Bool = false) async {
        guard var rec = record else { return }
        let interval = TimeInterval(AppConfig.Limits.validationIntervalDays * 86_400)
        guard force || Date().timeIntervalSince(rec.lastValidated) > interval else { return }

        do {
            let result = try await client.validate(key: rec.key, instanceID: rec.instanceID)
            if result.valid {
                rec.lastValidated = Date()
                rec.tier = result.tier
                rec.activationUsage = result.usage
                rec.activationLimit = result.limit
                Keychain.setObject(rec, account: account)
                record = rec
            } else {
                // Explicitly invalid (refunded / disabled) → drop the license.
                Log.licensing.notice("License reported invalid by server; clearing.")
                clearLocal()
            }
        } catch let e as LicenseError where Self.isServerConfirmedInvalid(e) {
            // The server actively rejected the key (refunded/disabled/wrong product)
            // — drop it now rather than honoring it for the 30-day grace window.
            Log.licensing.notice("License rejected by server; clearing.")
            clearLocal()
        } catch {
            // Offline / transient: keep the cached license under the grace window.
            Log.licensing.notice("Validation deferred (offline). Cached license stands under grace.")
        }
    }

    /// Distinguish a server-confirmed-invalid license from a transient/offline failure.
    private static func isServerConfirmedInvalid(_ error: LicenseError) -> Bool {
        switch error {
        case .invalidKey, .wrongProduct:
            return true
        case .serverMessage(let m):
            let s = m.lowercased()
            return ["disabled", "expired", "inactive", "revoked", "refund"].contains { s.contains($0) }
        case .network, .activationLimitReached:
            return false
        }
    }

    /// Free a device slot so the license can move to another Mac.
    func deactivateThisDevice() async {
        guard let rec = record else { return }
        isWorking = true; lastError = nil
        defer { isWorking = false }
        do {
            _ = try await client.deactivate(key: rec.key, instanceID: rec.instanceID)
            clearLocal()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearLocal() {
        Keychain.delete(account: account)
        record = nil
    }
}
