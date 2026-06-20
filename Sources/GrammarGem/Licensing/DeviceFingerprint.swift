import Foundation
import IOKit
import CryptoKit

/// Derives a stable, privacy-preserving device identifier.
///
/// Lemon Squeezy has no hardware fingerprinting of its own, so we build one
/// (spec §6): take the hardware `IOPlatformUUID`, SHA-256 it, and pass the hash
/// as the `instance_name` on activation. Same Mac → same instance → a reinstall
/// doesn't consume a second device slot. The raw UUID never leaves the device;
/// only its hash is sent.
enum DeviceFingerprint {
    /// SHA-256 of the hardware platform UUID, hex-encoded. Falls back to a
    /// persisted random ID if IOKit is somehow unavailable.
    static func stableID() -> String {
        if let uuid = platformUUID() {
            let digest = SHA256.hash(data: Data(uuid.utf8))
            return digest.map { String(format: "%02x", $0) }.joined()
        }
        return fallbackID()
    }

    private static func platformUUID() -> String? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard let cf = IORegistryEntryCreateCFProperty(
            service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)
        else { return nil }
        return cf.takeRetainedValue() as? String
    }

    /// A friendly, human-readable name for this Mac (for the Devices screen).
    static func deviceName() -> String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    private static func fallbackID() -> String {
        let key = "GrammarGem.fallbackDeviceID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}
