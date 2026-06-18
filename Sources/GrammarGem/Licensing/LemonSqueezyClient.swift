import Foundation

/// Talks to the **Lemon Squeezy License API** directly from the app — no server
/// of ours, no database, no per-user cost (spec §6). Exposes activate / validate
/// / deactivate and hard-verifies that a key belongs to GrammaGem + the claimed tier.
final class LemonSqueezyClient {
    private let session: URLSession
    private let base = AppConfig.LemonSqueezy.apiBase

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Endpoints

    func activate(key: String, instanceName: String) async throws -> ActivationResult {
        let res: LSActivateResponse = try await post(
            "licenses/activate",
            params: ["license_key": key, "instance_name": instanceName])

        if let err = res.error { throw mapServerError(err, limit: res.license_key?.activation_limit) }
        guard res.activated, let instance = res.instance else {
            throw LicenseError.serverMessage("Activation failed.")
        }
        let tier = try verifyAndResolveTier(meta: res.meta, licenseKey: res.license_key)
        return ActivationResult(
            instanceID: instance.id, tier: tier,
            usage: res.license_key?.activation_usage ?? 1,
            limit: res.license_key?.activation_limit ?? tier.deviceCap)
    }

    func validate(key: String, instanceID: String?) async throws -> ValidationResult {
        var params = ["license_key": key]
        if let instanceID { params["instance_id"] = instanceID }
        let res: LSValidateResponse = try await post("licenses/validate", params: params)

        if let err = res.error { throw mapServerError(err, limit: res.license_key?.activation_limit) }
        let tier = try verifyAndResolveTier(meta: res.meta, licenseKey: res.license_key)
        return ValidationResult(
            valid: res.valid, tier: tier,
            usage: res.license_key?.activation_usage ?? 0,
            limit: res.license_key?.activation_limit ?? tier.deviceCap)
    }

    @discardableResult
    func deactivate(key: String, instanceID: String) async throws -> Bool {
        let res: LSDeactivateResponse = try await post(
            "licenses/deactivate",
            params: ["license_key": key, "instance_id": instanceID])
        if let err = res.error { throw mapServerError(err) }
        return res.deactivated
    }

    // MARK: - Hard verification (spec §6)

    /// Confirm the key is for OUR store/product, then resolve which tier its
    /// variant corresponds to. Prevents a key from another LS product unlocking GrammaGem.
    private func verifyAndResolveTier(meta: LSMeta?, licenseKey: LSLicenseKey?) throws -> Tier {
        guard let meta else { throw LicenseError.wrongProduct }

        // Store + product check. If AppConfig still holds placeholder (non-numeric)
        // IDs, we log and skip the check so the stub flow runs — TODO(real-integration):
        // once real numeric IDs are set, this becomes a hard gate.
        if let expectedStore = Int(AppConfig.LemonSqueezy.expectedStoreID),
           let expectedProduct = Int(AppConfig.LemonSqueezy.expectedProductID) {
            guard meta.store_id == expectedStore, meta.product_id == expectedProduct else {
                throw LicenseError.wrongProduct
            }
        } else {
            Log.licensing.warning("Skipping store/product hard-verify — placeholder IDs in AppConfig.")
        }

        // Resolve tier from the variant id (reverse-lookup the configured map).
        if let variantID = meta.variant_id {
            for (tier, idString) in AppConfig.LemonSqueezy.variantID {
                if Int(idString) == variantID { return tier }
            }
        }
        // Fall back to whatever the variant name hints at, else Solo.
        switch meta.variant_name?.lowercased() {
        case let v? where v.contains("studio"): return .studio
        case let v? where v.contains("personal"): return .personal
        default: return .solo
        }
    }

    private func mapServerError(_ message: String, limit: Int? = nil) -> LicenseError {
        let m = message.lowercased()
        if m.contains("activation limit") {
            return .activationLimitReached(limit ?? 0)
        }
        if m.contains("not found") || m.contains("invalid") {
            return .invalidKey
        }
        return .serverMessage(message)
    }

    // MARK: - Transport

    private func post<T: Decodable>(_ path: String, params: [String: String]) async throws -> T {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formEncode(params).data(using: .utf8)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LicenseError.network("No HTTP response")
            }
            // LS returns 200 + {activated/valid:false} for soft failures, and 4xx
            // with a JSON `error`. Try to decode the body either way.
            if let decoded = try? JSONDecoder().decode(T.self, from: data) {
                return decoded
            }
            throw LicenseError.network("Unexpected response (\(http.statusCode))")
        } catch let e as LicenseError {
            throw e
        } catch {
            throw LicenseError.network(error.localizedDescription)
        }
    }

    private func formEncode(_ params: [String: String]) -> String {
        params.map { key, value in
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(key)=\(v)"
        }.joined(separator: "&")
    }
}
