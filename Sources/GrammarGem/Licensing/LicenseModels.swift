import Foundation

/// The locally-stored license record (Keychain-persisted).
struct LicenseRecord: Codable, Equatable {
    var key: String
    var instanceID: String          // Lemon Squeezy activation instance id
    var tier: Tier
    var lastValidated: Date
    var activatedAt: Date           // when this Mac was first activated
    var deviceName: String          // friendly name of this Mac
    var activationUsage: Int        // devices currently using the license
    var activationLimit: Int        // device cap for the tier
}

/// Result of an activate call.
struct ActivationResult {
    let instanceID: String
    let tier: Tier
    let usage: Int
    let limit: Int
}

/// Result of a validate call.
struct ValidationResult {
    let valid: Bool
    let tier: Tier
    let usage: Int
    let limit: Int
}

// MARK: - Lemon Squeezy API response shapes (subset we rely on)

struct LSActivateResponse: Codable {
    let activated: Bool
    let instance: LSInstance?
    let license_key: LSLicenseKey?
    let meta: LSMeta?
    let error: String?
}

struct LSValidateResponse: Codable {
    let valid: Bool
    let license_key: LSLicenseKey?
    let meta: LSMeta?
    let error: String?
}

struct LSDeactivateResponse: Codable {
    let deactivated: Bool
    let error: String?
}

struct LSInstance: Codable {
    let id: String
    let name: String
}

struct LSLicenseKey: Codable {
    let status: String       // "active", "expired", "disabled", …
    let activation_limit: Int?
    let activation_usage: Int?
}

/// `meta` carries the store/product/variant identity we *hard-verify* against
/// AppConfig so a key from another Lemon Squeezy product can't unlock GrammaGem.
struct LSMeta: Codable {
    let store_id: Int?
    let product_id: Int?
    let variant_id: Int?
    let variant_name: String?
}

enum LicenseError: LocalizedError, Equatable {
    case network(String)
    case invalidKey
    case wrongProduct
    case activationLimitReached(Int)
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .network(let m): return "Couldn't reach the license server: \(m)"
        case .invalidKey: return "That license key isn't valid."
        case .wrongProduct: return "That key belongs to a different product."
        case .activationLimitReached(let n): return "This plan is active on \(n) Macs — deactivate one or upgrade."
        case .serverMessage(let m): return m
        }
    }
}
