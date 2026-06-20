import Foundation
import Security

/// Minimal Keychain wrapper for the license record. The license key + instance
/// id + last-validated timestamp live here (never in plain UserDefaults).
enum Keychain {
    private static let service = AppConfig.bundleIdentifier

    static func set(_ data: Data, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess {
            Log.licensing.error("Keychain set failed: \(status)")
        }
    }

    static func get(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // Codable convenience.
    static func setObject<T: Encodable>(_ value: T, account: String) {
        if let data = try? JSONEncoder().encode(value) { set(data, account: account) }
    }

    static func getObject<T: Decodable>(_ type: T.Type, account: String) -> T? {
        guard let data = get(account: account) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
